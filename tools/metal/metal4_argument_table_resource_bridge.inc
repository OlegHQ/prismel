/* Exact MTL4ArgumentTable setResource:atBufferIndex: path.  The table stores a
   resource ID, not an owning object reference; the handwritten safe graph must
   retain the Buffer/AccelerationStructure until replacement or completion. */
extern "C" CAMLprim value caml_prismel_metal4_argument_table_set_resource(
    value table_raw, value resource_raw, value kind_raw, value index_raw) {
  CAMLparam4(table_raw, resource_raw, kind_raw, index_raw);
  if (@available(macOS 26.0, *)) {
    int kind = Long_val(kind_raw);
    int64_t index = Int64_val(index_raw);
    @try {
      PrismelMetal4ArgumentTableState *state =
          argument_table4_state_of_handle(table_raw);
      if (index < 0 || (uint64_t)index >= state.maxBufferBindCount)
        CAMLreturn(result_error_text("Metal4 argument-table buffer index is out of range"));
      MTLResourceID identifier;
      uint64_t resource_device = 0;
      if (kind == 0) {
        id<MTLAccelerationStructure> resource = object_of_handle(
            resource_raw, Handle_kind::Acceleration_structure);
        identifier = resource.gpuResourceID; resource_device = resource.device.registryID;
      } else if (kind == 1) {
        id<MTLTexture> resource = object_of_handle(resource_raw, Handle_kind::Texture);
        identifier = resource.gpuResourceID; resource_device = resource.device.registryID;
      } else if (kind == 2) {
        id<MTLSamplerState> resource = object_of_handle(resource_raw, Handle_kind::Sampler);
        identifier = resource.gpuResourceID; resource_device = resource.device.registryID;
      } else if (kind == 3) {
        id<MTLTensor> resource = object_of_handle(resource_raw, Handle_kind::Tensor);
        identifier = resource.gpuResourceID; resource_device = resource.device.registryID;
      } else if (kind == 4) {
        id<MTLComputePipelineState> resource = object_of_handle(resource_raw, Handle_kind::Compute_pipeline);
        identifier = resource.gpuResourceID; resource_device = resource.device.registryID;
      } else if (kind == 5) {
        id<MTLRenderPipelineState> resource = object_of_handle(resource_raw, Handle_kind::Render_pipeline);
        identifier = resource.gpuResourceID; resource_device = resource.device.registryID;
      } else if (kind == 6) {
        id<MTLVisibleFunctionTable> resource = object_of_handle(resource_raw, Handle_kind::Visible_function_table);
        identifier = resource.gpuResourceID; resource_device = resource.device.registryID;
      } else if (kind == 7) {
        id<MTLIntersectionFunctionTable> resource = object_of_handle(resource_raw, Handle_kind::Intersection_function_table);
        identifier = resource.gpuResourceID; resource_device = resource.device.registryID;
      } else if (kind == 8) {
        id<MTLFunctionHandle> resource = object_of_handle(resource_raw, Handle_kind::Function_handle);
        identifier = resource.gpuResourceID; resource_device = resource.device.registryID;
      } else if (kind == 9) {
        id<MTLIndirectCommandBuffer> resource = object_of_handle(resource_raw, Handle_kind::Indirect_command_buffer);
        identifier = resource.gpuResourceID; resource_device = resource.device.registryID;
      } else {
        CAMLreturn(result_error_text("unsupported Metal4 argument-table resource kind"));
      }
      if (resource_device != state.argumentTable.device.registryID || identifier._impl == 0)
        CAMLreturn(result_error_text("Metal4 argument-table resource belongs to another device or has no ID"));
      [state.argumentTable setResource:identifier atBufferIndex:(NSUInteger)index];
      /* Resource IDs do not own their source objects. The safe OCaml binding
         graph and command-buffer state retain the selected resource. */
      [state setBoundBuffer:nil atIndex:(NSUInteger)index];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_error_text("Metal4 argument-table resources require macOS 26"));
}
