type format=Rgba8|Bgra8|Depth32|Stencil8|Depth32_stencil8
type usage=Render_target|Resolve_target
type texture={id:int64;handle:unit Handle.t;format:format;samples:int;width:int;height:int;usage:usage list}
type load=Load|Clear|Dont_care
type store=Store|Discard|Resolve
type color={texture:texture;resolve:texture option;load:load;store:store;clear:float*float*float*float}
type depth={texture:texture;load:load;store:store;clear:float}
type stencil={texture:texture;load:load;store:store;clear:int}
type rect={x:int;y:int;width:int;height:int}
type descriptor={colors:color option array;depth:depth option;stencil:stencil option;viewport:rect;scissor:rect}
type cull=Cull_none|Cull_front|Cull_back
type comparison=Never|Less|Equal|Less_equal|Greater|Not_equal|Greater_equal|Always
type raster_state={cull:cull;depth_compare:comparison;depth_write:bool}
type stencil_operation=Keep|Zero|Replace|Increment_clamp|Decrement_clamp|Invert|Increment_wrap|Decrement_wrap
type stencil_face={compare:comparison;stencil_fail:stencil_operation;depth_fail:stencil_operation;pass:stencil_operation;read_mask:int32;write_mask:int32}
type stencil_state={front:stencil_face;back:stencil_face;front_reference:int32;back_reference:int32}
type t={descriptor:descriptor;raster_state:raster_state;stencil_state:stencil_state option;resources:(int64*Command.access)array}
type primitive=Triangle_list|Triangle_strip
type index_type=Uint16|Uint32
type buffer_binding={stage:Command.stage;index:int;buffer_id:int64;offset:int64}
type texture_binding={stage:Command.stage;index:int;texture_id:int64}
type sampler_binding={stage:Command.stage;index:int;sampler:Types.sampler_descriptor}
type draw={pipeline_key:string;buffers:buffer_binding list;textures:texture_binding list;samplers:sampler_binding list;primitive:primitive;vertex_start:int;vertex_count:int;index:(index_type*int64*int64*int)option}
type submission={pass:t;draws:draw list}
let invalid text=Error(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument text)
let color_format=function Rgba8|Bgra8->true|_->false
let depth_format=function Depth32|Depth32_stencil8->true|_->false
let stencil_format=function Stencil8|Depth32_stencil8->true|_->false
let finite4(a,b,c,d)=List.for_all Float.is_finite[a;b;c;d]
let valid_rect bounds r=r.x>=0&&r.y>=0&&r.width>0&&r.height>0&&r.x<=bounds.width-r.width&&r.y<=bounds.height-r.height
let default_raster_state={cull=Cull_none;depth_compare=Always;depth_write=false}
let default_stencil_face={compare=Always;stencil_fail=Keep;depth_fail=Keep;pass=Keep;read_mask=Int32.minus_one;write_mask=Int32.minus_one}
let default_stencil_state={front=default_stencil_face;back=default_stencil_face;front_reference=0l;back_reference=0l}
let create ?(raster_state=default_raster_state) ?stencil_state device descriptor=
  if Array.length descriptor.colors>8 then invalid"more than eight color attachments"else let seen=Hashtbl.create 16 and resources=ref[]and extent=ref None and failure=ref None in
  let texture role expected usage texture=if !failure=None then match Handle.validate_for ~operation:"Ogpu.Render_pass.create"device texture.handle with Error e->failure:=Some e|Ok()when texture.id<=0L||texture.samples<=0||texture.width<=0||texture.height<=0->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"attachment dimensions/id/sample count are invalid")|Ok()when not(expected texture.format)||not(List.mem usage texture.usage)->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument(role^" attachment format/usage is incompatible"))|Ok()when Hashtbl.mem seen texture.id->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"attachment resource is duplicated")|Ok()->Hashtbl.add seen texture.id();resources:=(texture.id,Command.Write)::!resources;match!extent with None->extent:=Some(texture.width,texture.height)|Some(w,h)when w<>texture.width||h<>texture.height->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"attachment extents differ")|Some _->()in
  Array.iter(function None->()|Some(color:color)->texture"color"color_format Render_target color.texture;if not(finite4 color.clear)then failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"color clear value is non-finite");match color.store,color.resolve with Resolve,Some target->texture"resolve"color_format Resolve_target target;if target.samples<>1||target.format<>color.texture.format||color.texture.samples=1 then failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"resolve target format/sample count is incompatible")|Resolve,None->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"resolve store requires a target")|_,Some _->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"resolve target requires resolve store")|_,None->())descriptor.colors;
  Option.iter(fun(depth:depth)->texture"depth"depth_format Render_target depth.texture;if not(Float.is_finite depth.clear)||depth.clear<0.||depth.clear>1. then failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"depth clear is invalid"))descriptor.depth;
  Option.iter(fun(stencil:stencil)->texture"stencil"stencil_format Render_target stencil.texture;if stencil.clear<0||stencil.clear>255 then failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"stencil clear is invalid"))descriptor.stencil;
  match!failure,!extent with Some e,_->Error e|None,None->invalid"render pass has no attachments"|None,Some(width,height)->let bounds={x=0;y=0;width;height}in if not(valid_rect bounds descriptor.viewport&&valid_rect bounds descriptor.scissor)then invalid"viewport/scissor is outside attachment extent"else if (raster_state.depth_compare<>Always||raster_state.depth_write)&&Option.is_none descriptor.depth then invalid"depth state requires a depth attachment"else if Option.is_some stencil_state&&Option.is_none descriptor.stencil then invalid"stencil state requires a stencil attachment"else Ok{descriptor={descriptor with colors=Array.copy descriptor.colors};raster_state;stencil_state;resources=Array.of_list(List.rev!resources)}
