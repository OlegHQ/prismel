/* Exact MTL4StitchedFunctionDescriptor function-descriptor ownership graph.
   The stitching graph is nullable; this callable slice deliberately exposes
   nil rather than manufacturing an unchecked classic graph. */
static NSArray<MTL4FunctionDescriptor *> *metal4_function_descriptors(value raw) {
  const mlsize_t count = Wosize_val(raw);
  NSMutableArray<MTL4FunctionDescriptor *> *items =
      [[NSMutableArray alloc] initWithCapacity:count];
  for (mlsize_t index = 0; index < count; ++index) {
    MTL4FunctionDescriptor *descriptor = object_of_handle(
        Field(raw, index), Handle_kind::Function_descriptor4);
    [items addObject:descriptor];
  }
  return items;
}

extern "C" CAMLprim value caml_prismel_metal4_stitched_descriptor(
    value raw_descriptors) {
  CAMLparam1(raw_descriptors);
  CAMLlocal2(raw, result);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4StitchedFunctionDescriptor *descriptor =
          [MTL4StitchedFunctionDescriptor new];
      descriptor.functionGraph = nil;
      descriptor.functionDescriptors = metal4_function_descriptors(raw_descriptors);
      if (descriptor.functionGraph != nil ||
          descriptor.functionDescriptors.count != Wosize_val(raw_descriptors)) {
        CAMLreturn(result_error_text("Metal changed stitched graph ownership"));
      }
      raw = allocate_handle(descriptor, Handle_kind::Stitched_function_descriptor4);
      result = result_ok(raw);
      CAMLreturn(result);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_stitched_get(value raw_descriptor) {
  CAMLparam1(raw_descriptor);
  CAMLlocal3(output, raw, result);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4StitchedFunctionDescriptor *descriptor = object_of_handle(
          raw_descriptor, Handle_kind::Stitched_function_descriptor4);
      NSArray<MTL4FunctionDescriptor *> *items = descriptor.functionDescriptors;
      if (descriptor.functionGraph != nil) {
        CAMLreturn(result_error_text("unchecked non-null stitching graph"));
      }
      output = caml_alloc(items.count, 0);
      for (NSUInteger index = 0; index < items.count; ++index) {
        raw = allocate_handle(items[index], Handle_kind::Function_descriptor4);
        Store_field(output, index, raw);
      }
      result = result_ok(output);
      CAMLreturn(result);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_stitched_set(
    value raw_descriptor, value raw_descriptors) {
  CAMLparam2(raw_descriptor, raw_descriptors);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4StitchedFunctionDescriptor *descriptor = object_of_handle(
          raw_descriptor, Handle_kind::Stitched_function_descriptor4);
      descriptor.functionGraph = nil;
      descriptor.functionDescriptors = metal4_function_descriptors(raw_descriptors);
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}
