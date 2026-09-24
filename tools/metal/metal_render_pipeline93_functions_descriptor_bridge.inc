/* RenderPipeline93 functions-descriptor closure (exact 10 IDs): class plus
   getter/setter/property triples for vertex, fragment and tile additional
   binary-linkable MTLFunction values.  Shared hookup must add the exact owned handle kind
   Render_pipeline_functions_descriptor.  Arrays are validated completely
   before any SDK setter executes; the safe layer retains logical children and
   validates one device identity when attaching this descriptor to a pipeline. */

static NSArray<id<MTLFunction>> *
prismel_render93_binary_array(value raw) {
  NSMutableArray<id<MTLFunction>> *items =
      [NSMutableArray arrayWithCapacity:Wosize_val(raw)];
  for (mlsize_t index = 0; index < Wosize_val(raw); ++index) {
    id<MTLFunction> function =
        object_of_handle(Field(raw,index),Handle_kind::Function);
    [items addObject:function];
  }
  return [items copy];
}

static value prismel_render93_copy_binary_array(
    NSArray<id<MTLFunction>> *items) {
  CAMLparam0();
  CAMLlocal2(array,handle);
  array = caml_alloc(items.count,0);
  for (NSUInteger index = 0; index < items.count; ++index) {
    handle = allocate_handle(items[index],Handle_kind::Function);
    Store_field(array,index,handle);
  }
  CAMLreturn(array);
}

extern "C" CAMLprim value
caml_prismel_metal_render93_functions_descriptor_create(value unit_raw) {
  CAMLparam1(unit_raw);
  CAMLlocal2(handle,result);
  (void)unit_raw;
  @try {
    MTLRenderPipelineFunctionsDescriptor *descriptor =
        [MTLRenderPipelineFunctionsDescriptor new];
    handle = allocate_handle(
        descriptor,Handle_kind::Render_pipeline_functions_descriptor);
    result = result_ok(handle);
    CAMLreturn(result);
  } @catch(NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_render93_functions_descriptor_array(value descriptor_raw,
                                                        value stage_raw,
                                                        value set_raw,
                                                        value replacement) {
  CAMLparam4(descriptor_raw,stage_raw,set_raw,replacement);
  CAMLlocal2(snapshot,result);
  @try {
    MTLRenderPipelineFunctionsDescriptor *descriptor = object_of_handle(
        descriptor_raw,Handle_kind::Render_pipeline_functions_descriptor);
    NSArray<id<MTLFunction>> *next = nil;
    if (Bool_val(set_raw)) next = prismel_render93_binary_array(replacement);
    NSArray<id<MTLFunction>> *current = nil;
    switch (Long_val(stage_raw)) {
      case 0:
        if (Bool_val(set_raw)) descriptor.vertexAdditionalBinaryFunctions = next;
        current = descriptor.vertexAdditionalBinaryFunctions;
        break;
      case 1:
        if (Bool_val(set_raw)) descriptor.fragmentAdditionalBinaryFunctions = next;
        current = descriptor.fragmentAdditionalBinaryFunctions;
        break;
      case 2:
        if (Bool_val(set_raw)) descriptor.tileAdditionalBinaryFunctions = next;
        current = descriptor.tileAdditionalBinaryFunctions;
        break;
      default:
        CAMLreturn(result_error_text(
            "unknown render pipeline functions descriptor stage"));
    }
    snapshot = prismel_render93_copy_binary_array(current ?: @[]);
    result = result_ok(snapshot);
    CAMLreturn(result);
  } @catch(NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}
