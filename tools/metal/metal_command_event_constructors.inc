/* Constructible Command-support event handles. The source registry ID is
   returned with the handle because some valid shared events report nil from
   MTLEvent.device on older Metal runtimes. */

static value prismel_command_event_result(id<MTLEvent> event,
                                          Handle_kind kind,
                                          id<MTLDevice> source) {
  CAMLparam0(); CAMLlocal4(handle, registry, pair, result);
  if (event == nil) CAMLreturn(result_error_text("Metal returned no event"));
  if (event.device != nil && event.device.registryID != source.registryID)
    CAMLreturn(result_error_text("Metal returned an event for another device"));
  handle = allocate_handle(event, kind);
  registry = caml_copy_int64(source.registryID);
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, handle);
  Store_field(pair, 1, registry);
  result = result_ok(pair);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_command_event_create(value raw_device) {
  CAMLparam1(raw_device); @autoreleasepool { @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    id<MTLEvent> event = [device newEvent];
    CAMLreturn(prismel_command_event_result(event, Handle_kind::Event, device));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
}

extern "C" CAMLprim value caml_prismel_metal_command_shared_event_create(value raw_device) {
  CAMLparam1(raw_device); @autoreleasepool { @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    id<MTLSharedEvent> event = [device newSharedEvent];
    CAMLreturn(prismel_command_event_result(event, Handle_kind::Shared_event, device));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
}
