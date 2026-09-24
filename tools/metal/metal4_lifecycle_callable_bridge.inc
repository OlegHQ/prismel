/* Exact CAML Result adapters for the authoritative Metal4 lifecycle shard.
   Metal.command4_buffer_create already begins its command buffer, so [begin]
   validates the retained allocator and applies the optional label instead of
   illegally beginning the same native command buffer twice. */

extern "C" CAMLprim value caml_prismel_metal4_begin(
    value raw_buffer, value raw_allocator, value raw_label) {
  CAMLparam3(raw_buffer, raw_allocator, raw_label);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetal4CommandBufferState *state =
            command_buffer4_state_of_handle(raw_buffer);
        id<MTL4CommandAllocator> allocator =
            object_of_handle(raw_allocator, Handle_kind::Command_allocator4);
        if (state.allocator != allocator ||
            state.commandBuffer.device.registryID != allocator.device.registryID) {
          CAMLreturn(result_error_text(
              "Metal 4 command buffer belongs to another allocator"));
        }
        if (Is_block(raw_label)) {
          NSString *label = string_from_ocaml(Field(raw_label, 0));
          if (label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 command-buffer label is not valid UTF-8"));
          }
          state.commandBuffer.label = label;
          if (![state.commandBuffer.label isEqualToString:label]) {
            CAMLreturn(result_error_text(
                "Metal changed the checked Metal 4 command-buffer label"));
          }
        }
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal4_wait_event(
    value raw_queue, value raw_event, value raw_value) {
  CAMLparam3(raw_queue, raw_event, raw_value);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4CommandQueue> queue =
            object_of_handle(raw_queue, Handle_kind::Command_queue4);
        id<MTLEvent> event = object_of_handle(raw_event, Handle_kind::Event);
        if (queue.device.registryID != event.device.registryID) {
          CAMLreturn(result_error_text(
              "Metal 4 event belongs to another device"));
        }
        int64_t event_value = Int64_val(raw_value);
        if (event_value < 0) {
          CAMLreturn(result_error_text(
              "Metal 4 event value must be non-negative"));
        }
        NSString *failure = nil;
        if (!prismel_metal4_wait_event(
                queue, event, static_cast<uint64_t>(event_value),
                &failure)) {
          CAMLreturn(result_error(failure));
        }
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}
