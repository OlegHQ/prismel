extern "C" CAMLprim value caml_prismel_metal_generated_buffer_remove_all_debug_markers(value raw) {
  CAMLparam1(raw); @autoreleasepool { @try {
    id<MTLBuffer> object=object_of_handle(raw,Handle_kind::Buffer);
    [object removeAllDebugMarkers]; CAMLreturn(result_unit());
  } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
}
extern "C" CAMLprim value caml_prismel_metal_generated_device_sparse_tile_size(value raw,value raw_type,value raw_format,value raw_samples) {
  CAMLparam4(raw,raw_type,raw_format,raw_samples); CAMLlocal3(tuple,item,result); @autoreleasepool { @try {
    id<MTLDevice> object=object_of_handle(raw,Handle_kind::Device);
    MTLSize size=[object sparseTileSizeWithTextureType:(MTLTextureType)Int64_val(raw_type) pixelFormat:(MTLPixelFormat)Int64_val(raw_format) sampleCount:(NSUInteger)Int64_val(raw_samples)];
    tuple=caml_alloc_tuple(3); item=caml_copy_int64(size.width); Store_field(tuple,0,item);
    item=caml_copy_int64(size.height); Store_field(tuple,1,item); item=caml_copy_int64(size.depth); Store_field(tuple,2,item);
    result=result_ok(tuple); CAMLreturn(result);
  } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
}
extern "C" CAMLprim value caml_prismel_metal_generated_heap_resource_options(value raw) {
  CAMLparam1(raw); CAMLlocal2(copied,result); @autoreleasepool { @try {
    id<MTLHeap> object=object_of_handle(raw,Handle_kind::Heap); copied=caml_copy_int64(object.resourceOptions);
    result=result_ok(copied); CAMLreturn(result);
  } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
}
extern "C" CAMLprim value caml_prismel_metal_generated_resource_allocated_size(value raw) {
  CAMLparam1(raw); CAMLlocal2(copied,result); @autoreleasepool { @try {
    id<MTLResource> object=resource_of_handle(raw); copied=caml_copy_int64(object.allocatedSize);
    result=result_ok(copied); CAMLreturn(result);
  } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
}
extern "C" CAMLprim value caml_prismel_metal_generated_resource_options(value raw) {
  CAMLparam1(raw); CAMLlocal2(copied,result); @autoreleasepool { @try {
    id<MTLResource> object=resource_of_handle(raw); copied=caml_copy_int64(object.resourceOptions);
    result=result_ok(copied); CAMLreturn(result);
  } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
}
extern "C" CAMLprim value caml_prismel_metal_generated_texture_framebuffer_only(value raw) {
  CAMLparam1(raw); @autoreleasepool { @try {
    id<MTLTexture> object=object_of_handle(raw,Handle_kind::Texture);
    CAMLreturn(result_ok(Val_bool(object.framebufferOnly)));
  } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
}