let descriptor value={value.descriptor with colors=Array.copy value.descriptor.colors}
let raster_state value=value.raster_state
let stencil_state value=value.stencil_state
let encode value command=Result.bind(Command.begin_pass command Command.Render)(fun()->let declared=Array.fold_left(fun result(id,access)->Result.bind result(fun()->Command.declare_resource command ~resource_id:id ~access ~stages:[Command.Fragment]))(Ok())value.resources in Result.bind declared(fun()->Command.end_pass command))
let submit pass draws =
  let invalid text =
    Error (Error.make "Ogpu.Render_pass.submit" Error.Invalid_argument text)
  in
  if draws = [] then invalid "render submission has no draws"
  else
    let seen_buffers=Hashtbl.create 16 and seen_textures=Hashtbl.create 16 and seen_samplers=Hashtbl.create 16 in
    let valid_stage = function Command.Vertex | Fragment -> true | _ -> false in
    let rec bindings = function
      | [] -> Ok ()
      | (`Buffer (b : buffer_binding)) :: _
        when (not (valid_stage b.stage)) || b.index < 0 || b.index > 30
             || b.buffer_id <= 0L || b.offset < 0L ->
          invalid "buffer binding is invalid"
      | `Texture (t : texture_binding) :: _
        when (not (valid_stage t.stage)) || t.index < 0 || t.index > 30
             || t.texture_id <= 0L ->
          invalid "texture binding is invalid"
      | `Sampler (s : sampler_binding) :: _ when(not(valid_stage s.stage))||s.index<0||s.index>30->invalid "sampler binding is invalid"
      | `Buffer b :: xs ->
          let key = (b.stage, b.index) in
          if Hashtbl.mem seen_buffers key then invalid "buffer stage/index is duplicated"
          else (
            Hashtbl.add seen_buffers key ();
            bindings xs)
      | `Texture t :: xs ->
          let key = (t.stage, t.index) in
          if Hashtbl.mem seen_textures key then invalid "texture stage/index is duplicated"
          else (
            Hashtbl.add seen_textures key ();
            bindings xs)
      | `Sampler s :: xs ->
          let key=(s.stage,s.index)in(match Types.validate_sampler s.sampler with Error _ as e->e|Ok()->if Hashtbl.mem seen_samplers key then invalid "sampler stage/index is duplicated"else(Hashtbl.add seen_samplers key();bindings xs))
    in
    let rec loop = function
      | [] -> Ok { pass; draws }
      | d :: _ when d.pipeline_key = "" || d.vertex_start < 0 || d.vertex_count <= 0 ->
          invalid "draw pipeline/range is invalid"
      | d :: _ when d.textures<>[]&&d.samplers=[]->invalid "sampled textures require sampler state"
      | d :: _
        when d.primitive = Triangle_list && Option.is_none d.index
             && d.vertex_count mod 3 <> 0 ->
          invalid "triangle-list count is not divisible by three"
      | d :: _ when d.primitive = Triangle_strip && d.vertex_count < 3 ->
          invalid "triangle strip requires three vertices"
      | d :: ds ->
          Hashtbl.clear seen_buffers;Hashtbl.clear seen_textures;Hashtbl.clear seen_samplers;
          (match
             bindings
               (List.map (fun x -> `Buffer x) d.buffers
               @ List.map (fun x -> `Texture x) d.textures
               @ List.map (fun x -> `Sampler x) d.samplers)
           with
          | Error _ as e -> e
          | Ok () -> (
              match d.index with
              | Some (_, id, offset, count)
                when id <= 0L || offset < 0L || count <= 0 ->
                  invalid "index draw is invalid"
              | _ -> loop ds))
    in
    loop draws
let submission_pass value=value.pass
let submission_draws value=value.draws
