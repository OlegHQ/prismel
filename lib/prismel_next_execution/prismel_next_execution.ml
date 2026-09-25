type error_kind = Invalid_argument | Unsupported | Backend | Resource | Destroyed
type error = { operation:string; kind:error_kind; message:string }
let pp_error formatter value =
  Format.fprintf formatter "%s: %s" value.operation value.message
let fail operation kind message = Error { operation; kind; message }
let backend operation value =
  Error { operation; kind=Backend; message=Ogpu.Error.to_string value }
let resource operation value =
  Error { operation; kind=Resource; message=Format.asprintf "%a" Prismel_next_resources.pp_error value }

type configuration = { logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; title:string;vsync:bool }
let default_configuration = { logical_width=640; logical_height=480;
  drawable_width=640; drawable_height=480; title="Prismel";vsync=true }
type family = Scene_execution.pipeline_family = Scene2 | Scene2_textured | Scene3 | Scene3_points | Scene3_textured | Scene3_shadow |
  Scene3_stencil | Scene3_textured_stencil | Scene3_shadow_stencil | Ui
type blend = Ogpu.Pipeline.blend = Replace | Alpha | Add | Multiply | Screen | Subtract
type draw = { family:family; blend:blend; texture:Scene_execution.sampled_texture option;
  auxiliary:Scene_execution.auxiliary_resource option;samples:int;value:Scene_execution.draw }
type cached_scene2_geometry={vertices:float array;indices:int array;color:int32;
  clip:int*int*int*int;uniform_bytes:bytes;mutable used_frame:int;draw:draw}
(* Content-equal geometries drawn twice in one frame need two entries. *)
type scene2_geometry_bucket={mutable entries:cached_scene2_geometry list;mutable bucket_bytes:int}
type scene2_geometry_candidate={candidate_vertex_count:int;
  candidate_index_count:int;candidate_color:int32;
  candidate_clip:int*int*int*int}
type cached_scene2_batch={batch_fingerprint:int;batch_draw_count:int;
  batch_source_bytes:int;batch_draw:draw}
module Int_table=Lru.Make(Int)
module Structural_key(T:sig type t end)=struct type t=T.t let equal=(=) let hash=Hashtbl.hash end
(* texture (physical), destination, transform, clip, uv, framebuffer *)
module Quad_key=struct
  type t=Scene_execution.sampled_texture*Scene_command.Render_ir.rect*
    Scene_command.Render_ir.transform*(int*int*int*int)*(float*float*float*float)*(int*int*int*int)
  let equal ((t,d,x,c,u,f):t) ((t',d',x',c',u',f'):t)=t==t'&&d=d'&&x=x'&&c=c'&&u=u'&&f=f'
  let hash ((t,d,x,c,u,f):t)=Hashtbl.hash(t.Scene_execution.key,d,x,c,u,f) end
module Quad_table=Lru.Make(Quad_key)
module Quad_payload_table=Lru.Make(Structural_key(struct
  type t=Scene_command.Render_ir.rect*Scene_command.Render_ir.transform*(int*int*int*int)*(float*float*float*float) end))
type cached_scene2_quad_payload={payload_mesh_key:string;payload_vertices:bytes;payload_indices:bytes}
module Debug_table=Lru.Make(Structural_key(struct
  type t=Scene_command.Render_ir.debug_text*Scene_command.Render_ir.transform*(int*int*int*int) end))
type resource=Image of Prismel_next_resources.Image.t|Text of Prismel_next_resources.Text.t
  |Canvas of Prismel_next_resources.Canvas.t
type scene2_resource_stamp=
  |Image_stamp of int*Prismel_next_resources.Image.t*int
  |Text_stamp of int*Prismel_next_resources.Text.t*int
  |Canvas_stamp of int*Prismel_next_resources.Canvas.t*int
type cached_scene2_plan={mutable plan_ir_id:int;plan_command_count:int;
  plan_source_bytes:int;plan_density:int;
  plan_extent:int*int*int*int;plan_resources:scene2_resource_stamp list;
  mutable plan_ir:Scene_command.Render_ir.t;plan_draws:draw list}
let prepared_draw ~family ?(blend=Replace) ?texture ?auxiliary ?(samples=1) value =
  {family;blend;texture;auxiliary;samples;value}

let default_state viewport scissor = { Scene_execution.viewport; scissor;
  cull=Ogpu.Render_pass.Cull_none; depth_compare=Ogpu.Render_pass.Always;
  depth_write=false; depth_load=Ogpu.Render_pass.Load; depth_clear=1.;
  transform_uniforms=None; stencil_state=None; stencil_load=Ogpu.Render_pass.Load;
  stencil_clear=0 }
let put_float bytes offset value = Bytes.set_int64_le bytes offset (Int64.bits_of_float value)
(* Scene2 keeps affine coefficients as f64 through command lowering.  The
   native execution boundary narrows these values to the six-f32 Metal ABI. *)
let identity_affine_uniforms=let bytes=Bytes.make 24 '\000'in
  Bytes.set_int32_le bytes 0(Int32.bits_of_float 1.);
  Bytes.set_int32_le bytes 16(Int32.bits_of_float 1.);bytes
module Command = Scene_command.Render_ir
let write_affine bytes (transform:Scene_command.Render_ir.transform)=
  let put index value=Bytes.set_int32_le bytes(index*4)(Int32.bits_of_float value)in
  put 0 transform.xx;put 1 transform.yx;put 2 transform.tx;
  put 3 transform.xy;put 4 transform.yy;put 5 transform.ty
let affine_uniforms (transform:Command.transform)=
  if transform.xx=1.&&transform.xy=0.&&transform.yx=0.&&transform.yy=1.&&
    transform.tx=0.&&transform.ty=0. then identity_affine_uniforms else
  let bytes=Bytes.make 24 '\000'in
  write_affine bytes {Scene_command.Render_ir.xx=transform.xx;xy=transform.xy;
    yx=transform.yx;yy=transform.yy;tx=transform.tx;ty=transform.ty};bytes
let identity_transform (transform:Command.transform)=
  transform.xx=1.&&transform.xy=0.&&transform.yx=0.&&transform.yy=1.&&
  transform.tx=0.&&transform.ty=0.
