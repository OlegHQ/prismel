/* Exact MTLDevice asynchronous library selectors, surfaced as bounded
   synchronous native Results so completion blocks never retain OCaml roots. */
extern "C" CAMLprim value caml_prismel_metal_device_async_library_source(
    value raw_device, value raw_source, value raw_options) {
  CAMLparam3(raw_device, raw_source, raw_options); CAMLlocal2(raw, result);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    NSString *source = string_from_ocaml(raw_source);
    MTLCompileOptions *options = Is_none(raw_options) ? nil :
        object_of_handle(Field(raw_options, 0), Handle_kind::Compile_options);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block id<MTLLibrary> library = nil; __block NSError *failure = nil;
    [device newLibraryWithSource:source options:options
        completionHandler:^(id<MTLLibrary> _Nullable value,
                            NSError * _Nullable error) {
          library = value; failure = error; dispatch_semaphore_signal(done);
        }];
    if (!prismel_device_async_wait(done))
      CAMLreturn(result_error_text("library source completion timed out"));
    if (library == nil)
      CAMLreturn(result_error(error_description(failure, @"library compilation failed")));
    raw = allocate_handle(library, Handle_kind::Library);
    result = result_ok(raw); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_async_library_stitched(
    value raw_device, value raw_descriptor) {
  CAMLparam2(raw_device, raw_descriptor); CAMLlocal2(raw, result);
  @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    MTLStitchedLibraryDescriptor *descriptor = object_of_handle(
        raw_descriptor, Handle_kind::Stitched_library_descriptor);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block id<MTLLibrary> library = nil; __block NSError *failure = nil;
    [device newLibraryWithStitchedDescriptor:descriptor
        completionHandler:^(id<MTLLibrary> _Nullable value,
                            NSError * _Nullable error) {
          library = value; failure = error; dispatch_semaphore_signal(done);
        }];
    if (!prismel_device_async_wait(done))
      CAMLreturn(result_error_text("stitched library completion timed out"));
    if (library == nil)
      CAMLreturn(result_error(error_description(failure, @"stitched library creation failed")));
    raw = allocate_handle(library, Handle_kind::Library);
    result = result_ok(raw); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
