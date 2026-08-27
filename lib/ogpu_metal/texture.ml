type format = R8_unorm | Rgba8_unorm | Bgra8_unorm | Rgba16_float | Depth32_float
type memory = Device_local | Shared
type t =
  { metal : Metal.Texture.t; handle : unit Ogpu.Handle.t; device : Device.t
  ; descriptor : Ogpu.Types.texture_descriptor; format : format
  ; view_formats : format list; parent : t option; mutable live_views : int }

let error operation kind message = Error (Ogpu.Error.make operation kind message)
let metal_format = function R8_unorm->Metal.Texture.R8_unorm|Rgba8_unorm->Metal.Texture.Rgba8_unorm|Bgra8_unorm->Metal.Texture.Bgra8_unorm|Rgba16_float->Metal.Texture.Rgba16_float|Depth32_float->Metal.Texture.Depth32_float
let bytes_per_pixel = function R8_unorm->1|Rgba8_unorm|Bgra8_unorm|Depth32_float->4|Rgba16_float->8
let add_unique x xs = if List.mem x xs then xs else x :: xs
let validation_format=function R8_unorm->Ogpu.Validation.R8_unorm|Rgba8_unorm->Rgba8_unorm|Bgra8_unorm->Bgra8_unorm|Rgba16_float->Rgba16_float|Depth32_float->Depth32_float
let validation_storage=function Device_local->Ogpu.Validation.Device_local|Shared->Shared
let validation_usage=function Ogpu.Types.Texture_binding->Ogpu.Validation.Binding|Render_attachment->Attachment|Texture_copy_src->Copy_src|Texture_copy_dst->Copy_dst

let validate_descriptor (value : Ogpu.Types.texture_descriptor) format =
  let operation="Ogpu_metal.Texture.create" in
  let max_mips = 1 + int_of_float (Float.floor (Float.log2 (float_of_int (max value.width (max value.height value.depth))))) in
  if value.mip_levels > max_mips then error operation Ogpu.Error.Invalid_argument "mip count exceeds texture extent"
  else if not (List.mem value.sample_count [1;2;4]) then error operation Ogpu.Error.Invalid_argument "sample count must be 1, 2, or 4"
  else if value.sample_count > 1 && (value.depth <> 1 || value.mip_levels <> 1) then error operation Ogpu.Error.Invalid_argument "multisample textures are 2D and single-mip"
  else if format=Depth32_float && List.mem Ogpu.Types.Texture_binding value.usage then error operation Ogpu.Error.Invalid_argument "depth sampling is not exposed by this foundation"
  else Ok ()

let usage values =
  List.fold_left (fun result -> function
    | Ogpu.Types.Texture_binding -> add_unique Metal.Texture.Shader_read result
    | Render_attachment -> add_unique Metal.Texture.Render_target result
    | Texture_copy_src | Texture_copy_dst -> result) [] values

let create device ~memory ~format ?(view_formats=[]) descriptor =
  let operation="Ogpu_metal.Texture.create" in
  if Device.destroyed device then error operation Ogpu.Error.Stale_handle "device is destroyed"
  else match Ogpu.Types.validate_texture (Device.capabilities device) descriptor with Error _ as e->e|Ok()->
    let profile:Ogpu.Validation.texture_profile={format=validation_format format;storage=validation_storage memory;
      width=descriptor.width;height=descriptor.height;depth=descriptor.depth;mip_levels=descriptor.mip_levels;
      sample_count=descriptor.sample_count;usage=List.map validation_usage descriptor.usage}in
    match Ogpu.Validation.validate_texture_profile(Device.capabilities device)profile with Error _ as e->e|Ok()->
    match validate_descriptor descriptor format with Error _ as e->e|Ok()->
    let storage=match memory with Device_local->Metal.Buffer.Private|Shared->Metal.Buffer.Shared in
    let native_usage=usage descriptor.usage |> fun values -> if view_formats=[] then values else add_unique Metal.Texture.Pixel_format_view values in
    let base=Metal.Texture.descriptor_2d ~storage ~usage:native_usage ?label:descriptor.label ~format:(metal_format format) ~width:descriptor.width ~height:descriptor.height () in
    let native={base with kind=(if descriptor.sample_count>1 then Metal.Texture.Texture_2d_multisample else if descriptor.depth>1 then Texture_3d else Texture_2d);depth=descriptor.depth;mip_levels=descriptor.mip_levels;sample_count=descriptor.sample_count} in
    match Metal.Texture.create ~device:(Device.Private.metal device) native with Error e->Error(Adapter.error~operation e)|Ok metal->
      let value={metal;handle=Ogpu.Handle.create~device:(Device.Private.handle device);device;descriptor;format;view_formats;parent=None;live_views=0}in
      Device.Private.attach_resource device;Ok value

