type package=Packed_float3|Packed_quaternion|Packed_float4x3|Bounding_box|Component_transform
type item={id:string;package:package;public_value:string;tests:string list}
val classify:string->item
val validate:item list->unit
