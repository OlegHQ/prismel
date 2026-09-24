/* MTL4RenderPipeline3 isolated reset shard. Constructors are support machinery
   for safe ownership of the two reset receivers and do not add inventory IDs. */
extern "C" CAMLprim value caml_prismel_metal4_render_pipeline3_create(
    value kind_raw) {
  CAMLparam1(kind_raw); CAMLlocal2(handle, result);
  if (@available(macOS 26.0, *)) {
    @try { if (Long_val(kind_raw) == 0) {
        MTL4RenderPipelineColorAttachmentDescriptor *attachment =
          [MTL4RenderPipelineColorAttachmentDescriptor new];
        handle = allocate_handle(attachment, Handle_kind::Color_attachment_descriptor4);
      } else if (Long_val(kind_raw) == 1) {
        MTL4RenderPipelineDescriptor *pipeline = [MTL4RenderPipelineDescriptor new];
        handle = allocate_handle(pipeline.colorAttachments,
          Handle_kind::Color_attachment_array4);
      } else CAMLreturn(result_error_text("unknown Metal4 render reset receiver"));
      result = result_ok(handle); CAMLreturn(result);
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal4 render pipelines require macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_render_pipeline3_reset(
    value raw, value kind_raw, value active_raw) {
  CAMLparam3(raw, kind_raw, active_raw);
  if (!Bool_val(active_raw))
    CAMLreturn(result_error_text("Metal4 render reset receiver is destroyed"));
  if (@available(macOS 26.0, *)) {
    @try { if (Long_val(kind_raw) == 0) {
        MTL4RenderPipelineColorAttachmentDescriptor *attachment =
          object_of_handle(raw, Handle_kind::Color_attachment_descriptor4);
        [attachment reset];
      } else if (Long_val(kind_raw) == 1) {
        MTL4RenderPipelineColorAttachmentDescriptorArray *array =
          object_of_handle(raw, Handle_kind::Color_attachment_array4);
        [array reset];
      } else CAMLreturn(result_error_text("unknown Metal4 render reset receiver"));
      CAMLreturn(result_unit());
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal4 render pipelines require macOS 26"));
}
