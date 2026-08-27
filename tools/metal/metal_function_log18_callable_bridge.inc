/* FunctionLog18 ownership shard.  The scalar type/line/column selectors live
   in the mechanical command-support shard.  These wrappers preserve nullable
   protocol edges with exact handle kinds and copy NSString/NSURL text before
   the command-completion callback which supplied the log is allowed to end. */
extern "C" CAMLprim value caml_prismel_metal_command_function_logs(value raw) {
  CAMLparam1(raw); CAMLlocal3(array, handle, result); @try {
    id<MTLCommandBuffer> command = object_of_handle(raw, Handle_kind::Command_buffer);
    NSMutableArray<id<MTLFunctionLog>> *logs = [NSMutableArray array];
    for (id candidate in command.logs) {
      if (![candidate respondsToSelector:@selector(type)] ||
          ![candidate respondsToSelector:@selector(debugLocation)] ||
          ![candidate respondsToSelector:@selector(encoderLabel)] ||
          ![candidate respondsToSelector:@selector(function)])
        CAMLreturn(result_error_text("Metal log container yielded an incompatible diagnostic"));
      id<MTLFunctionLog> log = candidate;
      [logs addObject:log];
    }
    array = caml_alloc(logs.count, 0);
    for (NSUInteger index = 0; index < logs.count; ++index) {
      handle = allocate_handle(logs[index], Handle_kind::Function_log);
      Store_field(array, index, handle);
    }
    result = result_ok(array); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_function_log_location(value raw) {
  CAMLparam1(raw); CAMLlocal3(option, handle, result); @try {
    id<MTLFunctionLog> log = object_of_handle(raw, Handle_kind::Function_log);
    id<MTLFunctionLogDebugLocation> location = log.debugLocation;
    if (location == nil) option = Val_none;
    else { handle = allocate_handle(location, Handle_kind::Function_log_location);
      option = caml_alloc(1, 0); Store_field(option, 0, handle); }
    result = result_ok(option); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_function_log_encoder_label(value raw) {
  CAMLparam1(raw); CAMLlocal2(snapshot, result); @try {
    id<MTLFunctionLog> log = object_of_handle(raw, Handle_kind::Function_log);
    snapshot = copy_optional_string(log.encoderLabel);
    result = result_ok(snapshot); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_function_log_function(value raw) {
  CAMLparam1(raw); CAMLlocal3(option, handle, result); @try {
    id<MTLFunctionLog> log = object_of_handle(raw, Handle_kind::Function_log);
    id<MTLFunction> function = log.function;
    if (function == nil) option = Val_none;
    else { handle = allocate_handle(function, Handle_kind::Function);
      option = caml_alloc(1, 0); Store_field(option, 0, handle); }
    result = result_ok(option); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_function_log_location_url(value raw) {
  CAMLparam1(raw); CAMLlocal2(snapshot, result); @try {
    id<MTLFunctionLogDebugLocation> location =
      object_of_handle(raw, Handle_kind::Function_log_location);
    /* absoluteString is copied while URL and callback-owned log are alive. */
    snapshot = copy_optional_string(location.URL.absoluteString);
    result = result_ok(snapshot); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_function_log_location_function_name(value raw) {
  CAMLparam1(raw); CAMLlocal2(snapshot, result); @try {
    id<MTLFunctionLogDebugLocation> location =
      object_of_handle(raw, Handle_kind::Function_log_location);
    snapshot = copy_optional_string(location.functionName);
    result = result_ok(snapshot); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
