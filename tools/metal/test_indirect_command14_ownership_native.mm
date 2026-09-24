#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static void qualify(id<MTLIndirectComputeCommand> compute,
                    id<MTLIndirectRenderCommand> render,
                    id<MTLBuffer> buffer,
                    id<MTLRenderPipelineState> pipeline) {
  if (!compute || !render) return;
  [compute setKernelBuffer:buffer offset:0 attributeStride:4 atIndex:0];
  [render setFragmentBuffer:buffer offset:0 atIndex:0];
  [render setMeshBuffer:buffer offset:0 atIndex:0];
  [render setObjectBuffer:buffer offset:0 atIndex:0];
  [render setRenderPipelineState:pipeline];
  [render setVertexBuffer:buffer offset:0 atIndex:0];
  [render setVertexBuffer:buffer offset:0 attributeStride:4 atIndex:0];
  [render drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3
      instanceCount:1 baseInstance:0];
  [render drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:3
      indexType:MTLIndexTypeUInt16 indexBuffer:buffer indexBufferOffset:0
      instanceCount:1 baseVertex:0 baseInstance:0];
  [render drawPatches:3 patchStart:0 patchCount:1 patchIndexBuffer:buffer
      patchIndexBufferOffset:0 instanceCount:1 baseInstance:0
      tessellationFactorBuffer:buffer tessellationFactorBufferOffset:0
      tessellationFactorBufferInstanceStride:0];
  [render drawIndexedPatches:3 patchStart:0 patchCount:1
      patchIndexBuffer:buffer patchIndexBufferOffset:0
      controlPointIndexBuffer:buffer controlPointIndexBufferOffset:0
      instanceCount:1 baseInstance:0 tessellationFactorBuffer:buffer
      tessellationFactorBufferOffset:0 tessellationFactorBufferInstanceStride:0];
  [render reset];
}

int main() { @autoreleasepool {
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (!device) return 77;
  MTLIndirectCommandBufferDescriptor *descriptor =
    [MTLIndirectCommandBufferDescriptor new];
  descriptor.commandTypes = MTLIndirectCommandTypeDraw;
  descriptor.inheritBuffers = NO;
  descriptor.inheritPipelineState = YES;
  descriptor.maxVertexBufferBindCount = 1;
  descriptor.maxFragmentBufferBindCount = 1;
  id<MTLIndirectCommandBuffer> icb =
    [device newIndirectCommandBufferWithDescriptor:descriptor
      maxCommandCount:1 options:0];
  if (!icb) return 77;
  id<MTLBuffer> buffer = [device newBufferWithLength:64
    options:MTLResourceStorageModeShared];
  __weak id weak = buffer;
  id retained = buffer; // mirrors the safe parent retention table
  id<MTLIndirectRenderCommand> command = [icb indirectRenderCommandAtIndex:0];
  [command setVertexBuffer:buffer offset:0 atIndex:0];
  [command drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3
    instanceCount:1 baseInstance:0];
  buffer = nil;
  (void)retained;
  if (!weak) return 1;
  [command reset];
  retained = nil;
  if (weak) return 2;
  qualify(nil, nil, nil, nil);
  return 0;
} }
