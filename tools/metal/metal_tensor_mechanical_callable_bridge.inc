/* Exact MTLTensor.h mechanical18 native closure. */
static_assert(std::is_same_v<decltype(((id<MTLTensor>)nil).bufferOffset), NSUInteger>);
static_assert(std::is_same_v<decltype(((id<MTLTensor>)nil).dataType), MTLTensorDataType>);
static_assert(std::is_same_v<decltype(((id<MTLTensor>)nil).gpuResourceID), MTLResourceID>);
static_assert(std::is_same_v<decltype(((id<MTLTensor>)nil).usage), MTLTensorUsage>);
static_assert(std::is_same_v<decltype(((MTLTensorDescriptor *)nil).cpuCacheMode), MTLCPUCacheMode>);
static_assert(std::is_same_v<decltype(((MTLTensorDescriptor *)nil).hazardTrackingMode), MTLHazardTrackingMode>);
static_assert(std::is_same_v<decltype(((MTLTensorDescriptor *)nil).resourceOptions), MTLResourceOptions>);
static_assert(std::is_same_v<decltype(((MTLTensorDescriptor *)nil).storageMode), MTLStorageMode>);
static_assert(std::is_same_v<decltype(((MTLTensorExtents *)nil).rank), NSUInteger>);
#define PRISMEL_TENSOR_GET(NAME, KIND, TYPE, EXPR)                              \
  extern "C" CAMLprim value NAME(value raw) {                                  \
    CAMLparam1(raw); CAMLlocal2(v, result);                                     \
    @try { TYPE object = object_of_handle(raw, KIND);                           \
      v = caml_copy_int64(static_cast<int64_t>(EXPR)); result = result_ok(v);   \
      CAMLreturn(result);                                                       \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }
#define PRISMEL_TENSOR_SET(NAME, EXPR)                                         \
  extern "C" CAMLprim value NAME(value raw, value input) {                     \
    CAMLparam2(raw, input);                                                     \
    @try { MTLTensorDescriptor *object = object_of_handle(raw, Handle_kind::Tensor_descriptor); \
      EXPR; CAMLreturn(result_unit());                                          \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }

PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_buffer_offset, Handle_kind::Tensor, id<MTLTensor>, object.bufferOffset)
PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_data_type, Handle_kind::Tensor, id<MTLTensor>, object.dataType)
PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_gpu_resource_id, Handle_kind::Tensor, id<MTLTensor>, object.gpuResourceID._impl)
PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_usage, Handle_kind::Tensor, id<MTLTensor>, object.usage)
PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_descriptor_cpu_cache_mode, Handle_kind::Tensor_descriptor, MTLTensorDescriptor *, object.cpuCacheMode)
PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_descriptor_data_type, Handle_kind::Tensor_descriptor, MTLTensorDescriptor *, object.dataType)
PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_descriptor_hazard_tracking_mode, Handle_kind::Tensor_descriptor, MTLTensorDescriptor *, object.hazardTrackingMode)
PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_descriptor_resource_options, Handle_kind::Tensor_descriptor, MTLTensorDescriptor *, object.resourceOptions)
PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_descriptor_storage_mode, Handle_kind::Tensor_descriptor, MTLTensorDescriptor *, object.storageMode)
PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_descriptor_usage, Handle_kind::Tensor_descriptor, MTLTensorDescriptor *, object.usage)
PRISMEL_TENSOR_SET(caml_prismel_metal_tensor_descriptor_set_cpu_cache_mode, object.cpuCacheMode = static_cast<MTLCPUCacheMode>(Int64_val(input)))
PRISMEL_TENSOR_SET(caml_prismel_metal_tensor_descriptor_set_data_type, object.dataType = static_cast<MTLTensorDataType>(Int64_val(input)))
PRISMEL_TENSOR_SET(caml_prismel_metal_tensor_descriptor_set_hazard_tracking_mode, object.hazardTrackingMode = static_cast<MTLHazardTrackingMode>(Int64_val(input)))
PRISMEL_TENSOR_SET(caml_prismel_metal_tensor_descriptor_set_resource_options, object.resourceOptions = static_cast<MTLResourceOptions>(Int64_val(input)))
PRISMEL_TENSOR_SET(caml_prismel_metal_tensor_descriptor_set_storage_mode, object.storageMode = static_cast<MTLStorageMode>(Int64_val(input)))
PRISMEL_TENSOR_SET(caml_prismel_metal_tensor_descriptor_set_usage, object.usage = static_cast<MTLTensorUsage>(Int64_val(input)))

extern "C" CAMLprim value caml_prismel_metal_tensor_extents_extent(value raw, value index) {
  CAMLparam2(raw, index); CAMLlocal2(v, result);
  @try { MTLTensorExtents *object = object_of_handle(raw, Handle_kind::Tensor_extents);
    v = caml_copy_int64(static_cast<int64_t>([object extentAtDimensionIndex:static_cast<NSUInteger>(Int64_val(index))]));
    result = result_ok(v); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
PRISMEL_TENSOR_GET(caml_prismel_metal_tensor_extents_rank, Handle_kind::Tensor_extents, MTLTensorExtents *, object.rank)

#undef PRISMEL_TENSOR_GET
#undef PRISMEL_TENSOR_SET
