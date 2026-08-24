/* Constructor enabler for the StageInputOutput7 ownership graph.  The SDK
   factory owns the attribute/layout arrays; OCaml receives only the parent
   handle here and materializes retained child handles through the existing
   stage_io_children trampoline. */
extern "C" CAMLprim value
caml_prismel_metal_stage_io_create(value unit_raw)
{
  CAMLparam1(unit_raw);
  CAMLlocal2(handle, result);
  (void)unit_raw;
  @try {
    MTLStageInputOutputDescriptor *descriptor =
        [MTLStageInputOutputDescriptor stageInputOutputDescriptor];
    if (descriptor == nil)
      CAMLreturn(result_error_text("Metal returned no stage input/output descriptor"));
    handle = allocate_handle(descriptor, Handle_kind::Shader_stage_descriptor);
    result = result_ok(handle);
    CAMLreturn(result);
  } @catch (NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}