let validate operation device value=Ogpu.Handle.validate_for~operation(Device.Private.handle device)value.handle
let id value=Ogpu.Handle.id value.handle
let generation value=Ogpu.Handle.generation value.handle
let device_id value=Device.id value.device
let destroyed value=Ogpu.Handle.destroyed value.handle
let descriptor device value=Result.map(fun()->value.descriptor)(validate"Ogpu_metal.Texture.descriptor"device value)
let format device value=Result.map(fun()->value.format)(validate"Ogpu_metal.Texture.format"device value)

let create_view device parent ~format ~base_mip ~mip_count ~base_slice ~slice_count =
  let operation="Ogpu_metal.Texture.create_view" in
  match validate operation device parent with Error _ as e->e|Ok()->
  if not(List.mem format parent.view_formats) then error operation Ogpu.Error.Invalid_argument "view format was not declared"
  else if format <> parent.format then error operation Ogpu.Error.Invalid_argument "view format is not in the parent's compatibility class"
  else if base_mip<0||mip_count<=0||base_mip+mip_count>parent.descriptor.mip_levels||base_slice<>0||slice_count<>1 then error operation Ogpu.Error.Invalid_argument "view range is outside the parent"
  else match Metal.Texture.create_view parent.metal~format:(metal_format format)~base_mip~mip_count~base_slice~slice_count()with Error e->Error(Adapter.error~operation e)|Ok metal->
    let extent shift x=max 1(x lsr shift)in
    let descriptor={parent.descriptor with width=extent base_mip parent.descriptor.width;height=extent base_mip parent.descriptor.height;depth=extent base_mip parent.descriptor.depth;mip_levels=mip_count;sample_count=parent.descriptor.sample_count}in
    let value={metal;handle=Ogpu.Handle.create~device:(Device.Private.handle device);device;descriptor;format;view_formats=[];parent=Some parent;live_views=0}in
    parent.live_views<-parent.live_views+1;Device.Private.attach_resource device;Ok value

let read_bytes device value ~mip_level ~bytes_per_row =
  let operation="Ogpu_metal.Texture.read_bytes"in match validate operation device value with Error _ as e->e|Ok()->
  if mip_level<0||mip_level>=value.descriptor.mip_levels then error operation Ogpu.Error.Invalid_argument "mip level is outside the texture"
  else let width=max 1(value.descriptor.width lsr mip_level)and height=max 1(value.descriptor.height lsr mip_level)in
    let minimum=width*bytes_per_pixel value.format in
    if bytes_per_row<minimum||bytes_per_row>max_int/height then error operation Ogpu.Error.Invalid_argument "bytes_per_row is invalid"
    else match Metal.Texture.read_bytes value.metal~region:{x=0;y=0;z=0;width;height;depth=1}~mip_level~slice:0~bytes_per_row~bytes_per_image:(bytes_per_row*height)with Ok x->Ok x|Error e->Error(Adapter.error~operation e)

let write_bytes device value ~mip_level ~bytes_per_row bytes =
  let operation="Ogpu_metal.Texture.write_bytes"in match validate operation device value with Error _ as e->e|Ok()->
  if mip_level<0||mip_level>=value.descriptor.mip_levels then error operation Ogpu.Error.Invalid_argument "mip level is outside the texture"
  else let width=max 1(value.descriptor.width lsr mip_level)and height=max 1(value.descriptor.height lsr mip_level)in
    let minimum=width*bytes_per_pixel value.format in
    if bytes_per_row<minimum||bytes_per_row>max_int/height then error operation Ogpu.Error.Invalid_argument "texture row layout is invalid"
    else let required=bytes_per_row*height in
      if Bytes.length bytes<>required then error operation Ogpu.Error.Invalid_argument "texture byte cardinality is invalid"
      else match Metal.Texture.write_bytes value.metal~region:{x=0;y=0;z=0;width;height;depth=1}~mip_level~slice:0~bytes_per_row~bytes_per_image:required bytes with Ok()->Ok()|Error e->Error(Adapter.error~operation e)

let destroy value =
  let operation="Ogpu_metal.Texture.destroy"in if destroyed value then Ok()else if value.live_views<>0 then error operation Ogpu.Error.Invalid_state "texture still owns live views"else
  match Metal.Texture.destroy value.metal with Error e->Error(Adapter.error~operation e)|Ok()->Ogpu.Handle.destroy value.handle;Option.iter(fun parent->parent.live_views<-parent.live_views-1)value.parent;Device.Private.detach_resource value.device;Ok()

module Private=struct let metal value=value.metal let resource_handle value=value.handle end
