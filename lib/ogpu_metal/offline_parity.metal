#include <metal_stdlib>
using namespace metal;
kernel void offline_parity(device uint *values [[buffer(0)]], uint index [[thread_position_in_grid]]) { values[index] = values[index] * 2 + 3; }
