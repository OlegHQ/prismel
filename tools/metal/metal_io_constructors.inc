/* Smallest complete retained Metal IO ownership chain. Queue and file-handle
   protocols do not expose a device property, so constructors return the
   authoritative source-device registry ID alongside their typed handle. */

static value prismel_io_handle_with_device(id object, Handle_kind kind,
                                           id<MTLDevice> device) {
  CAMLparam0(); CAMLlocal4(handle, registry, pair, result);
  if (object == nil) CAMLreturn(result_error_text("Metal returned no IO object"));
  handle = allocate_handle(object, kind);
  registry = caml_copy_int64(device.registryID);
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, handle);
  Store_field(pair, 1, registry);
  result = result_ok(pair);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_io_queue_create(
    value raw_device, value raw_type, value raw_max_buffers,
    value raw_max_commands, value raw_label) {
  CAMLparam5(raw_device, raw_type, raw_max_buffers, raw_max_commands, raw_label);
  @autoreleasepool {
    if (@available(macOS 13.0, *)) { @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      int64_t max_buffers = Int64_val(raw_max_buffers);
      int64_t max_commands = Int64_val(raw_max_commands);
      if (max_buffers <= 0 || max_commands < 0)
        CAMLreturn(result_error_text("IO queue limits are invalid"));
      NSString *label = Is_block(raw_label)
          ? string_from_ocaml(Field(raw_label, 0)) : nil;
      if (Is_block(raw_label) && label == nil)
        CAMLreturn(result_error_text("IO queue label is not valid UTF-8"));
      MTLIOCommandQueueDescriptor *descriptor = [MTLIOCommandQueueDescriptor new];
      descriptor.type = static_cast<MTLIOCommandQueueType>(Long_val(raw_type));
      descriptor.maxCommandBufferCount = static_cast<NSUInteger>(max_buffers);
      descriptor.maxCommandsInFlight = static_cast<NSUInteger>(max_commands);
      NSError *error = nil;
      id<MTLIOCommandQueue> queue =
          [device newIOCommandQueueWithDescriptor:descriptor error:&error];
      if (queue == nil)
        CAMLreturn(result_error(error_description(error, @"Metal IO queue creation failed")));
      queue.label = label;
      if ((label == nil) != (queue.label == nil) ||
          (label != nil && ![queue.label isEqualToString:label]))
        CAMLreturn(result_error_text("Metal changed the IO queue label"));
      CAMLreturn(prismel_io_handle_with_device(queue,
          Handle_kind::Io_command_queue, device));
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
    CAMLreturn(result_error_text("Metal IO queues require macOS 13"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_io_file_create(
    value raw_device, value raw_path, value raw_label) {
  CAMLparam3(raw_device, raw_path, raw_label);
  @autoreleasepool {
    if (@available(macOS 13.0, *)) { @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      NSString *path = string_from_ocaml(raw_path);
      if (path == nil || path.length == 0)
        CAMLreturn(result_error_text("IO file path is not valid UTF-8"));
      NSString *label = Is_block(raw_label)
          ? string_from_ocaml(Field(raw_label, 0)) : nil;
      if (Is_block(raw_label) && label == nil)
        CAMLreturn(result_error_text("IO file label is not valid UTF-8"));
      NSError *error = nil;
      id<MTLIOFileHandle> file = [device
          newIOFileHandleWithURL:[NSURL fileURLWithPath:path]
                           error:&error];
      if (file == nil)
        CAMLreturn(result_error(error_description(error, @"Metal IO file creation failed")));
      file.label = label;
      if ((label == nil) != (file.label == nil) ||
          (label != nil && ![file.label isEqualToString:label]))
        CAMLreturn(result_error_text("Metal changed the IO file label"));
      CAMLreturn(prismel_io_handle_with_device(file,
          Handle_kind::Io_file_handle, device));
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
    CAMLreturn(result_error_text("Metal IO files require macOS 13"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_io_command_create(
    value raw_queue, value raw_label) {
  CAMLparam2(raw_queue, raw_label); CAMLlocal2(handle, result);
  @autoreleasepool {
    if (@available(macOS 13.0, *)) { @try {
      id<MTLIOCommandQueue> queue = object_of_handle(
          raw_queue, Handle_kind::Io_command_queue);
      NSString *label = Is_block(raw_label)
          ? string_from_ocaml(Field(raw_label, 0)) : nil;
      if (Is_block(raw_label) && label == nil)
        CAMLreturn(result_error_text("IO command label is not valid UTF-8"));
      id<MTLIOCommandBuffer> commands = [queue commandBuffer];
      if (commands == nil) CAMLreturn(result_error_text("Metal returned no IO command buffer"));
      commands.label = label;
      handle = allocate_handle(commands, Handle_kind::Io_command_buffer);
      result = result_ok(handle); CAMLreturn(result);
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
    CAMLreturn(result_error_text("Metal IO commands require macOS 13"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_io_command_commit_wait(value raw) {
  CAMLparam1(raw); CAMLlocal2(status_value, result);
  @autoreleasepool {
    if (@available(macOS 13.0, *)) { @try {
      id<MTLIOCommandBuffer> commands = object_of_handle(
          raw, Handle_kind::Io_command_buffer);
      [commands commit];
      __block NSString *wait_failure = nil;
      caml_enter_blocking_section();
      @try { [commands waitUntilCompleted]; }
      @catch (NSException *exception) { wait_failure = [exception.reason copy]; }
      caml_leave_blocking_section();
      if (wait_failure != nil) CAMLreturn(result_error(wait_failure));
      if (commands.status != MTLIOStatusComplete)
        CAMLreturn(result_error(error_description(commands.error,
            @"Metal IO command did not complete")));
      status_value = Val_long(static_cast<intnat>(commands.status));
      result = result_ok(status_value); CAMLreturn(result);
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
    CAMLreturn(result_error_text("Metal IO commands require macOS 13"));
  }
}
