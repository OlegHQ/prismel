#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static void qualify_all(id<MTLComputeCommandEncoder> e, id<MTLBuffer> buffer,
                        id<MTLTexture> texture, id<MTLSamplerState> sampler,
                        id<MTLAccelerationStructure> acceleration,
                        id<MTLIntersectionFunctionTable> intersection,
                        id<MTLVisibleFunctionTable> visible,
                        id<MTLIndirectCommandBuffer> indirect,
                        id<MTLCounterSampleBuffer> counters, id<MTLFence> fence,
                        id<MTLHeap> heap) {
  if (e == nil) return;
  id<MTLBuffer> buffers[1] = { buffer };
  id<MTLTexture> textures[1] = { texture };
  id<MTLSamplerState> samplers[1] = { sampler };
  id<MTLResource> resources[1] = { buffer };
  id<MTLHeap> heaps[1] = { heap };
  id<MTLIntersectionFunctionTable> intersections[1] = { intersection };
  id<MTLVisibleFunctionTable> visibles[1] = { visible };
  NSUInteger offsets[1] = { 0 }, strides[1] = { 4 };
  float mins[1] = { 0.0f }, maxs[1] = { 1.0f };
  uint32_t bytes = 0;
  [e dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
  [e dispatchThreadgroupsWithIndirectBuffer:buffer indirectBufferOffset:0 threadsPerThreadgroup:MTLSizeMake(1,1,1)];
  (void)e.dispatchType;
  [e executeCommandsInBuffer:indirect indirectBuffer:buffer indirectBufferOffset:0];
  [e memoryBarrierWithResources:resources count:1];
  [e memoryBarrierWithScope:MTLBarrierScopeBuffers];
  [e sampleCountersInBuffer:counters atSampleIndex:0 withBarrier:YES];
  [e setAccelerationStructure:acceleration atBufferIndex:0];
  [e setBuffer:buffer offset:0 attributeStride:4 atIndex:0];
  [e setBufferOffset:0 atIndex:0];
  [e setBufferOffset:0 attributeStride:4 atIndex:0];
  [e setBuffers:buffers offsets:offsets attributeStrides:strides withRange:NSMakeRange(0,1)];
  [e setBuffers:buffers offsets:offsets withRange:NSMakeRange(0,1)];
  [e setBytes:&bytes length:sizeof(bytes) atIndex:0];
  [e setBytes:&bytes length:sizeof(bytes) attributeStride:sizeof(bytes) atIndex:0];
  [e setImageblockWidth:1 height:1];
  [e setIntersectionFunctionTable:intersection atBufferIndex:0];
  [e setIntersectionFunctionTables:intersections withBufferRange:NSMakeRange(0,1)];
  [e setSamplerState:sampler atIndex:0];
  [e setSamplerState:sampler lodMinClamp:0 lodMaxClamp:1 atIndex:0];
  [e setSamplerStates:samplers lodMinClamps:mins lodMaxClamps:maxs withRange:NSMakeRange(0,1)];
  [e setSamplerStates:samplers withRange:NSMakeRange(0,1)];
  [e setStageInRegion:MTLRegionMake1D(0,1)];
  [e setStageInRegionWithIndirectBuffer:buffer indirectBufferOffset:0];
  [e setTextures:textures withRange:NSMakeRange(0,1)];
  [e setThreadgroupMemoryLength:4 atIndex:0];
  [e setVisibleFunctionTable:visible atBufferIndex:0];
  [e setVisibleFunctionTables:visibles withBufferRange:NSMakeRange(0,1)];
  [e updateFence:fence];
  [e useHeap:heap];
  [e useHeaps:heaps count:1];
  [e useResource:buffer usage:MTLResourceUsageRead];
  [e useResources:resources count:1 usage:MTLResourceUsageRead];
  [e waitForFence:fence];
}

int main(void) {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return 77;
    NSError *error = nil;
    NSString *source = @"#include <metal_stdlib>\nusing namespace metal; kernel void k(device uint *x [[buffer(0)]]) { x[0] += 1; }";
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (!library) return 2;
    id<MTLFunction> function = [library newFunctionWithName:@"k"];
    id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];
    if (!pipeline) return 3;
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
    id<MTLBuffer> buffer = [device newBufferWithLength:4 options:MTLResourceStorageModeShared];
    [encoder setComputePipelineState:pipeline];
    [encoder setBuffer:buffer offset:0 atIndex:0];
    [encoder dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
    [encoder endEncoding];
    [command commit];
    [command waitUntilCompleted];
    if (command.status != MTLCommandBufferStatusCompleted) return 4;
    qualify_all(nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil);
    return *(uint32_t *)buffer.contents == 1 ? 0 : 5;
  }
}
