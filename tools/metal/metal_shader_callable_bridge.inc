/* Shader157 callable native subset.
   Exact OCaml descriptor schemas do not yet exist for stitching graphs,
   stitched-library descriptors, reflection objects, preprocessor dictionaries,
   or callback compilation. Those ownership IDs intentionally have no bridge
   symbol here. */

static value prismel_shader_handle_array(NSArray *objects, Handle_kind kind) {
  CAMLparam0();
  CAMLlocal2(array, item);
  array = caml_alloc(static_cast<mlsize_t>(objects.count), 0);
  for (NSUInteger index = 0; index < objects.count; ++index) {
    item = allocate_handle(objects[index], kind);
    Store_field(array, static_cast<mlsize_t>(index), item);
  }
  CAMLreturn(array);
}

#define PRISMEL_SHADER_INT(NAME, KIND, TYPE, EXPR)                         \
  extern "C" CAMLprim value NAME(value raw) {                            \
    CAMLparam1(raw); CAMLlocal2(v, result); @try {                        \
      TYPE object = object_of_handle(raw, KIND);                          \
      v = caml_copy_int64(static_cast<int64_t>(EXPR));                    \
      result = result_ok(v); CAMLreturn(result);                          \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }
#define PRISMEL_SHADER_BOOL(NAME, KIND, TYPE, EXPR)                        \
  extern "C" CAMLprim value NAME(value raw) {                            \
    CAMLparam1(raw); @try { TYPE object = object_of_handle(raw, KIND);     \
      CAMLreturn(result_ok(Val_bool(EXPR)));                              \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }
#define PRISMEL_SHADER_SET_INT(NAME, KIND, TYPE, STMT)                     \
  extern "C" CAMLprim value NAME(value raw, value raw_value) {           \
    CAMLparam2(raw, raw_value); @try { TYPE object = object_of_handle(raw, KIND); \
      int64_t input = Int64_val(raw_value); if (input < 0)                 \
        CAMLreturn(result_error_text("shader property must be non-negative")); \
      STMT; CAMLreturn(result_unit());                                    \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }

PRISMEL_SHADER_INT(caml_prismel_metal_shader_function_options,
  Handle_kind::Function, id<MTLFunction>, object.options)
PRISMEL_SHADER_INT(caml_prismel_metal_shader_function_patch_control_point_count,
  Handle_kind::Function, id<MTLFunction>, object.patchControlPointCount)
PRISMEL_SHADER_INT(caml_prismel_metal_shader_function_patch_type,
  Handle_kind::Function, id<MTLFunction>, object.patchType)

extern "C" CAMLprim value caml_prismel_metal_shader_function_attributes(
    value raw, value raw_vertex) {
  CAMLparam2(raw, raw_vertex); CAMLlocal2(array, result);
  @try {
    id<MTLFunction> object = object_of_handle(raw, Handle_kind::Function);
    const bool vertex = Bool_val(raw_vertex);
    NSArray *objects = vertex ? static_cast<NSArray *>(object.vertexAttributes)
                              : static_cast<NSArray *>(object.stageInputAttributes);
    array = prismel_shader_handle_array(objects ?: @[],
        vertex ? Handle_kind::Shader_vertex_attribute : Handle_kind::Shader_attribute);
    result = result_ok(array); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_shader_function_argument_encoder(
    value raw, value raw_index) {
  CAMLparam2(raw, raw_index); CAMLlocal2(handle, result);
  @try {
    int64_t index = Int64_val(raw_index);
    if (index < 0) CAMLreturn(result_error_text("argument buffer index must be non-negative"));
    id<MTLFunction> object = object_of_handle(raw, Handle_kind::Function);
    id<MTLArgumentEncoder> encoder =
        [object newArgumentEncoderWithBufferIndex:static_cast<NSUInteger>(index)];
    if (encoder == nil) CAMLreturn(result_error_text("Metal returned no argument encoder"));
    handle = allocate_handle(encoder, Handle_kind::Shader_argument_encoder);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_shader_attribute_name(
    value raw, value raw_vertex) {
  CAMLparam2(raw, raw_vertex); CAMLlocal2(name, result);
  @try {
    NSString *text = Bool_val(raw_vertex)
      ? static_cast<MTLVertexAttribute *>(object_of_handle(raw, Handle_kind::Shader_vertex_attribute)).name
      : static_cast<MTLAttribute *>(object_of_handle(raw, Handle_kind::Shader_attribute)).name;
    name = copy_optional_string(text); result = result_ok(name); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
#define PRISMEL_SHADER_ATTRIBUTE_INT(NAME, FIELD)                          \
  extern "C" CAMLprim value NAME(value raw, value raw_vertex) {          \
    CAMLparam2(raw, raw_vertex); CAMLlocal2(v, result); @try {             \
      int64_t output = Bool_val(raw_vertex)                               \
        ? static_cast<int64_t>(static_cast<MTLVertexAttribute *>(object_of_handle(raw, Handle_kind::Shader_vertex_attribute)).FIELD) \
        : static_cast<int64_t>(static_cast<MTLAttribute *>(object_of_handle(raw, Handle_kind::Shader_attribute)).FIELD); \
      v = caml_copy_int64(output); result = result_ok(v); CAMLreturn(result); \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }
#define PRISMEL_SHADER_ATTRIBUTE_BOOL(NAME, FIELD)                         \
  extern "C" CAMLprim value NAME(value raw, value raw_vertex) {          \
    CAMLparam2(raw, raw_vertex); @try {                                   \
      bool output = Bool_val(raw_vertex)                                  \
        ? static_cast<MTLVertexAttribute *>(object_of_handle(raw, Handle_kind::Shader_vertex_attribute)).FIELD \
        : static_cast<MTLAttribute *>(object_of_handle(raw, Handle_kind::Shader_attribute)).FIELD; \
      CAMLreturn(result_ok(Val_bool(output)));                            \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }
PRISMEL_SHADER_ATTRIBUTE_INT(caml_prismel_metal_shader_attribute_index, attributeIndex)
PRISMEL_SHADER_ATTRIBUTE_INT(caml_prismel_metal_shader_attribute_type, attributeType)
PRISMEL_SHADER_ATTRIBUTE_BOOL(caml_prismel_metal_shader_attribute_active, active)
PRISMEL_SHADER_ATTRIBUTE_BOOL(caml_prismel_metal_shader_attribute_patch_control_point, patchControlPointData)
PRISMEL_SHADER_ATTRIBUTE_BOOL(caml_prismel_metal_shader_attribute_patch_data, patchData)

PRISMEL_SHADER_INT(caml_prismel_metal_shader_attribute_descriptor_buffer_index,
  Handle_kind::Shader_attribute_descriptor, MTLAttributeDescriptor *, object.bufferIndex)
PRISMEL_SHADER_INT(caml_prismel_metal_shader_attribute_descriptor_offset,
  Handle_kind::Shader_attribute_descriptor, MTLAttributeDescriptor *, object.offset)
PRISMEL_SHADER_INT(caml_prismel_metal_shader_attribute_descriptor_format,
  Handle_kind::Shader_attribute_descriptor, MTLAttributeDescriptor *, object.format)
PRISMEL_SHADER_SET_INT(caml_prismel_metal_shader_attribute_descriptor_set_buffer_index,
  Handle_kind::Shader_attribute_descriptor, MTLAttributeDescriptor *, object.bufferIndex = static_cast<NSUInteger>(input))
PRISMEL_SHADER_SET_INT(caml_prismel_metal_shader_attribute_descriptor_set_offset,
  Handle_kind::Shader_attribute_descriptor, MTLAttributeDescriptor *, object.offset = static_cast<NSUInteger>(input))
PRISMEL_SHADER_SET_INT(caml_prismel_metal_shader_attribute_descriptor_set_format,
  Handle_kind::Shader_attribute_descriptor, MTLAttributeDescriptor *, object.format = static_cast<MTLAttributeFormat>(input))

extern "C" CAMLprim value caml_prismel_metal_shader_attribute_descriptor_at(
    value raw, value raw_index) {
  CAMLparam2(raw, raw_index); CAMLlocal2(handle, result); @try {
    int64_t index = Int64_val(raw_index);
    if (index < 0) CAMLreturn(result_error_text("attribute index must be non-negative"));
    MTLAttributeDescriptorArray *array = object_of_handle(raw, Handle_kind::Shader_attribute_descriptor_array);
    MTLAttributeDescriptor *descriptor = array[static_cast<NSUInteger>(index)];
    if (descriptor == nil) CAMLreturn(result_error_text("Metal returned no attribute descriptor"));
    handle = allocate_handle(descriptor, Handle_kind::Shader_attribute_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_shader_attribute_descriptor_set_at(
    value raw, value raw_index, value raw_descriptor) {
  CAMLparam3(raw, raw_index, raw_descriptor); @try {
    int64_t index = Int64_val(raw_index);
    if (index < 0) CAMLreturn(result_error_text("attribute index must be non-negative"));
    MTLAttributeDescriptorArray *array = object_of_handle(raw, Handle_kind::Shader_attribute_descriptor_array);
    MTLAttributeDescriptor *descriptor = object_of_handle(raw_descriptor, Handle_kind::Shader_attribute_descriptor);
    array[static_cast<NSUInteger>(index)] = descriptor; CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_shader_stage_descriptor_create(value unit) {
  CAMLparam1(unit); CAMLlocal2(handle, result); @try {
    MTLStageInputOutputDescriptor *object = [MTLStageInputOutputDescriptor stageInputOutputDescriptor];
    handle = allocate_handle(object, Handle_kind::Shader_stage_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
PRISMEL_SHADER_INT(caml_prismel_metal_shader_stage_descriptor_index_buffer_index,
  Handle_kind::Shader_stage_descriptor, MTLStageInputOutputDescriptor *, object.indexBufferIndex)
PRISMEL_SHADER_INT(caml_prismel_metal_shader_stage_descriptor_index_type,
  Handle_kind::Shader_stage_descriptor, MTLStageInputOutputDescriptor *, object.indexType)
PRISMEL_SHADER_SET_INT(caml_prismel_metal_shader_stage_descriptor_set_index_buffer_index,
  Handle_kind::Shader_stage_descriptor, MTLStageInputOutputDescriptor *, object.indexBufferIndex = static_cast<NSUInteger>(input))
PRISMEL_SHADER_SET_INT(caml_prismel_metal_shader_stage_descriptor_set_index_type,
  Handle_kind::Shader_stage_descriptor, MTLStageInputOutputDescriptor *, object.indexType = static_cast<MTLIndexType>(input))
extern "C" CAMLprim value caml_prismel_metal_shader_stage_descriptor_reset(value raw) {
  CAMLparam1(raw); @try { MTLStageInputOutputDescriptor *object = object_of_handle(raw, Handle_kind::Shader_stage_descriptor);
    [object reset]; CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_shader_stage_descriptor_child(value raw, value raw_attributes) {
  CAMLparam2(raw, raw_attributes); CAMLlocal2(handle, result); @try {
    MTLStageInputOutputDescriptor *object = object_of_handle(raw, Handle_kind::Shader_stage_descriptor);
    id child = Bool_val(raw_attributes) ? object.attributes : object.layouts;
    Handle_kind kind = Bool_val(raw_attributes) ? Handle_kind::Shader_attribute_descriptor_array
                                                 : Handle_kind::Buffer_layout_descriptor_array;
    handle = allocate_handle(child, kind); result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_shader_stitching_input_create(value raw_index) {
  CAMLparam1(raw_index); CAMLlocal2(handle, result); @try {
    int64_t index = Int64_val(raw_index);
    if (index < 0) CAMLreturn(result_error_text("stitching argument index must be non-negative"));
    MTLFunctionStitchingInputNode *object =
        [[MTLFunctionStitchingInputNode alloc] initWithArgumentIndex:static_cast<NSUInteger>(index)];
    handle = allocate_handle(object, Handle_kind::Shader_stitching_input_node);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
PRISMEL_SHADER_INT(caml_prismel_metal_shader_stitching_input_index,
  Handle_kind::Shader_stitching_input_node, MTLFunctionStitchingInputNode *, object.argumentIndex)
PRISMEL_SHADER_SET_INT(caml_prismel_metal_shader_stitching_input_set_index,
  Handle_kind::Shader_stitching_input_node, MTLFunctionStitchingInputNode *, object.argumentIndex = static_cast<NSUInteger>(input))

#undef PRISMEL_SHADER_INT
#undef PRISMEL_SHADER_BOOL
#undef PRISMEL_SHADER_SET_INT
#undef PRISMEL_SHADER_ATTRIBUTE_INT
#undef PRISMEL_SHADER_ATTRIBUTE_BOOL
