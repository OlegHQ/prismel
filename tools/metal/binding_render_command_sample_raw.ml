module Make(Types:sig type handle end)=struct
 type handle=Types.handle
 external create:unit->(handle,string)result="caml_prismel_metal_render_sample_attachment_create"
 external start_vertex:handle->(int64,string)result="caml_prismel_metal_render_sample_start_vertex"
 external set_start_vertex:handle->int64->(unit,string)result="caml_prismel_metal_render_sample_set_start_vertex"
 external end_vertex:handle->(int64,string)result="caml_prismel_metal_render_sample_end_vertex"
 external set_end_vertex:handle->int64->(unit,string)result="caml_prismel_metal_render_sample_set_end_vertex"
 external start_fragment:handle->(int64,string)result="caml_prismel_metal_render_sample_start_fragment"
 external set_start_fragment:handle->int64->(unit,string)result="caml_prismel_metal_render_sample_set_start_fragment"
 external end_fragment:handle->(int64,string)result="caml_prismel_metal_render_sample_end_fragment"
 external set_end_fragment:handle->int64->(unit,string)result="caml_prismel_metal_render_sample_set_end_fragment"
 external sample_buffer:handle->(handle option,string)result="caml_prismel_metal_render_sample_buffer"
 external set_sample_buffer:handle->handle option->(unit,string)result="caml_prismel_metal_render_sample_set_buffer"
 external array_get:handle->int64->(handle option,string)result="caml_prismel_metal_render_sample_array_get"
 external array_set:handle->int64->handle option->(unit,string)result="caml_prismel_metal_render_sample_array_set"
end