let scene2_vertex_stride=24
(* Diagnostic baseline for measuring the existing per-geometry preparation. *)
let dense_scene2_runs = Sys.getenv_opt "PRISMEL_SCENE2_DENSE_RUNS" <> Some "0"
let mesh_of_geometry number transform ~viewport clip (geometry:Command.geometry) =
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
  let vx,vy,vw,vh=viewport and sx,sy,sw,sh=clip in
  { family=Scene2;blend=Alpha;texture=None;auxiliary=None;samples=1; value={Scene_execution.mesh={key=Printf.sprintf "ir-%Ld-%d" 0L number;
      vertices;vertex_count=count;indices;index_count=Array.length geometry.indices;primitive=Triangle_list};
      state={(default_state (vx,vy,vw,vh) (sx,sy,sw,sh))with
        transform_uniforms=(if identity_transform transform then None else Some(affine_uniforms transform))}} }

(* Dense runs already share transform, clip, blend, and painter order. Pack
   their per-vertex colors directly instead of constructing and caching one
   temporary native draw per color, then copying all those draws into a batch.
   Two passes, O(vertices + indices + commands) work and final-buffer storage.
   Small runs retain the existing independently cached geometry path. *)
let mesh_of_geometry_run number transform ~viewport clip commands first stop =
  let vertex_count=ref 0 and index_count=ref 0 in
  for i=first to stop-1 do match commands.(i) with
    |Scene_command.Render_ir.Geometry g ->
        vertex_count:= !vertex_count+Array.length g.vertices/2;
        index_count:= !index_count+Array.length g.indices
    |_->assert false
  done;
  let vertices=Bytes.make (!vertex_count*scene2_vertex_stride) '\000'
  and indices=Bytes.create (!index_count*4) in
  let vertex_offset=ref 0 and index_offset=ref 0 in
  for i=first to stop-1 do match commands.(i) with
    |Scene_command.Render_ir.Geometry g ->
        let count=Array.length g.vertices/2 in
        for j=0 to count-1 do
          let offset=(!vertex_offset+j)*scene2_vertex_stride in
          put_float vertices offset g.vertices.(j*2);
          put_float vertices (offset+8) g.vertices.(j*2+1);
          Bytes.set_int32_le vertices (offset+16) g.color
        done;
        for j=0 to Array.length g.indices-1 do
          Bytes.set_int32_le indices ((!index_offset+j)*4)
            (Int32.of_int (g.indices.(j)+ !vertex_offset))
        done;
        vertex_offset:= !vertex_offset+count;
        index_offset:= !index_offset+Array.length g.indices
    |_->assert false
  done;
  {family=Scene2;blend=Alpha;texture=None;auxiliary=None;samples=1;
   value={Scene_execution.mesh={key=Printf.sprintf "ir-run-%d" number;
     vertices;vertex_count= !vertex_count;indices;index_count= !index_count;primitive=Triangle_list};
     state={(default_state viewport clip) with
       transform_uniforms=(if identity_transform transform then None
         else Some (affine_uniforms transform))}}}
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
let compose_raster (a:Scene_command.Render_ir.transform) (b:Scene_command.Render_ir.transform)=
  if b.xx=1.&&b.xy=0.&&b.yx=0.&&b.yy=1.&&b.tx=0.&&b.ty=0. then a
  else if a.xx=1.&&a.xy=0.&&a.yx=0.&&a.yy=1.&&a.tx=0.&&a.ty=0. then b
  else {Scene_command.Render_ir.xx=a.xx*.b.xx+.a.yx*.b.xy;
  xy=a.xy*.b.xx+.a.yy*.b.xy;yx=a.xx*.b.yx+.a.yx*.b.yy;
  yy=a.xy*.b.yx+.a.yy*.b.yy;tx=a.xx*.b.tx+.a.yx*.b.ty+.a.tx;
  ty=a.xy*.b.tx+.a.yy*.b.ty+.a.ty}
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
       first.family<>cached.batch_draw.family || first.blend<>cached.batch_draw.blend ||
       first.samples<>cached.batch_draw.samples ||
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

let batch_scene2_draws ~cache draws =
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
        (match Int_table.find cache fingerprint with
         |cached when batch_matches group cached-> [cached.batch_draw]
         |_|exception Not_found->
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
          vertices; vertex_count; indices; index_count;
          primitive=first.value.mesh.primitive } in
        let draw={ first with value={first.value with mesh} } in
        let cached={batch_fingerprint=fingerprint;
          batch_draw_count=List.length group;
          batch_source_bytes=Bytes.length vertices+Bytes.length indices;
          batch_draw=draw} in
        Int_table.add cache~bytes:cached.batch_source_bytes fingerprint cached;
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
type offscreen_runtime={runtime:Runtime_next.offscreen;lease_shared:bool;
  mutable facts:presentation_facts;mutable frames:int64;
  mutable logical_draws:int64;mutable logical_passes:int64;
  mutable logical_submissions:int64}
type runtime=Window of Runtime_next_orchestrator.t|Offscreen of offscreen_runtime
type submission_state=Open|Closed
exception Resource_resolver_raised of exn
type snapshot_cache_entry={mutable snapshot_generation:int;
  snapshot_width:int;snapshot_height:int;
  mutable snapshot_texture:Scene_execution.sampled_texture}
(* key, density *)
module Snapshot_table=Lru.Make(Structural_key(struct type t=string*int end))
module Segment_table=Lru.Make(struct type t=int64 let equal=Int64.equal let hash=Hashtbl.hash end)
type retained_scene2_segment={segment_version:int64;
  segment_density:int;segment_width:int;segment_height:int;
  segment_draws:draw list}
let retained_scene2_segment_capacity=256
let retained_scene2_segment_byte_capacity=64*1024*1024
let snapshot_cache_capacity=256
let snapshot_cache_byte_capacity=64*1024*1024
(* Full-window snapshots change frequently and already have bounded double
   buffers in [Image].  Keeping entries below 1 MiB admits UI/text assets but
   deliberately leaves a 640x480 RGBA frame (1,228,800 bytes) transient. *)
let snapshot_cache_entry_byte_capacity=1024*1024
let sampled_texture_bytes (texture:Scene_execution.sampled_texture)=
  if Option.is_some texture.gpu then 0 else Array.fold_left(fun total level->
    let bytes=Bytes.length level.Scene_execution.bytes in
    if total>snapshot_cache_entry_byte_capacity-bytes then
      snapshot_cache_entry_byte_capacity+1 else total+bytes)0 texture.levels
