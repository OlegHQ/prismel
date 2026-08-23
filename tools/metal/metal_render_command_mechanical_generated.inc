#define PRISMEL_RENDER_WRAP1(NAME,CALL) extern "C" CAMLprim value NAME(value re,value a){CAMLparam2(re,a);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);CALL;CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_RENDER_WRAP2(NAME,CALL) extern "C" CAMLprim value NAME(value re,value a,value b){CAMLparam3(re,a,b);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);CALL;CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_RENDER_WRAP3(NAME,CALL) extern "C" CAMLprim value NAME(value re,value a,value b,value c){CAMLparam4(re,a,b,c);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);CALL;CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_RENDER_WRAP4(NAME,CALL) extern "C" CAMLprim value NAME(value re,value a,value b,value c,value d){CAMLparam5(re,a,b,c,d);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);CALL;CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
PRISMEL_RENDER_WRAP3(caml_prismel_metal_render_command_draw,[e drawPrimitives:(MTLPrimitiveType)Long_val(a) vertexStart:Int64_val(b) vertexCount:Int64_val(c)])
extern "C" CAMLprim value caml_prismel_metal_render_command_draw_instances(value re,value a,value b,value c,value d,value base){CAMLparam5(re,a,b,c,d);CAMLxparam1(base);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);[e drawPrimitives:(MTLPrimitiveType)Long_val(a) vertexStart:Int64_val(b) vertexCount:Int64_val(c) instanceCount:Int64_val(d) baseInstance:Int64_val(base)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_command_draw_instances_bytecode(value*argv,int argc){(void)argc;return caml_prismel_metal_render_command_draw_instances(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5]);}
PRISMEL_RENDER_WRAP1(caml_prismel_metal_render_command_depth_clip,[e setDepthClipMode:(MTLDepthClipMode)Long_val(a)])
PRISMEL_RENDER_WRAP2(caml_prismel_metal_render_command_depth_bounds,[e setDepthTestMinBound:Double_val(a) maxBound:Double_val(b)])
PRISMEL_RENDER_WRAP2(caml_prismel_metal_render_command_fragment_buffer_offset,[e setFragmentBufferOffset:Int64_val(a) atIndex:Int64_val(b)])
PRISMEL_RENDER_WRAP2(caml_prismel_metal_render_command_mesh_buffer_offset,[e setMeshBufferOffset:Int64_val(a) atIndex:Int64_val(b)])
PRISMEL_RENDER_WRAP2(caml_prismel_metal_render_command_object_buffer_offset,[e setObjectBufferOffset:Int64_val(a) atIndex:Int64_val(b)])
PRISMEL_RENDER_WRAP2(caml_prismel_metal_render_command_object_threadgroup_memory,[e setObjectThreadgroupMemoryLength:Int64_val(a) atIndex:Int64_val(b)])
PRISMEL_RENDER_WRAP1(caml_prismel_metal_render_command_stencil_reference,[e setStencilReferenceValue:(uint32_t)Int64_val(a)])
PRISMEL_RENDER_WRAP1(caml_prismel_metal_render_command_tessellation_scale,[e setTessellationFactorScale:Double_val(a)])
PRISMEL_RENDER_WRAP3(caml_prismel_metal_render_command_threadgroup_memory,[e setThreadgroupMemoryLength:Int64_val(a) offset:Int64_val(b) atIndex:Int64_val(c)])
PRISMEL_RENDER_WRAP2(caml_prismel_metal_render_command_tile_buffer_offset,[e setTileBufferOffset:Int64_val(a) atIndex:Int64_val(b)])
PRISMEL_RENDER_WRAP2(caml_prismel_metal_render_command_vertex_buffer_offset,[e setVertexBufferOffset:Int64_val(a) atIndex:Int64_val(b)])
PRISMEL_RENDER_WRAP3(caml_prismel_metal_render_command_vertex_buffer_offset_stride,[e setVertexBufferOffset:Int64_val(a) attributeStride:Int64_val(b) atIndex:Int64_val(c)])
#undef PRISMEL_RENDER_WRAP1
#undef PRISMEL_RENDER_WRAP2
#undef PRISMEL_RENDER_WRAP3
#undef PRISMEL_RENDER_WRAP4
