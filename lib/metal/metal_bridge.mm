#define CAML_NAME_SPACE

#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <mutex>

#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/threads.h>

#include <mach/mach.h>

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

namespace {

enum class Handle_kind : std::uint32_t {
  Device = 1,
  Buffer,
  Library,
  Function,
  Compute_pipeline,
  Command_queue,
  Command_buffer,
  Compute_encoder,
};

struct Handle {
  void *object;
  std::uint64_t generation;
  Handle_kind kind;
};

constexpr std::size_t release_capacity = 65'536;
std::array<void *, release_capacity> release_queue{};
std::size_t release_head = 0;
std::size_t release_count = 0;
std::mutex release_mutex;
std::mutex handle_mutex;
std::atomic<std::uint64_t> next_generation{1};
std::atomic<std::uint64_t> dropped_releases{0};
std::atomic<std::uint64_t> live_handle_count{0};
std::atomic<std::uint64_t> total_created_count{0};
std::atomic<std::uint64_t> total_released_count{0};

Handle *handle_of_value(value raw) {
  return static_cast<Handle *>(Data_custom_val(raw));
}

void *take_pointer(Handle *handle) {
  std::lock_guard<std::mutex> lock(handle_mutex);
  void *pointer = handle->object;
  handle->object = nullptr;
  return pointer;
}

void enqueue_release(void *pointer) {
  if (pointer == nullptr) {
    return;
  }
  std::lock_guard<std::mutex> lock(release_mutex);
  if (release_count == release_capacity) {
    dropped_releases.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  const std::size_t tail = (release_head + release_count) % release_capacity;
  release_queue[tail] = pointer;
  ++release_count;
}

void finalize_handle(value raw) {
  enqueue_release(take_pointer(handle_of_value(raw)));
}

struct custom_operations handle_operations = {
    const_cast<char *>("prismel.metal.handle.v1"),
    finalize_handle,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default,
};

value allocate_handle(id object, Handle_kind kind) {
  CAMLparam0();
  CAMLlocal1(raw);
  if (object == nil) {
    caml_failwith("attempted to allocate a nil Metal handle");
  }
  raw = caml_alloc_custom_mem(&handle_operations, sizeof(Handle), sizeof(Handle));
  auto *handle = handle_of_value(raw);
  handle->object = (__bridge_retained void *)object;
  handle->generation = next_generation.fetch_add(1, std::memory_order_relaxed);
  handle->kind = kind;
  live_handle_count.fetch_add(1, std::memory_order_relaxed);
  total_created_count.fetch_add(1, std::memory_order_relaxed);
  CAMLreturn(raw);
}

id object_of_handle(value raw, Handle_kind expected) {
  auto *handle = handle_of_value(raw);
  std::lock_guard<std::mutex> lock(handle_mutex);
  if (handle->kind != expected) {
    caml_failwith("Metal custom handle kind mismatch");
  }
  if (handle->object == nullptr) {
    caml_failwith("Metal custom handle is destroyed");
  }
  return (__bridge id)handle->object;
}

void release_pointer(void *pointer) {
  if (pointer == nullptr) {
    return;
  }
  @autoreleasepool {
    id object = (__bridge_transfer id)pointer;
    (void)object;
  }
  live_handle_count.fetch_sub(1, std::memory_order_relaxed);
  total_released_count.fetch_add(1, std::memory_order_relaxed);
}

value result_ok(value payload) {
  CAMLparam1(payload);
  CAMLlocal1(result);
  result = caml_alloc(1, 0);
  Store_field(result, 0, payload);
  CAMLreturn(result);
}

value result_error_text(const char *message) {
  CAMLparam0();
  CAMLlocal2(result, text);
  text = caml_copy_string(message == nullptr ? "unknown Metal error" : message);
  result = caml_alloc(1, 1);
  Store_field(result, 0, text);
  CAMLreturn(result);
}

value result_error(NSString *message) {
  const char *utf8 = message == nil ? nullptr : message.UTF8String;
  return result_error_text(utf8);
}

NSString *error_description(NSError *error, NSString *fallback) {
  if (error == nil) {
    return fallback;
  }
  return [NSString
      stringWithFormat:@"%@ (domain=%@ code=%ld)",
                       error.localizedDescription ?: error.description,
                       error.domain, static_cast<long>(error.code)];
}

NSString *string_from_ocaml(value text) {
  return [[NSString alloc]
      initWithBytes:String_val(text)
             length:caml_string_length(text)
           encoding:NSUTF8StringEncoding];
}

value copy_optional_string(NSString *text) {
  CAMLparam0();
  CAMLlocal2(option, contents);
  if (text == nil) {
    CAMLreturn(Val_none);
  }
  const char *utf8 = text.UTF8String;
  if (utf8 == nullptr) {
    CAMLreturn(Val_none);
  }
  contents = caml_copy_string(utf8);
  option = caml_alloc(1, 0);
  Store_field(option, 0, contents);
  CAMLreturn(option);
}

value result_unit() { return result_ok(Val_unit); }

MTLResourceOptions resource_options(int storage) {
  switch (storage) {
  case 0:
    return MTLResourceStorageModeShared;
  case 1:
    return MTLResourceStorageModeManaged;
  case 2:
    return MTLResourceStorageModePrivate;
  default:
    caml_invalid_argument("invalid Metal storage mode");
  }
}

std::size_t tuple_dimension(value tuple, mlsize_t index) {
  const intnat dimension = Long_val(Field(tuple, index));
  if (dimension <= 0) {
    caml_invalid_argument("Metal dimensions must be positive");
  }
  return static_cast<std::size_t>(dimension);
}

} // namespace

extern "C" CAMLprim value caml_prismel_metal_is_main_thread(value unit) {
  CAMLparam1(unit);
  CAMLreturn(Val_bool(pthread_main_np() != 0));
}

extern "C" CAMLprim value caml_prismel_metal_generation(value raw) {
  CAMLparam1(raw);
  CAMLreturn(caml_copy_int64(
      static_cast<std::int64_t>(handle_of_value(raw)->generation)));
}

extern "C" CAMLprim value caml_prismel_metal_destroyed(value raw) {
  CAMLparam1(raw);
  bool destroyed = false;
  {
    std::lock_guard<std::mutex> lock(handle_mutex);
    destroyed = handle_of_value(raw)->object == nullptr;
  }
  CAMLreturn(Val_bool(destroyed));
}

extern "C" CAMLprim value caml_prismel_metal_destroy(value raw) {
  CAMLparam1(raw);
  void *pointer = take_pointer(handle_of_value(raw));
  if (pointer != nullptr) {
    release_pointer(pointer);
  }
  CAMLreturn(Val_bool(pointer != nullptr));
}

extern "C" CAMLprim value caml_prismel_metal_drain_releases(value unit) {
  CAMLparam1(unit);
  std::size_t drained = 0;
  for (;;) {
    void *pointer = nullptr;
    {
      std::lock_guard<std::mutex> lock(release_mutex);
      if (release_count == 0) {
        break;
      }
      pointer = release_queue[release_head];
      release_queue[release_head] = nullptr;
      release_head = (release_head + 1) % release_capacity;
      --release_count;
    }
    release_pointer(pointer);
    ++drained;
  }
  CAMLreturn(Val_long(drained));
}

extern "C" CAMLprim value caml_prismel_metal_pending_releases(value unit) {
  CAMLparam1(unit);
  std::size_t pending = 0;
  {
    std::lock_guard<std::mutex> lock(release_mutex);
    pending = release_count;
  }
  CAMLreturn(Val_long(pending));
}

extern "C" CAMLprim value caml_prismel_metal_dropped_releases(value unit) {
  CAMLparam1(unit);
  CAMLreturn(Val_long(dropped_releases.load(std::memory_order_relaxed)));
}

extern "C" CAMLprim value caml_prismel_metal_live_handles(value unit) {
  CAMLparam1(unit);
  CAMLreturn(Val_long(live_handle_count.load(std::memory_order_relaxed)));
}

extern "C" CAMLprim value caml_prismel_metal_total_created(value unit) {
  CAMLparam1(unit);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(
      total_created_count.load(std::memory_order_relaxed))));
}

