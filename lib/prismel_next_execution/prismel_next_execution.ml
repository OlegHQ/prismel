type target = Native | Headless | Web
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
type configuration = { target:target; logical_width:int; logical_height:int;
  drawable_width:int; drawable_height:int; title:string; timing:timing;
  max_events:int; max_file_bytes:int }
let default_configuration = { target=Headless; logical_width=640; logical_height=480;
  drawable_width=640; drawable_height=480; title="Prismel"; timing=Fixed (1. /. 60.);
  max_events=4096; max_file_bytes=16*1024*1024 }

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
type text_region = {x:int;y:int;width:int;height:int;focused:bool}
type audio_intent = Prismel_next_resources.Audio.intent
type family = Scene2 | Scene2_textured | Scene3 | Scene3_textured | Scene3_shadow |
  Scene3_stencil | Scene3_textured_stencil | Scene3_shadow_stencil
type blend = Replace | Alpha | Add | Multiply | Screen | Subtract
type draw = { family:family; blend:blend; texture:Scene_execution.sampled_texture option;
  auxiliary:Scene_execution.auxiliary_resource option;samples:int;value:Scene_execution.draw }
type resource=Image of Prismel_next_resources.Image.t|Text of Prismel_next_resources.Text.t
  |Canvas of Prismel_next_resources.Canvas.t
let prepared_draw ~family ?(blend=Replace) ?texture ?auxiliary ?(samples=1) value =
  {family;blend;texture;auxiliary;samples;value}

let default_state viewport scissor = { Scene_execution.viewport; scissor;
  cull=Ogpu.Render_pass.Cull_none; depth_compare=Ogpu.Render_pass.Always;
  depth_write=false; depth_load=Ogpu.Render_pass.Load; depth_clear=1.;
  transform_uniforms=None; stencil_state=None; stencil_load=Ogpu.Render_pass.Load;
  stencil_clear=0 }
let finite value = Float.is_finite value
let put_float bytes offset value = Bytes.set_int64_le bytes offset (Int64.bits_of_float value)
let mesh_of_geometry number transform clip (geometry:Raster2.Render_ir.geometry) =
  let count=Array.length geometry.vertices/2 in
  let vertices=Bytes.create(count*16) in
  for index=0 to count-1 do
    let x=geometry.vertices.(index*2) and y=geometry.vertices.(index*2+1) in
    let tx=transform.Raster2.Render_ir.xx*.x+.transform.yx*.y+.transform.tx
    and ty=transform.xy*.x+.transform.yy*.y+.transform.ty in
    put_float vertices(index*16)tx; put_float vertices(index*16+8)ty
  done;
  let indices=Bytes.create(Array.length geometry.indices*4) in
  Array.iteri(fun index value->Bytes.set_int32_le indices(index*4)(Int32.of_int value))geometry.indices;
  let x,y,width,height=clip in
  { family=Scene2;blend=Replace;texture=None;auxiliary=None;samples=1; value={Scene_execution.mesh={key=Printf.sprintf "ir-%Ld-%d" 0L number;
      vertices;vertex_count=count;indices;index_count=Array.length geometry.indices};
      state=default_state (x,y,width,height) (x,y,width,height)} }
let debug_text_geometry transform (debug:Raster2.Render_ir.debug_text) =
  let stop = match String.index_opt debug.text '\000' with
    | Some index -> index | None -> String.length debug.text in
  let pixels = ref 0 in
  for character = 0 to stop - 1 do
    for row = 0 to Raster2.Debug_font.height - 1 do
      let bits = Raster2.Debug_font.glyph_row debug.text.[character] row in
      for column = 0 to Raster2.Debug_font.width - 1 do
        if bits land (0x80 lsr column) <> 0 then incr pixels
      done
    done
  done;
  let vertices = Array.make (!pixels * 8) 0.
  and indices = Array.make (!pixels * 6) 0 in
  let anchor_x = transform.Raster2.Render_ir.xx *. debug.x
    +. transform.yx *. debug.y +. transform.tx
  and anchor_y = transform.xy *. debug.x
    +. transform.yy *. debug.y +. transform.ty in
  let pixel = ref 0 in
  for character = 0 to stop - 1 do
    for row = 0 to Raster2.Debug_font.height - 1 do
      let bits = Raster2.Debug_font.glyph_row debug.text.[character] row in
      for column = 0 to Raster2.Debug_font.width - 1 do
        if bits land (0x80 lsr column) <> 0 then begin
          let x = anchor_x +. float (character * Raster2.Debug_font.width + column)
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
  { Raster2.Render_ir.vertices; indices; color=debug.color }
