/* Remaining MTLCommandEncoder ownership/effect selectors.  MTLStages' nine
   values are already promoted.  Debug depth is threaded through the safe API,
   so a pop cannot silently unbalance the native stack. */
static bool prismel_command_encoder_stage_mask(NSUInteger stages) {
  if (stages == MTLStageAll) return true;
  const NSUInteger known = MTLStageVertex | MTLStageFragment | MTLStageTile |
    MTLStageObject | MTLStageMesh | MTLStageResourceState | MTLStageDispatch |
    MTLStageBlit | MTLStageAccelerationStructure | MTLStageMachineLearning;
  return stages != 0 && (stages & ~known) == 0;
}

extern "C" CAMLprim value caml_prismel_metal_command_encoder_barrier(
    value raw, value after_raw, value before_raw) {
  CAMLparam3(raw, after_raw, before_raw);
  NSUInteger after = (NSUInteger)Int64_val(after_raw);
  NSUInteger before = (NSUInteger)Int64_val(before_raw);
  if (!prismel_command_encoder_stage_mask(after) ||
      !prismel_command_encoder_stage_mask(before))
    CAMLreturn(result_error_text("command encoder barrier stages must be nonempty known masks"));
  @try {
    id<MTLCommandEncoder> encoder = command_encoder_of_handle(raw);
    [encoder barrierAfterQueueStages:after beforeStages:before];
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_command_encoder_device_id(value raw) {
  CAMLparam1(raw); CAMLlocal2(identifier, result); @try {
    id<MTLCommandEncoder> encoder = command_encoder_of_handle(raw);
    identifier = caml_copy_int64(encoder.device.registryID);
    result = result_ok(identifier); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_command_encoder_label(value raw) {
  CAMLparam1(raw); CAMLlocal2(label, result); @try {
    label = copy_optional_string(command_encoder_of_handle(raw).label);
    result = result_ok(label); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_command_encoder_set_label(
    value raw, value option) {
  CAMLparam2(raw, option); @try {
    NSString *label = Is_none(option) ? nil : string_from_ocaml(Field(option, 0));
    if (!Is_none(option) && label == nil)
      CAMLreturn(result_error_text("command encoder label is not valid UTF-8"));
    command_encoder_of_handle(raw).label = label;
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

/* operation: 0 signpost, 1 push, 2 pop.  Returns the new checked depth. */
extern "C" CAMLprim value caml_prismel_metal_command_encoder_debug(
    value raw, value operation_raw, value text, value depth_raw) {
  CAMLparam4(raw, operation_raw, text, depth_raw); CAMLlocal2(depth_value, result);
  int operation = Long_val(operation_raw); int64_t depth = Int64_val(depth_raw);
  if (depth < 0 || (operation == 2 && depth == 0))
    CAMLreturn(result_error_text("unbalanced command encoder debug group"));
  @try {
    id<MTLCommandEncoder> encoder = command_encoder_of_handle(raw);
    if (operation == 2) { [encoder popDebugGroup]; --depth; }
    else {
      if (Is_none(text)) CAMLreturn(result_error_text("debug text is required"));
      NSString *label = string_from_ocaml(Field(text, 0));
      if (label == nil) CAMLreturn(result_error_text("debug text is not valid UTF-8"));
      if (operation == 0) [encoder insertDebugSignpost:label];
      else if (operation == 1) { [encoder pushDebugGroup:label]; ++depth; }
      else CAMLreturn(result_error_text("unknown command encoder debug operation"));
    }
    depth_value = caml_copy_int64(depth); result = result_ok(depth_value);
    CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
