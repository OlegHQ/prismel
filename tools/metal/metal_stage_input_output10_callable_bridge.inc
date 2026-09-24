/* StageInputOutputDescriptor10 isolated ownership shard. Attribute replacement
   is decoded before mutation; returned child arrays/descriptors are retained
   exact-kind handles. The safe graph owns descriptor children until reset. */
extern "C" CAMLprim value caml_prismel_metal_stage_io_attribute_at(
    value array_raw, value index_raw) {
  CAMLparam2(array_raw, index_raw); CAMLlocal3(option, handle, result);
  int64_t index = Int64_val(index_raw);
  if (index < 0) CAMLreturn(result_error_text("stage attribute index is negative"));
  @try {
    MTLAttributeDescriptorArray *array = object_of_handle(
      array_raw, Handle_kind::Shader_attribute_descriptor_array);
    MTLAttributeDescriptor *descriptor = array[(NSUInteger)index];
    if (descriptor == nil) option = Val_none;
    else { handle = allocate_handle(descriptor, Handle_kind::Shader_attribute_descriptor);
      option = caml_alloc(1, 0); Store_field(option, 0, handle); }
    result = result_ok(option); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_stage_io_attribute_set(
    value array_raw, value index_raw, value descriptor_raw) {
  CAMLparam3(array_raw, index_raw, descriptor_raw);
  int64_t index = Int64_val(index_raw);
  if (index < 0) CAMLreturn(result_error_text("stage attribute index is negative"));
  @try {
    MTLAttributeDescriptor *descriptor = Is_none(descriptor_raw) ? nil :
      object_of_handle(Field(descriptor_raw, 0), Handle_kind::Shader_attribute_descriptor);
    MTLAttributeDescriptorArray *array = object_of_handle(
      array_raw, Handle_kind::Shader_attribute_descriptor_array);
    array[(NSUInteger)index] = descriptor;
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_stage_io_children(value raw) {
  CAMLparam1(raw); CAMLlocal4(tuple, attributes, layouts, result);
  @try {
    MTLStageInputOutputDescriptor *descriptor = object_of_handle(
      raw, Handle_kind::Shader_stage_descriptor);
    attributes = allocate_handle(descriptor.attributes,
      Handle_kind::Shader_attribute_descriptor_array);
    layouts = allocate_handle(descriptor.layouts,
      Handle_kind::Buffer_layout_descriptor_array);
    tuple = caml_alloc_tuple(2); Store_field(tuple, 0, attributes);
    Store_field(tuple, 1, layouts); result = result_ok(tuple); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_stage_io_reset(value raw) {
  CAMLparam1(raw);
  @try { MTLStageInputOutputDescriptor *descriptor = object_of_handle(
      raw, Handle_kind::Shader_stage_descriptor);
    [descriptor reset]; CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
