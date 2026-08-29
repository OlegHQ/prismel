type error_kind = Invalid_argument | Unsupported | Backend | Resource | Destroyed
type error = { operation:string; kind:error_kind; message:string }
let pp_error formatter value =
  Format.fprintf formatter "%s: %s" value.operation value.message
let fail operation kind message = Error { operation; kind; message }
let backend operation value =
  Error { operation; kind=Backend; message=Ogpu.Error.to_string value }
let resource operation value =
  Error { operation; kind=Resource; message=Format.asprintf "%a" Prismel_next_resources.pp_error value }

type timing = Fixed of float | Variable
type configuration = { logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; title:string; timing:timing;
  max_events:int; max_file_bytes:int;vsync:bool }
let default_configuration = { logical_width=640; logical_height=480;
  drawable_width=640; drawable_height=480; title="Prismel"; timing=Fixed (1. /. 60.);
  max_events=4096; max_file_bytes=16*1024*1024;vsync=true }

type mouse_button = Left | Middle | Right | X1 | X2
type modifier = Shift | Control | Alt | Meta | Num_lock | Caps_lock | Scroll_lock
type key = { name:string; modifiers:modifier list; repeat:bool }
type event = Pointer_moved of float*float | Pointer_pressed of mouse_button*float*float
  | Pointer_released of mouse_button*float*float | Pointer_cancelled of mouse_button
  | Wheel of float*float | Key_pressed of key | Key_released of key
  | Text_input of string | Text_editing of {text:string;start:int;length:int}
  | Focus_lost | Focus_gained | Visibility_changed of bool | Quit
  | Resized of int*int | File_dropped of {name:string;contents:bytes option}
type facts = { frame:int64; time:float; dt:float; logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; pixel_scale:float; events:event list;
  pointer:float*float; mouse_delta:float*float; wheel_delta:float*float;
  dropped_events:int }
type family = Scene2 | Scene2_textured | Scene3 | Scene3_textured | Scene3_shadow |
  Scene3_stencil | Scene3_textured_stencil | Scene3_shadow_stencil
type blend = Replace | Alpha | Add | Multiply | Screen | Subtract
type draw = { family:family; blend:blend; texture:Scene_execution.sampled_texture option;
  auxiliary:Scene_execution.auxiliary_resource option;samples:int;value:Scene_execution.draw }
type cached_scene2_geometry={vertices:float array;indices:int array;fingerprint:int;source_bytes:int;color:int32;
  clip:int*int*int*int;draw:draw}
type scene2_geometry_candidate={candidate_vertex_count:int;
  candidate_index_count:int;candidate_fingerprint:int;candidate_source_bytes:int;candidate_color:int32;
  candidate_clip:int*int*int*int}
type cached_scene2_batch={batch_fingerprint:int;batch_draw_count:int;
  batch_source_bytes:int;batch_draw:draw}
type cached_scene2_quad={quad_texture:Scene_execution.sampled_texture;
  quad_destination:Scene_command.Render_ir.rect;quad_transform:Scene_command.Render_ir.transform;
  quad_clip:int*int*int*int;quad_uv:float*float*float*float;quad_draw:draw}
type cached_scene2_quad_payload={payload_destination:Scene_command.Render_ir.rect;
  payload_transform:Scene_command.Render_ir.transform;payload_clip:int*int*int*int;
  payload_uv:float*float*float*float;payload_mesh_key:string;
  payload_vertices:bytes;payload_indices:bytes}
type cached_scene2_debug={debug_source:Scene_command.Render_ir.debug_text;
  debug_transform:Scene_command.Render_ir.transform;debug_clip:int*int*int*int;
  debug_draw:draw option}
type resource=Image of Prismel_next_resources.Image.t|Text of Prismel_next_resources.Text.t
  |Canvas of Prismel_next_resources.Canvas.t
type scene2_resource_stamp=
  |Image_stamp of int*Prismel_next_resources.Image.t*int
  |Text_stamp of int*Prismel_next_resources.Text.t*int
  |Canvas_stamp of int*Prismel_next_resources.Canvas.t*int
type cached_scene2_plan={plan_fingerprint:int;plan_command_count:int;
  plan_source_bytes:int;plan_density:int;
  plan_extent:int*int*int*int;plan_resources:scene2_resource_stamp list;
  plan_ir:Scene_command.Render_ir.t;plan_draws:draw list}
type scene2_plan_candidate={candidate_plan_fingerprint:int;
  candidate_plan_command_count:int;candidate_plan_density:int;
  candidate_plan_extent:int*int*int*int;
  candidate_plan_resources:scene2_resource_stamp list}
let prepared_draw ~family ?(blend=Replace) ?texture ?auxiliary ?(samples=1) value =
  {family;blend;texture;auxiliary;samples;value}

let default_state viewport scissor = { Scene_execution.viewport; scissor;
  cull=Ogpu.Render_pass.Cull_none; depth_compare=Ogpu.Render_pass.Always;
  depth_write=false; depth_load=Ogpu.Render_pass.Load; depth_clear=1.;
  transform_uniforms=None; stencil_state=None; stencil_load=Ogpu.Render_pass.Load;
  stencil_clear=0 }
let finite value = Float.is_finite value
let put_float bytes offset value = Bytes.set_int64_le bytes offset (Int64.bits_of_float value)
(* Scene2 keeps affine coefficients as f64 through command lowering.  The
   native execution boundary narrows these values to the six-f32 Metal ABI. *)
let identity_affine_uniforms=let bytes=Bytes.make 48 '\000'in
  Bytes.set_int64_le bytes 0(Int64.bits_of_float 1.);
  Bytes.set_int64_le bytes 32(Int64.bits_of_float 1.);bytes
module Command = Scene_execution.Scene2_command
let affine_uniforms (transform:Command.transform)=
  if transform.xx=1.&&transform.xy=0.&&transform.yx=0.&&transform.yy=1.&&
    transform.tx=0.&&transform.ty=0. then identity_affine_uniforms else
  let bytes=Bytes.make 48 '\000'in
  let put index value=Bytes.set_int64_le bytes(index*8)(Int64.bits_of_float value)in
  put 0 transform.xx;put 1 transform.yx;put 2 transform.tx;
  put 3 transform.xy;put 4 transform.yy;put 5 transform.ty;bytes
let identity_transform (transform:Command.transform)=
  transform.xx=1.&&transform.xy=0.&&transform.yx=0.&&transform.yy=1.&&
  transform.tx=0.&&transform.ty=0.
let scene2_vertex_stride=24
let mesh_of_geometry number transform clip (geometry:Command.geometry) =
  let count=Array.length geometry.vertices/2 in
  let vertices=Bytes.create(count*scene2_vertex_stride) in
  for index=0 to count-1 do
    let x=geometry.vertices.(index*2) and y=geometry.vertices.(index*2+1) in
    let offset=index*scene2_vertex_stride in
    put_float vertices offset x;put_float vertices(offset+8)y;
    Bytes.set_int32_le vertices(offset+16)geometry.color
  done;
  let indices=Bytes.create(Array.length geometry.indices*4) in
  Array.iteri(fun index value->Bytes.set_int32_le indices(index*4)(Int32.of_int value))geometry.indices;
  let x,y,width,height=clip in
  { family=Scene2;blend=Replace;texture=None;auxiliary=None;samples=1; value={Scene_execution.mesh={key=Printf.sprintf "ir-%Ld-%d" 0L number;
      vertices;vertex_count=count;indices;index_count=Array.length geometry.indices};
      state={(default_state (x,y,width,height) (x,y,width,height))with
        transform_uniforms=(if identity_transform transform then None else Some(affine_uniforms transform))}} }
