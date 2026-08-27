type format = R8_unorm | Rgba8_unorm | Bgra8_unorm | Rgba16_float | Depth32_float
type storage = Device_local | Shared | Upload | Readback
type texture_usage = Binding | Attachment | Copy_src | Copy_dst
type texture_profile =
  { format:format; storage:storage; width:int; height:int; depth:int;
    mip_levels:int; sample_count:int; usage:texture_usage list }

val validate_label : operation:string -> string option -> (unit,Error.t) result
val validate_buffer : operation:string -> max_size:int64 -> size:int64 ->
  usage_count:int -> (unit,Error.t) result
val validate_texture_shape : operation:string -> max_dimension:int ->
  max_samples:int -> width:int -> height:int -> depth:int -> mip_levels:int ->
  sample_count:int -> usage_count:int -> (unit,Error.t) result
val validate_texture_profile : Capabilities.t -> texture_profile -> (unit,Error.t) result
val validate_range : operation:string -> size:int64 -> offset:int64 ->
  length:int64 -> alignment:int64 -> (unit,Error.t) result
val validate_layout : operation:string -> (int * int list) list -> (unit,Error.t) result
val validate_groups : operation:string -> max_groups:int -> int list -> (unit,Error.t) result
val format_storage_table : (format * storage * bool) array
