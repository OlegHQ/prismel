/* Exact synchronous MTLLibrary constructors from the MTLDevice.h residual.
   Every returned library is owned by its OCaml handle.  Input bytes are copied
   into dispatch-owned storage before the synchronous Metal call. */

static value prismel_device_library_result(id<MTLLibrary> _Nullable library,
                                           NSError * _Nullable error,
                                           NSString * _Nonnull fallback) {
  if (library == nil) return result_error(error_description(error, fallback));
  return result_ok(allocate_handle(library, Handle_kind::Library));
}

extern "C" CAMLprim value caml_prismel_metal_device_default_library(value raw_device) {
  CAMLparam1(raw_device);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    CAMLreturn(prismel_device_library_result(
        [device newDefaultLibrary], nil, @"Metal returned no default library"));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_default_library_bundle(
    value raw_device, value raw_path) {
  CAMLparam2(raw_device, raw_path);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    NSString *path = string_from_ocaml(raw_path);
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    if (bundle == nil) CAMLreturn(result_error_text("invalid library bundle path"));
    NSError *error = nil;
    id<MTLLibrary> library = [device newDefaultLibraryWithBundle:bundle error:&error];
    CAMLreturn(prismel_device_library_result(
        library, error, @"Metal returned no bundle default library"));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_library_data(
    value raw_device, value raw_bytes) {
  CAMLparam2(raw_device, raw_bytes);
  @try {
    mlsize_t length = caml_string_length(raw_bytes);
    void *copy = malloc(length == 0 ? 1 : length);
    if (copy == nullptr) CAMLreturn(result_error_text("unable to copy library data"));
    if (length != 0) memcpy(copy, String_val(raw_bytes), length);
    dispatch_data_t data = dispatch_data_create(
        copy, length, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
        ^{ free(copy); });
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithData:data error:&error];
    CAMLreturn(prismel_device_library_result(
        library, error, @"Metal rejected library data"));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_library_file(
    value raw_device, value raw_path) {
  CAMLparam2(raw_device, raw_path);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    id<MTLLibrary> library = [device newLibraryWithFile:string_from_ocaml(raw_path)
                                                  error:&error];
#pragma clang diagnostic pop
    CAMLreturn(prismel_device_library_result(
        library, error, @"Metal rejected library file"));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_library_stitched(
    value raw_device, value raw_descriptor) {
  CAMLparam2(raw_device, raw_descriptor);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    MTLStitchedLibraryDescriptor *descriptor = object_of_handle(
        raw_descriptor, Handle_kind::Stitched_library_descriptor);
    NSError *error = nil;
    id<MTLLibrary> library =
        [device newLibraryWithStitchedDescriptor:descriptor error:&error];
    CAMLreturn(prismel_device_library_result(
        library, error, @"Metal rejected stitched library descriptor"));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