type t = { runtime:runtime;
  assets:Prismel_next_resources.Assets.t; mutable dead:bool;
  snapshots:snapshot_cache_entry Snapshot_table.t;
  scene2_geometry_cache:scene2_geometry_bucket Int_table.t;
  mutable lowering_frame:int;
  scene2_geometry_candidates:scene2_geometry_candidate Int_table.t;
  scene2_batch_cache:cached_scene2_batch Int_table.t;
  scene2_quad_cache:draw Quad_table.t;
  scene2_quad_payload_cache:cached_scene2_quad_payload Quad_payload_table.t;
  scene2_debug_cache:draw option Debug_table.t;
  scene2_plan_cache:cached_scene2_plan Int_table.t;
  scene2_plan_by_ir:(int,cached_scene2_plan)Hashtbl.t;
  retained_scene2_segments:retained_scene2_segment Segment_table.t;
  mutable retained_scene2_segment_hits:int64;
  mutable retained_scene2_segment_misses:int64;
  mutable submissions:submission list;
  mutable last_step_draws:draw list;
  mutable last_step_prepared:Runtime_next_orchestrator.prepared list;
  mutable scene2_out_slots:draw array;
  mutable scene2_out_list:draw list;
  mutable last_presentation:presentation_facts option;
}
and submission={owner:t;mutable submission_state:submission_state;
  mutable image_leases:Prismel_next_resources.Image.Private.lease list}
and batch={batch_owner:submission;batch_draws:draw list}
(* ponytail: one active native window; pass an explicit renderer token if sketches
   start owning multiple windows concurrently. *)
let active_window : t option ref=ref None
(* Device leases: the active window's device when one exists, otherwise one
   lazily created headless device shared by every lease and released with the
   last one. Offscreen executions (Canvas) and GPU film producers both lease. *)
let headless_gpu:(Ogpu.Backend.device*int ref)option ref=ref None
let release_headless()=match !headless_gpu with
  |Some(device,count)->decr count;
      if !count<=0 then(headless_gpu:=None;ignore(Ogpu.Backend.destroy_device device))
  |None->()
let acquire_device operation=
  let shared=match !active_window with
    |Some{runtime=Window runtime;dead=false;_}->Some(Runtime_next_orchestrator.device runtime)
    |Some _|None->None in
  match shared with
  |Some(Ok device)->Ok(device,true)
  |Some(Error e)->backend operation e
  |None->(match !headless_gpu with
    |Some(device,count)->incr count;Ok(device,false)
    |None->let driver,_=Ogpu.Impl.create_driver()in
        match Ogpu.Backend.create_device driver with
        |Error e->backend operation e
        |Ok device->headless_gpu:=Some(device,ref 1);Ok(device,false))
let release_device shared=if not shared then release_headless()
type lease_policy=Copy_image_snapshots|Retain_image_snapshots of submission
let valid_configuration operation (configuration:configuration)=
  let positive x=x>0 in
  if not(List.for_all positive[configuration.logical_width;configuration.logical_height;
      configuration.drawable_width;configuration.drawable_height])then
    fail operation Invalid_argument"dimensions must be positive"
  else Ok()
let finish_create runtime=
  let scene2_plan_by_ir=Hashtbl.create 16 in
  {runtime;assets=Prismel_next_resources.Assets.create();
      dead=false;
      snapshots=Snapshot_table.create snapshot_cache_capacity
        ~byte_capacity:snapshot_cache_byte_capacity;
      scene2_geometry_cache=Int_table.create 256~byte_capacity:scene2_geometry_byte_capacity;
      lowering_frame=0;
      scene2_geometry_candidates=Int_table.create 64~byte_capacity:scene2_geometry_byte_capacity;
      scene2_batch_cache=Int_table.create 256~byte_capacity:scene2_geometry_byte_capacity;
      scene2_quad_cache=Quad_table.create 1024;
      scene2_quad_payload_cache=Quad_payload_table.create 256;
      scene2_debug_cache=Debug_table.create 256;
      scene2_plan_cache=Int_table.create 16~byte_capacity:scene2_geometry_byte_capacity
        ~release:(fun _ plan->match Hashtbl.find_opt scene2_plan_by_ir plan.plan_ir_id with
          |Some current when current==plan->Hashtbl.remove scene2_plan_by_ir plan.plan_ir_id
          |_->());
      scene2_plan_by_ir;
      retained_scene2_segments=Segment_table.create retained_scene2_segment_capacity
        ~byte_capacity:retained_scene2_segment_byte_capacity;
      retained_scene2_segment_hits=0L;retained_scene2_segment_misses=0L;
      submissions=[];last_step_draws=[];last_step_prepared=[];
      scene2_out_slots=[||];scene2_out_list=[];last_presentation=None}
let create (configuration:configuration) =
  let operation="Prismel_next_execution.create" in
  match valid_configuration operation configuration with Error _ as error->error|Ok()->
    let config:Runtime_next_orchestrator.configuration={
      logical_width=configuration.logical_width;logical_height=configuration.logical_height;
      drawable_width=configuration.drawable_width;drawable_height=configuration.drawable_height;
      title=configuration.title;vsync=configuration.vsync}in
    match Runtime_next_orchestrator.create config with Error e->backend operation e|Ok runtime->
      let value=finish_create(Window runtime) in
      active_window:=Some value;Ok value
let create_offscreen (configuration:configuration)=
  let operation="Prismel_next_execution.create_offscreen"in
  match valid_configuration operation configuration with Error _ as error->error|Ok()->
  match acquire_device operation with Error _ as error->error|Ok(device,lease_shared)->
  match Runtime_next.create_offscreen ~device
      ~logical_width:configuration.logical_width
      ~logical_height:configuration.logical_height
      ~width:configuration.drawable_width
      ~height:configuration.drawable_height () with
  |Error error->release_device lease_shared;backend operation error
  |Ok runtime->
      let pixel_density=float configuration.drawable_width/.
        float configuration.logical_width in
      let facts={title=configuration.title;
        logical_width=configuration.logical_width;
        logical_height=configuration.logical_height;
        drawable_width=configuration.drawable_width;
        drawable_height=configuration.drawable_height;position=None;pixel_density;
        display_scale=pixel_density;refresh_rate=None;vsync=false}in
      let state={runtime;lease_shared;facts;frames=0L;logical_draws=0L;logical_passes=0L;
        logical_submissions=0L}in
      Ok(finish_create(Offscreen state))
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
      |Ok facts->
          (match value.last_presentation with
           |Some p when p.logical_width=facts.logical_width&&p.logical_height=facts.logical_height&&
               p.drawable_width=facts.drawable_width&&p.drawable_height=facts.drawable_height&&
               p.pixel_density=facts.pixel_density&&p.display_scale=facts.display_scale&&
               p.vsync=facts.vsync&&p.title=facts.title&&p.position=facts.position&&
               p.refresh_rate=facts.refresh_rate->Ok p
           |_->let p={title=facts.title;logical_width=facts.logical_width;
               logical_height=facts.logical_height;drawable_width=facts.drawable_width;
               drawable_height=facts.drawable_height;position=facts.position;
               pixel_density=facts.pixel_density;display_scale=facts.display_scale;
               refresh_rate=facts.refresh_rate;vsync=facts.vsync}in
               value.last_presentation<-Some p;Ok p))
    |Offscreen state->Ok state.facts
