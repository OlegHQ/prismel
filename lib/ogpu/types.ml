type buffer_usage=Copy_src|Copy_dst|Uniform|Storage|Vertex|Index
type buffer_descriptor={label:string option;size:int64;usage:buffer_usage list}
type texture_usage=Texture_binding|Render_attachment|Texture_copy_src|Texture_copy_dst
type texture_descriptor={label:string option;width:int;height:int;depth:int;mip_levels:int;sample_count:int;usage:texture_usage list}
let validate_buffer (caps:Capabilities.t) (value:buffer_descriptor)=
  let operation="Ogpu.Types.validate_buffer"in match Validation.validate_label~operation value.label with Error _ as failure->failure|Ok()->
  Validation.validate_buffer~operation~max_size:caps.Capabilities.limits.max_buffer_size~size:value.size~usage_count:(List.length value.usage)
let validate_texture (caps:Capabilities.t) (value:texture_descriptor)=
  let operation="Ogpu.Types.validate_texture"and l=caps.Capabilities.limits in match Validation.validate_label~operation value.label with Error _ as failure->failure|Ok()->
  Validation.validate_texture_shape~operation~max_dimension:l.max_texture_dimension_2d~max_samples:l.max_sample_count
    ~width:value.width~height:value.height~depth:value.depth~mip_levels:value.mip_levels~sample_count:value.sample_count~usage_count:(List.length value.usage)
