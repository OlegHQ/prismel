type filter=Nearest|Linear
type address_mode=Clamp_to_edge|Repeat|Mirror_repeat
type descriptor={min_filter:filter;mag_filter:filter;address_mode:address_mode;max_anisotropy:int;lod_min:float;lod_max:float;label:string option}
type sampler_kind
type t={metal:Metal.Sampler.t;handle:sampler_kind Ogpu.Handle.t;device:Device.t;descriptor:descriptor}
let default={min_filter=Linear;mag_filter=Linear;address_mode=Clamp_to_edge;max_anisotropy=1;lod_min=0.;lod_max=32.;label=None}
let filter=function Nearest->Metal.Sampler.Nearest|Linear->Metal.Sampler.Linear
let address=function Clamp_to_edge->Metal.Sampler.Clamp_to_edge|Repeat->Metal.Sampler.Repeat|Mirror_repeat->Metal.Sampler.Mirror_repeat
let create device descriptor=let operation="Ogpu_metal.Sampler.create"in
  if Device.destroyed device then Error(Ogpu.Error.make operation Ogpu.Error.Stale_handle "device is destroyed")
  else if descriptor.max_anisotropy<1||descriptor.max_anisotropy>16||not(Float.is_finite descriptor.lod_min)||not(Float.is_finite descriptor.lod_max)||descriptor.lod_min<0.||descriptor.lod_max<descriptor.lod_min then Error(Ogpu.Error.make operation Ogpu.Error.Invalid_argument "sampler limits are invalid")
  else let native={ (Metal.Sampler.default ?label:descriptor.label ()) with min_filter=filter descriptor.min_filter;mag_filter=filter descriptor.mag_filter;max_anisotropy=descriptor.max_anisotropy;s_address=address descriptor.address_mode;t_address=address descriptor.address_mode;r_address=address descriptor.address_mode;lod_min_clamp=descriptor.lod_min;lod_max_clamp=descriptor.lod_max}in
    match Metal.Sampler.create~device:(Device.Private.metal device)native with Error e->Error(Adapter.error~operation e)|Ok metal->let value={metal;handle=Ogpu.Handle.create~device:(Device.Private.handle device);device;descriptor}in Device.Private.attach_resource device;Ok value
let id value=Ogpu.Handle.id value.handle
let generation value=Ogpu.Handle.generation value.handle
let device_id value=Device.id value.device
let destroyed value=Ogpu.Handle.destroyed value.handle
let descriptor device value=Result.map(fun()->value.descriptor)(Ogpu.Handle.validate_for~operation:"Ogpu_metal.Sampler.descriptor"(Device.Private.handle device)value.handle)
let destroy value=let operation="Ogpu_metal.Sampler.destroy"in if destroyed value then Ok()else match Metal.Sampler.destroy value.metal with Error e->Error(Adapter.error~operation e)|Ok()->Ogpu.Handle.destroy value.handle;Device.Private.detach_resource value.device;Ok()