extern "C" CAMLprim value caml_prismel_metal_total_released(value unit) {
  CAMLparam1(unit);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(
      total_released_count.load(std::memory_order_relaxed))));
}

extern "C" CAMLprim value caml_prismel_metal_resident_bytes(value unit) {
  CAMLparam1(unit);
  mach_task_basic_info_data_t information{};
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  const kern_return_t status = task_info(
      mach_task_self(), MACH_TASK_BASIC_INFO,
      reinterpret_cast<task_info_t>(&information), &count);
  if (status != KERN_SUCCESS) {
    CAMLreturn(caml_copy_int64(-1));
  }
  CAMLreturn(caml_copy_int64(
      static_cast<std::int64_t>(information.resident_size)));
}

extern "C" CAMLprim value caml_prismel_metal_default_device(value unit) {
  CAMLparam1(unit);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) {
      CAMLreturn(result_error_text("Metal has no system default device"));
    }
    raw = allocate_handle(device, Handle_kind::Device);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_all_devices(value unit) {
  CAMLparam1(unit);
  CAMLlocal3(array, raw, result);
  @autoreleasepool {
    NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();
    if (devices == nil) {
      CAMLreturn(result_error_text("MTLCopyAllDevices returned nil"));
    }
    const NSUInteger count = devices.count;
    array = caml_alloc(static_cast<mlsize_t>(count), 0);
    for (NSUInteger index = 0; index < count; ++index) {
      raw = allocate_handle(devices[index], Handle_kind::Device);
      Store_field(array, static_cast<mlsize_t>(index), raw);
    }
    result = result_ok(array);
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_device_name(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
    result = caml_copy_string(device.name.UTF8String ?: "Unnamed Metal device");
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_device_registry_id(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(device.registryID)));
}

extern "C" CAMLprim value caml_prismel_metal_device_is_low_power(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.lowPower));
}

