/* BinaryArchive5 isolated descriptor-addition shard. Descriptor/library device
   metadata is checked in full before invoking the selected archive mutation.
   Safe integration retains successful descriptor/library edges only after Ok. */
extern "C" CAMLprim value caml_prismel_metal_binary_archive5_descriptor_create(
    value kind_raw) {
  CAMLparam1(kind_raw); CAMLlocal2(handle, result); id descriptor = nil;
  Handle_kind kind;
  @try { switch (Long_val(kind_raw)) {
      case 0: descriptor = [MTLFunctionDescriptor functionDescriptor];
        kind = Handle_kind::Function_descriptor; break;
      case 1: descriptor = [MTLStitchedLibraryDescriptor new];
        kind = Handle_kind::Stitched_library_descriptor; break;
      case 2: descriptor = [MTLMeshRenderPipelineDescriptor new];
        kind = Handle_kind::Mesh_pipeline_descriptor; break;
      case 3: descriptor = [MTLRenderPipelineDescriptor new];
        kind = Handle_kind::Render_pipeline_descriptor; break;
      case 4: descriptor = [MTLTileRenderPipelineDescriptor new];
        kind = Handle_kind::Tile_pipeline_descriptor; break;
      default: CAMLreturn(result_error_text("unknown binary archive descriptor kind"));
    }
    if (descriptor == nil) CAMLreturn(result_error_text("Metal returned no archive descriptor"));
    handle = allocate_handle(descriptor, kind); result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_binary_archive5_configured_descriptor(
    value kind_raw, value first_raw, value second_raw, value format_raw) {
  CAMLparam4(kind_raw, first_raw, second_raw, format_raw); CAMLlocal2(handle, result);
  @try {
    int kind = Long_val(kind_raw); id descriptor = nil; Handle_kind handle_kind;
    id<MTLFunction> first = object_of_handle(first_raw, Handle_kind::Function);
    if (kind == 0) {
      MTLFunctionDescriptor *function = [MTLFunctionDescriptor functionDescriptor];
      function.name = first.name; descriptor = function;
      handle_kind = Handle_kind::Function_descriptor;
    } else if (kind == 2) {
      MTLMeshRenderPipelineDescriptor *mesh = [MTLMeshRenderPipelineDescriptor new];
      mesh.meshFunction = first;
      if (Is_block(second_raw)) mesh.fragmentFunction = object_of_handle(
        Field(second_raw, 0), Handle_kind::Function);
      mesh.colorAttachments[0].pixelFormat = (MTLPixelFormat)Int64_val(format_raw);
      descriptor = mesh; handle_kind = Handle_kind::Mesh_pipeline_descriptor;
    } else if (kind == 3) {
      if (Is_none(second_raw)) CAMLreturn(result_error_text("render archive descriptor requires a fragment function"));
      id<MTLFunction> second = object_of_handle(Field(second_raw, 0), Handle_kind::Function);
      MTLRenderPipelineDescriptor *render = [MTLRenderPipelineDescriptor new];
      render.vertexFunction = first; render.fragmentFunction = second;
      render.colorAttachments[0].pixelFormat = (MTLPixelFormat)Int64_val(format_raw);
      descriptor = render; handle_kind = Handle_kind::Render_pipeline_descriptor;
    } else if (kind == 4) {
      if (Is_block(second_raw)) CAMLreturn(result_error_text("tile archive descriptor has an unexpected second function"));
      MTLTileRenderPipelineDescriptor *tile = [MTLTileRenderPipelineDescriptor new];
      tile.tileFunction = first;
      tile.colorAttachments[0].pixelFormat = (MTLPixelFormat)Int64_val(format_raw);
      descriptor = tile; handle_kind = Handle_kind::Tile_pipeline_descriptor;
    } else CAMLreturn(result_error_text("binary archive descriptor kind is not configured by this safe path"));
    handle = allocate_handle(descriptor, handle_kind); result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_binary_archive5_add(
    value archive_raw, value kind_raw, value descriptor_raw, value library_raw,
    value archive_device_raw, value descriptor_device_raw, value library_device_raw) {
  CAMLparam5(archive_raw, kind_raw, descriptor_raw, library_raw,
    archive_device_raw); CAMLxparam2(descriptor_device_raw, library_device_raw);
  int kind = Long_val(kind_raw); int64_t archive_device = Int64_val(archive_device_raw);
  if (kind < 0 || kind > 4 || Int64_val(descriptor_device_raw) != archive_device)
    CAMLreturn(result_error_text("binary archive descriptor kind/device mismatch"));
  @try { id<MTLBinaryArchive> archive = object_of_handle(
      archive_raw, Handle_kind::Binary_archive);
    if ((int64_t)archive.device.registryID != archive_device)
      CAMLreturn(result_error_text("binary archive device identity changed"));
    NSError *error = nil; BOOL success = NO;
    if (kind == 0) {
      if (Is_none(library_raw) || Is_none(library_device_raw)
          || Int64_val(Field(library_device_raw, 0)) != archive_device)
        CAMLreturn(result_error_text("binary archive function library device mismatch"));
      id<MTLLibrary> library = object_of_handle(Field(library_raw, 0), Handle_kind::Library);
      if ((int64_t)library.device.registryID != archive_device)
        CAMLreturn(result_error_text("binary archive function library identity changed"));
      MTLFunctionDescriptor *descriptor = object_of_handle(
        descriptor_raw, Handle_kind::Function_descriptor);
      success = [archive addFunctionWithDescriptor:descriptor library:library error:&error];
    } else {
      if (!Is_none(library_raw) || !Is_none(library_device_raw))
        CAMLreturn(result_error_text("unexpected binary archive library edge"));
      if (kind == 1) success = [archive addLibraryWithDescriptor:object_of_handle(
          descriptor_raw, Handle_kind::Stitched_library_descriptor) error:&error];
      else if (kind == 2) success = [archive addMeshRenderPipelineFunctionsWithDescriptor:
          object_of_handle(descriptor_raw, Handle_kind::Mesh_pipeline_descriptor) error:&error];
      else if (kind == 3) success = [archive addRenderPipelineFunctionsWithDescriptor:
          object_of_handle(descriptor_raw, Handle_kind::Render_pipeline_descriptor) error:&error];
      else success = [archive addTileRenderPipelineFunctionsWithDescriptor:
          object_of_handle(descriptor_raw, Handle_kind::Tile_pipeline_descriptor) error:&error];
    }
    if (!success) CAMLreturn(result_error(error_description(error,
      @"binary archive descriptor addition failed")));
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_binary_archive5_add_bytecode(
    value *argv, int argc) { (void)argc;
  return caml_prismel_metal_binary_archive5_add(argv[0], argv[1], argv[2],
    argv[3], argv[4], argv[5], argv[6]);
}
