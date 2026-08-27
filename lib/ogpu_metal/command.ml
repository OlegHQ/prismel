type operation=
  | Copy of Buffer.t*int64*Buffer.t*int64*int64
  | Compute of string*string*Buffer.t*int
  | Clear of Texture.t*(float*float*float*float)
type t={portable:Ogpu.Command.t;mutable operations:operation list;mutable ended:bool}
let create()={portable=Ogpu.Command.begin_encoder();operations=[];ended=false}
let error op message=Error(Ogpu.Error.make op Ogpu.Error.Invalid_state message)
let add value pass operation resources =
  if value.ended then error"Ogpu_metal.Command.record""command is ended"else
  match Ogpu.Command.begin_pass value.portable pass with Error _ as e->e|Ok()->
  let rec declare=function []->Ok()|(id,access,stages)::rest->(match Ogpu.Command.declare_resource value.portable~resource_id:id~access~stages with Error _ as e->e|Ok()->declare rest)in
  match declare resources with Error _ as e->e|Ok()->match Ogpu.Command.end_pass value.portable with Error _ as e->e|Ok()->value.operations<-operation::value.operations;Ok()
let copy_buffer value~source~source_offset~destination~destination_offset~length=
  if length<=0L||source_offset<0L||destination_offset<0L then Error(Ogpu.Error.make"Ogpu_metal.Command.copy_buffer"Ogpu.Error.Invalid_argument"copy range is invalid")else
  add value Ogpu.Command.Transfer (Copy(source,source_offset,destination,destination_offset,length))
    [Buffer.id source,Ogpu.Command.Read,[Ogpu.Command.Transfer_stage];Buffer.id destination,Write,[Transfer_stage]]
let compute value~source~entry~buffer~threads=
  if threads<=0||source=""||entry="" then Error(Ogpu.Error.make"Ogpu_metal.Command.compute"Ogpu.Error.Invalid_argument"compute payload is invalid")else
  add value Ogpu.Command.Compute (Compute(source,entry,buffer,threads))[Buffer.id buffer,Ogpu.Command.Read_write,[Ogpu.Command.Compute_stage]]
let clear value texture~color=add value Ogpu.Command.Render(Clear(texture,color))[Texture.id texture,Ogpu.Command.Write,[Ogpu.Command.Fragment]]
let end_ value=if value.ended then error"Ogpu_metal.Command.end""command already ended"else match Ogpu.Command.end_encoder value.portable with Error _ as e->e|Ok()->value.ended<-true;Ok()
let descriptions value=Ogpu.Command.descriptions value.portable
module Private=struct
  type nonrec operation=operation=Copy of Buffer.t*int64*Buffer.t*int64*int64|Compute of string*string*Buffer.t*int|Clear of Texture.t*(float*float*float*float)
  let portable value=value.portable
  let operations value=List.rev value.operations
end
