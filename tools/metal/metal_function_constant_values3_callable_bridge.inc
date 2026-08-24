/* FunctionConstantValues3 isolated shard. Values are passed as owned OCaml
   byte snapshots. The data type determines exact element width; the complete
   payload and range are validated before the single native mutation. */
static bool prismel_function_constant_width(MTLDataType type, size_t *width) {
  switch (type) {
    case MTLDataTypeFloat: *width = 4; return true;
    case MTLDataTypeFloat2: *width = 8; return true;
    case MTLDataTypeFloat3: *width = 12; return true;
    case MTLDataTypeFloat4: *width = 16; return true;
    case MTLDataTypeHalf: *width = 2; return true;
    case MTLDataTypeHalf2: *width = 4; return true;
    case MTLDataTypeHalf3: *width = 6; return true;
    case MTLDataTypeHalf4: *width = 8; return true;
    case MTLDataTypeInt: case MTLDataTypeUInt: *width = 4; return true;
    case MTLDataTypeInt2: case MTLDataTypeUInt2: *width = 8; return true;
    case MTLDataTypeInt3: case MTLDataTypeUInt3: *width = 12; return true;
    case MTLDataTypeInt4: case MTLDataTypeUInt4: *width = 16; return true;
    case MTLDataTypeShort: case MTLDataTypeUShort: *width = 2; return true;
    case MTLDataTypeShort2: case MTLDataTypeUShort2: *width = 4; return true;
    case MTLDataTypeShort3: case MTLDataTypeUShort3: *width = 6; return true;
    case MTLDataTypeShort4: case MTLDataTypeUShort4: *width = 8; return true;
    case MTLDataTypeChar: case MTLDataTypeUChar: case MTLDataTypeBool:
      *width = 1; return true;
    case MTLDataTypeChar2: case MTLDataTypeUChar2: case MTLDataTypeBool2:
      *width = 2; return true;
    case MTLDataTypeChar3: case MTLDataTypeUChar3: case MTLDataTypeBool3:
      *width = 3; return true;
    case MTLDataTypeChar4: case MTLDataTypeUChar4: case MTLDataTypeBool4:
      *width = 4; return true;
    default: return false;
  }
}

extern "C" CAMLprim value caml_prismel_metal_function_constants3_create(value unit) {
  CAMLparam1(unit); CAMLlocal2(handle, result); (void)unit;
  @try { MTLFunctionConstantValues *values = [MTLFunctionConstantValues new];
    if (values == nil) CAMLreturn(result_error_text("Metal returned no function constants"));
    handle = allocate_handle(values, Handle_kind::Function_constant_values);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_function_constants3_reset(value raw) {
  CAMLparam1(raw); @try { MTLFunctionConstantValues *values = object_of_handle(
      raw, Handle_kind::Function_constant_values);
    [values reset]; CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_function_constants3_set_index(
    value raw, value data_type_raw, value index_raw, value bytes_raw) {
  CAMLparam4(raw, data_type_raw, index_raw, bytes_raw);
  int64_t index = Int64_val(index_raw); MTLDataType type =
    (MTLDataType)Long_val(data_type_raw); size_t width = 0;
  if (index < 0 || !prismel_function_constant_width(type, &width)
      || caml_string_length(bytes_raw) != width)
    CAMLreturn(result_error_text("function constant type/index/value size mismatch"));
  @try { MTLFunctionConstantValues *values = object_of_handle(
      raw, Handle_kind::Function_constant_values);
    [values setConstantValue:String_val(bytes_raw) type:type atIndex:(NSUInteger)index];
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_function_constants3_set_range(
    value raw, value data_type_raw, value range_raw, value bytes_raw) {
  CAMLparam4(raw, data_type_raw, range_raw, bytes_raw);
  int64_t start = Int64_val(Field(range_raw, 0));
  int64_t count = Int64_val(Field(range_raw, 1));
  MTLDataType type = (MTLDataType)Long_val(data_type_raw); size_t width = 0;
  if (start < 0 || count <= 0 || !prismel_function_constant_width(type, &width)
      || (uint64_t)count > SIZE_MAX / width
      || caml_string_length(bytes_raw) != (size_t)count * width)
    CAMLreturn(result_error_text("function constant type/range/cardinality mismatch"));
  @try { MTLFunctionConstantValues *values = object_of_handle(
      raw, Handle_kind::Function_constant_values);
    [values setConstantValues:String_val(bytes_raw) type:type
      withRange:NSMakeRange((NSUInteger)start, (NSUInteger)count)];
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_function_constants3_specialize(
    value library_raw, value values_raw, value name_raw) {
  CAMLparam3(library_raw, values_raw, name_raw); CAMLlocal2(handle, result);
  @try { id<MTLLibrary> library = object_of_handle(library_raw, Handle_kind::Library);
    MTLFunctionConstantValues *values = object_of_handle(
      values_raw, Handle_kind::Function_constant_values);
    NSString *name = [NSString stringWithUTF8String:String_val(name_raw)];
    NSError *error = nil;
    if (name.length == 0) CAMLreturn(result_error_text("function name is empty"));
    id<MTLFunction> function = [library newFunctionWithName:name
      constantValues:values error:&error];
    if (function == nil) CAMLreturn(result_error(error_description(
      error, @"Metal function specialization failed")));
    handle = allocate_handle(function, Handle_kind::Function);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
