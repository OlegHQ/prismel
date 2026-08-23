#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cassert>

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    assert(device != nil);
    MTLTextureDescriptor *descriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                        width:4 height:4 mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [device newTextureWithDescriptor:descriptor];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target;
    id<MTLCommandBuffer> commands = [[device newCommandQueue] commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
    const NSUInteger width_method = [encoder tileWidth];
    const NSUInteger height_method = [encoder tileHeight];
    const NSUInteger width_property = encoder.tileWidth;
    const NSUInteger height_property = encoder.tileHeight;
    assert(width_method > 0 && height_method > 0);
    assert(width_method == width_property && height_method == height_property);
    [encoder endEncoding]; [commands commit]; [commands waitUntilCompleted];
    assert(commands.status == MTLCommandBufferStatusCompleted);
  }
  return 0;
}
