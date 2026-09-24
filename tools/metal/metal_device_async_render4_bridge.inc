/* Exact MTLDevice asynchronous classic render, mesh, and tile pipeline calls. */
extern "C" CAMLprim value caml_prismel_metal_device_async_render_descriptor(
    value raw_device, value raw_descriptor, value raw_with_options, value raw_options) {
  CAMLparam4(raw_device, raw_descriptor, raw_with_options, raw_options); CAMLlocal2(raw, result);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    MTLRenderPipelineDescriptor *descriptor = object_of_handle(
        raw_descriptor, Handle_kind::Render_pipeline_descriptor);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block id<MTLRenderPipelineState> pipeline = nil; __block NSError *failure = nil;
    if (!Bool_val(raw_with_options)) {
      [device newRenderPipelineStateWithDescriptor:descriptor
          completionHandler:^(id<MTLRenderPipelineState> _Nullable value,
                              NSError * _Nullable error) {
            pipeline = value; failure = error; dispatch_semaphore_signal(done);
          }];
    } else {
      [device newRenderPipelineStateWithDescriptor:descriptor
          options:(MTLPipelineOption)Int64_val(raw_options)
          completionHandler:^(id<MTLRenderPipelineState> _Nullable value,
                              MTLRenderPipelineReflection * _Nullable reflection,
                              NSError * _Nullable error) {
            (void)reflection; pipeline = value; failure = error;
            dispatch_semaphore_signal(done);
          }];
    }
    if (!prismel_device_async_wait(done))
      CAMLreturn(result_error_text("render pipeline completion timed out"));
    if (pipeline == nil)
      CAMLreturn(result_error(error_description(failure, @"render pipeline creation failed")));
    raw = allocate_handle(pipeline, Handle_kind::Render_pipeline);
    result = result_ok(raw); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_async_mesh_pipeline(
    value raw_device, value raw_descriptor, value raw_options) {
  CAMLparam3(raw_device, raw_descriptor, raw_options); CAMLlocal2(raw, result);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    MTLMeshRenderPipelineDescriptor *descriptor = object_of_handle(
        raw_descriptor, Handle_kind::Mesh_pipeline_descriptor);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block id<MTLRenderPipelineState> pipeline = nil; __block NSError *failure = nil;
    [device newRenderPipelineStateWithMeshDescriptor:descriptor
        options:(MTLPipelineOption)Int64_val(raw_options)
        completionHandler:^(id<MTLRenderPipelineState> _Nullable value,
                            MTLRenderPipelineReflection * _Nullable reflection,
                            NSError * _Nullable error) {
          (void)reflection; pipeline = value; failure = error;
          dispatch_semaphore_signal(done);
        }];
    if (!prismel_device_async_wait(done))
      CAMLreturn(result_error_text("mesh pipeline completion timed out"));
    if (pipeline == nil)
      CAMLreturn(result_error(error_description(failure, @"mesh pipeline creation failed")));
    raw = allocate_handle(pipeline, Handle_kind::Render_pipeline);
    result = result_ok(raw); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_async_tile_pipeline(
    value raw_device, value raw_descriptor, value raw_options) {
  CAMLparam3(raw_device, raw_descriptor, raw_options); CAMLlocal2(raw, result);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    MTLTileRenderPipelineDescriptor *descriptor = object_of_handle(
        raw_descriptor, Handle_kind::Tile_pipeline_descriptor);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block id<MTLRenderPipelineState> pipeline = nil; __block NSError *failure = nil;
    [device newRenderPipelineStateWithTileDescriptor:descriptor
        options:(MTLPipelineOption)Int64_val(raw_options)
        completionHandler:^(id<MTLRenderPipelineState> _Nullable value,
                            MTLRenderPipelineReflection * _Nullable reflection,
                            NSError * _Nullable error) {
          (void)reflection; pipeline = value; failure = error;
          dispatch_semaphore_signal(done);
        }];
    if (!prismel_device_async_wait(done))
      CAMLreturn(result_error_text("tile pipeline completion timed out"));
    if (pipeline == nil)
      CAMLreturn(result_error(error_description(failure, @"tile pipeline creation failed")));
    raw = allocate_handle(pipeline, Handle_kind::Render_pipeline);
    result = result_ok(raw); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
