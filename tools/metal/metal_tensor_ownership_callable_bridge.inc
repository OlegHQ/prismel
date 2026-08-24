/* Handwritten Tensor ownership15 bridge; returned objects receive exact kinds. */
static std::vector<NSInteger> prismel_tensor_int_array(value raw) {
  const mlsize_t length = Wosize_val(raw); std::vector<NSInteger> values(length);
  for (mlsize_t i = 0; i < length; ++i) values[i] = static_cast<NSInteger>(Int64_val(Field(raw, i)));
  return values;
}
extern "C" CAMLprim value caml_prismel_metal_tensor_extents_create(value raw_values) {
  CAMLparam1(raw_values); CAMLlocal2(raw, result); @try {
    auto values = prismel_tensor_int_array(raw_values);
    if (values.empty()) CAMLreturn(result_error_text("tensor extents rank must be positive"));
    MTLTensorExtents *object = [[MTLTensorExtents alloc] initWithRank:values.size() values:values.data()];
    raw = allocate_handle(object, Handle_kind::Tensor_extents); result = result_ok(raw); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_tensor_descriptor_create(value unit) {
  CAMLparam1(unit); CAMLlocal2(raw, result); @try { MTLTensorDescriptor *object = [MTLTensorDescriptor new];
    raw = allocate_handle(object, Handle_kind::Tensor_descriptor); result = result_ok(raw); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
#define PRISMEL_TENSOR_OBJECT_GET(NAME, KIND, TYPE, EXPR, RESULT_KIND)          \
extern "C" CAMLprim value NAME(value raw) { CAMLparam1(raw); CAMLlocal3(out, option, result); @try { \
  TYPE object = object_of_handle(raw, KIND); id child = (EXPR); if (child == nil) CAMLreturn(result_ok(Val_int(0))); \
  out = allocate_handle(child, RESULT_KIND); option = caml_alloc(1, 0); Store_field(option, 0, out); result = result_ok(option); CAMLreturn(result); \
} @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
PRISMEL_TENSOR_OBJECT_GET(caml_prismel_metal_tensor_buffer, Handle_kind::Tensor, id<MTLTensor>, object.buffer, Handle_kind::Buffer)
PRISMEL_TENSOR_OBJECT_GET(caml_prismel_metal_tensor_dimensions, Handle_kind::Tensor, id<MTLTensor>, object.dimensions, Handle_kind::Tensor_extents)
PRISMEL_TENSOR_OBJECT_GET(caml_prismel_metal_tensor_strides, Handle_kind::Tensor, id<MTLTensor>, object.strides, Handle_kind::Tensor_extents)
PRISMEL_TENSOR_OBJECT_GET(caml_prismel_metal_tensor_descriptor_dimensions, Handle_kind::Tensor_descriptor, MTLTensorDescriptor *, object.dimensions, Handle_kind::Tensor_extents)
PRISMEL_TENSOR_OBJECT_GET(caml_prismel_metal_tensor_descriptor_strides, Handle_kind::Tensor_descriptor, MTLTensorDescriptor *, object.strides, Handle_kind::Tensor_extents)
#undef PRISMEL_TENSOR_OBJECT_GET
extern "C" CAMLprim value caml_prismel_metal_tensor_descriptor_set_dimensions(value raw, value child) { CAMLparam2(raw, child); @try {
  MTLTensorDescriptor *object=object_of_handle(raw,Handle_kind::Tensor_descriptor); object.dimensions=object_of_handle(child,Handle_kind::Tensor_extents); CAMLreturn(result_unit());
} @catch(NSException *exception){CAMLreturn(result_error(exception.reason));} }
extern "C" CAMLprim value caml_prismel_metal_tensor_descriptor_set_strides(value raw, value child) { CAMLparam2(raw, child); @try {
  MTLTensorDescriptor *object=object_of_handle(raw,Handle_kind::Tensor_descriptor); object.strides=object_of_handle(child,Handle_kind::Tensor_extents); CAMLreturn(result_unit());
} @catch(NSException *exception){CAMLreturn(result_error(exception.reason));} }
static bool prismel_tensor_slice_args(id<MTLTensor> tensor, MTLTensorExtents *strides, MTLTensorExtents *origin, MTLTensorExtents *dimensions) {
  NSUInteger rank=tensor.dimensions.rank;
  return rank>0 && strides.rank==rank && origin.rank==rank && dimensions.rank==rank;
}
extern "C" CAMLprim value caml_prismel_metal_tensor_get_bytes(value raw, value bytes, value raw_strides, value raw_origin, value raw_dimensions) {
  CAMLparam5(raw,bytes,raw_strides,raw_origin,raw_dimensions); @try { id<MTLTensor> tensor=object_of_handle(raw,Handle_kind::Tensor); MTLTensorExtents *strides=object_of_handle(raw_strides,Handle_kind::Tensor_extents),*origin=object_of_handle(raw_origin,Handle_kind::Tensor_extents),*dimensions=object_of_handle(raw_dimensions,Handle_kind::Tensor_extents);
    if(caml_string_length(bytes)==0||!prismel_tensor_slice_args(tensor,strides,origin,dimensions)) CAMLreturn(result_error_text("tensor byte slice rank/length is invalid"));
    [tensor getBytes:Bytes_val(bytes) strides:strides fromSliceOrigin:origin sliceDimensions:dimensions]; CAMLreturn(result_unit());
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));} }
extern "C" CAMLprim value caml_prismel_metal_tensor_get_bytes_bytecode(value *argv,int argn){(void)argn;return caml_prismel_metal_tensor_get_bytes(argv[0],argv[1],argv[2],argv[3],argv[4]);}
extern "C" CAMLprim value caml_prismel_metal_tensor_replace_bytes(value raw, value bytes, value raw_strides, value raw_origin, value raw_dimensions) {
  CAMLparam5(raw,bytes,raw_strides,raw_origin,raw_dimensions); @try { id<MTLTensor> tensor=object_of_handle(raw,Handle_kind::Tensor); MTLTensorExtents *strides=object_of_handle(raw_strides,Handle_kind::Tensor_extents),*origin=object_of_handle(raw_origin,Handle_kind::Tensor_extents),*dimensions=object_of_handle(raw_dimensions,Handle_kind::Tensor_extents);
    if(caml_string_length(bytes)==0||!prismel_tensor_slice_args(tensor,strides,origin,dimensions)) CAMLreturn(result_error_text("tensor byte slice rank/length is invalid"));
    [tensor replaceSliceOrigin:origin sliceDimensions:dimensions withBytes:Bytes_val(bytes) strides:strides]; CAMLreturn(result_unit());
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));} }
extern "C" CAMLprim value caml_prismel_metal_tensor_replace_bytes_bytecode(value *argv,int argn){(void)argn;return caml_prismel_metal_tensor_replace_bytes(argv[0],argv[1],argv[2],argv[3],argv[4]);}
static MTLTensorDescriptor* prismel_device_tensor_descriptor(MTLTensorDescriptor*x){MTLTensorDescriptor*y=[MTLTensorDescriptor new];y.dimensions=x.dimensions;y.dataType=x.dataType;y.storageMode=x.storageMode;y.cpuCacheMode=x.cpuCacheMode;y.hazardTrackingMode=x.hazardTrackingMode;y.resourceOptions=x.resourceOptions;y.usage=x.usage;return y;}
extern "C" CAMLprim value caml_prismel_metal_tensor_device_create(value device,value descriptor){CAMLparam2(device,descriptor);CAMLlocal2(handle,result);@try{if(@available(macOS 26.0,*)){id<MTLDevice>d=object_of_handle(device,Handle_kind::Device);MTLTensorDescriptor*x=prismel_device_tensor_descriptor(object_of_handle(descriptor,Handle_kind::Tensor_descriptor));NSError*error=nil;id<MTLTensor>tensor=[d newTensorWithDescriptor:x error:&error];if(!tensor)CAMLreturn(result_error(error.localizedDescription?:@"newTensor returned nil"));handle=allocate_handle(tensor,Handle_kind::Tensor);result=result_ok(handle);CAMLreturn(result);}CAMLreturn(result_error_text("device tensors require macOS 26"));}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_tensor_device_size_align(value device,value descriptor){CAMLparam2(device,descriptor);CAMLlocal2(pair,result);@try{if(@available(macOS 26.0,*)){id<MTLDevice>d=object_of_handle(device,Handle_kind::Device);MTLTensorDescriptor*x=prismel_device_tensor_descriptor(object_of_handle(descriptor,Handle_kind::Tensor_descriptor));MTLSizeAndAlign a=[d tensorSizeAndAlignWithDescriptor:x];pair=caml_alloc_tuple(2);Store_field(pair,0,caml_copy_int64(a.size));Store_field(pair,1,caml_copy_int64(a.align));result=result_ok(pair);CAMLreturn(result);}CAMLreturn(result_error_text("tensor size/alignment requires macOS 26"));}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
