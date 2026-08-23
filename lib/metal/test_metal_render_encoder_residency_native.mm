#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cassert>

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    assert(device != nil);
    MTLHeapDescriptor *hd = [MTLHeapDescriptor new]; hd.size = 4096;
    hd.storageMode = MTLStorageModePrivate;
    id<MTLHeap> heap = [device newHeapWithDescriptor:hd]; assert(heap != nil);
    id<MTLBuffer> resource = [heap newBufferWithLength:256 options:MTLResourceStorageModePrivate];
    assert(resource != nil);
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [device newTextureWithDescriptor:td];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target;
    id<MTLCommandBuffer> commands = [[device newCommandQueue] commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
    id<MTLResource> resources[] = {resource}; id<MTLHeap> heaps[] = {heap};
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [encoder useResource:resource usage:MTLResourceUsageRead];
    [encoder useResources:resources count:1 usage:MTLResourceUsageRead];
    [encoder useHeap:heap]; [encoder useHeaps:heaps count:1];
#pragma clang diagnostic pop
    [encoder useResource:resource usage:MTLResourceUsageRead stages:MTLRenderStageVertex];
    [encoder useResources:resources count:1 usage:MTLResourceUsageRead stages:MTLRenderStageVertex];
    [encoder useHeap:heap stages:MTLRenderStageVertex];
    [encoder useHeaps:heaps count:1 stages:MTLRenderStageVertex];
    [encoder endEncoding]; [commands commit]; [commands waitUntilCompleted];
    assert(commands.status == MTLCommandBufferStatusCompleted);
  }
  return 0;
}
