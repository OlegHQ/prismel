#include <metal_stdlib>
using namespace metal;
kernel void kernel_d99241f0a19773f6c54bd43c3918fce4(
  device const float* input0 [[buffer(0)]],
  device float* output [[buffer(1)]],
  constant uint* uniforms [[buffer(2)]],
  uint i [[thread_position_in_grid]]) {
  if(i>=uniforms[0]) return;
  float r0=input0[i*1+0];
  float r1=as_type<float>(uniforms[1]);
  float r2=(r0<r1);
  float r3=as_type<float>(0x3f800000u);
  float r4=(r0+r3);
  float r5=as_type<float>(0x3f800000u);
  float r6=(r0-r5);
  float r7=(r2!=0.0f?r4:r6);
  output[i*1+0]=r7;
}