let debug_text_geometry (transform:Command.transform) (debug:Command.debug_text) =
  let stop = match String.index_opt debug.text '\000' with
    | Some index -> index | None -> String.length debug.text in
  let pixels = ref 0 in
  for character = 0 to stop - 1 do
    for row = 0 to Scene_command.Debug_font.height - 1 do
      let bits = Scene_command.Debug_font.glyph_row debug.text.[character] row in
      for column = 0 to Scene_command.Debug_font.width - 1 do
        if bits land (0x80 lsr column) <> 0 then incr pixels
      done
    done
  done;
  let vertices = Array.make (!pixels * 8) 0.
  and indices = Array.make (!pixels * 6) 0 in
  let anchor_x = transform.xx *. debug.x
    +. transform.yx *. debug.y +. transform.tx
  and anchor_y = transform.xy *. debug.x
    +. transform.yy *. debug.y +. transform.ty in
  let pixel = ref 0 in
  for character = 0 to stop - 1 do
    for row = 0 to Scene_command.Debug_font.height - 1 do
      let bits = Scene_command.Debug_font.glyph_row debug.text.[character] row in
      for column = 0 to Scene_command.Debug_font.width - 1 do
        if bits land (0x80 lsr column) <> 0 then begin
          let x = anchor_x +. float (character * Scene_command.Debug_font.width + column)
          and y = anchor_y +. float row in
          let vertex = !pixel * 8 and index = !pixel * 6
          and base = !pixel * 4 in
          vertices.(vertex) <- x; vertices.(vertex + 1) <- y;
          vertices.(vertex + 2) <- x +. 1.; vertices.(vertex + 3) <- y;
          vertices.(vertex + 4) <- x +. 1.; vertices.(vertex + 5) <- y +. 1.;
          vertices.(vertex + 6) <- x; vertices.(vertex + 7) <- y +. 1.;
          indices.(index) <- base; indices.(index + 1) <- base + 1;
          indices.(index + 2) <- base + 2; indices.(index + 3) <- base;
          indices.(index + 4) <- base + 2; indices.(index + 5) <- base + 3;
          incr pixel
        end
      done
    done
  done;
  Command.{vertices;indices;color=debug.color}
let compose (a:Command.transform) (b:Command.transform) = Command.{xx=a.xx*.b.xx+.a.yx*.b.xy;
  xy=a.xy*.b.xx+.a.yy*.b.xy; yx=a.xx*.b.yx+.a.yx*.b.yy;
  yy=a.xy*.b.yx+.a.yy*.b.yy; tx=a.xx*.b.tx+.a.yx*.b.ty+.a.tx;
  ty=a.xy*.b.tx+.a.yy*.b.ty+.a.ty }
let compose_raster (a:Scene_command.Render_ir.transform) (b:Scene_command.Render_ir.transform)={Scene_command.Render_ir.xx=a.xx*.b.xx+.a.yx*.b.xy;
  xy=a.xy*.b.xx+.a.yy*.b.xy;yx=a.xx*.b.yx+.a.yx*.b.yy;
  yy=a.xy*.b.yx+.a.yy*.b.yy;tx=a.xx*.b.tx+.a.yx*.b.ty+.a.tx;
  ty=a.xy*.b.tx+.a.yy*.b.ty+.a.ty}
let command_transform_of_raster (value:Scene_command.Render_ir.transform):Command.transform=
  {xx=value.xx;xy=value.xy;yx=value.yx;yy=value.yy;tx=value.tx;ty=value.ty}
let command_geometry_of_raster (value:Scene_command.Render_ir.geometry):Command.geometry=
  {vertices=value.vertices;indices=value.indices;color=value.color}
let scene2_commands commands =
  let identity=Command.{xx=1.;xy=0.;yx=0.;yy=1.;tx=0.;ty=0.} in
  let transforms=ref[identity] and clips=ref[(0,0,-1,-1)]
  and blend=ref Alpha and draws=ref[] and number=ref 0 and failure=ref None in
  Array.iter(fun command->if !failure=None then match command with
    |Command.Clear _->()
    |Set_blend mode->blend:=(match mode with Command.Replace->Replace|Alpha->Alpha
        |Add->Add|Multiply->Multiply|Screen->Screen|Subtract->Subtract)
    |Push_transform value->transforms:=compose(List.hd!transforms)value::!transforms
    |Pop_transform->(match !transforms with _::(_::_ as rest)->transforms:=rest|_->())
    |Push_clip rect->
        if not(List.for_all finite[rect.x;rect.y;rect.width;rect.height])then failure:=Some"non-finite clip"
        else let x=int_of_float(floor rect.x)and y=int_of_float(floor rect.y)
          and w=max 0(int_of_float(ceil rect.width))and h=max 0(int_of_float(ceil rect.height))in
          clips:=(x,y,w,h)::!clips
    |Pop_clip->(match !clips with _::(_::_ as rest)->clips:=rest|_->())
    |Geometry geometry->
        let draw=mesh_of_geometry !number(List.hd!transforms)(List.hd!clips)geometry in
        draws:={draw with blend= !blend}::!draws;incr number
    |Debug_text debug->
        let geometry=debug_text_geometry(List.hd!transforms)debug in
        if Array.length geometry.indices>0 then begin
          let draw=mesh_of_geometry !number identity(List.hd!clips)geometry in
          draws:={draw with blend= !blend}::!draws;
          incr number
        end
    ) commands;
  match !failure with Some message->fail"Prismel_next_execution.scene2_commands"Unsupported message
  |None->Ok(List.rev!draws)

let batch_fingerprint draws =
  List.fold_left (fun fingerprint (draw:draw) ->
    let mesh=draw.value.mesh in
    Hashtbl.seeded_hash fingerprint
      (mesh.key,mesh.vertex_count,mesh.index_count,mesh.vertices,mesh.indices,
       draw.value.state)) 0 draws

let bytes_segment_equal left left_offset right =
  let length=Bytes.length right in
  if left_offset<0 || left_offset+length>Bytes.length left then false
  else
    let equal=ref true and index=ref 0 in
    while !equal && !index<length do
      if Bytes.get left(left_offset+ !index)<>Bytes.get right !index then equal:=false;
      incr index
    done;
    !equal

let batch_matches sources (cached:cached_scene2_batch) =
  if List.length sources<>cached.batch_draw_count ||
     batch_fingerprint sources<>cached.batch_fingerprint ||
     (match sources with []->true|first::_->
       first.value.state<>cached.batch_draw.value.state) then false
  else
    let merged=cached.batch_draw.value.mesh in
    let vertex_offset=ref 0 and index_offset=ref 0 and matches=ref true in
    List.iter (fun (draw:draw) ->
      if !matches then begin
        let mesh=draw.value.mesh in
        let vertex_bytes=mesh.vertex_count*scene2_vertex_stride in
        if not(bytes_segment_equal merged.vertices !vertex_offset mesh.vertices)
        then matches:=false
        else begin
          for index=0 to mesh.index_count-1 do
            let actual=Int32.to_int(Bytes.get_int32_le merged.indices
              (!index_offset+index*4))
            and expected=Int32.to_int(Bytes.get_int32_le mesh.indices(index*4))+
              (!vertex_offset/scene2_vertex_stride) in
            if actual<>expected then matches:=false
          done;
          vertex_offset:=!vertex_offset+vertex_bytes;
          index_offset:=!index_offset+mesh.index_count*4
        end
      end) sources;
    !matches && !vertex_offset=Bytes.length merged.vertices &&
    !index_offset=Bytes.length merged.indices

let scene2_geometry_byte_capacity=64*1024*1024
let trim_scene2_entries ?(capacity=256) bytes entries =
  let rec loop count total kept = function
    | [] -> List.rev kept
    | entry::rest ->
        let size=bytes entry in
        if count<capacity&&size<=scene2_geometry_byte_capacity-total then
          loop(count+1)(total+size)(entry::kept)rest
        else loop count total kept rest
  in loop 0 0 [] entries

let batch_scene2_draws ~cache ~set_cache draws =
  let preserve_independent = List.length draws <= 64 in
  let compatible (left : draw) (right : draw) =
    left.family = Scene2 && right.family = Scene2
    && left.blend = right.blend && left.texture = None && right.texture = None
    && left.auxiliary = None && right.auxiliary = None
    && left.samples = right.samples && left.value.state = right.value.state
  in
  let merge reversed =
    match List.rev reversed with
    | [] -> assert false
    | [draw] -> [draw]
    (* Preserve independent stable identities for ordinary scene-sized runs.
       If one member moves, eagerly combining a small run re-uploads every
       unchanged neighbour.  Large UI runs still batch to keep draw and cache
       cardinality bounded. *)
    | group when preserve_independent -> group
    | first :: _ as group ->
        let fingerprint=batch_fingerprint group in
        (match List.find_opt (batch_matches group) cache with
         |Some cached-> [cached.batch_draw]
         |None->
        let vertex_count = List.fold_left
            (fun count draw -> count + draw.value.mesh.vertex_count) 0 group
        and index_count = List.fold_left
            (fun count draw -> count + draw.value.mesh.index_count) 0 group in
        let vertices = Bytes.create (vertex_count * scene2_vertex_stride)
        and indices = Bytes.create (index_count * 4) in
        let vertex_offset = ref 0 and index_offset = ref 0 in
        List.iter (fun draw ->
          let mesh = draw.value.mesh in
          Bytes.blit mesh.vertices 0 vertices (!vertex_offset * scene2_vertex_stride)
            (mesh.vertex_count * scene2_vertex_stride);
          for index = 0 to mesh.index_count - 1 do
            let source = Int32.to_int (Bytes.get_int32_le mesh.indices (index * 4)) in
            Bytes.set_int32_le indices ((!index_offset + index) * 4)
              (Int32.of_int (source + !vertex_offset))
          done;
          vertex_offset := !vertex_offset + mesh.vertex_count;
          index_offset := !index_offset + mesh.index_count) group;
        let mesh : Scene_execution.mesh = {
          key=Printf.sprintf "%s+%d" first.value.mesh.key (List.length group);
          vertices; vertex_count; indices; index_count } in
        let draw={ first with value={first.value with mesh} } in
        let cached={batch_fingerprint=fingerprint;
          batch_draw_count=List.length group;
          batch_source_bytes=Bytes.length vertices+Bytes.length indices;
          batch_draw=draw} in
        set_cache(trim_scene2_entries (fun cached->cached.batch_source_bytes)
          (cached::cache));
        [draw])
  in
  let flush output current = List.rev_append (merge current) output in
  let rec loop output current = function
    | [] -> List.rev (match current with [] -> output | _ -> flush output current)
    | draw :: rest ->
        (match current with
         | previous :: _ when compatible previous draw ->
             loop output (draw :: current) rest
         | [] -> loop output [draw] rest
         | _ -> loop (flush output current) [draw] rest)
  in
  loop [] [] draws

