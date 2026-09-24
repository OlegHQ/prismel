/* Remaining MTL4CommandEncoder fence wait.  The command-buffer state is the
   retention owner; validation completes before the native command mutation. */
extern "C" CAMLprim value caml_prismel_metal4_encoder_wait_fence(
    value encoder_raw, value command_buffer_raw, value fence_raw,
    value stages_raw) {
  CAMLparam4(encoder_raw, command_buffer_raw, fence_raw, stages_raw);
  if (@available(macOS 26.0, *)) {
    int64_t stages = Int64_val(stages_raw);
    if (stages <= 0)
      CAMLreturn(result_error_text("Metal4 fence wait requires nonempty stages"));
    @try {
      id<MTL4CommandEncoder> encoder;
      PrismelMetal4CommandBufferState *state;
      NSString *failure = nil;
      if (!prismel_metal4_encoder_graph(encoder_raw, command_buffer_raw,
                                        &encoder, &state, &failure))
        CAMLreturn(result_error(failure));
      id<MTLFence> fence = object_of_handle(fence_raw, Handle_kind::Fence);
      if (fence.device.registryID != state.commandBuffer.device.registryID)
        CAMLreturn(result_error_text("Metal4 fence belongs to another device"));
      [encoder waitForFence:fence beforeEncoderStages:(MTLStages)stages];
      [state retainEncodedObject:fence];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_error_text("Metal4 fence waits require macOS 26"));
}
