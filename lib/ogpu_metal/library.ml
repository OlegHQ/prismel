type t={metal:Metal.Library.t;device:Device.t;shader:Ogpu_core.Shader.t;handle:unit Ogpu_core.Handle.t;mutable pipelines:int;mutable dead:bool;dynamic:Metal.Dynamic_library.t list}
let error op kind message=Error(Ogpu_core.Error.make op kind message)
let compile_native ?(dynamic=[]) op device shader=
  if Ogpu_core.Shader.backend shader<>"metal"then
    error op Ogpu_core.Error.Invalid_argument"shader backend is not metal"
  else
    let bytes=Bytes.to_string(Ogpu_core.Shader.bytes shader) in
    let result=match Ogpu_core.Shader.format shader,dynamic with
      |Ogpu_core.Shader.Msl_source,[]->Metal.Library.compile_source
        ~device:(Device.Private.metal device)
        ?label:(Ogpu_core.Shader.label shader) bytes
      (* Source linked against dynamic libraries resolves their symbols now. *)
      |Ogpu_core.Shader.Msl_source,libraries->Metal.Dynamic_library.compile_source
        ~device:(Device.Private.metal device) ~libraries
        ?label:(Ogpu_core.Shader.label shader) bytes
      |Ogpu_core.Shader.Metallib,_->Metal.Library.load_data
        ~device:(Device.Private.metal device) bytes in
    Result.map_error(Device.of_metal_error~operation:op)result
let create ?(dynamic=[]) device shader=
  let op="Ogpu_metal.Library.create"in
  if Device.destroyed device then error op Ogpu_core.Error.Stale_handle"device is destroyed"
  else match compile_native ~dynamic op device shader with Error _ as e->e|Ok metal->
    Device.Private.attach_resource device;
    Ok{metal;device;shader;handle=Ogpu_core.Handle.create~device:(Device.Private.handle device);pipelines=0;dead=false;dynamic}
let validate device value=Ogpu_core.Handle.validate_for~operation:"Ogpu_metal.Library.validate"(Device.Private.handle device)value.handle
let shader value=value.shader
let destroyed value=value.dead
let destroy value=
  let op="Ogpu_metal.Library.destroy"in
  if value.dead then Ok()
  else if value.pipelines>0 then error op Ogpu_core.Error.Invalid_state"library has live pipelines"
  else match Metal.Library.destroy value.metal with
    |Error e->Error(Device.of_metal_error~operation:op e)
    |Ok()->value.dead<-true;Ogpu_core.Handle.destroy value.handle;Device.Private.detach_resource value.device;Ok()
module Private=struct
  let metal value=value.metal
  let dynamic value=value.dynamic
  let attach_pipeline value=value.pipelines<-value.pipelines+1
  let detach_pipeline value=value.pipelines<-value.pipelines-1
end
