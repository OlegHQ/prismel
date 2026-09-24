#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<decltype([MTLFunctionConstantValues new]),
                             MTLFunctionConstantValues *>);

int main()
{
  __weak MTLFunctionConstantValues *weak_values = nil;
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    NSError *error = nil;
    NSString *source =
        @"constant int first [[function_constant(0)]];"
         "constant int second [[function_constant(1)]];"
         "kernel void constant_copy(device int *out [[buffer(0)]]) {"
         "  out[0] = first * 100 + second;"
         "}";
    id<MTLLibrary> library =
        [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) return 77;

    MTLFunctionConstantValues *values = [MTLFunctionConstantValues new];
    weak_values = values;
    int32_t source_values[2] = {7, 11};
    [values setConstantValues:source_values
                         type:MTLDataTypeInt
                    withRange:NSMakeRange(0, 2)];
    /* The SDK setter must consume/copy the caller-owned bytes immediately. */
    source_values[0] = 99;
    source_values[1] = 99;
    id<MTLFunction> function =
        [library newFunctionWithName:@"constant_copy"
                      constantValues:values
                               error:&error];
    if (function == nil) return 1;

    id<MTLComputePipelineState> pipeline =
        [device newComputePipelineStateWithFunction:function error:&error];
    id<MTLBuffer> output = [device newBufferWithLength:sizeof(int32_t)
                                            options:MTLResourceStorageModeShared];
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
    if (pipeline == nil || output == nil || queue == nil || command == nil ||
        encoder == nil)
      return 77;
    [encoder setComputePipelineState:pipeline];
    [encoder setBuffer:output offset:0 atIndex:0];
    [encoder dispatchThreadgroups:MTLSizeMake(1, 1, 1)
            threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
    [encoder endEncoding];
    [command commit];
    [command waitUntilCompleted];
    if (command.status != MTLCommandBufferStatusCompleted ||
        *((int32_t *)output.contents) != 711)
      return 2;

    [values reset];
    error = nil;
    id<MTLFunction> missing =
        [library newFunctionWithName:@"constant_copy"
                      constantValues:values
                               error:&error];
    if (missing != nil || error == nil) return 3;
    values = nil;
  }
  if (weak_values != nil) return 4;
  return 0;
}
