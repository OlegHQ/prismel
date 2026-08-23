type handle
type scissor=int64*int64*int64*int64
type viewport=float*float*float*float*float*float
type view_mapping=int64*int64
module Make(T:sig type handle end)=struct type handle=T.handle
 external indexed_patches_indirect:handle->int64->handle->int64->handle->int64->handle->int64->(unit,string)result="caml_prismel_metal_render_draw_indexed_patches_indirect_bytecode" "caml_prismel_metal_render_draw_indexed_patches_indirect"
 external indexed_patches:handle->int64->int64->int64->handle->int64->handle->int64->int64->int64->(unit,string)result="caml_prismel_metal_render_draw_indexed_patches_bytecode" "caml_prismel_metal_render_draw_indexed_patches"
 external indexed:handle->int->int64->int->handle->int64->int64->int64->int64->(unit,string)result="caml_prismel_metal_render_draw_indexed_bytecode" "caml_prismel_metal_render_draw_indexed"
 external indexed_instances:handle->int->int64->int->handle->int64->int64->(unit,string)result="caml_prismel_metal_render_draw_indexed_instances_bytecode" "caml_prismel_metal_render_draw_indexed_instances"
 external indexed_basic:handle->int->int64->int->handle->int64->(unit,string)result="caml_prismel_metal_render_draw_indexed_basic_bytecode" "caml_prismel_metal_render_draw_indexed_basic"
 external indexed_indirect:handle->int->int->handle->int64->handle->int64->(unit,string)result="caml_prismel_metal_render_draw_indexed_indirect_bytecode" "caml_prismel_metal_render_draw_indexed_indirect"
 external patches_indirect:handle->int64->handle->int64->handle->int64->(unit,string)result="caml_prismel_metal_render_draw_patches_indirect_bytecode" "caml_prismel_metal_render_draw_patches_indirect"
 external patches:handle->int64->int64->int64->handle->int64->int64->int64->(unit,string)result="caml_prismel_metal_render_draw_patches_bytecode" "caml_prismel_metal_render_draw_patches"
 external indirect:handle->int->handle->int64->(unit,string)result="caml_prismel_metal_render_draw_indirect"
 external sample_counters:handle->handle->int64->bool->(unit,string)result="caml_prismel_metal_render_sample_counters"
 external color_attachment_map:handle->handle option->(unit,string)result="caml_prismel_metal_render_color_attachment_map"
 external depth_stencil:handle->handle option->(unit,string)result="caml_prismel_metal_render_depth_stencil"
 external scissors:handle->scissor array->(unit,string)result="caml_prismel_metal_render_scissors"
 external tessellation_buffer:handle->handle option->int64->int64->(unit,string)result="caml_prismel_metal_render_tessellation_buffer"
 external vertex_amplification:handle->view_mapping array->(unit,string)result="caml_prismel_metal_render_vertex_amplification"
 external viewports:handle->viewport array->(unit,string)result="caml_prismel_metal_render_viewports"
end
