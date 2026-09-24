type filter=Ogpu.Types.sampler_filter=Nearest|Linear
type mip_filter=Ogpu.Types.mip_filter=No_mip|Nearest_mip|Linear_mip
type address_mode=Ogpu.Types.address_mode=Clamp_to_edge|Repeat|Mirror_repeat
type descriptor=Ogpu.Types.sampler_descriptor
type sampler_kind
type t={metal:Metal.Sampler.t;handle:sampler_kind Ogpu.Handle.t;device:Device.t;descriptor:descriptor;mutable submissions:int}
let default:descriptor={min_filter=Linear;mag_filter=Linear;mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;max_anisotropy=1;lod_min=0.;lod_max=32.;label=None}
let filter=function Nearest->Metal.Sampler.Nearest|Linear->Metal.Sampler.Linear
let mip=function No_mip->Metal.Sampler.Not_mipmapped|Nearest_mip->Mip_nearest|Linear_mip->Mip_linear
let address=function Clamp_to_edge->Metal.Sampler.Clamp_to_edge|Repeat->Metal.Sampler.Repeat|Mirror_repeat->Metal.Sampler.Mirror_repeat
let create device (descriptor:descriptor)=let operation="Ogpu_metal.Sampler.create"in
  if Device.destroyed device then Error(Ogpu.Error.make operation Ogpu.Error.Stale_handle "device is destroyed")
  else if descriptor.max_anisotropy<1||descriptor.max_anisotropy>16||not(Float.is_finite descriptor.lod_min)||not(Float.is_finite descriptor.lod_max)||descriptor.lod_min<0.||descriptor.lod_max<descriptor.lod_min then Error(Ogpu.Error.make operation Ogpu.Error.Invalid_argument "sampler limits are invalid")
  else let native={ (Metal.Sampler.default ?label:descriptor.label ()) with min_filter=filter descriptor.min_filter;mag_filter=filter descriptor.mag_filter;mip_filter=mip descriptor.mip_filter;max_anisotropy=descriptor.max_anisotropy;s_address=address descriptor.address_u;t_address=address descriptor.address_v;r_address=address descriptor.address_v;lod_min_clamp=descriptor.lod_min;lod_max_clamp=descriptor.lod_max}in
    match Metal.Sampler.create~device:(Device.Private.metal device)native with Error e->Error(Adapter.error~operation e)|Ok metal->let value={metal;handle=Ogpu.Handle.create~device:(Device.Private.handle device);device;descriptor;submissions=0}in Device.Private.attach_resource device;Ok value
let id value=Ogpu.Handle.id value.handle
let generation value=Ogpu.Handle.generation value.handle
let device_id value=Device.id value.device
let destroyed value=Ogpu.Handle.destroyed value.handle
let descriptor device value=Result.map(fun()->value.descriptor)(Ogpu.Handle.validate_for~operation:"Ogpu_metal.Sampler.descriptor"(Device.Private.handle device)value.handle)
let destroy value=let operation="Ogpu_metal.Sampler.destroy"in if destroyed value then Ok()else if value.submissions>0 then Error(Ogpu.Error.make operation Ogpu.Error.Invalid_state"sampler is retained by submitted work")else match Metal.Sampler.destroy value.metal with Error e->Error(Adapter.error~operation e)|Ok()->Ogpu.Handle.destroy value.handle;Device.Private.detach_resource value.device;Ok()
module Private=struct let metal value=value.metal let descriptor value=value.descriptor let create_argument device(descriptor:descriptor)=let native={ (Metal.Sampler.default ?label:descriptor.label ()) with min_filter=filter descriptor.min_filter;mag_filter=filter descriptor.mag_filter;mip_filter=mip descriptor.mip_filter;max_anisotropy=descriptor.max_anisotropy;s_address=address descriptor.address_u;t_address=address descriptor.address_v;r_address=address descriptor.address_v;lod_min_clamp=descriptor.lod_min;lod_max_clamp=descriptor.lod_max;support_argument_buffers=true}in Metal.Sampler.create~device:(Device.Private.metal device)native let retain_submission value=if destroyed value then Error(Ogpu.Error.make"Ogpu_metal.Sampler.retain"Ogpu.Error.Stale_handle"sampler is destroyed")else(value.submissions<-value.submissions+1;Ok())let release_submission value=if value.submissions>0 then value.submissions<-value.submissions-1 end
