/* Exact classic MTLDevice async compute selector shard.  The public safe
   boundary deliberately presents these legacy completion-only APIs as a
   bounded synchronous Result: no OCaml value is captured by an escaping
   block, and all native inputs remain strongly retained until completion. */
static bool prismel_device_async_wait(dispatch_semaphore_t semaphore) {
  return dispatch_semaphore_wait(
      semaphore, dispatch_time(DISPATCH_TIME_NOW, 60LL * NSEC_PER_SEC)) == 0;
}

extern "C" CAMLprim value caml_prismel_metal_device_async_compute_function(
    value raw_device, value raw_function, value raw_with_options, value raw_options) {
  CAMLparam4(raw_device, raw_function, raw_with_options, raw_options); CAMLlocal2(raw, result);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    id<MTLFunction> function = object_of_handle(raw_function, Handle_kind::Function);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block id<MTLComputePipelineState> pipeline = nil;
    __block NSError *failure = nil;
    if (!Bool_val(raw_with_options)) {
      [device newComputePipelineStateWithFunction:function
          completionHandler:^(id<MTLComputePipelineState> _Nullable value,
                              NSError * _Nullable error) {
            pipeline = value; failure = error; dispatch_semaphore_signal(done);
          }];
    } else {
      [device newComputePipelineStateWithFunction:function
          options:(MTLPipelineOption)Int64_val(raw_options)
          completionHandler:^(id<MTLComputePipelineState> _Nullable value,
                              MTLComputePipelineReflection * _Nullable reflection,
                              NSError * _Nullable error) {
            (void)reflection; pipeline = value; failure = error;
            dispatch_semaphore_signal(done);
          }];
    }
    if (!prismel_device_async_wait(done))
      CAMLreturn(result_error_text("compute pipeline completion timed out"));
    if (pipeline == nil)
      CAMLreturn(result_error(error_description(failure, @"compute pipeline creation failed")));
    raw = allocate_handle(pipeline, Handle_kind::Compute_pipeline);
    result = result_ok(raw); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_async_compute_descriptor(
    value raw_device, value raw_descriptor, value raw_options) {
  CAMLparam3(raw_device, raw_descriptor, raw_options); CAMLlocal2(raw, result);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    MTLComputePipelineDescriptor *descriptor =
        object_of_handle(raw_descriptor, Handle_kind::Compute_pipeline_descriptor);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block id<MTLComputePipelineState> pipeline = nil;
    __block NSError *failure = nil;
    [device newComputePipelineStateWithDescriptor:descriptor
        options:(MTLPipelineOption)Int64_val(raw_options)
        completionHandler:^(id<MTLComputePipelineState> _Nullable value,
                            MTLComputePipelineReflection * _Nullable reflection,
                            NSError * _Nullable error) {
          (void)reflection; pipeline = value; failure = error;
          dispatch_semaphore_signal(done);
        }];
    if (!prismel_device_async_wait(done))
      CAMLreturn(result_error_text("compute descriptor completion timed out"));
    if (pipeline == nil)
      CAMLreturn(result_error(error_description(failure, @"compute descriptor creation failed")));
    raw = allocate_handle(pipeline, Handle_kind::Compute_pipeline);
    result = result_ok(raw); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