type presentation_facts={title:string;logical_width:int;logical_height:int;
  drawable_width:int;drawable_height:int;position:(int*int)option;
  pixel_density:float;display_scale:float;refresh_rate:float option;vsync:bool}
type offscreen_runtime={runtime:Runtime_next.offscreen;
  mutable facts:presentation_facts;mutable frames:int64;
  mutable logical_draws:int64;mutable logical_passes:int64;
  mutable logical_submissions:int64}
type runtime=Window of Runtime_next_orchestrator.t|Offscreen of offscreen_runtime
type submission_state=Open|Closed
exception Resource_resolver_raised of exn
type snapshot_cache_entry={snapshot_key:string;snapshot_generation:int;
  snapshot_density:int;snapshot_width:int;snapshot_height:int;
  snapshot_bytes:int;snapshot_texture:Scene_execution.sampled_texture}
let snapshot_cache_capacity=256
let snapshot_cache_byte_capacity=64*1024*1024
(* Full-window snapshots change frequently and already have bounded double
   buffers in [Image].  Keeping entries below 1 MiB admits UI/text assets but
   deliberately leaves a 640x480 RGBA frame (1,228,800 bytes) transient. *)
let snapshot_cache_entry_byte_capacity=1024*1024
let sampled_texture_bytes (texture:Scene_execution.sampled_texture)=
  Array.fold_left(fun total level->
    let bytes=Bytes.length level.Scene_execution.bytes in
    if total>snapshot_cache_entry_byte_capacity-bytes then
      snapshot_cache_entry_byte_capacity+1 else total+bytes)0 texture.levels
type t = { runtime:runtime; input:Runtime_next_input.t;
  assets:Prismel_next_resources.Assets.t; timing:timing; mutable frame:int64;
  mutable elapsed:float; mutable last_clock:float; mutable dead:bool;
  mutable snapshots:snapshot_cache_entry list;mutable snapshot_bytes:int;
  mutable scene2_geometry_cache:cached_scene2_geometry list;
  mutable scene2_geometry_candidates:scene2_geometry_candidate list;
  mutable scene2_batch_cache:cached_scene2_batch list;
  mutable scene2_quad_cache:cached_scene2_quad list;
  mutable scene2_quad_payload_cache:cached_scene2_quad_payload list;
  mutable scene2_debug_cache:cached_scene2_debug list;
  mutable scene2_plan_cache:cached_scene2_plan list;
  mutable scene2_plan_candidates:scene2_plan_candidate list;
  mutable scene2_probe_count:int;mutable scene2_probe_density:int;
  mutable scene2_probe_fingerprint:int;
  mutable scene2_probe_cooldown:int;
  mutable submissions:submission list;
  mutable canvas_keys:(Prismel_next_resources.Canvas.t*string)list;mutable next_canvas_key:int }
and submission={owner:t;mutable submission_state:submission_state;
  mutable image_leases:Prismel_next_resources.Image.Private.lease list}
and batch={batch_owner:submission;batch_draws:draw list}
type lease_policy=Copy_image_snapshots|Retain_image_snapshots of submission
let valid_configuration operation (configuration:configuration)=
  let positive x=x>0 in
  if not(List.for_all positive[configuration.logical_width;configuration.logical_height;
      configuration.drawable_width;configuration.drawable_height;configuration.max_events;
      configuration.max_file_bytes])then fail operation Invalid_argument"dimensions and bounds must be positive"
  else(match configuration.timing with Fixed dt when not(finite dt&&dt>0.)->
      fail operation Invalid_argument"fixed dt must be finite and positive"|_->Ok())
let finish_create operation configuration runtime destroy_runtime=
  match Runtime_next_input.create~max_events:configuration.max_events
    ~max_file_bytes:configuration.max_file_bytes~logical_width:configuration.logical_width
    ~logical_height:configuration.logical_height with
  |Error message->ignore(destroy_runtime());fail operation Backend message
  |Ok input->Ok{runtime;input;assets=Prismel_next_resources.Assets.create();
      timing=configuration.timing;frame=0L;elapsed=0.;last_clock=Unix.gettimeofday();
      dead=false;snapshots=[];snapshot_bytes=0;scene2_geometry_cache=[];scene2_geometry_candidates=[];
      scene2_batch_cache=[];scene2_quad_cache=[];scene2_quad_payload_cache=[];
      scene2_debug_cache=[];scene2_plan_cache=[];scene2_plan_candidates=[];
      scene2_probe_count=(-1);scene2_probe_density=0;scene2_probe_fingerprint=0;
      scene2_probe_cooldown=0;submissions=[];canvas_keys=[];next_canvas_key=0}
let create (configuration:configuration) =
  let operation="Prismel_next_execution.create" in
  match valid_configuration operation configuration with Error _ as error->error|Ok()->
    let config:Runtime_next_orchestrator.configuration={
      logical_width=configuration.logical_width;logical_height=configuration.logical_height;
      drawable_width=configuration.drawable_width;drawable_height=configuration.drawable_height;
      title=configuration.title;vsync=configuration.vsync}in
    match Runtime_next_orchestrator.create config with Error e->backend operation e|Ok runtime->
      finish_create operation configuration(Window runtime)
        (fun()->Runtime_next_orchestrator.destroy runtime)
let create_offscreen (configuration:configuration)=
  let operation="Prismel_next_execution.create_offscreen"in
  match valid_configuration operation configuration with Error _ as error->error|Ok()->
  match Runtime_next.create_offscreen~width:configuration.drawable_width
      ~height:configuration.drawable_height with
  |Error error->backend operation error
  |Ok runtime->
      let pixel_density=float configuration.drawable_width/.
        float configuration.logical_width in
      let facts={title=configuration.title;
        logical_width=configuration.logical_width;
        logical_height=configuration.logical_height;
        drawable_width=configuration.drawable_width;
        drawable_height=configuration.drawable_height;position=None;pixel_density;
        display_scale=pixel_density;refresh_rate=None;vsync=false}in
      let state={runtime;facts;frames=0L;logical_draws=0L;logical_passes=0L;
        logical_submissions=0L}in
      finish_create operation configuration(Offscreen state)
        (fun()->Runtime_next.destroy_offscreen runtime)
let assets value=value.assets
let snapshot_cache_entries value=List.length value.snapshots
let scene2_geometry_cache_entries value=
  List.length value.scene2_geometry_cache,List.length value.scene2_geometry_candidates
let ensure operation value=if value.dead then fail operation Destroyed"coordinator is destroyed"else Ok()
let release_image_leases leases=
  List.iter Prismel_next_resources.Image.Private.release_snapshot leases
let close_submission submission=
  if submission.submission_state=Open then begin
    submission.submission_state<-Closed;
    release_image_leases submission.image_leases;
    submission.image_leases<-[];
    submission.owner.submissions<-
      List.filter((!=)submission)submission.owner.submissions
  end
let begin_submission value=
  match ensure"Prismel_next_execution.Private.begin_submission"value with
  |Error _ as e->e
  |Ok()->
      let submission={owner=value;submission_state=Open;image_leases=[]}in
      value.submissions<-submission::value.submissions;
      Ok submission
let ensure_submission operation submission=
  if submission.submission_state=Closed then
    fail operation Invalid_argument"submission is already closed"
  else ensure operation submission.owner
let lease_checkpoint=function
  |Copy_image_snapshots->None
  |Retain_image_snapshots submission->Some submission.image_leases
