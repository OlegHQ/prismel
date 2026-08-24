/* RenderPipeline93 pipeline-state function lookup closure (exact 3 IDs).
   Results are nullable and become independently owned Function_handle values.
   The safe layer validates liveness, same-device identity, one exact stage bit,
   UTF-8/NUL-free names, and retains the source function through this call. */

static bool prismel_render93_single_stage(int64_t stage) {
  return stage == (int64_t)MTLRenderStageVertex ||
         stage == (int64_t)MTLRenderStageFragment ||
         stage == (int64_t)MTLRenderStageTile ||
         stage == (int64_t)MTLRenderStageObject ||
         stage == (int64_t)MTLRenderStageMesh;
}

static value prismel_render93_function_handle_result(
    id<MTLFunctionHandle> _Nullable function) {
  CAMLparam0();
  CAMLlocal2(handle,option);
  if (function == nil) CAMLreturn(Val_none);
  handle = allocate_handle(function,Handle_kind::Function_handle);
  option = caml_alloc(1,0);
  Store_field(option,0,handle);
  CAMLreturn(option);
}

extern "C" CAMLprim value
caml_prismel_metal_render93_function_handle(value pipeline_raw,
                                             value operation_raw,
                                             value argument_raw,
                                             value stage_raw) {
  CAMLparam4(pipeline_raw,operation_raw,argument_raw,stage_raw);
  CAMLlocal2(option,result);
  int64_t stage = Int64_val(stage_raw);
  if (!prismel_render93_single_stage(stage))
    CAMLreturn(result_error_text("render pipeline function stage must contain one exact stage"));
  @try {
    id<MTLRenderPipelineState> pipeline =
        object_of_handle(pipeline_raw,Handle_kind::Render_pipeline);
    id<MTLFunctionHandle> function = nil;
    switch (Long_val(operation_raw)) {
      case 0: {
        id<MTLFunction> source =
            object_of_handle(argument_raw,Handle_kind::Function);
        function = [pipeline functionHandleWithFunction:source
                                                  stage:(MTLRenderStages)stage];
        break;
      }
      case 1:
        if (@available(macOS 26.0,*)) {
          id<MTL4BinaryFunction> source =
              object_of_handle(argument_raw,Handle_kind::Binary_function);
          function = [pipeline functionHandleWithBinaryFunction:source
                                                           stage:(MTLRenderStages)stage];
        } else {
          CAMLreturn(result_error_text(
              "render pipeline binary-function lookup requires macOS 26"));
        }
        break;
      case 2:
        if (@available(macOS 26.0,*)) {
          NSString *name = string_from_ocaml(argument_raw);
          if (name == nil)
            CAMLreturn(result_error_text("render pipeline function name is not valid UTF-8"));
          function = [pipeline functionHandleWithName:name
                                                stage:(MTLRenderStages)stage];
        } else {
          CAMLreturn(result_error_text(
              "render pipeline named-function lookup requires macOS 26"));
        }
        break;
      default:
        CAMLreturn(result_error_text("unknown render pipeline function lookup"));
    }
    option = prismel_render93_function_handle_result(function);
    result = result_ok(option);
    CAMLreturn(result);
  } @catch(NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}
