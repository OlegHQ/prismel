#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cassert>

static id<MTLTexture> texture(id<MTLDevice> device, MTLPixelFormat format) {
  MTLTextureDescriptor *descriptor =
    [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:4 height:4 mipmapped:NO];
  descriptor.usage = MTLTextureUsageRenderTarget;
  descriptor.storageMode = MTLStorageModePrivate;
  return [device newTextureWithDescriptor:descriptor];
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    assert(device != nil);
    id<MTLTexture> color = texture(device, MTLPixelFormatRGBA8Unorm);
    id<MTLTexture> depth = texture(device, MTLPixelFormatDepth32Float);
    id<MTLTexture> stencil = texture(device, MTLPixelFormatStencil8);
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = color;
    pass.depthAttachment.texture = depth;
    pass.stencilAttachment.texture = stencil;
    id<MTLCommandBuffer> commands = [[device newCommandQueue] commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
    [encoder setColorStoreAction:MTLStoreActionStore atIndex:0];
    [encoder setColorStoreActionOptions:MTLStoreActionOptionNone atIndex:0];
    [encoder setDepthStoreAction:MTLStoreActionStore];
    [encoder setDepthStoreActionOptions:MTLStoreActionOptionNone];
    [encoder setStencilStoreAction:MTLStoreActionStore];
    [encoder setStencilStoreActionOptions:MTLStoreActionOptionNone];
    [encoder endEncoding]; [commands commit]; [commands waitUntilCompleted];
    assert(commands.status == MTLCommandBufferStatusCompleted);
  }
  return 0;
}
