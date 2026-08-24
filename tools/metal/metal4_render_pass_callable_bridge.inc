/* Checked callable closure for the seven ownership-bearing MTL4RenderPassDescriptor
   method/property IDs. Nullable attachment/rate-map fields are reset explicitly;
   non-null object graphs remain the responsibility of the existing checked
   command4_render_encoder_create path. */
extern "C" CAMLprim value caml_prismel_metal4_render_pass_descriptor(value unit) {
  CAMLparam1(unit);
  CAMLlocal2(raw, result);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4RenderPassDescriptor *descriptor = [MTL4RenderPassDescriptor new];
      descriptor.depthAttachment = nil;
      descriptor.stencilAttachment = nil;
      descriptor.rasterizationRateMap = nil;
      if (descriptor.depthAttachment == nil || descriptor.stencilAttachment == nil ||
          descriptor.rasterizationRateMap != nil) {
        CAMLreturn(result_error_text("Metal changed render-pass nullable defaults"));
      }
      raw = allocate_handle(descriptor, Handle_kind::Render_pass_descriptor4);
      result = result_ok(raw);
      CAMLreturn(result);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_render_pass_sample_positions(
    value raw_descriptor, value raw_positions) {
  CAMLparam2(raw_descriptor, raw_positions);
  CAMLlocal3(result, pair, output);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4RenderPassDescriptor *descriptor = object_of_handle(
          raw_descriptor, Handle_kind::Render_pass_descriptor4);
      const mlsize_t count = Wosize_val(raw_positions);
      if (count != 0 && count != 2 && count != 4 && count != 8) {
        CAMLreturn(result_error_text("Metal 4 sample-position count must be 0, 2, 4, or 8"));
      }
      std::vector<MTLSamplePosition> positions(count);
      for (mlsize_t index = 0; index < count; ++index) {
        value item = Field(raw_positions, index);
        if (!Is_block(item) || Wosize_val(item) != 2) {
          CAMLreturn(result_error_text("Metal 4 sample-position shape is invalid"));
        }
        const double x = Double_val(Field(item, 0));
        const double y = Double_val(Field(item, 1));
        if (!std::isfinite(x) || !std::isfinite(y) || x < 0.0 || x > 1.0 ||
            y < 0.0 || y > 1.0) {
          CAMLreturn(result_error_text("Metal 4 sample position is out of range"));
        }
        positions[index] = MTLSamplePositionMake((float)x, (float)y);
      }
      [descriptor setSamplePositions:count == 0 ? nullptr : positions.data()
                                count:count];
      const NSUInteger actual = [descriptor getSamplePositions:nullptr count:0];
      if (actual != count) {
        CAMLreturn(result_error_text("Metal changed sample-position cardinality"));
      }
      std::vector<MTLSamplePosition> copied(actual);
      if ([descriptor getSamplePositions:actual == 0 ? nullptr : copied.data()
                                      count:actual] != actual) {
        CAMLreturn(result_error_text("Metal failed to copy sample positions"));
      }
      output = caml_alloc(actual, 0);
      for (NSUInteger index = 0; index < actual; ++index) {
        pair = caml_alloc_tuple(2);
        Store_field(pair, 0, caml_copy_double(copied[index].x));
        Store_field(pair, 1, caml_copy_double(copied[index].y));
        Store_field(output, index, pair);
      }
      result = result_ok(output);
      CAMLreturn(result);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_render_pass_rate_map(
    value raw_descriptor, value raw_map) {
  CAMLparam2(raw_descriptor, raw_map);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4RenderPassDescriptor *descriptor = object_of_handle(
          raw_descriptor, Handle_kind::Render_pass_descriptor4);
      id<MTLRasterizationRateMap> map = nil;
      if (Is_block(raw_map))
        map = object_of_handle(Field(raw_map, 0), Handle_kind::Rasterization_rate_map);
      descriptor.rasterizationRateMap = map;
      if (descriptor.rasterizationRateMap != map)
        CAMLreturn(result_error_text("Metal changed render-pass rasterization-rate map"));
      CAMLreturn(result_unit());
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_render_pass_depth_attachment(
    value raw_descriptor, value raw_texture, value raw_values) {
  CAMLparam3(raw_descriptor, raw_texture, raw_values);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4RenderPassDescriptor *descriptor = object_of_handle(raw_descriptor, Handle_kind::Render_pass_descriptor4);
      MTLRenderPassDepthAttachmentDescriptor *attachment = nil;
      if (Is_block(raw_texture)) {
        attachment = [MTLRenderPassDepthAttachmentDescriptor new];
        attachment.texture = object_of_handle(Field(raw_texture, 0), Handle_kind::Texture);
        attachment.loadAction = (MTLLoadAction)Long_val(Field(raw_values, 0));
        attachment.storeAction = (MTLStoreAction)Long_val(Field(raw_values, 1));
        attachment.clearDepth = Double_val(Field(raw_values, 2));
      }
      descriptor.depthAttachment = attachment;
      if (descriptor.depthAttachment != attachment)
        CAMLreturn(result_error_text("Metal changed render-pass depth attachment"));
      CAMLreturn(result_unit());
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_render_pass_stencil_attachment(
    value raw_descriptor, value raw_texture, value raw_values) {
  CAMLparam3(raw_descriptor, raw_texture, raw_values);
  if (@available(macOS 26.0, *)) {
    @try {
      MTL4RenderPassDescriptor *descriptor = object_of_handle(raw_descriptor, Handle_kind::Render_pass_descriptor4);
      MTLRenderPassStencilAttachmentDescriptor *attachment = nil;
      if (Is_block(raw_texture)) {
        attachment = [MTLRenderPassStencilAttachmentDescriptor new];
        attachment.texture = object_of_handle(Field(raw_texture, 0), Handle_kind::Texture);
        attachment.loadAction = (MTLLoadAction)Long_val(Field(raw_values, 0));
        attachment.storeAction = (MTLStoreAction)Long_val(Field(raw_values, 1));
        attachment.clearStencil = (uint32_t)Int32_val(Field(raw_values, 2));
      }
      descriptor.stencilAttachment = attachment;
      if (descriptor.stencilAttachment != attachment)
        CAMLreturn(result_error_text("Metal changed render-pass stencil attachment"));
      CAMLreturn(result_unit());
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}
