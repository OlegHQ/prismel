extern "C" CAMLprim value caml_prismel_metal_compute_pipeline11_named(
    value pipeline_raw, value name_raw) {
  CAMLparam2(pipeline_raw, name_raw); CAMLlocal3(option, handle, result);
  @try {
    id<MTLComputePipelineState> pipeline = object_of_handle(
      pipeline_raw, Handle_kind::Compute_pipeline);
    id<MTLFunctionHandle> function = [pipeline functionHandleWithName:string_from_ocaml(name_raw)];
    if (function == nil) option = Val_none;
    else { handle = allocate_handle(function, Handle_kind::Function_handle);
      option = caml_alloc(1, 0); Store_field(option, 0, handle); }
    result = result_ok(option); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_compute_pipeline11_relink(
    value pipeline_raw, value binary_raw) {
  CAMLparam2(pipeline_raw, binary_raw); CAMLlocal2(handle, result);
  @try {
    id<MTLComputePipelineState> pipeline = object_of_handle(
      pipeline_raw, Handle_kind::Compute_pipeline);
    NSError *error = nil; id<MTLComputePipelineState> relinked = nil;
    if (Bool_val(binary_raw)) {
      if (@available(macOS 26.0, *))
        relinked = [pipeline newComputePipelineStateWithBinaryFunctions:@[] error:&error];
      else CAMLreturn(result_error_text("MTL4 binary relinking requires macOS 26"));
    } else
      relinked = [pipeline newComputePipelineStateWithAdditionalBinaryFunctions:@[] error:&error];
    if (relinked == nil) CAMLreturn(result_error(error_description(error,
      @"compute pipeline relink is unsupported")));
    handle = allocate_handle(relinked, Handle_kind::Compute_pipeline);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
