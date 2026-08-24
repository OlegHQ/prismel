#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdint>

static int run_iteration(id<MTLDevice> device, id<MTLCommandQueue> queue,
                         int iteration) {
  @autoreleasepool {
    MTLTextureDescriptor *texture_descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:4
                                                          height:4
                                                       mipmapped:NO];
    texture_descriptor.usage = MTLTextureUsageRenderTarget;
    texture_descriptor.storageMode = MTLStorageModeShared;
    id<MTLTexture> texture = [device newTextureWithDescriptor:texture_descriptor];
    if (texture == nil) return 1;
    __weak id<MTLTexture> weak_texture = texture;

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor =
        MTLClearColorMake(0.25, 0.5, 0.75, 1.0);

    id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
    id<MTLParallelRenderCommandEncoder> parent =
        [command_buffer parallelRenderCommandEncoderWithDescriptor:pass];
    if (parent == nil) return 2;

    /* Exercise the exact six store-state selectors.  Depth and stencil may be
       set to dont-care without attachments; color index zero is backed. */
    [parent setColorStoreAction:MTLStoreActionStore atIndex:0];
    [parent setColorStoreActionOptions:MTLStoreActionOptionNone atIndex:0];
    [parent setDepthStoreAction:MTLStoreActionDontCare];
    [parent setDepthStoreActionOptions:MTLStoreActionOptionNone];
    [parent setStencilStoreAction:MTLStoreActionDontCare];
    [parent setStencilStoreActionOptions:MTLStoreActionOptionNone];

    id<MTLRenderCommandEncoder> first = [parent renderCommandEncoder];
    id<MTLRenderCommandEncoder> second = [parent renderCommandEncoder];
    if (first == nil || second == nil ||
        first.device.registryID != device.registryID ||
        second.device.registryID != device.registryID) return 3;

    /* Dropping the caller's strong texture reference must not break the pass:
       descriptor/encoder/command-buffer ownership retains it to completion. */
    texture = nil;
    if (weak_texture == nil) return 4;
    [second endEncoding];
    [first endEncoding];
    [parent endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];
    if (command_buffer.status != MTLCommandBufferStatusCompleted) return 5;

    uint8_t pixels[4 * 4 * 4] = {};
    [weak_texture getBytes:pixels
               bytesPerRow:4 * 4
                fromRegion:MTLRegionMake2D(0, 0, 4, 4)
               mipmapLevel:0];
    if (pixels[0] < 190 || pixels[1] < 125 || pixels[2] < 60 ||
        pixels[3] != 255) return 6;
    if (iteration < 0) return 7;
  }
  return 0;
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    id<MTLCommandQueue> queue = [device newCommandQueue];
    if (queue == nil) return 77;
    for (int iteration = 0; iteration < 256; ++iteration) {
      int result = run_iteration(device, queue, iteration);
      if (result != 0) return result;
    }
  }
  return 0;
}
