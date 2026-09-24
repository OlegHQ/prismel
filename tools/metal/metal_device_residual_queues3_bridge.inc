/* Exact MTLDevice queue constructors. Returned queue handles own the native
   object; descriptor log-state identity is validated before construction. */
extern "C" CAMLprim value caml_prismel_metal_device_queue_descriptor(
    value raw_device, value raw_descriptor) {
  CAMLparam2(raw_device, raw_descriptor); CAMLlocal2(handle, result);
  if (@available(macOS 15.0, *)) {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      PrismelMetalCommandQueueDescriptorState *wrapper = object_of_handle(
          raw_descriptor, Handle_kind::Command_queue_descriptor);
      if (wrapper.logState != nil &&
          wrapper.logState.registryID != device.registryID)
        CAMLreturn(result_error_text("queue log state belongs to another device"));
      id<MTLCommandQueue> queue =
          [device newCommandQueueWithDescriptor:wrapper.descriptor];
      if (queue == nil) CAMLreturn(result_error_text("Metal returned no command queue"));
      handle = allocate_handle(queue, Handle_kind::Command_queue);
      result = result_ok(handle); CAMLreturn(result);
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("command queue descriptors require macOS 15"));
}

extern "C" CAMLprim value caml_prismel_metal_device_queue_maximum(
    value raw_device, value raw_maximum) {
  CAMLparam2(raw_device, raw_maximum); CAMLlocal2(handle, result);
  int64_t maximum = Int64_val(raw_maximum);
  if (maximum <= 0) CAMLreturn(result_error_text("queue maximum must be positive"));
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    id<MTLCommandQueue> queue =
        [device newCommandQueueWithMaxCommandBufferCount:(NSUInteger)maximum];
    if (queue == nil) CAMLreturn(result_error_text("Metal returned no command queue"));
    handle = allocate_handle(queue, Handle_kind::Command_queue);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_queue4_default(value raw_device) {
  CAMLparam1(raw_device); CAMLlocal2(handle, result);
  if (@available(macOS 26.0, *)) {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      if (![device supportsFamily:MTLGPUFamilyMetal4])
        CAMLreturn(result_error_text("device does not support Metal 4"));
      id<MTL4CommandQueue> queue = [device newMTL4CommandQueue];
      if (queue == nil) CAMLreturn(result_error_text("Metal returned no Metal 4 queue"));
      handle = allocate_handle(queue, Handle_kind::Command_queue4);
      result = result_ok(handle); CAMLreturn(result);
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal 4 command queues require macOS 26"));
}
