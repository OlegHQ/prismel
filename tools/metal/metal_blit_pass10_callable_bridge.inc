/* BlitPass10 residual ownership shard. Descriptor creation and attachment-array
   acquisition already use Blit_pass_descriptor/Blit_sample_attachment_array.
   These adapters complete nullable array and counter-buffer graph ownership. */
extern "C" CAMLprim value caml_prismel_metal_blit_pass10_attachment_at(
    value array_raw, value index_raw) {
  CAMLparam2(array_raw, index_raw); CAMLlocal3(option, handle, result);
  int64_t index = Int64_val(index_raw);
  if (index < 0) CAMLreturn(result_error_text("blit attachment index is negative"));
  @try { MTLBlitPassSampleBufferAttachmentDescriptorArray *array =
      object_of_handle(array_raw, Handle_kind::Blit_sample_attachment_array);
    MTLBlitPassSampleBufferAttachmentDescriptor *attachment = array[(NSUInteger)index];
    if (attachment == nil) option = Val_none;
    else { handle = allocate_handle(attachment, Handle_kind::Blit_sample_attachment);
      option = caml_alloc(1, 0); Store_field(option, 0, handle); }
    result = result_ok(option); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_blit_pass10_attachment_set(
    value array_raw, value index_raw, value attachment_raw) {
  CAMLparam3(array_raw, index_raw, attachment_raw);
  int64_t index = Int64_val(index_raw);
  if (index < 0) CAMLreturn(result_error_text("blit attachment index is negative"));
  @try { MTLBlitPassSampleBufferAttachmentDescriptor *attachment =
      Is_none(attachment_raw) ? nil : object_of_handle(Field(attachment_raw, 0),
        Handle_kind::Blit_sample_attachment);
    MTLBlitPassSampleBufferAttachmentDescriptorArray *array =
      object_of_handle(array_raw, Handle_kind::Blit_sample_attachment_array);
    array[(NSUInteger)index] = attachment; CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_blit_pass10_sample_buffer(value raw) {
  CAMLparam1(raw); CAMLlocal3(option, handle, result);
  @try { MTLBlitPassSampleBufferAttachmentDescriptor *attachment =
      object_of_handle(raw, Handle_kind::Blit_sample_attachment);
    id<MTLCounterSampleBuffer> buffer = attachment.sampleBuffer;
    if (buffer == nil) option = Val_none;
    else { handle = allocate_handle(buffer, Handle_kind::Counter_sample_buffer);
      option = caml_alloc(1, 0); Store_field(option, 0, handle); }
    result = result_ok(option); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_blit_pass10_set_sample_buffer(
    value raw, value buffer_raw, value device_raw) {
  CAMLparam3(raw, buffer_raw, device_raw);
  @try { id<MTLCounterSampleBuffer> buffer = Is_none(buffer_raw) ? nil :
      object_of_handle(Field(buffer_raw, 0), Handle_kind::Counter_sample_buffer);
    if (buffer != nil && (int64_t)buffer.device.registryID != Int64_val(device_raw))
      CAMLreturn(result_error_text("blit sample buffer device mismatch"));
    MTLBlitPassSampleBufferAttachmentDescriptor *attachment =
      object_of_handle(raw, Handle_kind::Blit_sample_attachment);
    attachment.sampleBuffer = buffer; CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
