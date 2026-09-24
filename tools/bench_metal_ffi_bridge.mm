#define CAML_NAME_SPACE

#include <cstdint>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <mach/mach_time.h>

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

namespace {

id<MTLDevice> benchmark_device = nil;

id<MTLDevice> require_device() {
  if (benchmark_device == nil) {
    caml_failwith("Metal FFI benchmark device is not initialized");
  }
  return benchmark_device;
}

std::uint64_t query_checksum(id<MTLDevice> device, intnat iterations) {
  std::uint64_t checksum = 0;
  for (intnat index = 0; index < iterations; ++index) {
    checksum += static_cast<std::uint64_t>(device.registryID) ^
                static_cast<std::uint64_t>(index);
  }
  return checksum;
}

std::uint64_t nanoseconds(std::uint64_t ticks) {
  mach_timebase_info_data_t timebase{};
  if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.denom == 0) {
    caml_failwith("mach_timebase_info failed");
  }
  const long double value =
      static_cast<long double>(ticks) * timebase.numer / timebase.denom;
  return static_cast<std::uint64_t>(value);
}

} // namespace

extern "C" CAMLprim value caml_prismel_bench_metal_initialize(value unit) {
  CAMLparam1(unit);
  @autoreleasepool {
    benchmark_device = MTLCreateSystemDefaultDevice();
  }
  CAMLreturn(Val_bool(benchmark_device != nil));
}

extern "C" CAMLprim value caml_prismel_bench_metal_shutdown(value unit) {
  CAMLparam1(unit);
  benchmark_device = nil;
  CAMLreturn(Val_unit);
}

extern "C" CAMLprim value caml_prismel_bench_metal_direct_query(value unit) {
  CAMLparam1(unit);
  id<MTLDevice> device = require_device();
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(device.registryID)));
}

extern "C" CAMLprim value caml_prismel_bench_metal_batched_query(
    value raw_iterations) {
  CAMLparam1(raw_iterations);
  const intnat iterations = Long_val(raw_iterations);
  if (iterations <= 0) {
    caml_invalid_argument("Metal FFI benchmark iterations must be positive");
  }
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(
      query_checksum(require_device(), iterations))));
}

extern "C" CAMLprim value caml_prismel_bench_metal_native_timed_query(
    value raw_iterations) {
  CAMLparam1(raw_iterations);
  CAMLlocal3(result, checksum_value, nanoseconds_value);
  const intnat iterations = Long_val(raw_iterations);
  if (iterations <= 0) {
    caml_invalid_argument("Metal FFI benchmark iterations must be positive");
  }
  id<MTLDevice> device = require_device();
  const std::uint64_t started = mach_continuous_time();
  const std::uint64_t checksum = query_checksum(device, iterations);
  const std::uint64_t elapsed = mach_continuous_time() - started;
  checksum_value = caml_copy_int64(static_cast<std::int64_t>(checksum));
  nanoseconds_value =
      caml_copy_int64(static_cast<std::int64_t>(nanoseconds(elapsed)));
  result = caml_alloc_tuple(2);
  Store_field(result, 0, checksum_value);
  Store_field(result, 1, nanoseconds_value);
  CAMLreturn(result);
}