let rollback_leases policy checkpoint=match policy,checkpoint with
  |Copy_image_snapshots,_->()
  |Retain_image_snapshots submission,Some before->
      let rec release=function
        |leases when leases==before->()
        |lease::rest->
            Prismel_next_resources.Image.Private.release_snapshot lease;
            release rest
        |[]->()in
      release submission.image_leases;
      submission.image_leases<-before
  |Retain_image_snapshots _,None->assert false
type stats=Runtime_next_orchestrator.stats={frames:int64;presented:int64;logical_draws:int64;
  logical_passes:int64;logical_submissions:int64;uploaded_bytes:int64;cache_entries:int;
  gpu_timing_supported:bool;gpu_duration_seconds:float;gpu_sample_count:int64;
  retained_plan_builds:int64;retained_plan_hits:int64;retained_plan_misses:int64;
  retained_plan_evictions:int64;retained_plan_executions:int64;
  retained_plan_entries:int;retained_plan_capacity:int}
let stats value=match ensure"Prismel_next_execution.stats"value with Error _ as e->e|Ok()->
  match value.runtime with
  |Window runtime->Result.map_error(fun error->{operation="Prismel_next_execution.stats";
      kind=Backend;message=Ogpu.Error.to_string error})
      (Runtime_next_orchestrator.stats runtime)
  |Offscreen state->
      let native=Runtime_next.offscreen_stats state.runtime in
      Ok{frames=state.frames;presented=0L;logical_draws=state.logical_draws;
        logical_passes=state.logical_passes;
        logical_submissions=state.logical_submissions;
        uploaded_bytes=native.uploaded_bytes;cache_entries=native.mesh_cache_entries;
        gpu_timing_supported=native.gpu_timing_supported;
        gpu_duration_seconds=native.gpu_duration_seconds;
        gpu_sample_count=native.gpu_sample_count;
        retained_plan_builds=native.retained_plan_builds;
        retained_plan_hits=native.retained_plan_hits;
        retained_plan_misses=native.retained_plan_misses;
        retained_plan_evictions=native.retained_plan_evictions;
        retained_plan_executions=native.retained_plan_executions;
        retained_plan_entries=native.retained_plan_entries;
        retained_plan_capacity=native.retained_plan_capacity}
let presentation_facts value=match ensure"Prismel_next_execution.presentation_facts"value with
  |Error _ as e->e
  |Ok()->match value.runtime with
    |Window runtime->(match Runtime_next_orchestrator.facts runtime with
      |Error error->{operation="Prismel_next_execution.presentation_facts";
          kind=Backend;message=Ogpu.Error.to_string error}|>Result.error
      |Ok facts->Ok{title=facts.title;logical_width=facts.logical_width;
          logical_height=facts.logical_height;drawable_width=facts.drawable_width;
          drawable_height=facts.drawable_height;position=facts.position;
          pixel_density=facts.pixel_density;display_scale=facts.display_scale;
          refresh_rate=facts.refresh_rate;vsync=facts.vsync})
    |Offscreen state->Ok state.facts
type diagnostics={active:bool;resource_count:int;cache_entries:int;
  release_queue_pending:int option;release_queue_live_handles:int option;
  release_queue_total_created:int64 option;release_queue_total_released:int64 option}
let native_release_queue=Runtime_next_orchestrator.native_release_queue
let window operation call value=match ensure operation value with Error _ as e->e|Ok()->
  match value.runtime with
  |Offscreen _->fail operation Unsupported"operation requires a presentation window"
  |Window runtime->Result.map_error(fun error->{operation;kind=Backend;
      message=Ogpu.Error.to_string error})(call runtime)
let show value=window"Prismel_next_execution.show"Runtime_next_orchestrator.show value
let hide value=window"Prismel_next_execution.hide"Runtime_next_orchestrator.hide value
let visible value=window"Prismel_next_execution.visible"Runtime_next_orchestrator.visible value
let diagnostics value=
  let active,cache_entries,release_queue_pending,release_queue_live_handles,
      release_queue_total_created,release_queue_total_released=
    match value.runtime with
    |Window runtime->let diagnostic=Runtime_next_orchestrator.diagnostics runtime in
      diagnostic.active,diagnostic.cache_entries,diagnostic.release_queue_pending,
      diagnostic.release_queue_live_handles,diagnostic.release_queue_total_created,
      diagnostic.release_queue_total_released
    |Offscreen state->
      let native=Runtime_next.offscreen_stats state.runtime in
      let release=Runtime_next_orchestrator.native_release_queue()in
      true,native.mesh_cache_entries+native.pipeline_cache_entries,
      Option.map(fun(a,_,_,_)->a)release,Option.map(fun(_,a,_,_)->a)release,
      Option.map(fun(_,_,a,_)->a)release,Option.map(fun(_,_,_,a)->a)release in
  {active=not value.dead&&active;
   resource_count=Prismel_next_resources.Assets.count value.assets;
   cache_entries=cache_entries+List.length value.snapshots+
     List.length value.scene2_geometry_cache+
     List.length value.scene2_geometry_candidates+List.length value.scene2_batch_cache+
     List.length value.scene2_quad_cache+List.length value.scene2_debug_cache+
     List.length value.scene2_plan_cache+List.length value.scene2_plan_candidates+
     List.length value.canvas_keys;
   release_queue_pending;release_queue_live_handles;release_queue_total_created;
   release_queue_total_released}
