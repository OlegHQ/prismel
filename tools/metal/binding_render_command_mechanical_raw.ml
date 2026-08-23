module Make(Types:sig type handle end)=struct
 type handle=Types.handle
 external draw:handle->int->int64->int64->(unit,string)result="caml_prismel_metal_render_command_draw"
 external draw_instances:handle->int->int64->int64->int64->int64->(unit,string)result="caml_prismel_metal_render_command_draw_instances_bytecode" "caml_prismel_metal_render_command_draw_instances"
 external depth_clip:handle->int->(unit,string)result="caml_prismel_metal_render_command_depth_clip"
 external depth_bounds:handle->float->float->(unit,string)result="caml_prismel_metal_render_command_depth_bounds"
 external fragment_buffer_offset:handle->int64->int64->(unit,string)result="caml_prismel_metal_render_command_fragment_buffer_offset"
 external mesh_buffer_offset:handle->int64->int64->(unit,string)result="caml_prismel_metal_render_command_mesh_buffer_offset"
 external object_buffer_offset:handle->int64->int64->(unit,string)result="caml_prismel_metal_render_command_object_buffer_offset"
 external object_threadgroup_memory:handle->int64->int64->(unit,string)result="caml_prismel_metal_render_command_object_threadgroup_memory"
 external stencil_reference:handle->int64->(unit,string)result="caml_prismel_metal_render_command_stencil_reference"
 external tessellation_scale:handle->float->(unit,string)result="caml_prismel_metal_render_command_tessellation_scale"
 external threadgroup_memory:handle->int64->int64->int64->(unit,string)result="caml_prismel_metal_render_command_threadgroup_memory"
 external tile_buffer_offset:handle->int64->int64->(unit,string)result="caml_prismel_metal_render_command_tile_buffer_offset"
 external vertex_buffer_offset:handle->int64->int64->(unit,string)result="caml_prismel_metal_render_command_vertex_buffer_offset"
 external vertex_buffer_offset_stride:handle->int64->int64->int64->(unit,string)result="caml_prismel_metal_render_command_vertex_buffer_offset_stride"
end
