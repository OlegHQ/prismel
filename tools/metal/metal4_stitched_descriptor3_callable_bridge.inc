/* MTL4StitchedFunctionDescriptor3 isolated graph shard. Function descriptors
   and their classic stitching graph are replaced as one validated ownership
   pair. Safe owners supply authoritative device IDs for opaque SDK graph nodes. */
extern "C" CAMLprim value caml_prismel_metal4_stitched_graph_pair(
    value raw, value descriptors_raw, value graph_raw, value descriptor_devices_raw,
    value graph_device_raw, value expected_device_raw, value active_raw) {
  CAMLparam5(raw, descriptors_raw, graph_raw, descriptor_devices_raw,
    graph_device_raw); CAMLxparam2(expected_device_raw, active_raw);
  if (!Bool_val(active_raw))
    CAMLreturn(result_error_text("Metal4 stitched descriptor is destroyed"));
  if (@available(macOS 26.0, *)) {
    int64_t expected = Int64_val(expected_device_raw);
    bool none = Is_none(descriptors_raw) && Is_none(graph_raw);
    if (Is_none(descriptors_raw) != Is_none(graph_raw))
      CAMLreturn(result_error_text("stitched function descriptors and graph must be paired"));
    NSArray<MTL4FunctionDescriptor *> *descriptors = nil;
    MTLFunctionStitchingGraph *graph = nil;
    @try {
      if (!none) {
        value items = Field(descriptors_raw, 0);
        if (Wosize_val(items) == 0 || Wosize_val(descriptor_devices_raw) != Wosize_val(items)
            || Is_none(graph_device_raw) || Int64_val(Field(graph_device_raw, 0)) != expected)
          CAMLreturn(result_error_text("stitched graph cardinality/device mismatch"));
        NSMutableArray<MTL4FunctionDescriptor *> *decoded =
          [NSMutableArray arrayWithCapacity:Wosize_val(items)];
        for (mlsize_t index = 0; index < Wosize_val(items); ++index) {
          if (Int64_val(Field(descriptor_devices_raw, index)) != expected)
            CAMLreturn(result_error_text("stitched function descriptor device mismatch"));
          MTL4FunctionDescriptor *descriptor = object_of_handle(Field(items, index),
            Handle_kind::Function_descriptor4);
          if ([decoded containsObject:descriptor])
            CAMLreturn(result_error_text("duplicate stitched function descriptor"));
          [decoded addObject:descriptor];
        }
        descriptors = [decoded copy];
        graph = object_of_handle(Field(graph_raw, 0), Handle_kind::Stitching_graph);
      } else if (Wosize_val(descriptor_devices_raw) != 0 || !Is_none(graph_device_raw)) {
        CAMLreturn(result_error_text("nil stitched graph has unexpected device metadata"));
      }
      MTL4StitchedFunctionDescriptor *owner = object_of_handle(raw,
        Handle_kind::Stitched_function_descriptor4);
      owner.functionDescriptors = descriptors; owner.functionGraph = graph;
      CAMLreturn(result_unit());
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal4 stitched functions require macOS 26"));
}
extern "C" CAMLprim value caml_prismel_metal4_stitched_graph_pair_bytecode(
    value *argv, int argc) { (void)argc;
  return caml_prismel_metal4_stitched_graph_pair(argv[0], argv[1], argv[2],
    argv[3], argv[4], argv[5], argv[6]);
}

extern "C" CAMLprim value caml_prismel_metal4_stitched_graph_snapshot(value raw) {
  CAMLparam1(raw); CAMLlocal4(pair, descriptors, graph_option, graph_handle);
  if (@available(macOS 26.0, *)) {
    @try { MTL4StitchedFunctionDescriptor *owner = object_of_handle(raw,
        Handle_kind::Stitched_function_descriptor4);
      NSArray<MTL4FunctionDescriptor *> *items = owner.functionDescriptors;
      descriptors = caml_alloc(items.count, 0);
      for (NSUInteger index = 0; index < items.count; ++index)
        Store_field(descriptors, index, allocate_handle(items[index],
          Handle_kind::Function_descriptor4));
      if (owner.functionGraph == nil) graph_option = Val_none;
      else { graph_handle = allocate_handle(owner.functionGraph, Handle_kind::Stitching_graph);
        graph_option = caml_alloc(1, 0); Store_field(graph_option, 0, graph_handle); }
      pair = caml_alloc_tuple(2); Store_field(pair, 0, descriptors);
      Store_field(pair, 1, graph_option); CAMLreturn(result_ok(pair));
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal4 stitched functions require macOS 26"));
}
