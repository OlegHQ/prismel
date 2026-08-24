type kind=Buffer|Texture|Tensor|Indirect|Counter_buffer|Fence
type resource={token:int;device:int;kind:kind;length:int;destroyed:bool}
type range={offset:int;length:int}
type extent={width:int;height:int;depth:int}
type capability={managed_sync:bool;access_counters:bool}
val validate_resource:device:int->kind:kind->resource->(resource,string)result
val validate_range:resource->range->(unit,string)result
val validate_texture_layout:extent:extent->bytes_per_pixel:int->bytes_per_row:int->bytes_per_image:int->buffer:resource->offset:int->(unit,string)result
val validate_pair:device:int->source_kind:kind->destination_kind:kind->resource->resource->(unit,string)result
val validate_tensor_copy:device:int->resource->resource->source_origin:int64 array->source_dimensions:int64 array->destination_origin:int64 array->destination_dimensions:int64 array->(unit,string)result
val validate_sync:capability->resource->(unit,string)result
val validate_counter:capability->resource->range->(unit,string)result
val retain:resource array->resource array
val validate_handoff:unit->unit
