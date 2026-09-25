type operation=
  | Copy of Buffer.t*int64*Buffer.t*int64*int64
  | Compute of string*string*Buffer.t*int
  | Dispatch of Pipeline.t*Buffer.t*int
  | Clear of Texture.t*(float*float*float*float)
  | Draw_triangle of Pipeline.t*Texture.t
type t={portable:Ogpu_core.Command.t;mutable operations:operation list;mutable ended:bool}
let create()={portable=Ogpu_core.Command.begin_encoder();operations=[];ended=false}
let error op message=Error(Ogpu_core.Error.make op Ogpu_core.Error.Invalid_state message)
let add value pass operation resources =
  if value.ended then error"Ogpu_metal.Command.record""command is ended"else
  match Ogpu_core.Command.begin_pass value.portable pass with Error _ as e->e|Ok()->
  let rec declare=function []->Ok()|(id,access,stages)::rest->(match Ogpu_core.Command.declare_resource value.portable~resource_id:id~access~stages with Error _ as e->e|Ok()->declare rest)in
  match declare resources with Error _ as e->e|Ok()->match Ogpu_core.Command.end_pass value.portable with Error _ as e->e|Ok()->value.operations<-operation::value.operations;Ok()
let copy_buffer value~source~source_offset~destination~destination_offset~length=
  if length<=0L||source_offset<0L||destination_offset<0L then Error(Ogpu_core.Error.make"Ogpu_metal.Command.copy_buffer"Ogpu_core.Error.Invalid_argument"copy range is invalid")else
  add value Ogpu_core.Command.Transfer (Copy(source,source_offset,destination,destination_offset,length))
    [Buffer.id source,Ogpu_core.Command.Read,[Ogpu_core.Command.Transfer_stage];Buffer.id destination,Write,[Transfer_stage]]
let compute value~source~entry~buffer~threads=
  if threads<=0||source=""||entry="" then Error(Ogpu_core.Error.make"Ogpu_metal.Command.compute"Ogpu_core.Error.Invalid_argument"compute payload is invalid")else
  add value Ogpu_core.Command.Compute (Compute(source,entry,buffer,threads))[Buffer.id buffer,Ogpu_core.Command.Read_write,[Ogpu_core.Command.Compute_stage]]
let dispatch value~pipeline~buffer~threads=
  if threads<=0 then Error(Ogpu_core.Error.make"Ogpu_metal.Command.dispatch"Ogpu_core.Error.Invalid_argument"thread count is invalid")else
  add value Ogpu_core.Command.Compute(Dispatch(pipeline,buffer,threads))[Buffer.id buffer,Ogpu_core.Command.Read_write,[Ogpu_core.Command.Compute_stage]]
let clear value texture~color=add value Ogpu_core.Command.Render(Clear(texture,color))[Texture.id texture,Ogpu_core.Command.Write,[Ogpu_core.Command.Fragment]]
let draw_triangle value~pipeline~target=add value Ogpu_core.Command.Render(Draw_triangle(pipeline,target))[Texture.id target,Ogpu_core.Command.Write,[Ogpu_core.Command.Fragment]]
let end_ value=if value.ended then error"Ogpu_metal.Command.end""command already ended"else match Ogpu_core.Command.end_encoder value.portable with Error _ as e->e|Ok()->value.ended<-true;Ok()
let descriptions value=Ogpu_core.Command.descriptions value.portable
module Private=struct
  type nonrec operation=operation=Copy of Buffer.t*int64*Buffer.t*int64*int64|Compute of string*string*Buffer.t*int|Dispatch of Pipeline.t*Buffer.t*int|Clear of Texture.t*(float*float*float*float)|Draw_triangle of Pipeline.t*Texture.t
  let portable value=value.portable
  let operations value=List.rev value.operations
end
