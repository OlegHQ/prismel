/* IndirectCommand14 residual shard. expected_device is the authoritative ICB
   owner registry ID retained by the safe parent; all resource edges are fully
   checked before a command mutation. Safe integration retains bound resources
   by command slot and releases that slot atomically after reset. */
static bool prismel_indirect_buffer_range(id<MTLBuffer> buffer, int64_t offset,
                                          int64_t bytes, int64_t device) {
  return offset >= 0 && bytes >= 0 && (uint64_t)offset <= buffer.length &&
    (uint64_t)bytes <= buffer.length - (uint64_t)offset &&
    (int64_t)buffer.device.registryID == device;
}

extern "C" CAMLprim value caml_prismel_metal_indirect_command_set_buffer_stride(
    value command_raw, value buffer_raw, value offset_raw, value stride_raw,
    value index_raw, value stage_raw, value device_raw) {
  CAMLparam5(command_raw, buffer_raw, offset_raw, stride_raw, index_raw);
  CAMLxparam2(stage_raw, device_raw); int64_t offset = Int64_val(offset_raw);
  int64_t stride = Int64_val(stride_raw), index = Int64_val(index_raw);
  if (stride <= 0 || index < 0) CAMLreturn(result_error_text("invalid indirect buffer stride/index"));
  @try { id<MTLBuffer> buffer = object_of_handle(buffer_raw, Handle_kind::Buffer);
    if (!prismel_indirect_buffer_range(buffer, offset, 0, Int64_val(device_raw)))
      CAMLreturn(result_error_text("indirect buffer offset/device mismatch"));
    switch (Long_val(stage_raw)) {
      case 0: [object_of_handle(command_raw, Handle_kind::Indirect_compute_command)
        setKernelBuffer:buffer offset:offset attributeStride:stride atIndex:index]; break;
      case 1: [object_of_handle(command_raw, Handle_kind::Indirect_render_command)
        setVertexBuffer:buffer offset:offset attributeStride:stride atIndex:index]; break;
      default: CAMLreturn(result_error_text("unknown indirect stride binding stage"));
    } CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_indirect_command_set_buffer_stride_bytecode(
    value *argv, int argc) { (void)argc; return caml_prismel_metal_indirect_command_set_buffer_stride(
      argv[0],argv[1],argv[2],argv[3],argv[4],argv[5],argv[6]); }

extern "C" CAMLprim value caml_prismel_metal_indirect_render_set_stage_buffer(
    value command_raw, value buffer_raw, value offset_raw, value index_raw,
    value stage_raw, value device_raw) {
  CAMLparam5(command_raw, buffer_raw, offset_raw, index_raw, stage_raw); CAMLxparam1(device_raw);
  int64_t offset=Int64_val(offset_raw),index=Int64_val(index_raw);
  if(index<0)CAMLreturn(result_error_text("negative indirect binding index"));
  @try{id<MTLBuffer>b=object_of_handle(buffer_raw,Handle_kind::Buffer);
    if(!prismel_indirect_buffer_range(b,offset,0,Int64_val(device_raw)))
      CAMLreturn(result_error_text("indirect buffer offset/device mismatch"));
    id<MTLIndirectRenderCommand>c=object_of_handle(command_raw,Handle_kind::Indirect_render_command);
    switch(Long_val(stage_raw)){case 0:[c setVertexBuffer:b offset:offset atIndex:index];break;
      case 1:[c setFragmentBuffer:b offset:offset atIndex:index];break;
      case 2:[c setObjectBuffer:b offset:offset atIndex:index];break;
      case 3:[c setMeshBuffer:b offset:offset atIndex:index];break;
      default:CAMLreturn(result_error_text("unknown indirect render binding stage"));}
    CAMLreturn(result_unit());
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_indirect_render_set_stage_buffer_bytecode(
    value*argv,int argc){(void)argc;return caml_prismel_metal_indirect_render_set_stage_buffer(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5]);}

extern "C" CAMLprim value caml_prismel_metal_indirect_render_draw_indexed(
    value command_raw,value primitive_raw,value count_raw,value type_raw,
    value buffer_raw,value offset_raw,value instances_raw,value base_vertex_raw,
    value base_instance_raw,value device_raw){CAMLparam5(command_raw,primitive_raw,count_raw,type_raw,buffer_raw);CAMLxparam5(offset_raw,instances_raw,base_vertex_raw,base_instance_raw,device_raw);
  int64_t count=Int64_val(count_raw),offset=Int64_val(offset_raw),instances=Int64_val(instances_raw),base=Int64_val(base_instance_raw);int type=Long_val(type_raw);if(count<=0||instances<=0||base<0||(type!=0&&type!=1))CAMLreturn(result_error_text("invalid indexed indirect cardinality/type"));
  @try{id<MTLBuffer>b=object_of_handle(buffer_raw,Handle_kind::Buffer);int64_t element_bytes=type==0?2:4;if(count>INT64_MAX/element_bytes)CAMLreturn(result_error_text("indirect index byte count overflows"));int64_t bytes=count*element_bytes;if(!prismel_indirect_buffer_range(b,offset,bytes,Int64_val(device_raw)))CAMLreturn(result_error_text("indirect index range/device mismatch"));id<MTLIndirectRenderCommand>c=object_of_handle(command_raw,Handle_kind::Indirect_render_command);[c drawIndexedPrimitives:(MTLPrimitiveType)Long_val(primitive_raw) indexCount:count indexType:(MTLIndexType)type indexBuffer:b indexBufferOffset:offset instanceCount:instances baseVertex:Int64_val(base_vertex_raw) baseInstance:base];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_indirect_render_draw_indexed_bytecode(value*argv,int argc){(void)argc;return caml_prismel_metal_indirect_render_draw_indexed(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5],argv[6],argv[7],argv[8],argv[9]);}

/* Patch calls retain three buffers in the safe command slot. The positional
   tuple is (controlPoints,patchStart,patchCount,patchOffset,controlOffset,
   instances,baseInstance,tessOffset,tessStride), all int64. */
extern "C" CAMLprim value caml_prismel_metal_indirect_render_draw_patches(
    value command_raw,value patch_index,value control_raw,value tess_raw,value spec,value device_raw){CAMLparam5(command_raw,patch_index,control_raw,tess_raw,spec);CAMLxparam1(device_raw);
  int64_t points=Int64_val(Field(spec,0)),start=Int64_val(Field(spec,1)),count=Int64_val(Field(spec,2)),po=Int64_val(Field(spec,3)),co=Int64_val(Field(spec,4)),instances=Int64_val(Field(spec,5)),base=Int64_val(Field(spec,6)),to=Int64_val(Field(spec,7)),stride=Int64_val(Field(spec,8));if(points<=0||start<0||count<=0||po<0||co<0||instances<=0||base<0||to<0||stride<=0)CAMLreturn(result_error_text("invalid indirect patch cardinality/stride"));
  @try{id<MTLBuffer>control=object_of_handle(control_raw,Handle_kind::Buffer),tess=object_of_handle(tess_raw,Handle_kind::Buffer);id<MTLBuffer>patch=Is_none(patch_index)?nil:object_of_handle(Field(patch_index,0),Handle_kind::Buffer);int64_t dev=Int64_val(device_raw);if(!prismel_indirect_buffer_range(control,co,0,dev)||!prismel_indirect_buffer_range(tess,to,0,dev)||(patch&&!prismel_indirect_buffer_range(patch,po,0,dev)))CAMLreturn(result_error_text("indirect patch buffer offset/device mismatch"));id<MTLIndirectRenderCommand>c=object_of_handle(command_raw,Handle_kind::Indirect_render_command);if(patch)[c drawIndexedPatches:points patchStart:start patchCount:count patchIndexBuffer:patch patchIndexBufferOffset:po controlPointIndexBuffer:control controlPointIndexBufferOffset:co instanceCount:instances baseInstance:base tessellationFactorBuffer:tess tessellationFactorBufferOffset:to tessellationFactorBufferInstanceStride:stride];else[c drawPatches:points patchStart:start patchCount:count patchIndexBuffer:nil patchIndexBufferOffset:0 instanceCount:instances baseInstance:base tessellationFactorBuffer:tess tessellationFactorBufferOffset:to tessellationFactorBufferInstanceStride:stride];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_indirect_render_draw_patches_bytecode(value*argv,int argc){(void)argc;return caml_prismel_metal_indirect_render_draw_patches(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5]);}
