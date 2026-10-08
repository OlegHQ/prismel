#include <metal_stdlib>
using namespace metal;
kernel void kernel_20741aa715b022c7d2afec8a8bd48647(
  device const float* input0 [[buffer(0)]],
  device float* output [[buffer(1)]],
  constant uint* uniforms [[buffer(2)]],
  uint i [[thread_position_in_grid]]) {
  if(i>=uniforms[0]) return;
  float r0=input0[i*1+0];
  float r1=as_type<float>(0x40000000u);
  float r2=(r0*r1);
  float r3=as_type<float>(uniforms[1]);
  float r4=(r2+r3);
  output[i*1+0]=r4;
}