let window operation call value=match ensure operation value with Error _ as e->e|Ok()->
  match value.runtime with
  |Offscreen _->fail operation Unsupported"operation requires a presentation window"
  |Window runtime->Result.map_error(fun error->{operation;kind=Backend;
      message=Ogpu.Error.to_string error})(call runtime)
let show value=window"Prismel_next_execution.show"Runtime_next_orchestrator.show value
let hide value=window"Prismel_next_execution.hide"Runtime_next_orchestrator.hide value
let set_relative_mouse value enabled=window"Prismel_next_execution.set_relative_mouse"
  (fun runtime->Runtime_next_orchestrator.set_relative_mouse runtime enabled) value
let set_cursor value shape=window"Prismel_next_execution.set_cursor"
  (fun runtime->Runtime_next_orchestrator.set_cursor runtime shape)value
let set_text_input_area value area=window"Prismel_next_execution.set_text_input_area"
  (fun runtime->Runtime_next_orchestrator.set_text_input_area runtime area)value
let visible value=window"Prismel_next_execution.visible"Runtime_next_orchestrator.visible value
let snapshot value ~lease_policy ~density source =
  let operation="Prismel_next_execution.lower_scene2"in
  if density<=0 then fail operation Invalid_argument"density must be positive"else
  let find key generation=
    match Snapshot_table.find value.snapshots(key,density)with
    |entry when entry.snapshot_generation=generation->
        Some(entry.snapshot_width,entry.snapshot_height,entry.snapshot_texture)
    |_->None
    |exception Not_found->None in
  let store key generation width height texture bytes=
    if bytes<=snapshot_cache_entry_byte_capacity then
      Snapshot_table.add value.snapshots~bytes(key,density)
        {snapshot_generation=generation;snapshot_width=width;snapshot_height=height;
         snapshot_texture=texture}
    else Snapshot_table.remove value.snapshots(key,density)in
  let texture_key key generation=
    key^":"^string_of_int density^":"^string_of_int generation in
  let finish ?(copy=true) key generation width height pixels =
    match find key generation with
    |Some cached->Ok cached
    |None->
        let find_key()=match Snapshot_table.find value.snapshots(key,density)with
          |entry when entry.snapshot_width=width&&entry.snapshot_height=height->Some entry
          |_->None
          |exception Not_found->None in
        match find_key()with
        |Some entry->
            entry.snapshot_generation<-generation;
            let bytes=if copy then Bytes.copy pixels else pixels in
            (* The execution key carries the generation: same-key bytes are
               never re-hashed below, and a new generation recycles the
               same-shape texture with one upload. *)
            let texture={entry.snapshot_texture with
              key=texture_key key generation;
              levels=[|{entry.snapshot_texture.levels.(0) with bytes}|]}in
            entry.snapshot_texture<-texture;
            Ok(width,height,texture)
        |None->
        let sampler:Ogpu.Types.sampler_descriptor={label=Some"scene-image";min_filter=Linear;mag_filter=Linear;
          mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
        let bytes=if copy then Bytes.copy pixels else pixels in
        let texture:Scene_execution.sampled_texture={key=texture_key key generation;
          levels=[|{width;height;bytes}|];sampler;gpu=None}in
        store key generation width height texture(Bytes.length bytes);
        Ok(width,height,texture)in
  match source with
  |Image image->
      if Prismel_next_resources.Image.destroyed image then
        fail operation Destroyed"image snapshot is destroyed"
      else let key="image:"^string_of_int(Prismel_next_resources.Image.identity image)
      and generation=Prismel_next_resources.Image.generation image in
      (match Prismel_next_resources.Image.Private.gpu_snapshot image with
      |Some(width,height,generation,gpu) when (match value.runtime with Window _->true|Offscreen _->false)->
          let sampler:Ogpu.Types.sampler_descriptor={label=Some"scene-image";
            min_filter=Linear;mag_filter=Linear;mip_filter=No_mip;
            address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;
            max_anisotropy=1}in
          Ok(width,height,{Scene_execution.key=key^":"^string_of_int density^":"^
            string_of_int generation;levels=[|{width;height;bytes=Bytes.empty}|];
            sampler;gpu=Some gpu})
      |None|Some _->
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
          (* The generation is part of the GPU texture key: a replaced image
             (same identity, new pixels) then misses the executor's static
             image fast path and re-uploads into its same-shape texture. *)
          let texture={Scene_execution.key=key^":"^string_of_int density^":"^
              string_of_int borrowed_generation;
            levels=[|{width;height;bytes}|];sampler;gpu=None}in
          if cacheable then
            store key borrowed_generation width height texture(Bytes.length bytes);
          Ok(width,height,texture)
      |Error e->resource operation e))
  |Text text->(match Prismel_next_resources.Text.size text,Prismel_next_resources.Text.pixels text with
      |Ok(width,height),Ok pixels->finish("text:"^Digest.to_hex(Digest.bytes pixels))(Prismel_next_resources.Text.generation text)width height pixels
      |Error e,_|_,Error e->resource operation e)
  |Canvas canvas->
      let key="canvas:"^string_of_int(Prismel_next_resources.Canvas.Private.identity canvas)in
      (* A canvas rendered on this window's device is sampled in place. *)
      let gpu=match value.runtime,Prismel_next_resources.Canvas.Private.gpu_snapshot canvas with
        |Window runtime,Some(width,height,generation,texture)->
            let device_id,_=Ogpu.Backend.Private.texture_driver_token texture in
            (match Runtime_next_orchestrator.device runtime with
             |Ok device when Ogpu.Handle.device_id(Ogpu.Backend.device_handle device)=device_id->
                 Some(width,height,generation,texture)
             |_->None)
        |_->None in
      (match gpu with
       |Some(width,height,generation,texture)->
           let sampler:Ogpu.Types.sampler_descriptor={label=Some"scene-image";
             min_filter=Linear;mag_filter=Linear;mip_filter=No_mip;
             address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;
             max_anisotropy=1}in
           Ok(width,height,{Scene_execution.key=key^":"^string_of_int density^":"^
             string_of_int generation;levels=[|{width;height;bytes=Bytes.empty}|];
             sampler;gpu=Some texture})
       |None->
      match Prismel_next_resources.Canvas.snapshot canvas with
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
  let framebuffer=(0,0,facts.logical_width,facts.logical_height) in
  let transforms=ref[identity]and clips=ref[framebuffer]
  and blend=ref Alpha and number=ref 0 and failure=ref None in
  value.lowering_frame<-value.lowering_frame+1;
  let frame=value.lowering_frame in
  let emit draw=
    let draw=if draw.blend= !blend then draw else {draw with blend= !blend} in
    let i= !number in
    if i>=Array.length value.scene2_out_slots then
      value.scene2_out_slots<-Array.append value.scene2_out_slots
        (Array.make(max 8(Array.length value.scene2_out_slots))draw);
    value.scene2_out_slots.(i)<-draw;
    incr number in
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
    let same vertices indices color cached_clip viewport=
      vertices=geometry.vertices&&indices=geometry.indices&&
      color=geometry.color&&cached_clip=clip&&viewport=framebuffer in
    let bucket=match Int_table.find value.scene2_geometry_cache fingerprint with
      |bucket->Some bucket|exception Not_found->None in
    let hit=match bucket with None->None|Some bucket->
      List.find_opt(fun cached->cached.used_frame<>frame&&same cached.vertices cached.indices cached.color cached.clip cached.draw.value.state.viewport)bucket.entries in
    match hit with
    |Some cached->
        write_affine cached.uniform_bytes transform;
        cached.used_frame<-frame;cached.draw
    |None->
        let draw=mesh_of_geometry number transform
          ~viewport:framebuffer clip
          geometry in
        (* Admission candidates deliberately retain metadata, not the source
           arrays.  Scene construction commonly creates fresh arrays and an
           animated transform can make every prepared mesh unique.  Retaining
           copies for all of those one-hit values promoted a bounded but large
           stream of dead geometry into the major heap.  A matching token only
           authorizes admission; the cache entry below still owns fresh copies
           and every later hit performs an exact array comparison, so a hash
           collision cannot reuse incorrect prepared bytes. *)
        let candidate=match Int_table.find value.scene2_geometry_candidates fingerprint with
          |candidate when candidate.candidate_vertex_count=Array.length geometry.vertices&&
              candidate.candidate_index_count=Array.length geometry.indices&&
              candidate.candidate_color=geometry.color&&candidate.candidate_clip=clip->true
          |_->false|exception Not_found->false in
        if not candidate then begin
            Int_table.add value.scene2_geometry_candidates~bytes:source_bytes fingerprint{
              candidate_vertex_count=Array.length geometry.vertices;
              candidate_index_count=Array.length geometry.indices;
              candidate_color=geometry.color;candidate_clip=clip};draw
        end else begin
            Int_table.remove value.scene2_geometry_candidates fingerprint;
            let uniform=match draw.value.state.transform_uniforms with
              |Some bytes when Bytes.length bytes=24->bytes
              |_->Bytes.make 24 '\000'in
            write_affine uniform transform;
            let draw={draw with value={draw.value with state={draw.value.state with
              transform_uniforms=Some uniform}}}in
            let cached={vertices=Array.copy geometry.vertices;indices=Array.copy geometry.indices;
              color=geometry.color;clip;uniform_bytes=uniform;
              used_frame=frame;draw}in
            let bucket=match bucket with Some bucket->bucket
              |None->{entries=[];bucket_bytes=0}in
            bucket.entries<-cached::bucket.entries;
            bucket.bucket_bytes<-bucket.bucket_bytes+source_bytes;
            Int_table.add value.scene2_geometry_cache~bytes:bucket.bucket_bytes fingerprint bucket;
            draw
        end
    in
  let quad (texture:Scene_execution.sampled_texture)
      (destination:Scene_command.Render_ir.rect) (u0,v0,u1,v1 as uv) =
    let transform=render_transform(List.hd!transforms)in
    let clip=List.hd!clips in
    let quad_key=texture,destination,transform,clip,uv,framebuffer in
    match Quad_table.find value.scene2_quad_cache quad_key with
    |draw->draw
    |exception Not_found->
    let payload_key=destination,transform,clip,uv in
    let vertices,indices,mesh_key=match Quad_payload_table.find value.scene2_quad_payload_cache payload_key with
    |cached->cached.payload_vertices,cached.payload_indices,cached.payload_mesh_key
    |exception Not_found->
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
    Quad_payload_table.add value.scene2_quad_payload_cache payload_key
      {payload_mesh_key=mesh_key;payload_vertices=vertices;payload_indices=indices};
    vertices,indices,mesh_key in
    let draw={family=Scene2_textured;blend=Alpha;texture=Some texture;auxiliary=None;samples=1;
      value={Scene_execution.mesh={key=mesh_key;vertices;vertex_count=4;indices;index_count=6;primitive=Triangle_list};state=default_state framebuffer clip}}in
    if sampled_texture_bytes texture<=snapshot_cache_entry_byte_capacity then
      Quad_table.add value.scene2_quad_cache quad_key draw;
    draw in
  let image (command:Scene_command.Render_ir.image) = match resolve command.Scene_command.Render_ir.resource_id with None->failure:=Some"resource id is unbound"|Some source->
    match snapshot value~lease_policy~density source with Error e->failure:=Some(Format.asprintf"%a"pp_error e)|Ok(width,height,texture)->
      let s=command.source in if width<=0||height<=0 then failure:=Some"resource extent is invalid"else
      let u0=s.x/.float width and v0=s.y/.float height and u1=(s.x+.s.width)/.float width and v1=(s.y+.s.height)/.float height in
      let draw=quad texture command.destination(u0,v0,u1,v1)in
      emit draw in
  let commands=Scene_command.Render_ir.Private.commands_readonly ir in
  let cursor=ref 0 in
  while !cursor<Array.length commands && !failure=None do
    let first= !cursor in
    let command=commands.(first) in
    incr cursor;
    (match command with
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
    |Geometry geometry->
        let stop=ref !cursor in
        if dense_scene2_runs then begin
          while !stop<Array.length commands &&
            (match commands.(!stop) with Geometry _->true|_->false) do incr stop done
        end;
        if dense_scene2_runs && !stop-first>64 then begin
          cursor:= !stop;
          if clip_live() then emit (mesh_of_geometry_run !number
            (render_transform (List.hd !transforms))
            ~viewport:framebuffer (List.hd !clips) commands first !stop)
        end else if clip_live() then
          emit (geometry_draw !number (render_transform (List.hd !transforms))
            (List.hd !clips) geometry)
    |Debug_text debug->if clip_live()then
        let transform=render_transform(List.hd!transforms)and clip=List.hd!clips in
        let debug_key=debug,transform,clip in
        let draw=match Debug_table.find value.scene2_debug_cache debug_key with
        |draw->draw
        |exception Not_found->
            let geometry=debug_text_geometry transform debug in
            let draw=if Array.length geometry.indices=0 then None else
              Some(mesh_of_geometry!number identity
                ~viewport:framebuffer clip geometry)in
            Debug_table.add value.scene2_debug_cache debug_key draw;
            draw in
        Option.iter emit draw
    |Image command->if clip_live()then image command
    |Glyphs glyphs->if clip_live()&&Array.length glyphs.glyphs>0 then match resolve glyphs.resource_id with None->failure:=Some"glyph resource id is unbound"|Some source->
        match snapshot value~lease_policy~density source with Error e->failure:=Some(Format.asprintf"%a"pp_error e)|Ok(width,height,texture)->
          Array.iter(fun(glyph:Scene_command.Render_ir.glyph)->
            let destination={Scene_command.Render_ir.x=glyph.x;y=glyph.y;width=float width;height=float height}in
            let draw=quad texture destination(0.,0.,1.,1.)in
            emit draw)glyphs.glyphs)
  done;
  match!failure with Some message->release_new_leases();fail"Prismel_next_execution.lower_scene2"Resource message
  |None->
      let n= !number in
      let rec prefix_same i=function
        |[]->i=n
        |d::rest->i<n&&value.scene2_out_slots.(i)==d&&prefix_same(i+1)rest in
      if prefix_same 0 value.scene2_out_list then Ok value.scene2_out_list
      else
        let rec loop i acc=if i<0 then acc else loop(i-1)(value.scene2_out_slots.(i)::acc)in
        let list=loop(n-1)[]in
        value.scene2_out_list<-list;
        if n<=64 then Ok list
        else Ok(batch_scene2_draws ~cache:value.scene2_batch_cache list)
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
  let ir_id=Scene_command.Render_ir.Private.identity ir in
  let facts=presentation_facts value|>Result.get_ok in
  let extent=facts.logical_width,facts.logical_height,
    facts.drawable_width,facts.drawable_height in
  let same_context plan=plan.plan_density=density&&plan.plan_extent=extent in
  let slow ()=
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
    let cacheable,resources=scene2_resource_stamps resolve commands in
    let exact plan=
      plan.plan_command_count=command_count&&same_context plan&&
      same_scene2_resource_stamps plan.plan_resources resources&&
      Scene_command.Render_ir.Private.commands_readonly plan.plan_ir=commands in
    let rebind plan=
      if plan.plan_ir_id<>ir_id then begin
        (match Hashtbl.find_opt value.scene2_plan_by_ir plan.plan_ir_id with
         |Some current when current==plan->Hashtbl.remove value.scene2_plan_by_ir plan.plan_ir_id
         |_->());
        plan.plan_ir_id<-ir_id;plan.plan_ir<-ir;
        Hashtbl.replace value.scene2_plan_by_ir ir_id plan
      end in
    let hit=match Int_table.find value.scene2_plan_cache fingerprint with
      |plan when exact plan->Some plan|_->None|exception Not_found->None in
    if cacheable then match hit with
    |Some plan->rebind plan;Ok plan.plan_draws
    |None->
      (match lower_scene2_uncached value~lease_policy~density~resource:resolve ir with
      |Error _ as error->error
      |Ok draws as result->
        if List.exists(fun draw->match draw.texture with
          |Some texture->sampled_texture_bytes texture>snapshot_cache_entry_byte_capacity
          |None->false)draws then result else
        let plan={plan_ir_id=ir_id;
          plan_command_count=command_count;
          plan_source_bytes=scene2_plan_source_bytes commands;plan_density=density;
          plan_extent=extent;plan_resources=resources;
          plan_ir=ir;plan_draws=draws}in
        Int_table.add value.scene2_plan_cache~bytes:plan.plan_source_bytes fingerprint plan;
        Hashtbl.replace value.scene2_plan_by_ir ir_id plan;
        result)
    else lower_scene2_uncached value~lease_policy~density~resource:resolve ir in
  match Hashtbl.find_opt value.scene2_plan_by_ir ir_id with
  |Some plan when same_context plan&&plan.plan_resources=[]->Ok plan.plan_draws
  |Some plan when same_context plan->let cacheable,resources=scene2_resource_stamps resolve commands in
      if cacheable&&same_scene2_resource_stamps plan.plan_resources resources
      then Ok plan.plan_draws else slow()
  |_->slow()
let lower_scene2 value ~density ~resource ir=
  lower_scene2_with_policy value~lease_policy:Copy_image_snapshots
    ~density~resource ir
let resize value ~logical_width ~logical_height ~drawable_width ~drawable_height =
  match ensure"Prismel_next_execution.resize"value with Error _ as e->e|Ok()->
  let resized=match value.runtime with
  |Window runtime->Runtime_next_orchestrator.resize runtime~logical_width~logical_height
      ~drawable_width~drawable_height
  |Offscreen state->match Runtime_next.resize_offscreen state.runtime
      ~logical_width~logical_height
      ~width:drawable_width~height:drawable_height with
    |Error _ as error->error
    |Ok()->let pixel_density=float drawable_width/.float logical_width in
      state.facts<-{state.facts with logical_width;logical_height;drawable_width;
        drawable_height;pixel_density;display_scale=pixel_density};Ok()in
  Result.map_error (fun e->{operation="Prismel_next_execution.resize";
      kind=Backend;message=Ogpu.Error.to_string e}) resized
let replay_step ?clear ~identity ~version value=
  match ensure"Prismel_next_execution.Private.replay"value with
  |Error _ as error->error
  |Ok()->
      match presentation_facts value with
      |Error _ as error->error
      |Ok _->
          let replayed=match value.runtime with
          |Window runtime->Runtime_next_orchestrator.replay_retained ?clear
              ~identity ~version runtime
          |Offscreen _->Ok None in
          (match replayed with
          |Error error->backend"Prismel_next_execution.Private.replay"error
          |Ok None->Ok None
          |Ok(Some _)->Ok(Some()))
let step_core ?after_prepare ?clear ?identity ?version value draws=
  let after_prepare=Option.value after_prepare ~default:Fun.id in
  match ensure"Prismel_next_execution.step"value with Error _ as e->e|Ok()->
  match presentation_facts value with Error _ as error->after_prepare();error|Ok f->
    let replayed=match value.runtime,identity,version with
      |Window runtime,Some identity,Some version->
          Runtime_next_orchestrator.replay_retained ?clear ~identity ~version runtime
      |_->Ok None in
    let rendered=match replayed with
    |Error error->after_prepare();Error error
    |Ok(Some presented)->after_prepare();Ok presented
    |Ok None->
    let rec same_draws left right=match left,right with
      |[],[]->true|x::xs,y::ys->x==y&&same_draws xs ys|_->false in
    let draws=
      if same_draws draws value.last_step_draws then value.last_step_prepared
      else
        let prepared=List.map(fun x->let draw=x.value in let state=draw.Scene_execution.state in
          let viewport=match state.viewport with _,_,w,h when w<0||h<0->0,0,f.logical_width,f.logical_height|x->x in
          let scissor=match state.scissor with _,_,w,h when w<0||h<0->0,0,f.logical_width,f.logical_height|x->x in
          let draw=if viewport=state.viewport&&scissor=state.scissor then draw else
            {draw with Scene_execution.state={state with viewport;scissor}}in
          {Runtime_next_orchestrator.family=x.family;blend=x.blend;texture=x.texture;
            auxiliary=x.auxiliary;samples=x.samples;draw})draws in
        value.last_step_draws<-draws;value.last_step_prepared<-prepared;prepared in
    match value.runtime with
    |Window runtime->(match identity,version with
      |None,None->Runtime_next_orchestrator.render_prepared ~after_prepare ?clear runtime draws
      |Some identity,Some version->Runtime_next_orchestrator.render_retained ~after_prepare ?clear
          ~identity~version runtime draws
      |_->after_prepare();Error(Ogpu.Error.make"Prismel_next_execution.step"Ogpu.Error.Invalid_argument
          "prepared identity and version must be supplied together"))
    |Offscreen state->
      let result=match identity,version with
      |None,None->Runtime_next.render_offscreen ~after_prepare ?clear state.runtime draws
      |Some identity,Some version->Runtime_next.render_offscreen_prepared ~after_prepare ?clear
          ~identity~version state.runtime draws
      |_->after_prepare();Error(Ogpu.Error.make"Prismel_next_execution.step"Ogpu.Error.Invalid_argument
          "prepared identity and version must be supplied together")in
      (match result with Ok _->state.frames<-Int64.succ state.frames;
        state.logical_draws<-Int64.add state.logical_draws
          (Int64.of_int(List.length draws));
        state.logical_passes<-Int64.succ state.logical_passes;
        state.logical_submissions<-Int64.succ state.logical_submissions
      |Error _->());result in
    match rendered with Error e->backend"Prismel_next_execution.step"e
    |Ok _->Ok()
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
let retained_scene2_segment_bytes draws=List.fold_left(fun total draw->
  let value=draw.value in
  total+Bytes.length value.Scene_execution.mesh.vertices+
    Bytes.length value.mesh.indices+
    Option.fold~none:0~some:Bytes.length value.state.transform_uniforms+
    Option.fold~none:0~some:sampled_texture_bytes draw.texture+
    Option.fold~none:0~some:(fun auxiliary->
      Bytes.length auxiliary.Scene_execution.buffer+
      sampled_texture_bytes auxiliary.texture)draw.auxiliary)0 draws
let lower_scene2_segment submission ~identity ~version ~cacheable ~density
    ~resource ir=
  let operation="Prismel_next_execution.Private.lower_scene2_segment"in
  if identity<=0L||version<0L then begin
    close_submission submission;
    fail operation Invalid_argument"segment identity/version is invalid"
  end else match ensure_submission operation submission with
  |Error _ as error->close_submission submission;error
  |Ok()->
      let owner=submission.owner in
      match presentation_facts owner with
      |Error _ as error->close_submission submission;error
      |Ok facts->
      let find()=match Segment_table.find owner.retained_scene2_segments identity with
      |entry when entry.segment_version=version&&entry.segment_density=density&&
          entry.segment_width=facts.logical_width&&
          entry.segment_height=facts.logical_height->
          Some entry.segment_draws
      |_->None
      |exception Not_found->None in
      match if cacheable then find() else None with
      |Some draws->
          owner.retained_scene2_segment_hits<-
            Int64.succ owner.retained_scene2_segment_hits;
          Ok{batch_owner=submission;batch_draws=draws}
      |None->match lower_scene2_submission submission~density~resource ir with
        |Error _ as error->error
        |Ok batch->
            if cacheable then owner.retained_scene2_segment_misses<-
              Int64.succ owner.retained_scene2_segment_misses;
            if cacheable then begin
              let entry={segment_version=version;
                segment_density=density;segment_width=facts.logical_width;
                segment_height=facts.logical_height;
                segment_draws=batch.batch_draws}in
              Segment_table.add owner.retained_scene2_segments
                ~bytes:(retained_scene2_segment_bytes batch.batch_draws)identity entry
            end;
            Ok batch
(* PXUI instances: one [Ui] draw per Ui_batch batch. Glyphs sit on exact
   physical texels, so every UI texture samples nearest. *)
let ui_sampler:Ogpu.Types.sampler_descriptor={label=Some"ui";min_filter=Nearest;
  mag_filter=Nearest;mip_filter=No_mip;address_u=Clamp_to_edge;
  address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}
let ui_white_texture={Scene_execution.key="ui-white";
  levels=[|{width=1;height=1;bytes=Bytes.make 4 '\255'}|];sampler=ui_sampler;
  gpu=None}
let ui_indices=ref Bytes.empty
let ui_index_bytes count=
  let needed=count*24 in
  if Bytes.length!ui_indices<needed then begin
    let capacity=max needed(2*Bytes.length!ui_indices)in
    let bytes=Bytes.create capacity in
    for quad=0 to capacity/24-1 do
      let base=quad*4 in
      List.iteri(fun slot corner->
        Bytes.set_int32_le bytes((quad*6+slot)*4)(Int32.of_int(base+corner)))
        [0;1;2;0;2;3]
    done;
    ui_indices:=bytes
  end;
  Bytes.sub!ui_indices 0 needed
let lower_ui submission ~density ~resource ui=
  let operation="Prismel_next_execution.Private.lower_ui"in
  match ensure_submission operation submission with
  |Error _ as error->close_submission submission;error
  |Ok()->
  match presentation_facts submission.owner with
  |Error _ as error->close_submission submission;error
  |Ok facts->
  let width=float facts.logical_width and height=float facts.logical_height in
  let framebuffer=0,0,facts.logical_width,facts.logical_height in
  let instances=Scene_command.Ui_batch.instances ui in
  let texture id=
    if id<=0 then Ok ui_white_texture else match resource id with
    |None->fail operation Resource"UI texture resource id is unbound"
    |Some source->
        match snapshot submission.owner
          ~lease_policy:(Retain_image_snapshots submission)~density source with
        |Error _ as error->error
        |Ok(_,_,texture)->Ok{texture with Scene_execution.sampler=ui_sampler}in
  let draw index (batch:Scene_command.Ui_batch.batch)=
    Result.map(fun texture->
      let xform=batch.xform in
      let affine=Bytes.make 24 '\000'in
      write_affine affine{Scene_command.Render_ir.xx=2.*.xform.scale/.width;
        xy=0.;yx=0.;yy=(-2.)*.xform.scale/.height;
        tx=2.*.xform.tx/.width-.1.;ty=1.-.2.*.xform.ty/.height};
      let scissor=match batch.clip with
        |None->framebuffer
        |Some clip->
            let x=max 0(int_of_float(Float.floor clip.x))
            and y=max 0(int_of_float(Float.floor clip.y))in
            let right=min facts.logical_width
                (int_of_float(Float.ceil(clip.x+.clip.width)))
            and bottom=min facts.logical_height
                (int_of_float(Float.ceil(clip.y+.clip.height)))in
            x,y,max 0(right-x),max 0(bottom-y)in
      let vertices=Bytes.sub instances
          (batch.first*Scene_command.Ui_batch.instance_bytes)
          (batch.count*Scene_command.Ui_batch.instance_bytes)in
      {family=Ui;blend=Alpha;texture=Some texture;auxiliary=None;samples=1;
       value={Scene_execution.mesh={key="ui:"^string_of_int index;vertices;
         vertex_count=4*batch.count;indices=ui_index_bytes batch.count;
         index_count=6*batch.count;primitive=Ogpu.Render_pass.Triangle_list};
         state={(default_state framebuffer scissor)with
           transform_uniforms=Some affine}}})(texture batch.texture)in
  let batches=Scene_command.Ui_batch.batches ui in
  let rec build index reversed=
    if index=Array.length batches then Ok(List.rev reversed) else
    let batch=batches.(index)in
    let _,_,scissor_width,scissor_height=match batch.clip with
      |None->framebuffer
      |Some clip->0,0,int_of_float clip.width,int_of_float clip.height in
    if batch.count=0||scissor_width<=0||scissor_height<=0
    then build(index+1)reversed
    else match draw index batch with
      |Error _ as error->error
      |Ok value->build(index+1)(value::reversed)in
  match build 0[]with
  |Error _ as error->close_submission submission;error
  |Ok draws->Ok{batch_owner=submission;batch_draws=draws}
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
          let draws=match batches with
            |[batch]->batch.batch_draws
            |_->List.rev(List.fold_left(fun reversed batch->
                List.rev_append batch.batch_draws reversed)[]batches)in
          step_core ~after_prepare:(fun()->close_submission submission)
            ?clear ?identity ?version submission.owner draws)
let capture value=match ensure"Prismel_next_execution.capture"value with Error _ as e->e|Ok()->
  match presentation_facts value with Error _ as error->error|Ok facts->
  let captured=match value.runtime with
  |Window runtime->Runtime_next_orchestrator.capture runtime
      ~bytes_per_row:(facts.drawable_width*4)
  |Offscreen state->Runtime_next.read_offscreen state.runtime
      ~bytes_per_row:(facts.drawable_width*4)in
  match captured with Ok x->Ok x|Error e->backend"Prismel_next_execution.capture"e
let offscreen_target value=
  let operation="Prismel_next_execution.offscreen_target"in
  match ensure operation value with Error _ as e->e|Ok()->
  match value.runtime with
  |Offscreen state->(match Runtime_next.offscreen_target state.runtime with
      |Ok texture->Ok texture|Error e->backend operation e)
  |Window _->fail operation Unsupported"operation requires an offscreen execution"
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
    Snapshot_table.clear value.snapshots;Int_table.clear value.scene2_geometry_cache;
    Int_table.clear value.scene2_batch_cache;
    Quad_table.clear value.scene2_quad_cache;
    Quad_payload_table.clear value.scene2_quad_payload_cache;
    Debug_table.clear value.scene2_debug_cache;
    Int_table.clear value.scene2_plan_cache;Hashtbl.reset value.scene2_plan_by_ir;
    Segment_table.clear value.retained_scene2_segments;
    Int_table.clear value.scene2_geometry_candidates;value.last_step_draws<-[];
    value.last_step_prepared<-[];value.scene2_out_slots<-[||];
    value.scene2_out_list<-[];value.last_presentation<-None;value.dead<-true;
    (match !active_window with Some current when current==value->active_window:=None|_->());
    let destroyed=match value.runtime with
    |Window runtime->Runtime_next_orchestrator.destroy runtime
    |Offscreen state->
        let destroyed=Runtime_next.destroy_offscreen state.runtime in
        release_device state.lease_shared;destroyed in
    match destroyed with Ok()->Ok()|Error e->backend"Prismel_next_execution.destroy"e)
