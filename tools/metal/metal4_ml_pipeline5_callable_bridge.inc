/* MTL4MLPipeline5 isolated immutable state snapshot. copy_optional_string owns
   the UTF-8 snapshot independently of pipeline-state and autorelease lifetime. */
extern "C" CAMLprim value caml_prismel_metal4_ml_pipeline5_label(value raw) {
  CAMLparam1(raw); CAMLlocal2(label, result);
  if (@available(macOS 26.0, *)) {
    @try { id<MTL4MachineLearningPipelineState> pipeline = object_of_handle(
        raw, Handle_kind::Machine_learning_pipeline4);
      label = copy_optional_string(pipeline.label); result = result_ok(label);
      CAMLreturn(result);
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  }
  CAMLreturn(result_error_text("Metal4 ML pipelines require macOS 26"));
}
