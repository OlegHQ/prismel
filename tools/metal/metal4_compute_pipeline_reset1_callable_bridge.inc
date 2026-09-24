extern "C" CAMLprim value caml_prismel_metal4_compute_pipeline_reset1_create(
    value unit) {
  CAMLparam1(unit); CAMLlocal1(raw);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4ComputePipelineDescriptor *descriptor =
          [MTL4ComputePipelineDescriptor new];
      raw = allocate_handle(descriptor,
                            Handle_kind::Compute_pipeline_descriptor4);
      CAMLreturn(result_ok(raw));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_error_text("Metal4 compute pipelines require macOS 26"));
}

extern "C" CAMLprim value
caml_prismel_metal4_compute_pipeline_reset1_configure(
    value raw, value function_raw, value max_threads_raw, value multiple_raw) {
  CAMLparam4(raw, function_raw, max_threads_raw, multiple_raw);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4ComputePipelineDescriptor *descriptor = object_of_handle(
          raw, Handle_kind::Compute_pipeline_descriptor4);
      MTL4FunctionDescriptor *function = nil;
      if (Is_block(function_raw))
        function = object_of_handle(Field(function_raw, 0),
                                    Handle_kind::Function_descriptor4);
      int64_t max_threads = Int64_val(max_threads_raw);
      if (max_threads < 0)
        CAMLreturn(result_error_text("maximum thread count is negative"));
      descriptor.computeFunctionDescriptor = function;
      descriptor.maxTotalThreadsPerThreadgroup = (NSUInteger)max_threads;
      descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth =
          Bool_val(multiple_raw);
      if ((descriptor.computeFunctionDescriptor == nil) != (function == nil) ||
          (function != nil &&
           ![descriptor.computeFunctionDescriptor isKindOfClass:[function class]]) ||
          descriptor.maxTotalThreadsPerThreadgroup != (NSUInteger)max_threads ||
          descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth !=
              Bool_val(multiple_raw))
        CAMLreturn(result_error_text("Metal changed compute descriptor state"));
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_error_text("Metal4 compute pipelines require macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_compute_pipeline_reset1_reset(
    value raw) {
  CAMLparam1(raw);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4ComputePipelineDescriptor *descriptor = object_of_handle(
          raw, Handle_kind::Compute_pipeline_descriptor4);
      [descriptor reset];
      MTLSize threads = descriptor.requiredThreadsPerThreadgroup;
      if (descriptor.computeFunctionDescriptor != nil ||
          descriptor.maxTotalThreadsPerThreadgroup != 0 ||
          descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth ||
          threads.width != 0 || threads.height != 0 || threads.depth != 0 ||
          descriptor.supportBinaryLinking ||
          descriptor.staticLinkingDescriptor == nil ||
          descriptor.supportIndirectCommandBuffers !=
              MTL4IndirectCommandBufferSupportStateDisabled)
        CAMLreturn(result_error_text("Metal4 compute reset defaults changed"));
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_error_text("Metal4 compute pipelines require macOS 26"));
}