(* GPU film leases own their own queue, so their frame pacing never couples
   with presentation. *)
type gpu={gpu_device:Ogpu.Backend.device;gpu_queue:Ogpu.Backend.queue;
  gpu_shared:bool;mutable gpu_released:bool}
let acquire_gpu()=
  let operation="Prismel_next_execution.acquire_gpu"in
  match acquire_device operation with
  |Error _ as e->e
  |Ok(device,gpu_shared)->
      match Ogpu.Backend.create_queue device with
      |Error e->release_device gpu_shared;backend operation e
      |Ok queue->Ok{gpu_device=device;gpu_queue=queue;gpu_shared;gpu_released=false}
let gpu_device gpu=gpu.gpu_device
let gpu_queue gpu=gpu.gpu_queue
let gpu_shared gpu=gpu.gpu_shared
let release_gpu gpu=if not gpu.gpu_released then begin
  gpu.gpu_released<-true;
  ignore(Ogpu.Backend.destroy_queue gpu.gpu_queue);
  release_device gpu.gpu_shared
end
module Private=struct
  let snapshot_count_for_test value=Snapshot_table.length value.snapshots
  type nonrec submission=submission
  type nonrec batch=batch
  let begin_submission=begin_submission
  let lower_scene2=lower_scene2_submission
  let lower_scene2_segment=lower_scene2_segment
  let lower_ui=lower_ui
  let adopt_draws=adopt_draws
  let step=step_submission
  let replay=replay_step
  let cancel=close_submission
  let retained_scene2_segment_stats value=
    Segment_table.length value.retained_scene2_segments,
    value.retained_scene2_segment_hits,value.retained_scene2_segment_misses
end
