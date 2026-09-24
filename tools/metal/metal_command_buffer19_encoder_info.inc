extern "C" CAMLprim value caml_prismel_metal_command_buffer_encoder_infos(value raw) {
  CAMLparam1(raw);
  CAMLlocal5(result, array, tuple, label, signposts);
  @try {
    id<MTLCommandBuffer> command = object_of_handle(raw, Handle_kind::Command_buffer);
    if (command.status != MTLCommandBufferStatusError)
      CAMLreturn(result_error(@"encoder diagnostics require a failed command buffer"));
    NSArray<id<MTLCommandBufferEncoderInfo>> *infos =
      command.error.userInfo[MTLCommandBufferEncoderInfoErrorKey];
    if (infos == nil) infos = @[];
    array = caml_alloc((mlsize_t)infos.count, 0);
    for (NSUInteger i = 0; i < infos.count; ++i) {
      id<MTLCommandBufferEncoderInfo> info = infos[i];
      tuple = caml_alloc_tuple(3);
      label = copy_optional_string(info.label);
      Store_field(tuple, 0, label);
      NSArray<NSString *> *native_signposts = info.debugSignposts ?: @[];
      signposts = caml_alloc((mlsize_t)native_signposts.count, 0);
      for (NSUInteger j = 0; j < native_signposts.count; ++j)
        Store_field(signposts, j,
          caml_copy_string(native_signposts[j].UTF8String ?: ""));
      Store_field(tuple, 1, signposts);
      Store_field(tuple, 2, Val_long((long)info.errorState));
      Store_field(array, i, tuple);
    }
    result = result_ok(array);
    CAMLreturn(result);
  } @catch (NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}
