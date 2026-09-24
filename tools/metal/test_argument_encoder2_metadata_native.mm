#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <type_traits>

static const char *const kIds[] = {
  "protocol:MTLArgumentEncoder", "variable:MTLAttributeStrideStatic",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 2,
              "ArgumentEncoder2 exact closure drift");
static_assert(MTLAttributeStrideStatic == NSUIntegerMax,
              "MTLAttributeStrideStatic SDK value drift");
static_assert(std::is_same_v<decltype(((id<MTLArgumentEncoder>)nil).device),
                             id<MTLDevice>>);

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  NSError *error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:
    @"#include <metal_stdlib>\nusing namespace metal;"
     "struct A2 { device uint *output; uint value; };"
     "kernel void ae2(device A2 &args [[buffer(0)]]) { args.output[0]=args.value; }"
    options:nil error:&error];
  if (!library) return 77;
  id<MTLFunction> function = [library newFunctionWithName:@"ae2"];
  id<MTLArgumentEncoder> encoder = nil;
  @try { encoder = [function newArgumentEncoderWithBufferIndex:0]; }
  @catch (NSException *exception) {
    if (![exception.name isEqualToString:NSInvalidArgumentException]) return 1;
    return 77;
  }
  if (!encoder || encoder.device.registryID != device.registryID ||
      encoder.encodedLength == 0 || encoder.alignment == 0) return 2;
  id<MTLBuffer> arguments = [device newBufferWithLength:encoder.encodedLength
    options:MTLResourceStorageModeShared];
  id<MTLBuffer> output = [device newBufferWithLength:sizeof(uint32_t)
    options:MTLResourceStorageModeShared];
  [encoder setArgumentBuffer:arguments offset:0];
  [encoder setBuffer:output offset:0 atIndex:0];
  *static_cast<uint32_t *>([encoder constantDataAtIndex:1]) = 2;

  id<MTLComputePipelineState> pipeline =
    [device newComputePipelineStateWithFunction:function error:&error];
  id<MTLCommandBuffer> command = [[device newCommandQueue] commandBuffer];
  id<MTLComputeCommandEncoder> compute = [command computeCommandEncoder];
  [compute setComputePipelineState:pipeline]; [compute setBuffer:arguments offset:0 atIndex:0];
  [compute useResource:output usage:MTLResourceUsageWrite];
  [compute dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
  [compute endEncoding]; [command commit]; [command waitUntilCompleted];
  if (command.status != MTLCommandBufferStatusCompleted ||
      *static_cast<uint32_t *>(output.contents) != 2) return 3;
  return 0;
} }
