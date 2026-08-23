#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static void require(bool value, NSString *message) { if (!value) { NSLog(@"FAIL: %@",message); exit(1); } }
int main(void) { @autoreleasepool {
  id<MTLDevice> device=MTLCreateSystemDefaultDevice(); require(device!=nil,@"device");
  MTLSamplerDescriptor *sd=[MTLSamplerDescriptor new]; sd.minFilter=MTLSamplerMinMagFilterLinear;
  sd.magFilter=MTLSamplerMinMagFilterLinear; id<MTLSamplerState> sampler=[device newSamplerStateWithDescriptor:sd];
  require(sampler!=nil && sampler.device==device,@"sampler create/device");
  MTLHeapDescriptor *hd=[MTLHeapDescriptor new]; hd.size=1<<20; hd.storageMode=MTLStorageModeShared;
  id<MTLHeap> heap=[device newHeapWithDescriptor:hd]; require(heap!=nil && heap.device==device,@"heap create/device");
  id<MTLCommandQueue> queue=[device newCommandQueue];
  for (NSUInteger iteration=0; iteration<10000; ++iteration) { @autoreleasepool {
    id<MTLBuffer> source=[heap newBufferWithLength:256 options:MTLResourceStorageModeShared];
    id<MTLBuffer> target=[device newBufferWithLength:256 options:MTLResourceStorageModeShared];
    require(source && target && source.heap==heap && source.device==device,@"buffer ownership");
    memset(source.contents,(int)(iteration&255),256);
    id<MTLCommandBuffer> command=[queue commandBuffer]; id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
    [blit copyFromBuffer:source sourceOffset:0 toBuffer:target destinationOffset:0 size:256];
    [blit endEncoding]; [command commit]; [command waitUntilCompleted];
    require(command.status==MTLCommandBufferStatusCompleted,@"buffer GPU completion");
    require(((uint8_t *)target.contents)[0]==(iteration&255),@"buffer exact copy");
  }}
  MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
  td.storageMode=MTLStorageModeShared; td.usage=MTLTextureUsageShaderRead|MTLTextureUsagePixelFormatView;
  id<MTLTexture> texture=[device newTextureWithDescriptor:td];
  id<MTLTexture> view=[texture newTextureViewWithPixelFormat:MTLPixelFormatRGBA8Unorm];
  require(texture && view && view.parentTexture==texture && texture.device==device,@"texture/view ownership");
  NSLog(@"resource buffer/texture/heap/sampler 10000-iteration conformance passed"); return 0;
}}
