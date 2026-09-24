type kind=Buffer|Texture|Tensor|Indirect|Counter_buffer|Fence
type resource={token:int;device:int;kind:kind;length:int;destroyed:bool}
type range={offset:int;length:int}
type extent={width:int;height:int;depth:int}
type capability={managed_sync:bool;access_counters:bool}

let validate_resource ~device ~kind value=
 if value.destroyed then Error"destroyed blit resource"else if value.device<>device then Error"blit resource belongs to another device"else if value.kind<>kind then Error"wrong blit resource kind"else Ok value
let validate_range (value : resource) (range : range)=
 if range.offset<0||range.length<0||range.offset>value.length||range.length>value.length-range.offset then Error"blit range out of bounds"else Ok()
let checked_mul a b=if a<0||b<0||a<>0&&b>max_int/a then None else Some(a*b)
let validate_texture_layout ~extent ~bytes_per_pixel ~bytes_per_row ~bytes_per_image ~buffer ~offset=
 if extent.width<=0||extent.height<=0||extent.depth<=0||bytes_per_pixel<=0 then Error"invalid blit extent"
 else match checked_mul extent.width bytes_per_pixel with
 |None->Error"blit layout overflow"|Some row_min when bytes_per_row<row_min->Error"blit row stride too small"
 |Some _->(match checked_mul bytes_per_row extent.height with None->Error"blit layout overflow"|Some image_min when bytes_per_image<image_min->Error"blit image stride too small"|Some _->match checked_mul bytes_per_image extent.depth with None->Error"blit layout overflow"|Some length->validate_range buffer{offset;length})
let validate_pair ~device ~source_kind ~destination_kind source destination=
 match validate_resource~device~kind:source_kind source,validate_resource~device~kind:destination_kind destination with Error e,_|_,Error e->Error e|Ok _,Ok _->Ok()
let validate_tensor_copy ~device source destination ~source_origin ~source_dimensions ~destination_origin ~destination_dimensions=
 match validate_pair~device~source_kind:Tensor~destination_kind:Tensor source destination with Error e->Error e|Ok()->
 let rank=Array.length source_origin in if rank=0||List.exists((<>)rank)[Array.length source_dimensions;Array.length destination_origin;Array.length destination_dimensions]then Error"tensor copy rank/cardinality mismatch"else if Array.exists((>)0L)source_origin||Array.exists((>)0L)destination_origin||Array.exists((>=)0L)source_dimensions||Array.exists((>=)0L)destination_dimensions then Error"invalid tensor copy component"else Ok()
let validate_sync capability resource=if resource.destroyed then Error"destroyed synchronization resource"else if not capability.managed_sync then Error"managed synchronization unsupported"else Ok()
let validate_counter capability buffer range=if not capability.access_counters then Error"texture access counters unsupported"else match validate_resource~device:buffer.device~kind:Counter_buffer buffer with Error e->Error e|Ok _->validate_range buffer range
let retain resources=Array.copy resources
let validate_handoff()=if List.length Binding_blit_command_tail_handoff.callable_ids<>25 then invalid_arg"BlitCommand25 closure drift"