extern "C" CAMLprim value caml_prismel_metal_device_is_removable(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.removable));
}

extern "C" CAMLprim value caml_prismel_metal_device_is_headless(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.headless));
}

extern "C" CAMLprim value
caml_prismel_metal_device_has_unified_memory(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.hasUnifiedMemory));
}

extern "C" CAMLprim value
caml_prismel_metal_device_recommended_max_working_set_size(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(
      device.recommendedMaxWorkingSetSize)));
}

extern "C" CAMLprim value
caml_prismel_metal_device_current_allocated_size(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(caml_copy_int64(
      static_cast<std::int64_t>(device.currentAllocatedSize)));
}

extern "C" CAMLprim value
caml_prismel_metal_device_max_buffer_length(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(caml_copy_int64(
      static_cast<std::int64_t>(device.maxBufferLength)));
}

extern "C" CAMLprim value caml_prismel_metal_device_supports_family(
    value raw, value family) {
  CAMLparam2(raw, family);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  const auto family_value = static_cast<MTLGPUFamily>(Long_val(family));
  CAMLreturn(Val_bool([device supportsFamily:family_value]));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_raytracing(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.supportsRaytracing));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_raytracing_from_render(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  const bool supported =
      [device respondsToSelector:@selector(supportsRaytracingFromRender)] &&
      device.supportsRaytracingFromRender;
  CAMLreturn(Val_bool(supported));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_dynamic_libraries(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.supportsDynamicLibraries));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_function_pointers(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.supportsFunctionPointers));
}

