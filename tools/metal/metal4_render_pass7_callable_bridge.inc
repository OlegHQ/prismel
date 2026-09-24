/* MTL4RenderPass7 residual graph shard. Sample positions are already callable
   through metal4_render_pass_sample_positions. This completes rate-map and
   depth/stencil ownership after validating the entire graph before mutation. */
static bool prismel_metal4_render_attachment(
    MTLRenderPassAttachmentDescriptor *attachment, uint64_t device,
    NSUInteger samples) {
  if (attachment == nil) return true;
  id<MTLTexture> texture = attachment.texture;
  id<MTLTexture> resolve = attachment.resolveTexture;
  return (texture == nil || (texture.device.registryID == device
                            && texture.sampleCount == samples))
    && (resolve == nil || resolve.device.registryID == device);
}

extern "C" CAMLprim value caml_prismel_metal4_render_pass7_attachment_create(
    value kind_raw) {
  CAMLparam1(kind_raw); CAMLlocal2(handle, result);
  if (@available(macOS 26.0, *)) {
    @try { if (Long_val(kind_raw) == 0)
        handle = allocate_handle([MTLRenderPassDepthAttachmentDescriptor new],
          Handle_kind::Render_pass_depth_attachment);
      else if (Long_val(kind_raw) == 1)
        handle = allocate_handle([MTLRenderPassStencilAttachmentDescriptor new],
          Handle_kind::Render_pass_stencil_attachment);
      else CAMLreturn(result_error_text("unknown render-pass attachment kind"));
      result = result_ok(handle); CAMLreturn(result);
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal4 render passes require macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_render_pass7_set_graph(
    value raw, value rate_map_raw, value depth_raw, value stencil_raw,
    value device_raw, value sample_count_raw) {
  CAMLparam5(raw, rate_map_raw, depth_raw, stencil_raw, device_raw);
  CAMLxparam1(sample_count_raw);
  int64_t sample_count = Int64_val(sample_count_raw);
  if (sample_count <= 0) CAMLreturn(result_error_text("invalid render-pass sample count"));
  if (@available(macOS 26.0, *)) {
    @try { uint64_t device = (uint64_t)Int64_val(device_raw);
      id<MTLRasterizationRateMap> map = Is_none(rate_map_raw) ? nil :
        object_of_handle(Field(rate_map_raw, 0), Handle_kind::Raster_rate_map);
      MTLRenderPassDepthAttachmentDescriptor *depth = Is_none(depth_raw) ? nil :
        object_of_handle(Field(depth_raw, 0), Handle_kind::Render_pass_depth_attachment);
      MTLRenderPassStencilAttachmentDescriptor *stencil = Is_none(stencil_raw) ? nil :
        object_of_handle(Field(stencil_raw, 0), Handle_kind::Render_pass_stencil_attachment);
      if ((map != nil && map.device.registryID != device)
          || !prismel_metal4_render_attachment(depth, device, (NSUInteger)sample_count)
          || !prismel_metal4_render_attachment(stencil, device, (NSUInteger)sample_count))
        CAMLreturn(result_error_text("Metal4 render-pass graph device/sample mismatch"));
      MTL4RenderPassDescriptor *descriptor = object_of_handle(raw,
        Handle_kind::Render_pass_descriptor4);
      descriptor.rasterizationRateMap = map; descriptor.depthAttachment = depth;
      descriptor.stencilAttachment = stencil; CAMLreturn(result_unit());
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal4 render passes require macOS 26"));
}
extern "C" CAMLprim value caml_prismel_metal4_render_pass7_set_graph_bytecode(
    value *argv, int argc) { (void)argc;
  return caml_prismel_metal4_render_pass7_set_graph(argv[0], argv[1], argv[2],
    argv[3], argv[4], argv[5]);
}

extern "C" CAMLprim value caml_prismel_metal4_render_pass7_rate_map(value raw) {
  CAMLparam1(raw); CAMLlocal3(option, handle, result);
  if (@available(macOS 26.0, *)) {
    @try { MTL4RenderPassDescriptor *descriptor = object_of_handle(raw,
        Handle_kind::Render_pass_descriptor4);
      if (descriptor.rasterizationRateMap == nil) option = Val_none;
      else { handle = allocate_handle(descriptor.rasterizationRateMap,
          Handle_kind::Raster_rate_map); option = caml_alloc(1, 0);
        Store_field(option, 0, handle); }
      result = result_ok(option); CAMLreturn(result);
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal4 render passes require macOS 26"));
}
