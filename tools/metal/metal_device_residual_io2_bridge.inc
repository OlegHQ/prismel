/* Exact legacy MTLDevice IO-handle selectors. These remain public only as
   explicitly named compatibility constructors; returned handles are owned and
   carry authoritative device identity. */
static value prismel_device_legacy_io_result(id<MTLDevice> _Nonnull device,
                                             id<MTLIOFileHandle> _Nullable file,
                                             NSError * _Nullable error) {
  if (file == nil)
    return result_error(error_description(error, @"Metal IO handle creation failed"));
  return prismel_io_handle_with_device(file, Handle_kind::Io_file_handle, device);
}

extern "C" CAMLprim value caml_prismel_metal_device_io_handle_legacy(
    value raw_device, value raw_path) {
  CAMLparam2(raw_device, raw_path);
  if (@available(macOS 13.0, *)) { @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    NSString *path = string_from_ocaml(raw_path); NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    id<MTLIOFileHandle> file =
        [device newIOHandleWithURL:[NSURL fileURLWithPath:path] error:&error];
#pragma clang diagnostic pop
    CAMLreturn(prismel_device_legacy_io_result(device, file, error));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
  CAMLreturn(result_error_text("Metal IO handles require macOS 13"));
}

extern "C" CAMLprim value caml_prismel_metal_device_io_handle_compressed_legacy(
    value raw_device, value raw_path, value raw_method) {
  CAMLparam3(raw_device, raw_path, raw_method);
  if (@available(macOS 13.0, *)) { @try {
    int method = Long_val(raw_method);
    if (method < 0 || method > 4)
      CAMLreturn(result_error_text("unknown IO compression method"));
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    NSString *path = string_from_ocaml(raw_path); NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    id<MTLIOFileHandle> file = [device
        newIOHandleWithURL:[NSURL fileURLWithPath:path]
        compressionMethod:(MTLIOCompressionMethod)method error:&error];
#pragma clang diagnostic pop
    CAMLreturn(prismel_device_legacy_io_result(device, file, error));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
  CAMLreturn(result_error_text("compressed Metal IO handles require macOS 13"));
}