extern "C" CAMLprim value caml_prismel_metal_buffer_create(
    value raw_device, value raw_length, value raw_storage) {
  CAMLparam3(raw_device, raw_length, raw_storage);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    const std::int64_t signed_length = Int64_val(raw_length);
    if (signed_length <= 0) {
      CAMLreturn(result_error_text("buffer length must be positive"));
    }
    id<MTLBuffer> buffer = [device
        newBufferWithLength:static_cast<NSUInteger>(signed_length)
                   options:resource_options(Int_val(raw_storage))];
    if (buffer == nil) {
      CAMLreturn(result_error_text("Metal failed to allocate the buffer"));
    }
    raw = allocate_handle(buffer, Handle_kind::Buffer);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_buffer_length(value raw) {
  CAMLparam1(raw);
  id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(buffer.length)));
}

extern "C" CAMLprim value caml_prismel_metal_buffer_storage_mode(value raw) {
  CAMLparam1(raw);
  id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
  CAMLreturn(Val_int(static_cast<int>(buffer.storageMode)));
}

extern "C" CAMLprim value caml_prismel_metal_buffer_set_label(
    value raw, value raw_label) {
  CAMLparam2(raw, raw_label);
  @autoreleasepool {
    id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
    NSString *label = string_from_ocaml(raw_label);
    if (label == nil) {
      CAMLreturn(result_error_text("buffer label is not valid UTF-8"));
    }
    buffer.label = label;
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_buffer_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
    result = copy_optional_string(buffer.label);
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_buffer_write(
    value raw, value raw_offset, value source, value raw_source_offset,
    value raw_length) {
  CAMLparam5(raw, raw_offset, source, raw_source_offset, raw_length);
  id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
  const std::int64_t signed_offset = Int64_val(raw_offset);
  const intnat source_offset = Long_val(raw_source_offset);
  const intnat length = Long_val(raw_length);
  if (signed_offset < 0 || source_offset < 0 || length < 0 ||
      source_offset > static_cast<intnat>(caml_string_length(source)) ||
      length > static_cast<intnat>(caml_string_length(source)) - source_offset ||
      static_cast<std::uint64_t>(signed_offset) > buffer.length ||
      static_cast<std::uint64_t>(length) >
          buffer.length - static_cast<std::uint64_t>(signed_offset)) {
    CAMLreturn(result_error_text("buffer write range is invalid"));
  }
  void *contents = buffer.contents;
  if (contents == nullptr) {
    CAMLreturn(result_error_text("buffer storage is not CPU-accessible"));
  }
  std::memcpy(static_cast<std::uint8_t *>(contents) + signed_offset,
              reinterpret_cast<const std::uint8_t *>(Bytes_val(source)) +
                  source_offset,
              static_cast<std::size_t>(length));
  if (buffer.storageMode == MTLStorageModeManaged && length > 0) {
    [buffer didModifyRange:NSMakeRange(static_cast<NSUInteger>(signed_offset),
                                       static_cast<NSUInteger>(length))];
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_buffer_read(
    value raw, value raw_offset, value raw_length) {
  CAMLparam3(raw, raw_offset, raw_length);
  CAMLlocal2(contents_value, result);
  id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
  const std::int64_t signed_offset = Int64_val(raw_offset);
  const intnat length = Long_val(raw_length);
  if (signed_offset < 0 || length < 0 ||
      static_cast<std::uint64_t>(signed_offset) > buffer.length ||
      static_cast<std::uint64_t>(length) >
          buffer.length - static_cast<std::uint64_t>(signed_offset)) {
    CAMLreturn(result_error_text("buffer read range is invalid"));
  }
  const void *contents = buffer.contents;
  if (contents == nullptr) {
    CAMLreturn(result_error_text("buffer storage is not CPU-accessible"));
  }
  contents_value = caml_alloc_string(static_cast<mlsize_t>(length));
  std::memcpy(Bytes_val(contents_value),
              static_cast<const std::uint8_t *>(contents) + signed_offset,
              static_cast<std::size_t>(length));
  result = result_ok(contents_value);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_library_compile(
    value raw_device, value raw_source) {
  CAMLparam2(raw_device, raw_source);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    NSString *source = string_from_ocaml(raw_source);
    if (source == nil) {
      CAMLreturn(result_error_text("Metal source is not valid UTF-8"));
    }
    MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
    options.fastMathEnabled = NO;
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source
                                                  options:options
                                                    error:&error];
    if (library == nil) {
      CAMLreturn(result_error(error_description(
          error, @"Metal source compilation failed without NSError")));
    }
    raw = allocate_handle(library, Handle_kind::Library);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_function_find(
    value raw_library, value raw_name) {
  CAMLparam2(raw_library, raw_name);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLLibrary> library = object_of_handle(raw_library, Handle_kind::Library);
    NSString *name = string_from_ocaml(raw_name);
    if (name == nil) {
      CAMLreturn(result_error_text("Metal function name is not valid UTF-8"));
    }
    id<MTLFunction> function = [library newFunctionWithName:name];
    if (function == nil) {
      CAMLreturn(result_error(
          [NSString stringWithFormat:@"Metal library has no function named %@", name]));
    }
    raw = allocate_handle(function, Handle_kind::Function);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_function_name(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLFunction> function = object_of_handle(raw, Handle_kind::Function);
    result = caml_copy_string(function.name.UTF8String ?: "");
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_compute_pipeline_create(
    value raw_device, value raw_function) {
  CAMLparam2(raw_device, raw_function);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    id<MTLFunction> function =
        object_of_handle(raw_function, Handle_kind::Function);
    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [device newComputePipelineStateWithFunction:function error:&error];
    if (pipeline == nil) {
      CAMLreturn(result_error(error_description(
          error, @"Metal compute pipeline creation failed without NSError")));
    }
    raw = allocate_handle(pipeline, Handle_kind::Compute_pipeline);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compute_pipeline_thread_execution_width(value raw) {
  CAMLparam1(raw);
  id<MTLComputePipelineState> pipeline =
      object_of_handle(raw, Handle_kind::Compute_pipeline);
  CAMLreturn(Val_long(pipeline.threadExecutionWidth));
}

extern "C" CAMLprim value
caml_prismel_metal_compute_pipeline_max_total_threads(value raw) {
  CAMLparam1(raw);
  id<MTLComputePipelineState> pipeline =
      object_of_handle(raw, Handle_kind::Compute_pipeline);
  CAMLreturn(Val_long(pipeline.maxTotalThreadsPerThreadgroup));
}

extern "C" CAMLprim value caml_prismel_metal_command_queue_create(
    value raw_device) {
  CAMLparam1(raw_device);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    id<MTLCommandQueue> queue = [device newCommandQueue];
    if (queue == nil) {
      CAMLreturn(result_error_text("Metal failed to create a command queue"));
    }
    raw = allocate_handle(queue, Handle_kind::Command_queue);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_create(
    value raw_queue) {
  CAMLparam1(raw_queue);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLCommandQueue> queue =
        object_of_handle(raw_queue, Handle_kind::Command_queue);
    id<MTLCommandBuffer> buffer = [queue commandBuffer];
    if (buffer == nil) {
      CAMLreturn(result_error_text("Metal failed to create a command buffer"));
    }
    raw = allocate_handle(buffer, Handle_kind::Command_buffer);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_set_label(
    value raw, value raw_label) {
  CAMLparam2(raw, raw_label);
  @autoreleasepool {
    id<MTLCommandBuffer> buffer =
        object_of_handle(raw, Handle_kind::Command_buffer);
    NSString *label = string_from_ocaml(raw_label);
    if (label == nil) {
      CAMLreturn(result_error_text("command-buffer label is not valid UTF-8"));
    }
    buffer.label = label;
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_compute_encoder(
    value raw_buffer) {
  CAMLparam1(raw_buffer);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLCommandBuffer> buffer =
        object_of_handle(raw_buffer, Handle_kind::Command_buffer);
    id<MTLComputeCommandEncoder> encoder = [buffer computeCommandEncoder];
    if (encoder == nil) {
      CAMLreturn(result_error_text("Metal failed to create a compute encoder"));
    }
    raw = allocate_handle(encoder, Handle_kind::Compute_encoder);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_compute_encoder_set_pipeline(
    value raw_encoder, value raw_pipeline) {
  CAMLparam2(raw_encoder, raw_pipeline);
  id<MTLComputeCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Compute_encoder);
  id<MTLComputePipelineState> pipeline =
      object_of_handle(raw_pipeline, Handle_kind::Compute_pipeline);
  [encoder setComputePipelineState:pipeline];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_compute_encoder_set_buffer(
    value raw_encoder, value raw_buffer, value raw_offset, value raw_index) {
  CAMLparam4(raw_encoder, raw_buffer, raw_offset, raw_index);
  id<MTLComputeCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Compute_encoder);
  id<MTLBuffer> buffer = object_of_handle(raw_buffer, Handle_kind::Buffer);
  const std::int64_t offset = Int64_val(raw_offset);
  const intnat index = Long_val(raw_index);
  if (offset < 0 || static_cast<std::uint64_t>(offset) > buffer.length ||
      index < 0) {
    CAMLreturn(result_error_text("compute buffer binding is out of range"));
  }
  [encoder setBuffer:buffer
              offset:static_cast<NSUInteger>(offset)
             atIndex:static_cast<NSUInteger>(index)];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_compute_encoder_dispatch(
    value raw_encoder, value raw_threads, value raw_threadgroup) {
  CAMLparam3(raw_encoder, raw_threads, raw_threadgroup);
  id<MTLComputeCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Compute_encoder);
  const MTLSize threads =
      MTLSizeMake(tuple_dimension(raw_threads, 0),
                  tuple_dimension(raw_threads, 1),
                  tuple_dimension(raw_threads, 2));
  const MTLSize threadgroup =
      MTLSizeMake(tuple_dimension(raw_threadgroup, 0),
                  tuple_dimension(raw_threadgroup, 1),
                  tuple_dimension(raw_threadgroup, 2));
  [encoder dispatchThreads:threads threadsPerThreadgroup:threadgroup];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_compute_encoder_end(value raw) {
  CAMLparam1(raw);
  id<MTLComputeCommandEncoder> encoder =
      object_of_handle(raw, Handle_kind::Compute_encoder);
  [encoder endEncoding];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_commit(value raw) {
  CAMLparam1(raw);
  id<MTLCommandBuffer> buffer =
      object_of_handle(raw, Handle_kind::Command_buffer);
  [buffer commit];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_wait(value raw) {
  CAMLparam1(raw);
  id<MTLCommandBuffer> buffer =
      object_of_handle(raw, Handle_kind::Command_buffer);
  caml_enter_blocking_section();
  @autoreleasepool {
    [buffer waitUntilCompleted];
  }
  caml_leave_blocking_section();
  CAMLreturn(Val_unit);
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_status(value raw) {
  CAMLparam1(raw);
  id<MTLCommandBuffer> buffer =
      object_of_handle(raw, Handle_kind::Command_buffer);
  CAMLreturn(Val_int(static_cast<int>(buffer.status)));
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_error(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLCommandBuffer> buffer =
        object_of_handle(raw, Handle_kind::Command_buffer);
    NSError *error = buffer.error;
    result = error == nil
                 ? Val_none
                 : copy_optional_string(error_description(error, @"Metal error"));
  }
  CAMLreturn(result);
}