let snapshot value ~lease_policy ~density source =
  let operation="Prismel_next_execution.lower_scene2"in
  if density<=0 then fail operation Invalid_argument"density must be positive"else
  let find key generation=
    let rec loop before=function
      |[]->None
      |entry::after when entry.snapshot_key=key&&
          entry.snapshot_generation=generation&&entry.snapshot_density=density->
          value.snapshots<-entry::List.rev_append before after;
          Some(entry.snapshot_width,entry.snapshot_height,entry.snapshot_texture)
      |entry::after->loop(entry::before)after in
    loop[]value.snapshots in
  let remove_stale key=
    let kept,removed=List.partition(fun entry->
      entry.snapshot_key<>key||entry.snapshot_density<>density)value.snapshots in
    value.snapshots<-kept;
    value.snapshot_bytes<-value.snapshot_bytes-
      List.fold_left(fun bytes (entry:snapshot_cache_entry)->
        bytes+entry.snapshot_bytes)0 removed in
  let rec trim()=
    if List.length value.snapshots>snapshot_cache_capacity||
       value.snapshot_bytes>snapshot_cache_byte_capacity then
      match List.rev value.snapshots with
      |[]->()
      |oldest::rest->
          value.snapshots<-List.rev rest;
          value.snapshot_bytes<-value.snapshot_bytes-oldest.snapshot_bytes;
          trim()in
  let store key generation width height texture bytes=
    remove_stale key;
    if bytes<=snapshot_cache_entry_byte_capacity then begin
      value.snapshots<-{snapshot_key=key;snapshot_generation=generation;
        snapshot_density=density;snapshot_width=width;snapshot_height=height;
        snapshot_bytes=bytes;snapshot_texture=texture}::value.snapshots;
      value.snapshot_bytes<-value.snapshot_bytes+bytes;
      trim()
    end in
  let finish ?(copy=true) key generation width height pixels =
    match find key generation with
    |Some cached->Ok cached
    |None->
        let sampler:Ogpu.Types.sampler_descriptor={label=Some"scene-image";min_filter=Linear;mag_filter=Linear;
          mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
        let bytes=if copy then Bytes.copy pixels else pixels in
        let texture:Scene_execution.sampled_texture={key=key^":"^string_of_int density;
          levels=[|{width;height;bytes}|];sampler}in
        store key generation width height texture(Bytes.length bytes);
        Ok(width,height,texture)in
  match source with
  |Image image->
      if Prismel_next_resources.Image.destroyed image then
        fail operation Destroyed"image snapshot is destroyed"
      else let key="image:"^string_of_int(Prismel_next_resources.Image.identity image)
      and generation=Prismel_next_resources.Image.generation image in
      (match find key generation with
      |Some cached->Ok cached
      |None->match Prismel_next_resources.Image.Private.borrow_snapshot image with
      |Ok(width,height,borrowed_generation,pixels,lease)->
          let sampler:Ogpu.Types.sampler_descriptor={label=Some"scene-image";min_filter=Linear;mag_filter=Linear;
            mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
          let cacheable=Bytes.length pixels<=snapshot_cache_entry_byte_capacity in
          let bytes=if cacheable then
            Fun.protect
              ~finally:(fun()->Prismel_next_resources.Image.Private.release_snapshot lease)
              (fun()->Bytes.copy pixels)
          else match lease_policy with
            |Retain_image_snapshots submission->
                submission.image_leases<-lease::submission.image_leases;
                pixels
            |Copy_image_snapshots->
                Fun.protect
                  ~finally:(fun()->Prismel_next_resources.Image.Private.release_snapshot lease)
                  (fun()->Bytes.copy pixels)in
          let texture={Scene_execution.key=key^":"^string_of_int density;
            levels=[|{width;height;bytes}|];sampler}in
          if cacheable then
            store key borrowed_generation width height texture(Bytes.length bytes);
          Ok(width,height,texture)
      |Error e->resource operation e)
  |Text text->(match Prismel_next_resources.Text.size text,Prismel_next_resources.Text.pixels text with
      |Ok(width,height),Ok pixels->finish("text:"^Digest.to_hex(Digest.bytes pixels))(Prismel_next_resources.Text.generation text)width height pixels
      |Error e,_|_,Error e->resource operation e)
  |Canvas canvas->
      let key=match List.find_opt(fun(source,_)->source==canvas)value.canvas_keys with Some(_,key)->key|None->
        let key="canvas:"^string_of_int value.next_canvas_key in value.next_canvas_key<-value.next_canvas_key+1;
        value.canvas_keys<-(canvas,key)::value.canvas_keys;if List.length value.canvas_keys>256 then value.canvas_keys<-List.rev(List.tl(List.rev value.canvas_keys));key in
      (match Prismel_next_resources.Canvas.snapshot canvas with
       |Ok(width,height,generation,pixels)->finish~copy:false key generation width height pixels
       |Error e->resource operation e)
let lower_scene2_uncached value ~lease_policy ~density ~resource:resolve ir =
  match ensure"Prismel_next_execution.lower_scene2"value with Error _ as e->e|Ok()->
  let checkpoint=lease_checkpoint lease_policy in
  let release_new_leases()=rollback_leases lease_policy checkpoint in
  let identity={Scene_command.Render_ir.xx=1.;xy=0.;yx=0.;yy=1.;tx=0.;ty=0.}in
  let facts=presentation_facts value|>Result.get_ok in
  let native_projection={Scene_command.Render_ir.xx=2./.float facts.logical_width;xy=0.;yx=0.;
    yy=(-2.)/.float facts.logical_height;tx=(-1.);ty=1.} in
  let render_transform transform=compose_raster native_projection transform in
  let transforms=ref[identity]and clips=ref[(0,0,facts.drawable_width,facts.drawable_height)]
  and blend=ref Alpha and draws=ref[]and number=ref 0 and failure=ref None in
  let point transform x y=transform.Scene_command.Render_ir.xx*.x+.transform.yx*.y+.transform.tx,
    transform.xy*.x+.transform.yy*.y+.transform.ty in
  let clip_live()=let _,_,width,height=List.hd!clips in width>0&&height>0 in
  let geometry_draw number (transform:Scene_command.Render_ir.transform) clip
      (geometry:Scene_command.Render_ir.geometry)=
    (* [Render_ir] owns these arrays and exposes them read-only.  Public Scene
       lowering nevertheless constructs fresh, content-identical arrays every
       frame.  A physical-identity cache consequently re-uploaded every static
       primitive.  Hash first, then compare exactly so collisions cannot reuse
       the wrong geometry.  Retaining at most 256 immutable inputs makes the
       content cache bounded and lets the prepared byte buffers survive those
       fresh IR allocations. *)
    let fingerprint=Hashtbl.hash(geometry.vertices,geometry.indices)in
    let source_bytes=Array.length geometry.vertices*(Sys.word_size/8)+
      Array.length geometry.indices*(Sys.word_size/8)in
    let same vertices indices cached_fingerprint color cached_clip=
      cached_fingerprint=fingerprint&&vertices=geometry.vertices&&indices=geometry.indices&&
      color=geometry.color&&cached_clip=clip in
    match List.find_opt(fun cached->same cached.vertices cached.indices cached.fingerprint cached.color cached.clip)value.scene2_geometry_cache with
    |Some cached when identity_transform(command_transform_of_raster transform)->cached.draw
    |Some cached->{cached.draw with value={cached.draw.value with state={cached.draw.value.state with transform_uniforms=Some(affine_uniforms(command_transform_of_raster transform))}}}
    |None->
        let draw=mesh_of_geometry number(command_transform_of_raster transform)clip
          (command_geometry_of_raster geometry)in
        (* Admission candidates deliberately retain metadata, not the source
           arrays.  Scene construction commonly creates fresh arrays and an
           animated transform can make every prepared mesh unique.  Retaining
           copies for all of those one-hit values promoted a bounded but large
           stream of dead geometry into the major heap.  A matching token only
           authorizes admission; the cache entry below still owns fresh copies
           and every later hit performs an exact array comparison, so a hash
           collision cannot reuse incorrect prepared bytes. *)
        match List.find_opt(fun candidate->
          candidate.candidate_fingerprint=fingerprint&&
          candidate.candidate_vertex_count=Array.length geometry.vertices&&
          candidate.candidate_index_count=Array.length geometry.indices&&
          candidate.candidate_color=geometry.color&&candidate.candidate_clip=clip)
          value.scene2_geometry_candidates with
        |None->
            value.scene2_geometry_candidates<-{
              candidate_vertex_count=Array.length geometry.vertices;
              candidate_index_count=Array.length geometry.indices;
              candidate_fingerprint=fingerprint;
              candidate_source_bytes=source_bytes;
              candidate_color=geometry.color;candidate_clip=clip}::value.scene2_geometry_candidates;
            value.scene2_geometry_candidates<-trim_scene2_entries
              ~capacity:64
              (fun candidate->candidate.candidate_source_bytes)
              value.scene2_geometry_candidates;draw
        |Some candidate->
            value.scene2_geometry_candidates<-List.filter((!=)candidate)value.scene2_geometry_candidates;
            let cached={vertices=Array.copy geometry.vertices;indices=Array.copy geometry.indices;
              fingerprint;source_bytes;color=geometry.color;clip;draw}in
            value.scene2_geometry_cache<-cached::value.scene2_geometry_cache;
            value.scene2_geometry_cache<-trim_scene2_entries
              (fun cached->cached.source_bytes)value.scene2_geometry_cache;draw
    in
  let quad (texture:Scene_execution.sampled_texture)
      (destination:Scene_command.Render_ir.rect) (u0,v0,u1,v1 as uv) =
    let transform=render_transform(List.hd!transforms)in
    let clip=List.hd!clips in
    match List.find_opt(fun cached->cached.quad_texture==texture&&
      cached.quad_destination=destination&&cached.quad_transform=transform&&
      cached.quad_clip=clip&&cached.quad_uv=uv)value.scene2_quad_cache with
    |Some cached->cached.quad_draw
    |None->
    let vertices,indices,mesh_key=match List.find_opt(fun cached->
      cached.payload_destination=destination&&cached.payload_transform=transform&&
      cached.payload_clip=clip&&cached.payload_uv=uv)value.scene2_quad_payload_cache with
    |Some cached->cached.payload_vertices,cached.payload_indices,cached.payload_mesh_key
    |None->
    let x0,y0=point transform destination.Scene_command.Render_ir.x destination.y
    and x1,y0'=point transform(destination.x+.destination.width)destination.y
    and x1',y1=point transform(destination.x+.destination.width)(destination.y+.destination.height)
    and x0',y1'=point transform destination.x(destination.y+.destination.height)in
    let vertices=Bytes.make(68*4)'\000'in
    let put index x y u v=let offset=index*68 in put_float vertices offset x;put_float vertices(offset+8)y;
      put_float vertices(offset+40)1.;Bytes.set_int32_le vertices(offset+48)0xffffffffl;put_float vertices(offset+52)u;put_float vertices(offset+60)v in
    put 0 x0 y0 u0 v0;put 1 x1 y0' u1 v0;put 2 x1' y1 u1 v1;put 3 x0' y1' u0 v1;
    let indices=Bytes.create 24 in List.iteri(fun i n->Bytes.set_int32_le indices(i*4)(Int32.of_int n))[0;1;2;0;2;3];
    let cx,cy,cw,ch=clip in
    let mesh_key=Printf.sprintf
      "quad:%.8g,%.8g,%.8g,%.8g:%.8g,%.8g,%.8g,%.8g,%.8g,%.8g:%d,%d,%d,%d:%.8g,%.8g,%.8g,%.8g"
      destination.x destination.y destination.width destination.height
      transform.xx transform.xy transform.yx transform.yy transform.tx transform.ty
      cx cy cw ch u0 v0 u1 v1 in
    let cached={payload_destination=destination;payload_transform=transform;
      payload_clip=clip;payload_uv=uv;payload_mesh_key=mesh_key;
      payload_vertices=vertices;payload_indices=indices}in
    value.scene2_quad_payload_cache<-cached::value.scene2_quad_payload_cache;
    if List.length value.scene2_quad_payload_cache>256 then
      value.scene2_quad_payload_cache<-List.rev(List.tl(List.rev value.scene2_quad_payload_cache));
    vertices,indices,mesh_key in
    let x,y,w,h=clip in
    let draw={family=Scene2_textured;blend=Alpha;texture=Some texture;auxiliary=None;samples=1;
      value={Scene_execution.mesh={key=mesh_key;vertices;vertex_count=4;indices;index_count=6};state=default_state(x,y,w,h)(x,y,w,h)}}in
    let cached={quad_texture=texture;quad_destination=destination;
      quad_transform=transform;quad_clip=clip;quad_uv=uv;quad_draw=draw}in
    if sampled_texture_bytes texture<=snapshot_cache_entry_byte_capacity then begin
      value.scene2_quad_cache<-cached::value.scene2_quad_cache;
      if List.length value.scene2_quad_cache>1024 then
        value.scene2_quad_cache<-List.rev(List.tl(List.rev value.scene2_quad_cache))
    end;
    draw in
  let image (command:Scene_command.Render_ir.image) = match resolve command.Scene_command.Render_ir.resource_id with None->failure:=Some"resource id is unbound"|Some source->
    match snapshot value~lease_policy~density source with Error e->failure:=Some(Format.asprintf"%a"pp_error e)|Ok(width,height,texture)->
      let s=command.source in if width<=0||height<=0 then failure:=Some"resource extent is invalid"else
      let u0=s.x/.float width and v0=s.y/.float height and u1=(s.x+.s.width)/.float width and v1=(s.y+.s.height)/.float height in
      let draw=quad texture command.destination(u0,v0,u1,v1)in
      draws:={draw with blend= !blend}::!draws;incr number in
  Array.iter(fun command->if!failure=None then match command with
    |Scene_command.Render_ir.Clear _->()
    |Set_blend mode->blend:=(match mode with Scene_command.Render_ir.Replace->Replace
        |Copy->Replace|Alpha|Source_over->Alpha|Add->Add|Multiply->Multiply
        |Screen->Screen|Subtract->Subtract)
    |Push_transform transform->transforms:=compose_raster(List.hd!transforms)transform::!transforms
    |Pop_transform->(match!transforms with _::(_::_ as rest)->transforms:=rest|_->())
    |Push_clip rect->let px,py,pw,ph=List.hd!clips and x=int_of_float(floor rect.x)
      and y=int_of_float(floor rect.y)and right=int_of_float(ceil(rect.x+.rect.width))
      and bottom=int_of_float(ceil(rect.y+.rect.height))in
      let x=min(px+pw)(max px x)and y=min(py+ph)(max py y)in
      let right=min(px+pw)right and bottom=min(py+ph)bottom in
      clips:=(x,y,max 0(right-x),max 0(bottom-y))::!clips
    |Pop_clip->(match!clips with _::(_::_ as rest)->clips:=rest|_->())
    |Geometry geometry->if clip_live()then(
        let draw=geometry_draw!number(render_transform(List.hd!transforms))(List.hd!clips)geometry in
        draws:={draw with blend= !blend}::!draws;incr number)
    |Debug_text debug->if clip_live()then
        let transform=render_transform(List.hd!transforms)and clip=List.hd!clips in
        let draw=match List.find_opt(fun cached->cached.debug_source=debug&&
          cached.debug_transform=transform&&cached.debug_clip=clip)
          value.scene2_debug_cache with
        |Some cached->cached.debug_draw
        |None->
            let geometry=debug_text_geometry(command_transform_of_raster transform)
              Command.{x=debug.x;y=debug.y;text=debug.text;color=debug.color}in
            let draw=if Array.length geometry.indices=0 then None else
              Some(mesh_of_geometry!number(command_transform_of_raster identity)clip geometry)in
            value.scene2_debug_cache<-{debug_source=debug;debug_transform=transform;
              debug_clip=clip;debug_draw=draw}::value.scene2_debug_cache;
            if List.length value.scene2_debug_cache>256 then
              value.scene2_debug_cache<-List.rev(List.tl(List.rev value.scene2_debug_cache));
            draw in
        Option.iter(fun draw->draws:={draw with blend= !blend}::!draws;incr number)draw
    |Image command->if clip_live()then image command
    |Glyphs glyphs->if clip_live()&&Array.length glyphs.glyphs>0 then match resolve glyphs.resource_id with None->failure:=Some"glyph resource id is unbound"|Some source->
        match snapshot value~lease_policy~density source with Error e->failure:=Some(Format.asprintf"%a"pp_error e)|Ok(width,height,texture)->
          Array.iter(fun(glyph:Scene_command.Render_ir.glyph)->
            let destination={Scene_command.Render_ir.x=glyph.x;y=glyph.y;width=float width;height=float height}in
            let draw=quad texture destination(0.,0.,1.,1.)in
            draws:={draw with blend= !blend}::!draws;incr number)glyphs.glyphs)
    (Scene_command.Render_ir.Private.commands_readonly ir);
  match!failure with Some message->release_new_leases();fail"Prismel_next_execution.lower_scene2"Resource message
  |None->Ok(batch_scene2_draws ~cache:value.scene2_batch_cache
      ~set_cache:(fun cache->value.scene2_batch_cache<-cache)(List.rev!draws))
let scene2_plan_source_bytes commands=
  Array.fold_left(fun total->function
    |Scene_command.Render_ir.Geometry g->total+Array.length g.vertices*(Sys.word_size/8)+
      Array.length g.indices*(Sys.word_size/8)
    |Glyphs g->total+Array.length g.glyphs*24
    |Debug_text d->total+String.length d.text
    |_->total+32)0 commands
let same_scene2_resource_stamps left right=
  let rec loop left right=match left,right with
  |[],[]->true
  |Text_stamp(id,a,g)::xs,Text_stamp(id',b,g')::ys->
      id=id'&&a==b&&g=g'&&loop xs ys
  |Image_stamp(id,a,g)::xs,Image_stamp(id',b,g')::ys->
      id=id'&&a==b&&g=g'&&loop xs ys
  |Canvas_stamp(id,a,g)::xs,Canvas_stamp(id',b,g')::ys->
      id=id'&&a==b&&g=g'&&loop xs ys
  |_->false in loop left right
let scene2_resource_stamps resolve commands=
  let ids=ref[]and missing=ref false in
  Array.iter(function
    |Scene_command.Render_ir.Image image->ids:=image.resource_id::!ids
    |Glyphs glyphs->ids:=glyphs.resource_id::!ids|_->())commands;
  let stamps=List.filter_map(fun id->
    match resolve id with
    |None->missing:=true;None
    |Some(Image image)->if Prismel_next_resources.Image.destroyed image then(
        missing:=true;None)else
      Some(Image_stamp(id,image,Prismel_next_resources.Image.generation image))
    |Some(Text text)->if Prismel_next_resources.Text.destroyed text then(
        missing:=true;None)else
      Some(Text_stamp(id,text,Prismel_next_resources.Text.generation text))
    |Some(Canvas canvas)->if Prismel_next_resources.Canvas.destroyed canvas then(
        missing:=true;None)else
      Some(Canvas_stamp(id,canvas,Prismel_next_resources.Canvas.generation canvas)))
    (List.sort_uniq Int.compare!ids)in
  not!missing,stamps
let lower_scene2_with_policy value ~lease_policy ~density ~resource:resolve ir =
  if value.dead then lower_scene2_uncached value~lease_policy~density~resource:resolve ir else
  let commands=Scene_command.Render_ir.Private.commands_readonly ir in
  let fingerprint=ref(Hashtbl.hash commands)and command_count=Array.length commands in
  let mix value=fingerprint:=(!fingerprint*65599)lxor value in
  for index=0 to command_count-1 do match Array.unsafe_get commands index with
    |Scene_command.Render_ir.Push_transform transform->
      mix(Int64.to_int(Int64.bits_of_float transform.xx));
      mix(Int64.to_int(Int64.bits_of_float transform.xy));
      mix(Int64.to_int(Int64.bits_of_float transform.yx));
      mix(Int64.to_int(Int64.bits_of_float transform.yy));
      mix(Int64.to_int(Int64.bits_of_float transform.tx));
      mix(Int64.to_int(Int64.bits_of_float transform.ty))
    |Geometry geometry->mix(Hashtbl.hash geometry.vertices);
      mix(Hashtbl.hash geometry.indices);mix(Int32.to_int geometry.color)
    |_->()
  done;
  let fingerprint= !fingerprint in
  let same_probe=value.scene2_probe_count=command_count&&
    value.scene2_probe_density=density in
  if same_probe&&value.scene2_probe_cooldown>0 then(
    value.scene2_probe_cooldown<-value.scene2_probe_cooldown-1;
    lower_scene2_uncached value~lease_policy~density~resource:resolve ir)else
  if same_probe&&value.scene2_probe_fingerprint<>fingerprint then(
    value.scene2_probe_fingerprint<-fingerprint;value.scene2_probe_cooldown<-120;
    lower_scene2_uncached value~lease_policy~density~resource:resolve ir)else begin
  value.scene2_probe_count<-command_count;value.scene2_probe_density<-density;
  value.scene2_probe_fingerprint<-fingerprint;
  let cacheable,resources=scene2_resource_stamps resolve commands in
  let facts=presentation_facts value|>Result.get_ok in
  let extent=facts.logical_width,facts.logical_height,
    facts.drawable_width,facts.drawable_height in
  let exact plan=plan.plan_fingerprint=fingerprint&&
    plan.plan_command_count=command_count&&plan.plan_density=density&&
    plan.plan_extent=extent&&
    same_scene2_resource_stamps plan.plan_resources resources&&
    Scene_command.Render_ir.Private.commands_readonly plan.plan_ir=commands in
  if cacheable then match List.find_opt exact value.scene2_plan_cache with
  |Some plan->Ok plan.plan_draws
  |None->
    (match lower_scene2_uncached value~lease_policy~density~resource:resolve ir with
    |Error _ as error->error
    |Ok draws as result->
      if List.exists(fun draw->match draw.texture with
        |Some texture->sampled_texture_bytes texture>snapshot_cache_entry_byte_capacity
        |None->false)draws then result else
      let candidate=List.find_opt(fun candidate->
        candidate.candidate_plan_fingerprint=fingerprint&&
        candidate.candidate_plan_command_count=command_count&&
        candidate.candidate_plan_density=density&&
        candidate.candidate_plan_extent=extent&&
        same_scene2_resource_stamps candidate.candidate_plan_resources resources)
        value.scene2_plan_candidates in
      (match candidate with
      |None->value.scene2_plan_candidates<-{
          candidate_plan_fingerprint=fingerprint;candidate_plan_command_count=command_count;
          candidate_plan_density=density;
          candidate_plan_extent=extent;candidate_plan_resources=resources}::
          value.scene2_plan_candidates;
        value.scene2_plan_candidates<-trim_scene2_entries~capacity:64(fun _->64)
          value.scene2_plan_candidates
      |Some candidate->
        value.scene2_plan_candidates<-List.filter((!=)candidate)value.scene2_plan_candidates;
        let plan={plan_fingerprint=fingerprint;plan_command_count=command_count;
          plan_source_bytes=scene2_plan_source_bytes commands;plan_density=density;
          plan_extent=extent;plan_resources=resources;
          plan_ir=ir;plan_draws=draws}in
        value.scene2_plan_cache<-trim_scene2_entries~capacity:16
          (fun plan->plan.plan_source_bytes)(plan::value.scene2_plan_cache));result)
  else lower_scene2_uncached value~lease_policy~density~resource:resolve ir end
let lower_scene2 value ~density ~resource ir=
  lower_scene2_with_policy value~lease_policy:Copy_image_snapshots
    ~density~resource ir
let mb_to_input=function Left->Runtime_next_input.Left|Middle->Middle|Right->Right|X1->X1|X2->X2
let mod_to_input=function Shift->Runtime_next_input.Shift|Control->Control|Alt->Alt|Meta->Meta|Num_lock->Num_lock|Caps_lock->Caps_lock|Scroll_lock->Scroll_lock
let to_input=function Pointer_moved(x,y)->Runtime_next_input.Pointer_moved(x,y)
  |Pointer_pressed(b,x,y)->Pointer_pressed(mb_to_input b,x,y)|Pointer_released(b,x,y)->Pointer_released(mb_to_input b,x,y)
  |Pointer_cancelled b->Pointer_cancelled(mb_to_input b)|Wheel(x,y)->Wheel(x,y)
  |Key_pressed k->Key_pressed{Runtime_next_input.key=k.name;modifiers=List.map mod_to_input k.modifiers;repeat=k.repeat}
  |Key_released k->Key_released{Runtime_next_input.key=k.name;modifiers=List.map mod_to_input k.modifiers;repeat=k.repeat}
  |Text_input s->Text_input s|Text_editing{text;start;length}->Text_editing{text;start;length}|Focus_lost->Focus_lost|Focus_gained->Focus_gained
  |Visibility_changed x->Visibility_changed x|Quit->Quit|Resized(x,y)->Resized(x,y)|File_dropped{name;contents}->File_dropped{name;contents}
let push_event value event=match ensure"Prismel_next_execution.push_event"value with Error _ as e->e|Ok()->
  (match Runtime_next_input.push value.input(to_input event)with Ok()->Ok()|Error message->fail"Prismel_next_execution.push_event"Backend message)
let resize value ~logical_width ~logical_height ~drawable_width ~drawable_height =
  match ensure"Prismel_next_execution.resize"value with Error _ as e->e|Ok()->
  let resized=match value.runtime with
  |Window runtime->Runtime_next_orchestrator.resize runtime~logical_width~logical_height
      ~drawable_width~drawable_height
  |Offscreen state->match Runtime_next.resize_offscreen state.runtime
      ~width:drawable_width~height:drawable_height with
    |Error _ as error->error
    |Ok()->let pixel_density=float drawable_width/.float logical_width in
      state.facts<-{state.facts with logical_width;logical_height;drawable_width;
        drawable_height;pixel_density;display_scale=pixel_density};Ok()in
  match resized with
  |Ok()->push_event value(Resized(logical_width,logical_height))
  |Error e->backend"Prismel_next_execution.resize"e
let mod_of_input=function Runtime_next_input.Shift->Shift|Control->Control|Alt->Alt|Meta->Meta|Num_lock->Num_lock|Caps_lock->Caps_lock|Scroll_lock->Scroll_lock
let event_of_input=function Runtime_next_input.Pointer_moved(x,y)->Pointer_moved(x,y)|Pointer_pressed(b,x,y)->Pointer_pressed((match b with Left->Left|Middle->Middle|Right->Right|X1->X1|X2->X2),x,y)
  |Pointer_released(b,x,y)->Pointer_released((match b with Left->Left|Middle->Middle|Right->Right|X1->X1|X2->X2),x,y)
  |Pointer_cancelled b->Pointer_cancelled(match b with Left->Left|Middle->Middle|Right->Right|X1->X1|X2->X2)
  |Wheel(x,y)->Wheel(x,y)|Key_pressed k->Key_pressed{name=k.key;modifiers=List.map mod_of_input k.modifiers;repeat=k.repeat}|Key_released k->Key_released{name=k.key;modifiers=List.map mod_of_input k.modifiers;repeat=k.repeat}
  |Text_input s->Text_input s|Text_editing{text;start;length}->Text_editing{text;start;length}|Focus_lost->Focus_lost|Focus_gained->Focus_gained
  |Visibility_changed x->Visibility_changed x|Quit->Quit|Resized(x,y)->Resized(x,y)|File_dropped{name;contents}->File_dropped{name;contents}
let step_core ?after_prepare ?clear ?identity ?version value draws=
  let after_prepare=Option.value after_prepare ~default:Fun.id in
  match ensure"Prismel_next_execution.step"value with Error _ as e->e|Ok()->
  Runtime_next_input.begin_frame value.input;
  match presentation_facts value with Error _ as error->after_prepare();error|Ok f->
    let family=function Scene2->Runtime_next_orchestrator.Scene2|Scene2_textured->Scene2_textured|Scene3->Scene3
      |Scene3_textured->Scene3_textured|Scene3_shadow->Scene3_shadow|Scene3_stencil->Scene3_stencil
      |Scene3_textured_stencil->Scene3_textured_stencil|Scene3_shadow_stencil->Scene3_shadow_stencil in
    let blend=function Replace->Runtime_next_orchestrator.Replace|Alpha->Alpha|Add->Add
      |Multiply->Multiply|Screen->Screen|Subtract->Subtract in
    let replayed=match value.runtime,identity,version with
      |Window runtime,Some identity,Some version->
          Runtime_next_orchestrator.replay_retained ?clear ~identity ~version runtime
      |_->Ok None in
    let rendered=match replayed with
    |Error error->after_prepare();Error error
    |Ok(Some presented)->after_prepare();Ok presented
    |Ok None->
    let draws=List.map(fun x->let draw=x.value in let state=draw.Scene_execution.state in
      let viewport=match state.viewport with _,_,w,h when w<0||h<0->0,0,f.logical_width,f.logical_height|x->x in
      let scissor=match state.scissor with _,_,w,h when w<0||h<0->0,0,f.logical_width,f.logical_height|x->x in
      let draw=if viewport=state.viewport&&scissor=state.scissor then draw else
        {draw with Scene_execution.state={state with viewport;scissor}}in
      {Runtime_next_orchestrator.family=family x.family;blend=blend x.blend;texture=x.texture;
        auxiliary=x.auxiliary;samples=x.samples;draw})draws in
    match value.runtime with
    |Window runtime->(match identity,version with
      |None,None->Runtime_next_orchestrator.render_prepared ~after_prepare ?clear runtime draws
      |Some identity,Some version->Runtime_next_orchestrator.render_retained ~after_prepare ?clear
          ~identity~version runtime draws
      |_->after_prepare();Error(Ogpu.Error.make"Prismel_next_execution.step"Ogpu.Error.Invalid_argument
          "prepared identity and version must be supplied together"))
    |Offscreen state->
      let portable=List.map(fun draw->
        let family=match draw.Runtime_next_orchestrator.family with
        |Runtime_next_orchestrator.Scene2->Scene_execution.Scene2
        |Scene2_textured->Scene2_textured|Scene3->Scene3
        |Scene3_textured->Scene3_textured|Scene3_shadow->Scene3_shadow
        |Scene3_stencil->Scene3_stencil
        |Scene3_textured_stencil->Scene3_textured_stencil
        |Scene3_shadow_stencil->Scene3_shadow_stencil in
        let blend=match draw.blend with Runtime_next_orchestrator.Replace->Ogpu.Pipeline.Replace
        |Alpha->Alpha|Add->Add|Multiply->Multiply|Screen->Screen|Subtract->Subtract in
        family,blend,draw.texture,draw.auxiliary,draw.samples,draw.draw)draws in
      let result=match identity,version with
      |None,None->Runtime_next.render_offscreen ~after_prepare ?clear state.runtime portable
      |Some identity,Some version->Runtime_next.render_offscreen_prepared ~after_prepare ?clear
          ~identity~version state.runtime portable
      |_->after_prepare();Error(Ogpu.Error.make"Prismel_next_execution.step"Ogpu.Error.Invalid_argument
          "prepared identity and version must be supplied together")in
      (match result with Ok _->state.frames<-Int64.succ state.frames;
        state.logical_draws<-Int64.add state.logical_draws
          (Int64.of_int(List.length draws));
        state.logical_passes<-Int64.succ state.logical_passes;
        state.logical_submissions<-Int64.succ state.logical_submissions
      |Error _->());result in
    match rendered with Error e->backend"Prismel_next_execution.step"e|Ok _->
      let now=Unix.gettimeofday()in let dt=match value.timing with Fixed dt->dt|Variable->max 0.(now-.value.last_clock)in
      value.last_clock<-now;value.elapsed<-value.elapsed+.dt;value.frame<-Int64.succ value.frame;
      let events=List.map event_of_input(Runtime_next_input.drain value.input)and input=Runtime_next_input.snapshot value.input in
      Ok{frame=value.frame;time=value.elapsed;dt;logical_width=f.logical_width;logical_height=f.logical_height;
        drawable_width=f.drawable_width;drawable_height=f.drawable_height;pixel_scale=f.pixel_density;
        events;pointer=input.pointer;mouse_delta=input.mouse_delta;wheel_delta=input.wheel_delta;dropped_events=input.dropped_events}
let step ?clear value draws=step_core ?clear value draws
let lower_scene2_submission submission ~density ~resource ir=
  match ensure_submission"Prismel_next_execution.Private.lower_scene2"submission with
  |Error _ as e->close_submission submission;e
  |Ok()->
      let protected_resource id=try resource id with
        |(Out_of_memory|Stack_overflow|Sys.Break)as exn->raise exn
        |exn->raise(Resource_resolver_raised exn)in
      (try match lower_scene2_with_policy submission.owner
          ~lease_policy:(Retain_image_snapshots submission)~density
          ~resource:protected_resource ir with
       |Ok draws->Ok{batch_owner=submission;batch_draws=draws}
       |Error _ as error->close_submission submission;error
       with Resource_resolver_raised exn->
         close_submission submission;
         fail"Prismel_next_execution.Private.lower_scene2"Resource
           ("resource resolver raised: "^Printexc.to_string exn)
       |exn->close_submission submission;raise exn)
let adopt_draws submission draws=
  match ensure_submission"Prismel_next_execution.Private.adopt_draws"submission with
  |Error _ as error->close_submission submission;error
  |Ok()->Ok{batch_owner=submission;batch_draws=draws}
let step_submission ?clear ?identity ?version submission batches=
  match ensure_submission"Prismel_next_execution.Private.step"submission with
  |Error _ as e->close_submission submission;e
  |Ok()->Fun.protect~finally:(fun()->close_submission submission)
      (fun()->
        if List.exists(fun batch->batch.batch_owner!=submission)batches then
          fail"Prismel_next_execution.Private.step"Invalid_argument
            "draw batch belongs to another submission"
        else
          let reversed=List.fold_left(fun reversed batch->
            List.rev_append batch.batch_draws reversed)[]batches in
          step_core ~after_prepare:(fun()->close_submission submission)
            ?clear ?identity ?version submission.owner(List.rev reversed))
let capture value=match ensure"Prismel_next_execution.capture"value with Error _ as e->e|Ok()->
  match presentation_facts value with Error _ as error->error|Ok facts->
  let captured=match value.runtime with
  |Window runtime->Runtime_next_orchestrator.capture runtime
      ~bytes_per_row:(facts.drawable_width*4)
  |Offscreen state->Runtime_next.read_offscreen state.runtime
      ~bytes_per_row:(facts.drawable_width*4)in
  match captured with Ok x->Ok x|Error e->backend"Prismel_next_execution.capture"e
let capture_into value~destination=
  match ensure"Prismel_next_execution.capture_into"value with Error _ as e->e|Ok()->
  match presentation_facts value with Error _ as error->error|Ok facts->
  let captured=match value.runtime with
  |Window runtime->Runtime_next_orchestrator.capture_into runtime
      ~bytes_per_row:(facts.drawable_width*4)~destination
  |Offscreen state->Runtime_next.read_offscreen_into state.runtime
      ~bytes_per_row:(facts.drawable_width*4)~destination in
  match captured with Ok()->Ok()|Error e->backend"Prismel_next_execution.capture_into"e
let destroy value=if value.dead then Ok()else(
  List.iter close_submission value.submissions;
  match Prismel_next_resources.Assets.destroy value.assets with Error e->resource"Prismel_next_execution.destroy"e|Ok()->
    value.snapshots<-[];value.snapshot_bytes<-0;value.scene2_geometry_cache<-[];value.scene2_batch_cache<-[];
    value.scene2_quad_cache<-[];
    value.scene2_quad_payload_cache<-[];
    value.scene2_debug_cache<-[];
    value.scene2_plan_cache<-[];value.scene2_plan_candidates<-[];
    value.scene2_geometry_candidates<-[];value.canvas_keys<-[];value.dead<-true;
    let destroyed=match value.runtime with
    |Window runtime->Runtime_next_orchestrator.destroy runtime
    |Offscreen state->Runtime_next.destroy_offscreen state.runtime in
    match destroyed with Ok()->Ok()|Error e->backend"Prismel_next_execution.destroy"e)
module Private=struct
  type nonrec submission=submission
  type nonrec batch=batch
  let begin_submission=begin_submission
  let lower_scene2=lower_scene2_submission
  let adopt_draws=adopt_draws
  let step=step_submission
  let cancel=close_submission
  let draw_family_blend draw=draw.family,draw.blend
end
let run configuration body ~on_stop = match create configuration with Error _ as e->e|Ok value->
  let outcome=try body value with exn->fail"Prismel_next_execution.run"Backend(Printexc.to_string exn)in
  let stopped=try on_stop value with exn->fail"Prismel_next_execution.on_stop"Backend(Printexc.to_string exn)in
  let closed=destroy value in match outcome,stopped,closed with
  |(Error _ as e),_,_->e
  |Ok _,(Error _ as e),_->e
  |Ok _,Ok(),(Error _ as e)->e
  |Ok x,Ok(),Ok()->Ok x