let compose (a:Raster2.Render_ir.transform) (b:Raster2.Render_ir.transform) = { Raster2.Render_ir.xx=a.Raster2.Render_ir.xx*.b.xx+.a.yx*.b.xy;
  xy=a.xy*.b.xx+.a.yy*.b.xy; yx=a.xx*.b.yx+.a.yx*.b.yy;
  yy=a.xy*.b.yx+.a.yy*.b.yy; tx=a.xx*.b.tx+.a.yx*.b.ty+.a.tx;
  ty=a.xy*.b.tx+.a.yy*.b.ty+.a.ty }
let scene2_ir ir =
  let identity={Raster2.Render_ir.xx=1.;xy=0.;yx=0.;yy=1.;tx=0.;ty=0.} in
  let transforms=ref[identity] and clips=ref[(0,0,-1,-1)]
  and draws=ref[] and number=ref 0 and failure=ref None in
  Array.iter(fun command->if !failure=None then match command with
    |Raster2.Render_ir.Clear _|Set_blend _->()
    |Push_transform value->transforms:=compose(List.hd!transforms)value::!transforms
    |Pop_transform->(match !transforms with _::(_::_ as rest)->transforms:=rest|_->())
    |Push_clip rect->
        if not(List.for_all finite[rect.x;rect.y;rect.width;rect.height])then failure:=Some"non-finite clip"
        else let x=int_of_float(floor rect.x)and y=int_of_float(floor rect.y)
          and w=max 0(int_of_float(ceil rect.width))and h=max 0(int_of_float(ceil rect.height))in
          clips:=(x,y,w,h)::!clips
    |Pop_clip->(match !clips with _::(_::_ as rest)->clips:=rest|_->())
    |Geometry geometry->draws:=mesh_of_geometry !number(List.hd!transforms)(List.hd!clips)geometry::!draws;incr number
    |Debug_text debug->
        let geometry=debug_text_geometry(List.hd!transforms)debug in
        if Array.length geometry.indices>0 then begin
          draws:=mesh_of_geometry !number identity(List.hd!clips)geometry::!draws;
          incr number
        end
    |Image _|Glyphs _->failure:=Some"image/glyph resource binding is not available")
    (Raster2.Render_ir.Private.commands_readonly ir);
  match !failure with Some message->fail"Prismel_next_execution.scene2_ir"Unsupported message
  |None->Ok(List.rev!draws)

