#include <metal_stdlib>
using namespace metal;
kernel void kernel_7a412f30ae7c64fbb58af52a3b5688e5(
  device const float* input0 [[buffer(0)]],
  device float* output [[buffer(1)]],
  constant uint* uniforms [[buffer(2)]],
  device atomic_uint* status [[buffer(3)]],
  uint i [[thread_position_in_grid]]) {
  if(i>=uniforms[0]) return;
  if(i==0) atomic_fetch_or_explicit(status,0u,memory_order_relaxed);
  float r0=input0[i*1+0];
  float r1=as_type<float>(0x40000000u);
  float r2=(r0*r1);
  float r3=as_type<float>(uniforms[1]);
  float r4=(r2+r3);
  if(!isfinite(r4)) atomic_store_explicit(status,1u,memory_order_relaxed);
  output[i*1+0]=r4;
}
