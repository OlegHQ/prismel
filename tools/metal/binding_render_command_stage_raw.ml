type stage=Vertex|Fragment|Tile|Object|Mesh
module Make(T:sig type handle end)=struct type handle=T.handle
 external buffer:handle->int->handle option->int64->int64->int64->(unit,string)result="caml_prismel_metal_render_stage_buffer_bytecode" "caml_prismel_metal_render_stage_buffer"
 external buffers:handle->int->handle option array->int64 array->int64 array->int64->(unit,string)result="caml_prismel_metal_render_stage_buffers_bytecode" "caml_prismel_metal_render_stage_buffers"
 external bytes:handle->int->bytes->int64->int64->(unit,string)result="caml_prismel_metal_render_stage_bytes_bytecode" "caml_prismel_metal_render_stage_bytes"
 external sampler:handle->int->handle option->bool->(float*float)->int64->(unit,string)result="caml_prismel_metal_render_stage_sampler_bytecode" "caml_prismel_metal_render_stage_sampler"
 external samplers:handle->int->handle option array->bool->float array->float array->int64->(unit,string)result="caml_prismel_metal_render_stage_samplers_bytecode" "caml_prismel_metal_render_stage_samplers"
 external texture:handle->int->handle option->int64->(unit,string)result="caml_prismel_metal_render_stage_texture"
 external textures:handle->int->handle option array->int64->(unit,string)result="caml_prismel_metal_render_stage_textures"
 external acceleration:handle->int->handle option->int64->(unit,string)result="caml_prismel_metal_render_stage_acceleration"
 external intersection:handle->int->handle option->int64->(unit,string)result="caml_prismel_metal_render_stage_intersection"
 external intersections:handle->int->handle option array->int64->(unit,string)result="caml_prismel_metal_render_stage_intersections"
 external visible:handle->int->handle option->int64->(unit,string)result="caml_prismel_metal_render_stage_visible"
 external visibles:handle->int->handle option array->int64->(unit,string)result="caml_prismel_metal_render_stage_visibles"
end