let batch_scene2_draws draws =
  let compatible (left : draw) (right : draw) =
    left.family = Scene2 && right.family = Scene2
    && left.blend = right.blend && left.texture = None && right.texture = None
    && left.auxiliary = None && right.auxiliary = None
    && left.samples = right.samples && left.value.state = right.value.state
  in
  let merge reversed =
    match List.rev reversed with
    | [] -> assert false
    | [draw] -> draw
    | first :: _ as group ->
        let vertex_count = List.fold_left
            (fun count draw -> count + draw.value.mesh.vertex_count) 0 group
        and index_count = List.fold_left
            (fun count draw -> count + draw.value.mesh.index_count) 0 group in
        let vertices = Bytes.create (vertex_count * 16)
        and indices = Bytes.create (index_count * 4) in
        let vertex_offset = ref 0 and index_offset = ref 0 in
        List.iter (fun draw ->
          let mesh = draw.value.mesh in
          Bytes.blit mesh.vertices 0 vertices (!vertex_offset * 16)
            (mesh.vertex_count * 16);
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
        { first with value={first.value with mesh} }
  in
  let rec loop output current = function
    | [] -> List.rev (match current with [] -> output | _ -> merge current :: output)
    | draw :: rest ->
        (match current with
         | previous :: _ when compatible previous draw ->
             loop output (draw :: current) rest
         | [] -> loop output [draw] rest
         | _ -> loop (merge current :: output) [draw] rest)
  in
  loop [] [] draws

type t = { runtime:Runtime_next_orchestrator.t; input:Runtime_next_input.t;
  assets:Prismel_next_resources.Assets.t; timing:timing; mutable frame:int64;
  mutable elapsed:float; mutable last_clock:float; mutable dead:bool;
  mutable snapshots:(string*int*int*Scene_execution.sampled_texture)list;
  mutable canvas_keys:(Prismel_next_resources.Canvas.t*string)list;mutable next_canvas_key:int }
let runtime_target=function Native->Runtime_next_orchestrator.Native
  |Headless->Headless|Web->Web
let create (configuration:configuration) =
  let operation="Prismel_next_execution.create" in
  let positive x=x>0 in
  if not(List.for_all positive[configuration.logical_width;configuration.logical_height;
      configuration.drawable_width;configuration.drawable_height;configuration.max_events;
      configuration.max_file_bytes])then fail operation Invalid_argument"dimensions and bounds must be positive"
  else(match configuration.timing with Fixed dt when not(finite dt&&dt>0.)->
      fail operation Invalid_argument"fixed dt must be finite and positive"|_->
    let config:Runtime_next_orchestrator.configuration={target=runtime_target configuration.target;
      logical_width=configuration.logical_width;logical_height=configuration.logical_height;
      drawable_width=configuration.drawable_width;drawable_height=configuration.drawable_height;
      web_configuration=None}in
    match Runtime_next_orchestrator.create config with Error e->backend operation e|Ok runtime->
      match Runtime_next_input.create~max_events:configuration.max_events
        ~max_file_bytes:configuration.max_file_bytes~logical_width:configuration.logical_width
        ~logical_height:configuration.logical_height with
      |Error message->ignore(Runtime_next_orchestrator.destroy runtime);fail operation Backend message
      |Ok input->Ok{runtime;input;assets=Prismel_next_resources.Assets.create();timing=configuration.timing;
          frame=0L;elapsed=0.;last_clock=Unix.gettimeofday();dead=false;snapshots=[];
          canvas_keys=[];next_canvas_key=0})
let target value=match Runtime_next_orchestrator.target value.runtime with Native->Native|Headless->Headless|Web->Web
let assets value=value.assets
let snapshot_cache_entries value=List.length value.snapshots
let ensure operation value=if value.dead then fail operation Destroyed"coordinator is destroyed"else Ok()
type stats=Runtime_next_orchestrator.stats={frames:int64;presented:int64;logical_draws:int64;
  logical_passes:int64;logical_submissions:int64;uploaded_bytes:int64;cache_entries:int}
let stats value=match ensure"Prismel_next_execution.stats"value with Error _ as e->e|Ok()->
  Result.map_error(fun error->{operation="Prismel_next_execution.stats";kind=Backend;
    message=Ogpu.Error.to_string error})(Runtime_next_orchestrator.stats value.runtime)
let snapshot value ~density source =
  let operation="Prismel_next_execution.lower_scene2"in
  if density<=0 then fail operation Invalid_argument"density must be positive"else
  let finish key generation width height pixels =
    match List.find_opt(fun(k,g,d,_)->k=key&&g=generation&&d=density)value.snapshots with
    |Some(_,_,_,texture)->Ok(width,height,texture)
    |None->
        let sampler:Ogpu.Types.sampler_descriptor={label=Some key;min_filter=Linear;mag_filter=Linear;
          mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
        let texture:Scene_execution.sampled_texture={key=key^":"^string_of_int density;
          levels=[|{width;height;bytes=Bytes.copy pixels}|];sampler}in
        let others=List.filter(fun(k,_,d,_)->k<>key||d<>density)value.snapshots in
        value.snapshots<-(key,generation,density,texture)::others;
        if List.length value.snapshots>256 then value.snapshots<-List.rev(List.tl(List.rev value.snapshots));
        Ok(width,height,texture)in
  match source with
  |Image image->(match Prismel_next_resources.Image.size image,Prismel_next_resources.Image.pixels image with
      |Ok(width,height),Ok pixels->finish("image:"^string_of_int(Prismel_next_resources.Image.identity image))(Prismel_next_resources.Image.generation image)width height pixels
      |Error e,_|_,Error e->resource operation e)
  |Text text->(match Prismel_next_resources.Text.size text,Prismel_next_resources.Text.pixels text with
      |Ok(width,height),Ok pixels->finish("text:"^Digest.to_hex(Digest.bytes pixels))(Prismel_next_resources.Text.generation text)width height pixels
      |Error e,_|_,Error e->resource operation e)
  |Canvas canvas->(match Prismel_next_resources.Canvas.capture canvas with Error e->resource operation e|Ok image->
      let key=match List.find_opt(fun(source,_)->source==canvas)value.canvas_keys with Some(_,key)->key|None->
        let key="canvas:"^string_of_int value.next_canvas_key in value.next_canvas_key<-value.next_canvas_key+1;
        value.canvas_keys<-(canvas,key)::value.canvas_keys;if List.length value.canvas_keys>256 then value.canvas_keys<-List.rev(List.tl(List.rev value.canvas_keys));key in
      let result=match Prismel_next_resources.Image.size image,Prismel_next_resources.Image.pixels image with
        |Ok(width,height),Ok pixels->finish key(Prismel_next_resources.Canvas.generation canvas)width height pixels
        |Error e,_|_,Error e->resource operation e in ignore(Prismel_next_resources.Image.destroy image);result)
let lower_scene2 value ~density ~resource:resolve ir =
  match ensure"Prismel_next_execution.lower_scene2"value with Error _ as e->e|Ok()->
  let identity={Raster2.Render_ir.xx=1.;xy=0.;yx=0.;yy=1.;tx=0.;ty=0.}in
  let facts=Runtime_next_orchestrator.facts value.runtime|>Result.get_ok in
  let transforms=ref[identity]and clips=ref[(0,0,facts.drawable_width,facts.drawable_height)]and draws=ref[]and number=ref 0 and failure=ref None in
  let point transform x y=transform.Raster2.Render_ir.xx*.x+.transform.yx*.y+.transform.tx,
    transform.xy*.x+.transform.yy*.y+.transform.ty in
  let clip_live()=let _,_,width,height=List.hd!clips in width>0&&height>0 in
  let quad texture (destination:Raster2.Render_ir.rect) =
    let transform=List.hd!transforms in
    let x0,y0=point transform destination.Raster2.Render_ir.x destination.y
    and x1,y0'=point transform(destination.x+.destination.width)destination.y
    and x1',y1=point transform(destination.x+.destination.width)(destination.y+.destination.height)
    and x0',y1'=point transform destination.x(destination.y+.destination.height)in
    let vertices=Bytes.make(68*4)'\000'in
    let source=match texture with _->destination in ignore source;
    let put index x y u v=let offset=index*68 in put_float vertices offset x;put_float vertices(offset+8)y;
      put_float vertices(offset+40)1.;Bytes.set_int32_le vertices(offset+48)0xffffffffl;put_float vertices(offset+52)u;put_float vertices(offset+60)v in
    put 0 x0 y0 0. 0.;put 1 x1 y0' 1. 0.;put 2 x1' y1 1. 1.;put 3 x0' y1' 0. 1.;
    let indices=Bytes.create 24 in List.iteri(fun i n->Bytes.set_int32_le indices(i*4)(Int32.of_int n))[0;1;2;0;2;3];
    let x,y,w,h=List.hd!clips in
    {family=Scene2_textured;blend=Alpha;texture=Some texture;auxiliary=None;samples=1;
      value={Scene_execution.mesh={key=Printf.sprintf"snapshot-%d"!number;vertices;vertex_count=4;indices;index_count=6};state=default_state(x,y,w,h)(x,y,w,h)}}in
  let image (command:Raster2.Render_ir.image) = match resolve command.Raster2.Render_ir.resource_id with None->failure:=Some"resource id is unbound"|Some source->
    match snapshot value~density source with Error e->failure:=Some(Format.asprintf"%a"pp_error e)|Ok(width,height,texture)->
      let s=command.source in if width<=0||height<=0 then failure:=Some"resource extent is invalid"else
      let draw=quad texture command.destination in
      let vertices=Bytes.copy draw.value.mesh.vertices in
      let u0=s.x/.float width and v0=s.y/.float height and u1=(s.x+.s.width)/.float width and v1=(s.y+.s.height)/.float height in
      List.iteri(fun index(u,v)->put_float vertices(index*68+52)u;put_float vertices(index*68+60)v)[u0,v0;u1,v0;u1,v1;u0,v1];
      draws:={draw with value={draw.value with mesh={draw.value.mesh with vertices}}}::!draws;incr number in
  Array.iter(fun command->if!failure=None then match command with
    |Raster2.Render_ir.Clear _|Set_blend _->()
    |Push_transform transform->transforms:=compose(List.hd!transforms)transform::!transforms
    |Pop_transform->(match!transforms with _::(_::_ as rest)->transforms:=rest|_->())
    |Push_clip rect->let px,py,pw,ph=List.hd!clips and x=int_of_float(floor rect.x)
      and y=int_of_float(floor rect.y)and right=int_of_float(ceil(rect.x+.rect.width))
      and bottom=int_of_float(ceil(rect.y+.rect.height))in
      let x=min(px+pw)(max px x)and y=min(py+ph)(max py y)in
      let right=min(px+pw)right and bottom=min(py+ph)bottom in
      clips:=(x,y,max 0(right-x),max 0(bottom-y))::!clips
    |Pop_clip->(match!clips with _::(_::_ as rest)->clips:=rest|_->())
    |Geometry geometry->if clip_live()then(draws:=mesh_of_geometry!number(List.hd!transforms)(List.hd!clips)geometry::!draws;incr number)
    |Debug_text debug->if clip_live()then
        let geometry=debug_text_geometry(List.hd!transforms)debug in
        if Array.length geometry.indices>0 then begin
          draws:=mesh_of_geometry!number identity(List.hd!clips)geometry::!draws;
          incr number
        end
    |Image command->if clip_live()then image command
    |Glyphs glyphs->if clip_live()&&Array.length glyphs.glyphs>0 then match resolve glyphs.resource_id with None->failure:=Some"glyph resource id is unbound"|Some source->
        match snapshot value~density source with Error e->failure:=Some(Format.asprintf"%a"pp_error e)|Ok(width,height,texture)->
          Array.iter(fun(glyph:Raster2.Render_ir.glyph)->let destination={Raster2.Render_ir.x=glyph.x;y=glyph.y;width=float width;height=float height}in draws:=quad texture destination::!draws;incr number)glyphs.glyphs)
    (Raster2.Render_ir.Private.commands_readonly ir);
  match!failure with Some message->fail"Prismel_next_execution.lower_scene2"Resource message
  |None->Ok(batch_scene2_draws(List.rev!draws))
let mb_to_input=function Left->Runtime_next_input.Left|Middle->Middle|Right->Right|X1->X1|X2->X2
let mb_of_web=function Runtime_next_orchestrator.Left->Left|Middle->Middle|Right->Right|X1->X1|X2->X2
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
  match Runtime_next_orchestrator.resize value.runtime~logical_width~logical_height~drawable_width~drawable_height with
  |Ok()->push_event value(Resized(logical_width,logical_height))|Error e->backend"Prismel_next_execution.resize"e
let set_text_regions value regions=match ensure"Prismel_next_execution.set_text_regions"value with Error _ as e->e|Ok()->
  let regions=List.map(fun r->{Runtime_next_orchestrator.x=r.x;y=r.y;width=r.width;height=r.height;focused=r.focused})regions in
  match Runtime_next_orchestrator.set_text_input_regions value.runtime regions with Ok()->Ok()|Error e->backend"Prismel_next_execution.set_text_regions"e
let register_asset value ?content_type bytes=match ensure"Prismel_next_execution.register_asset"value with Error _ as e->e|Ok()->
  match Runtime_next_orchestrator.register_web_bytes value.runtime?content_type bytes with Ok x->Ok x|Error e->backend"Prismel_next_execution.register_asset"e
let remove_asset value asset=match ensure"Prismel_next_execution.remove_asset"value with Error _ as e->e|Ok()->
  match Runtime_next_orchestrator.remove_web_asset value.runtime asset with Ok x->Ok x|Error e->backend"Prismel_next_execution.remove_asset"e
let audio_command=function Prismel_next_resources.Audio.Master_volume x->Runtime_next_orchestrator.Audio_master_volume x
  |Stop_all->Audio_stop_all|Sample_play{asset;channel;loops;volume}->Audio_sample_play{asset;channel;loops;volume}|Sample_stop x->Audio_sample_stop x
  |Sample_pause x->Audio_sample_pause x|Sample_resume x->Audio_sample_resume x
  |Music_play{asset;loops;fade_ms}->Audio_music_play{asset;loops;fade_ms}|Music_volume x->Audio_music_volume x|Music_pause->Audio_music_pause
  |Music_resume->Audio_music_resume|Music_stop x->Audio_music_stop x|Asset_remove x->Audio_asset_remove x
let send_audio value intent=match ensure"Prismel_next_execution.send_audio"value with Error _ as e->e|Ok()->
  match Runtime_next_orchestrator.send_web_audio value.runtime(audio_command intent)with Ok()->Ok()|Error e->backend"Prismel_next_execution.send_audio"e
let download_frame value ~filename=match ensure"Prismel_next_execution.download_frame"value with Error _ as e->e|Ok()->
  match Runtime_next_orchestrator.download_web_frame value.runtime~filename with Ok()->Ok()|Error e->backend"Prismel_next_execution.download_frame"e
let mod_of_input=function Runtime_next_input.Shift->Shift|Control->Control|Alt->Alt|Meta->Meta|Num_lock->Num_lock|Caps_lock->Caps_lock|Scroll_lock->Scroll_lock
let event_of_input=function Runtime_next_input.Pointer_moved(x,y)->Pointer_moved(x,y)|Pointer_pressed(b,x,y)->Pointer_pressed((match b with Left->Left|Middle->Middle|Right->Right|X1->X1|X2->X2),x,y)
  |Pointer_released(b,x,y)->Pointer_released((match b with Left->Left|Middle->Middle|Right->Right|X1->X1|X2->X2),x,y)
  |Pointer_cancelled b->Pointer_cancelled(match b with Left->Left|Middle->Middle|Right->Right|X1->X1|X2->X2)
  |Wheel(x,y)->Wheel(x,y)|Key_pressed k->Key_pressed{name=k.key;modifiers=List.map mod_of_input k.modifiers;repeat=k.repeat}|Key_released k->Key_released{name=k.key;modifiers=List.map mod_of_input k.modifiers;repeat=k.repeat}
  |Text_input s->Text_input s|Text_editing{text;start;length}->Text_editing{text;start;length}|Focus_lost->Focus_lost|Focus_gained->Focus_gained
  |Visibility_changed x->Visibility_changed x|Quit->Quit|Resized(x,y)->Resized(x,y)|File_dropped{name;contents}->File_dropped{name;contents}
let push_web value =
  if target value<>Web then Ok()else match Runtime_next_orchestrator.drain_web_events value.runtime with Error e->backend"Prismel_next_execution.step"e|Ok events->
    let convert=function Runtime_next_orchestrator.Pointer_moved(x,y)->Pointer_moved(float x,float y)
      |Pointer_pressed(b,x,y)->Pointer_pressed(mb_of_web b,float x,float y)|Pointer_released(b,x,y)->Pointer_released(mb_of_web b,float x,float y)
      |Pointer_cancelled b->Pointer_cancelled(mb_of_web b)|Wheel(x,y)->Wheel(float x,float y)
      |Key_pressed name->Key_pressed{name;modifiers=[];repeat=false}|Key_released name->Key_released{name;modifiers=[];repeat=false}
      |Text_input s->Text_input s|Text_editing{text;start;length}->Text_editing{text;start;length}|Resized(x,y)->Resized(x,y)|Focus_lost->Focus_lost
      |File_uploaded{name;contents}->File_dropped{name;contents=Some contents}in
    let rec all=function []->Ok()|x::xs->match push_event value(convert x)with Ok()->all xs|Error _ as e->e in all events
let step value draws=match ensure"Prismel_next_execution.step"value with Error _ as e->e|Ok()->
  Runtime_next_input.begin_frame value.input;
  match push_web value with Error _ as e->e|Ok()->
  match Runtime_next_orchestrator.facts value.runtime with Error e->backend"Prismel_next_execution.step"e|Ok f->
    let family=function Scene2->Runtime_next_orchestrator.Scene2|Scene2_textured->Scene2_textured|Scene3->Scene3
      |Scene3_textured->Scene3_textured|Scene3_shadow->Scene3_shadow|Scene3_stencil->Scene3_stencil
      |Scene3_textured_stencil->Scene3_textured_stencil|Scene3_shadow_stencil->Scene3_shadow_stencil in
    let blend=function Replace->Runtime_next_orchestrator.Replace|Alpha->Alpha|Add->Add
      |Multiply->Multiply|Screen->Screen|Subtract->Subtract in
    let draws=List.map(fun x->let draw=x.value in let state=draw.Scene_execution.state in
      let viewport=match state.viewport with _,_,w,h when w<0||h<0->0,0,f.logical_width,f.logical_height|x->x in
      let scissor=match state.scissor with _,_,w,h when w<0||h<0->0,0,f.logical_width,f.logical_height|x->x in
      {Runtime_next_orchestrator.family=family x.family;blend=blend x.blend;texture=x.texture;
        auxiliary=x.auxiliary;samples=x.samples;draw={draw with Scene_execution.state={state with viewport;scissor}}})draws in
    match Runtime_next_orchestrator.render_prepared value.runtime draws with Error e->backend"Prismel_next_execution.step"e|Ok _->
      let now=Unix.gettimeofday()in let dt=match value.timing with Fixed dt->dt|Variable->max 0.(now-.value.last_clock)in
      value.last_clock<-now;value.elapsed<-value.elapsed+.dt;value.frame<-Int64.succ value.frame;
      let events=List.map event_of_input(Runtime_next_input.drain value.input)and input=Runtime_next_input.snapshot value.input in
      Ok{frame=value.frame;time=value.elapsed;dt;logical_width=f.logical_width;logical_height=f.logical_height;
        drawable_width=f.drawable_width;drawable_height=f.drawable_height;pixel_scale=f.pixel_density;
        events;pointer=input.pointer;mouse_delta=input.mouse_delta;wheel_delta=input.wheel_delta;dropped_events=input.dropped_events}
let capture value=match ensure"Prismel_next_execution.capture"value with Error _ as e->e|Ok()->
  match Runtime_next_orchestrator.facts value.runtime with Error e->backend"Prismel_next_execution.capture"e|Ok facts->
  match Runtime_next_orchestrator.capture value.runtime~bytes_per_row:(facts.drawable_width*4)with Ok x->Ok x|Error e->backend"Prismel_next_execution.capture"e
let destroy value=if value.dead then Ok()else(
  match Prismel_next_resources.Assets.destroy value.assets with Error e->resource"Prismel_next_execution.destroy"e|Ok()->
    value.snapshots<-[];value.canvas_keys<-[];value.dead<-true;match Runtime_next_orchestrator.destroy value.runtime with Ok()->Ok()|Error e->backend"Prismel_next_execution.destroy"e)
let run configuration body ~on_stop = match create configuration with Error _ as e->e|Ok value->
  let outcome=try body value with exn->fail"Prismel_next_execution.run"Backend(Printexc.to_string exn)in
  let stopped=try on_stop value with exn->fail"Prismel_next_execution.on_stop"Backend(Printexc.to_string exn)in
  let closed=destroy value in match outcome,stopped,closed with
  |(Error _ as e),_,_->e
  |Ok _,(Error _ as e),_->e
  |Ok _,Ok(),(Error _ as e)->e
  |Ok x,Ok(),Ok()->Ok x
