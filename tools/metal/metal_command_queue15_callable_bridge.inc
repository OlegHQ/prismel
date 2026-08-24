/* CommandQueue15 isolated shard. Integration adds Command_queue_descriptor and
   Log_state handle kinds. Handles allocated for unretained-reference command
   buffers retain the returned Objective-C object, making that SDK fast path
   safe across OCaml ownership and queue-parent lifetime. */
extern "C" CAMLprim value caml_prismel_metal_command_queue_descriptor_create(
    value max_raw, value log_state) {
  CAMLparam2(max_raw, log_state); CAMLlocal2(handle, result);
  if (@available(macOS 15.0, *)) {} else
    CAMLreturn(result_error_text("command queue descriptors require macOS 15"));
  int64_t maximum = Int64_val(max_raw);
  if (maximum <= 0) CAMLreturn(result_error_text("command queue maximum must be positive"));
  @try {
    PrismelMetalCommandQueueDescriptorState *wrapper = [PrismelMetalCommandQueueDescriptorState new];
    MTLCommandQueueDescriptor *descriptor = [MTLCommandQueueDescriptor new];
    descriptor.maxCommandBufferCount = (NSUInteger)maximum;
    PrismelMetalLogStateState *state = Is_none(log_state) ? nil :
      object_of_handle(Field(log_state, 0), Handle_kind::Log_state);
    descriptor.logState = state.state;
    wrapper.descriptor = descriptor; wrapper.logState = state;
    handle = allocate_handle(wrapper, Handle_kind::Command_queue_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_command_queue_descriptor_snapshot(value raw) {
  CAMLparam1(raw); CAMLlocal5(tuple, maximum, log_state, handle, result); @try {
    if (@available(macOS 15.0, *)) {} else
      CAMLreturn(result_error_text("command queue descriptors require macOS 15"));
    PrismelMetalCommandQueueDescriptorState *wrapper =
      object_of_handle(raw, Handle_kind::Command_queue_descriptor);
    MTLCommandQueueDescriptor *descriptor = wrapper.descriptor;
    maximum = caml_copy_int64(descriptor.maxCommandBufferCount);
    if (wrapper.logState == nil) log_state = Val_none;
    else { handle = allocate_handle(wrapper.logState, Handle_kind::Log_state);
      log_state = caml_alloc(1, 0); Store_field(log_state, 0, handle); }
    tuple = caml_alloc_tuple(2); Store_field(tuple, 0, maximum);
    Store_field(tuple, 1, log_state); result = result_ok(tuple); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_command_queue_descriptor_set(
    value raw, value max_raw, value log_state) {
  CAMLparam3(raw, max_raw, log_state); int64_t maximum = Int64_val(max_raw);
  if (@available(macOS 15.0, *)) {} else
    CAMLreturn(result_error_text("command queue descriptors require macOS 15"));
  if (maximum <= 0) CAMLreturn(result_error_text("command queue maximum must be positive"));
  @try { PrismelMetalCommandQueueDescriptorState *wrapper =
      object_of_handle(raw, Handle_kind::Command_queue_descriptor);
    MTLCommandQueueDescriptor *descriptor = wrapper.descriptor;
    PrismelMetalLogStateState *state = Is_none(log_state) ? nil :
      object_of_handle(Field(log_state, 0), Handle_kind::Log_state);
    /* Decode and validate every owned edge before mutating the descriptor. */
    descriptor.maxCommandBufferCount = (NSUInteger)maximum; descriptor.logState = state.state;
    wrapper.logState = state;
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

/* mode 0 is commandBufferWithUnretainedReferences; mode 1 materializes the
   exact command-buffer descriptor tuple (retainedReferences,errorOptions,log). */
extern "C" CAMLprim value caml_prismel_metal_command_queue_command_buffer(
    value raw, value mode_raw, value retained_raw, value error_options_raw,
    value log_state) {
  CAMLparam5(raw, mode_raw, retained_raw, error_options_raw, log_state);
  CAMLlocal2(handle, result); @try {
    id<MTLCommandQueue> queue = object_of_handle(raw, Handle_kind::Command_queue);
    id<MTLCommandBuffer> command = nil;
    if (Long_val(mode_raw) == 0) command = [queue commandBufferWithUnretainedReferences];
    else if (Long_val(mode_raw) == 1) {
      if (@available(macOS 15.0, *)) {} else
        CAMLreturn(result_error_text("command-buffer descriptors require macOS 15"));
      MTLCommandBufferDescriptor *descriptor = [MTLCommandBufferDescriptor new];
      descriptor.retainedReferences = Bool_val(retained_raw);
      descriptor.errorOptions = (MTLCommandBufferErrorOption)Int64_val(error_options_raw);
      PrismelMetalLogStateState *state = Is_none(log_state) ? nil :
        object_of_handle(Field(log_state, 0), Handle_kind::Log_state);
      if (state != nil && state.registryID != queue.device.registryID)
        CAMLreturn(result_error_text("log state belongs to another Metal device"));
      descriptor.logState = state.state;
      command = [queue commandBufferWithDescriptor:descriptor];
    } else CAMLreturn(result_error_text("unknown command-buffer constructor"));
    if (command == nil) CAMLreturn(result_error_text("Metal returned no command buffer"));
    /* allocate_handle retains even the SDK's unretained-references variant. */
    handle = allocate_handle(command, Handle_kind::Command_buffer);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_command_queue_snapshot(value raw) {
  CAMLparam1(raw); CAMLlocal4(tuple, label, device, result); @try {
    id<MTLCommandQueue> queue = object_of_handle(raw, Handle_kind::Command_queue);
    label = copy_optional_string(queue.label); device = caml_copy_int64(queue.device.registryID);
    tuple = caml_alloc_tuple(2); Store_field(tuple, 0, label); Store_field(tuple, 1, device);
    result = result_ok(tuple); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_command_queue_set_label(value raw, value option) {
  CAMLparam2(raw, option); @try {
    NSString *label = Is_none(option) ? nil : string_from_ocaml(Field(option, 0));
    if (!Is_none(option) && label == nil)
      CAMLreturn(result_error_text("command queue label is not valid UTF-8"));
    id<MTLCommandQueue> queue = object_of_handle(raw, Handle_kind::Command_queue);
    queue.label = label;
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
extern "C" CAMLprim value caml_prismel_metal_command_queue_capture_boundary(value raw) {
  CAMLparam1(raw); @try {
    id<MTLCommandQueue> queue = object_of_handle(raw, Handle_kind::Command_queue);
    [queue insertDebugCaptureBoundary]; CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
#pragma clang diagnostic pop
