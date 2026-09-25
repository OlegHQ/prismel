#include <metal_stdlib>
using namespace metal;

constant bool TRIPLE [[function_constant(0)]];

kernel void exact_compute_compiled(device uint *values [[buffer(0)]],
                                   uint i [[thread_position_in_grid]]) {
  values[i] = values[i] * (TRIPLE ? 3u : 2u) + 1u;
}
