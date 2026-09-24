type limits={max_buffer_size:int64;max_texture_dimension_2d:int;max_bind_groups:int;max_sample_count:int}
type t={limits:limits;ray_tracing:bool;metal_fx:bool}
let minimum_m1={limits={max_buffer_size=Int64.mul 256L(Int64.mul 1024L 1024L);max_texture_dimension_2d=16384;max_bind_groups=4;max_sample_count=4};ray_tracing=false;metal_fx=false}
let validate value=let l=value.limits in if l.max_buffer_size<=0L||l.max_texture_dimension_2d<=0||l.max_bind_groups<=0||l.max_sample_count<=0 then Error(Error.make "Ogpu.Capabilities.validate" Error.Invalid_argument "limits must be positive")else Ok()
