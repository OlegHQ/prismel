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
type t={descriptor:descriptor;resources:(int64*Command.access)array}
let invalid text=Error(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument text)
let color_format=function Rgba8|Bgra8->true|_->false
let depth_format=function Depth32|Depth32_stencil8->true|_->false
let stencil_format=function Stencil8|Depth32_stencil8->true|_->false
let finite4(a,b,c,d)=List.for_all Float.is_finite[a;b;c;d]
let valid_rect bounds r=r.x>=0&&r.y>=0&&r.width>0&&r.height>0&&r.x<=bounds.width-r.width&&r.y<=bounds.height-r.height
let create device descriptor=
  if Array.length descriptor.colors>8 then invalid"more than eight color attachments"else let seen=Hashtbl.create 16 and resources=ref[]and extent=ref None and failure=ref None in
  let texture role expected usage texture=if !failure=None then match Handle.validate_for ~operation:"Ogpu.Render_pass.create"device texture.handle with Error e->failure:=Some e|Ok()when texture.id<=0L||texture.samples<=0||texture.width<=0||texture.height<=0->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"attachment dimensions/id/sample count are invalid")|Ok()when not(expected texture.format)||not(List.mem usage texture.usage)->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument(role^" attachment format/usage is incompatible"))|Ok()when Hashtbl.mem seen texture.id->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"attachment resource is duplicated")|Ok()->Hashtbl.add seen texture.id();resources:=(texture.id,Command.Write)::!resources;match!extent with None->extent:=Some(texture.width,texture.height)|Some(w,h)when w<>texture.width||h<>texture.height->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"attachment extents differ")|Some _->()in
  Array.iter(function None->()|Some(color:color)->texture"color"color_format Render_target color.texture;if not(finite4 color.clear)then failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"color clear value is non-finite");match color.store,color.resolve with Resolve,Some target->texture"resolve"color_format Resolve_target target;if target.samples<>1||target.format<>color.texture.format||color.texture.samples=1 then failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"resolve target format/sample count is incompatible")|Resolve,None->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"resolve store requires a target")|_,Some _->failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"resolve target requires resolve store")|_,None->())descriptor.colors;
  Option.iter(fun(depth:depth)->texture"depth"depth_format Render_target depth.texture;if not(Float.is_finite depth.clear)||depth.clear<0.||depth.clear>1. then failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"depth clear is invalid"))descriptor.depth;
  Option.iter(fun(stencil:stencil)->texture"stencil"stencil_format Render_target stencil.texture;if stencil.clear<0||stencil.clear>255 then failure:=Some(Error.make"Ogpu.Render_pass.create"Error.Invalid_argument"stencil clear is invalid"))descriptor.stencil;
  match!failure,!extent with Some e,_->Error e|None,None->invalid"render pass has no attachments"|None,Some(width,height)->let bounds={x=0;y=0;width;height}in if not(valid_rect bounds descriptor.viewport&&valid_rect bounds descriptor.scissor)then invalid"viewport/scissor is outside attachment extent"else Ok{descriptor={descriptor with colors=Array.copy descriptor.colors};resources=Array.of_list(List.rev!resources)}
let descriptor value={value.descriptor with colors=Array.copy value.descriptor.colors}
let encode value command=Result.bind(Command.begin_pass command Command.Render)(fun()->let declared=Array.fold_left(fun result(id,access)->Result.bind result(fun()->Command.declare_resource command ~resource_id:id ~access ~stages:[Command.Fragment]))(Ok())value.resources in Result.bind declared(fun()->Command.end_pass command))
