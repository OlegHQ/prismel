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
static bool prismel_tensor_slice_args(id<MTLTensor> tensor, value raw_strides, MTLTensorExtents *origin, MTLTensorExtents *dimensions, std::vector<NSInteger> &strides) {
  strides=prismel_tensor_int_array(raw_strides); NSUInteger rank=tensor.dimensions.rank;
  return rank>0 && strides.size()==rank && origin.rank==rank && dimensions.rank==rank;
}
extern "C" CAMLprim value caml_prismel_metal_tensor_get_bytes(value raw, value bytes, value raw_strides, value raw_origin, value raw_dimensions) {
  CAMLparam5(raw,bytes,raw_strides,raw_origin,raw_dimensions); @try { id<MTLTensor> tensor=object_of_handle(raw,Handle_kind::Tensor); MTLTensorExtents *origin=object_of_handle(raw_origin,Handle_kind::Tensor_extents),*dimensions=object_of_handle(raw_dimensions,Handle_kind::Tensor_extents); std::vector<NSInteger> strides;
    if(caml_string_length(bytes)==0||!prismel_tensor_slice_args(tensor,raw_strides,origin,dimensions,strides)) CAMLreturn(result_error_text("tensor byte slice rank/length is invalid"));
    [tensor getBytes:Bytes_val(bytes) strides:strides.data() fromSliceOrigin:origin sliceDimensions:dimensions]; CAMLreturn(result_unit());
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));} }
extern "C" CAMLprim value caml_prismel_metal_tensor_get_bytes_bytecode(value *argv,int argn){(void)argn;return caml_prismel_metal_tensor_get_bytes(argv[0],argv[1],argv[2],argv[3],argv[4]);}
extern "C" CAMLprim value caml_prismel_metal_tensor_replace_bytes(value raw, value bytes, value raw_strides, value raw_origin, value raw_dimensions) {
  CAMLparam5(raw,bytes,raw_strides,raw_origin,raw_dimensions); @try { id<MTLTensor> tensor=object_of_handle(raw,Handle_kind::Tensor); MTLTensorExtents *origin=object_of_handle(raw_origin,Handle_kind::Tensor_extents),*dimensions=object_of_handle(raw_dimensions,Handle_kind::Tensor_extents); std::vector<NSInteger> strides;
    if(caml_string_length(bytes)==0||!prismel_tensor_slice_args(tensor,raw_strides,origin,dimensions,strides)) CAMLreturn(result_error_text("tensor byte slice rank/length is invalid"));
    [tensor replaceSliceOrigin:origin sliceDimensions:dimensions withBytes:Bytes_val(bytes) strides:strides.data()]; CAMLreturn(result_unit());
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));} }
extern "C" CAMLprim value caml_prismel_metal_tensor_replace_bytes_bytecode(value *argv,int argn){(void)argn;return caml_prismel_metal_tensor_replace_bytes(argv[0],argv[1],argv[2],argv[3],argv[4]);}
