#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cassert>

static MTLRenderPassDescriptor *pass(id<MTLTexture> texture) {
  MTLRenderPassDescriptor *result = [MTLRenderPassDescriptor renderPassDescriptor];
  result.colorAttachments[0].texture = texture;
  result.colorAttachments[0].loadAction = MTLLoadActionDontCare;
  result.colorAttachments[0].storeAction = MTLStoreActionStore;
  return result;
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    assert(device != nil);
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLFence> fence = [device newFence];
    assert(fence != nil);
    MTLTextureDescriptor *descriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                        width:4 height:4 mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModeShared;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    id<MTLCommandBuffer> commands = [queue commandBuffer];
    id<MTLRenderCommandEncoder> first =
      [commands renderCommandEncoderWithDescriptor:pass(texture)];
    [first memoryBarrierWithScope:MTLBarrierScopeTextures
                       afterStages:MTLRenderStageVertex
                      beforeStages:MTLRenderStageFragment];
    id<MTLResource> resources[] = {texture};
    [first memoryBarrierWithResources:resources count:1
                           afterStages:MTLRenderStageVertex
                          beforeStages:MTLRenderStageFragment];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [first textureBarrier];
#pragma clang diagnostic pop
    [first updateFence:fence afterStages:MTLRenderStageFragment];
    [first endEncoding];
    id<MTLRenderCommandEncoder> second =
      [commands renderCommandEncoderWithDescriptor:pass(texture)];
    [second waitForFence:fence beforeStages:MTLRenderStageVertex];
    [second endEncoding];
    [commands commit];
    [commands waitUntilCompleted];
    assert(commands.status == MTLCommandBufferStatusCompleted);
  }
  return 0;
}
