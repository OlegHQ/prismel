/* Exact synchronous Mesh/tile105 descriptor compilation selectors:
   method:-[MTLDevice newRenderPipelineStateWithMeshDescriptor:options:reflection:error:]
   method:-[MTLDevice newRenderPipelineStateWithTileDescriptor:options:reflection:error:]
   The two asynchronous callback selectors remain blocked. */

static bool prismel_mesh_tile_same_device(id<MTLDevice> device, id object) {
  return object == nil ||
         ![object respondsToSelector:@selector(device)] ||
         ((id<MTLDevice>)[object device]).registryID == device.registryID;
}

static value prismel_mesh_tile_pipeline_result(
    id<MTLRenderPipelineState> pipeline,
    MTLRenderPipelineReflection *reflection) {
  CAMLparam0(); CAMLlocal4(handle, reflected, pair, result);
  handle = allocate_handle(pipeline, Handle_kind::Render_pipeline);
  reflected = copy_render_reflection(reflection);
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, handle);
  Store_field(pair, 1, reflected);
  result = result_ok(pair);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_mesh_pipeline_compile(
    value raw_device, value raw_descriptor, value raw_options) {
  CAMLparam3(raw_device, raw_descriptor, raw_options);
  @autoreleasepool {
    if (@available(macOS 13.0, *)) { @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      MTLMeshRenderPipelineDescriptor *descriptor = object_of_handle(
          raw_descriptor, Handle_kind::Mesh_pipeline_descriptor);
      int64_t options = Int64_val(raw_options);
      if (options < 0) CAMLreturn(result_error_text("mesh pipeline options are invalid"));
      if (descriptor.meshFunction == nil ||
          !prismel_mesh_tile_same_device(device, descriptor.objectFunction) ||
          !prismel_mesh_tile_same_device(device, descriptor.meshFunction) ||
          !prismel_mesh_tile_same_device(device, descriptor.fragmentFunction))
        CAMLreturn(result_error_text("mesh descriptor has missing or cross-device functions"));
      for (id archive in descriptor.binaryArchives)
        if (!prismel_mesh_tile_same_device(device, archive))
          CAMLreturn(result_error_text("mesh descriptor has a cross-device archive"));
      MTLRenderPipelineReflection *reflection = nil;
      NSError *error = nil;
      id<MTLRenderPipelineState> pipeline = [device
          newRenderPipelineStateWithMeshDescriptor:descriptor
                                           options:static_cast<MTLPipelineOption>(options)
                                        reflection:&reflection error:&error];
      if (pipeline == nil)
        CAMLreturn(result_error(error_description(error,
            @"Metal mesh pipeline compilation failed")));
      if (pipeline.device.registryID != device.registryID)
        CAMLreturn(result_error_text("Metal returned a mesh pipeline for another device"));
      CAMLreturn(prismel_mesh_tile_pipeline_result(pipeline, reflection));
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
    CAMLreturn(result_error_text("Metal mesh pipelines require macOS 13"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_tile_pipeline_compile(
    value raw_device, value raw_descriptor, value raw_options) {
  CAMLparam3(raw_device, raw_descriptor, raw_options);
  @autoreleasepool {
    if (@available(macOS 11.0, *)) { @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      MTLTileRenderPipelineDescriptor *descriptor = object_of_handle(
          raw_descriptor, Handle_kind::Tile_pipeline_descriptor);
      int64_t options = Int64_val(raw_options);
      if (options < 0) CAMLreturn(result_error_text("tile pipeline options are invalid"));
      if (descriptor.tileFunction == nil ||
          !prismel_mesh_tile_same_device(device, descriptor.tileFunction))
        CAMLreturn(result_error_text("tile descriptor has a missing or cross-device function"));
      for (id archive in descriptor.binaryArchives)
        if (!prismel_mesh_tile_same_device(device, archive))
          CAMLreturn(result_error_text("tile descriptor has a cross-device archive"));
      for (id library in descriptor.preloadedLibraries)
        if (!prismel_mesh_tile_same_device(device, library))
          CAMLreturn(result_error_text("tile descriptor has a cross-device library"));
      MTLRenderPipelineReflection *reflection = nil;
      NSError *error = nil;
      id<MTLRenderPipelineState> pipeline = [device
          newRenderPipelineStateWithTileDescriptor:descriptor
                                           options:static_cast<MTLPipelineOption>(options)
                                        reflection:&reflection error:&error];
      if (pipeline == nil)
        CAMLreturn(result_error(error_description(error,
            @"Metal tile pipeline compilation failed")));
      if (pipeline.device.registryID != device.registryID)
        CAMLreturn(result_error_text("Metal returned a tile pipeline for another device"));
      CAMLreturn(prismel_mesh_tile_pipeline_result(pipeline, reflection));
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
    CAMLreturn(result_error_text("Metal tile pipelines require macOS 11"));
  }
}
