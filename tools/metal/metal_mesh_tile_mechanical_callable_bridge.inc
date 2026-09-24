/* Callable adapters for all 16 contained-value properties in the prepared
   Mesh/tile105 mechanical shard. Object graph properties remain handwritten. */

extern "C" CAMLprim value caml_prismel_metal_mesh_buffer_descriptor_create(value unit) {
  CAMLparam1(unit); CAMLlocal2(handle, result); @try {
    handle = allocate_handle([MTLPipelineBufferDescriptor new],
                             Handle_kind::Pipeline_buffer_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_mesh_buffer_set_mutability(
    value raw, value raw_mutability) {
  CAMLparam2(raw, raw_mutability); @try {
    MTLPipelineBufferDescriptor *descriptor = object_of_handle(
        raw, Handle_kind::Pipeline_buffer_descriptor);
    prismel_mtl_pipeline_buffer_set_mutability(
        descriptor, static_cast<MTLMutability>(Long_val(raw_mutability)));
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_mesh_color_attachment_create(value unit) {
  CAMLparam1(unit); CAMLlocal2(handle, result); @try {
    handle = allocate_handle([MTLRenderPipelineColorAttachmentDescriptor new],
                             Handle_kind::Color_attachment_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_mesh_color_attachment_set(
    value raw, value pixel, value source_rgb, value destination_rgb,
    value rgb_operation, value source_alpha, value destination_alpha,
    value alpha_operation, value write_mask) {
  CAMLparam5(raw, pixel, source_rgb, destination_rgb, rgb_operation);
  CAMLxparam4(source_alpha, destination_alpha, alpha_operation, write_mask);
  @try {
    MTLRenderPipelineColorAttachmentDescriptor *descriptor = object_of_handle(
        raw, Handle_kind::Color_attachment_descriptor);
    prismel_mtl_color_attachment_set_mechanical(
        descriptor, static_cast<MTLPixelFormat>(Int64_val(pixel)),
        static_cast<MTLBlendFactor>(Long_val(source_rgb)),
        static_cast<MTLBlendFactor>(Long_val(destination_rgb)),
        static_cast<MTLBlendOperation>(Long_val(rgb_operation)),
        static_cast<MTLBlendFactor>(Long_val(source_alpha)),
        static_cast<MTLBlendFactor>(Long_val(destination_alpha)),
        static_cast<MTLBlendOperation>(Long_val(alpha_operation)),
        static_cast<MTLColorWriteMask>(Int64_val(write_mask)));
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_mesh_color_attachment_set_bytecode(
    value *argv, int argn) {
  (void)argn;
  return caml_prismel_metal_mesh_color_attachment_set(
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7],
      argv[8]);
}

static bool prismel_mesh_size(value raw, MTLSize *size) {
  int64_t width = Int64_val(Field(raw, 0));
  int64_t height = Int64_val(Field(raw, 1));
  int64_t depth = Int64_val(Field(raw, 2));
  if (width <= 0 || height <= 0 || depth <= 0) return false;
  *size = MTLSizeMake(static_cast<NSUInteger>(width),
                      static_cast<NSUInteger>(height),
                      static_cast<NSUInteger>(depth));
  return true;
}

static bool prismel_mesh_object_size(value raw, MTLSize *size) {
  int64_t width = Int64_val(Field(raw, 0));
  int64_t height = Int64_val(Field(raw, 1));
  int64_t depth = Int64_val(Field(raw, 2));
  const bool all_zero = width == 0 && height == 0 && depth == 0;
  const bool all_positive = width > 0 && height > 0 && depth > 0;
  if (!all_zero && !all_positive) return false;
  *size = MTLSizeMake(static_cast<NSUInteger>(width),
                      static_cast<NSUInteger>(height),
                      static_cast<NSUInteger>(depth));
  return true;
}

extern "C" CAMLprim value caml_prismel_metal_mesh_descriptor_set_mechanical(
    value raw, value raw_label, value raw_depth, value raw_stencil,
    value raw_mesh_threads, value raw_object_threads) {
  CAMLparam5(raw, raw_label, raw_depth, raw_stencil, raw_mesh_threads);
  CAMLxparam1(raw_object_threads);
  @try {
    MTLMeshRenderPipelineDescriptor *descriptor = object_of_handle(
        raw, Handle_kind::Mesh_pipeline_descriptor);
    NSString *label = Is_block(raw_label)
        ? string_from_ocaml(Field(raw_label, 0)) : nil;
    if (Is_block(raw_label) && label == nil)
      CAMLreturn(result_error_text("mesh descriptor label is not valid UTF-8"));
    MTLSize mesh_threads, object_threads;
    if (!prismel_mesh_size(raw_mesh_threads, &mesh_threads) ||
        !prismel_mesh_object_size(raw_object_threads, &object_threads))
      CAMLreturn(result_error_text(
          "mesh threads must be positive; object threads must be positive or all zero"));
    prismel_mtl_mesh_descriptor_set_mechanical(
        descriptor, label, static_cast<MTLPixelFormat>(Int64_val(raw_depth)),
        static_cast<MTLPixelFormat>(Int64_val(raw_stencil)), mesh_threads,
        object_threads);
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_mesh_descriptor_set_mechanical_bytecode(
    value *argv, int argn) {
  (void)argn;
  return caml_prismel_metal_mesh_descriptor_set_mechanical(
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

extern "C" CAMLprim value caml_prismel_metal_tile_descriptor_set_mechanical(
    value raw, value raw_label, value raw_threads) {
  CAMLparam3(raw, raw_label, raw_threads); @try {
    MTLTileRenderPipelineDescriptor *descriptor = object_of_handle(
        raw, Handle_kind::Tile_pipeline_descriptor);
    NSString *label = Is_block(raw_label)
        ? string_from_ocaml(Field(raw_label, 0)) : nil;
    if (Is_block(raw_label) && label == nil)
      CAMLreturn(result_error_text("tile descriptor label is not valid UTF-8"));
    MTLSize threads;
    if (!prismel_mesh_size(raw_threads, &threads))
      CAMLreturn(result_error_text("tile threadgroup size must be positive"));
    prismel_mtl_tile_descriptor_set_mechanical(descriptor, label, threads);
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
