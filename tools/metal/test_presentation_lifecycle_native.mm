#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

static void require(bool condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) { @autoreleasepool {
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  require(device != nil, @"device");
  CAMetalLayer *layer = [CAMetalLayer layer];
  layer.device = device; layer.drawableSize = CGSizeMake(64, 32);
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  layer.framebufferOnly = NO; layer.maximumDrawableCount = 3;
  layer.allowsNextDrawableTimeout = YES; layer.displaySyncEnabled = NO;
  layer.presentsWithTransaction = NO;
  CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
  layer.colorspace = color; CGColorSpaceRelease(color);
  require(layer.device == device && layer.drawableSize.width == 64 &&
          layer.drawableSize.height == 32 && layer.pixelFormat == MTLPixelFormatBGRA8Unorm &&
          layer.maximumDrawableCount == 3 && layer.colorspace != nil,
          @"layer property roundtrip");
  layer.drawableSize = CGSizeMake(96, 48);
  require(layer.drawableSize.width == 96 && layer.drawableSize.height == 48, @"resize");
  id<CAMetalDrawable> drawable = [layer nextDrawable];
  require(drawable != nil && drawable.texture != nil && drawable.layer == layer,
          @"drawable acquisition and borrowed texture");
  id<CAMetalDrawable> held2 = [layer nextDrawable];
  id<CAMetalDrawable> held3 = [layer nextDrawable];
  require(held2 != nil && held3 != nil, @"maximum drawable pool acquisition");
  id<CAMetalDrawable> absent = [layer nextDrawable];
  /* Attached-window integration accepts nil here as recoverable timeout/loss. */
  if (absent == nil) require(layer.allowsNextDrawableTimeout, @"timeout policy");

  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
      MTLPixelFormatBGRA8Unorm width:4 height:4 mipmapped:NO];
  td.storageMode = MTLStorageModeShared; td.usage = MTLTextureUsageRenderTarget;
  id<MTLTexture> texture = [device newTextureWithDescriptor:td];
  MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.renderTargetWidth=4; pass.renderTargetHeight=4; pass.renderTargetArrayLength=1;
  pass.defaultRasterSampleCount=1; pass.tileWidth=0; pass.tileHeight=0;
  pass.threadgroupMemoryLength=0;
  pass.imageblockSampleLength=32; pass.threadgroupMemoryLength=64;
  pass.tileWidth=8; pass.tileHeight=8;
  pass.rasterizationRateMap=nil;
  MTLSamplePosition positions[2]={MTLSamplePositionMake(.25,.25),MTLSamplePositionMake(.75,.75)};
  [pass setSamplePositions:positions count:2];
  pass.colorAttachments[0].texture=texture;
  pass.colorAttachments[0].loadAction=MTLLoadActionClear;
  pass.colorAttachments[0].storeAction=MTLStoreActionStore;
  pass.colorAttachments[0].clearColor=MTLClearColorMake(0.25,0.5,0.75,1);
  require(pass.colorAttachments[0].texture == texture && pass.renderTargetWidth == 4 &&
          pass.imageblockSampleLength==32 && pass.threadgroupMemoryLength==64 &&
          pass.tileWidth==8 && pass.tileHeight==8 &&
          pass.rasterizationRateMap==nil && [pass getSamplePositions:nullptr count:0]==2,
          @"render-pass ownership and exact fields");
  pass.imageblockSampleLength=0; pass.threadgroupMemoryLength=0;
  pass.tileWidth=0; pass.tileHeight=0;
  [pass setSamplePositions:nullptr count:0];

  id<MTLCommandQueue> queue = [device newCommandQueue];
  id<MTLCommandBuffer> presentation = [queue commandBuffer];
  [presentation presentDrawable:drawable];
  [presentation commit]; [presentation waitUntilCompleted];
  require(presentation.status == MTLCommandBufferStatusCompleted,
          @"drawable presentation completion retention");
  __block NSUInteger completions = 0;
  for (NSUInteger frame=0; frame<10000; ++frame) { @autoreleasepool {
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
    [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
      require(completed.status == MTLCommandBufferStatusCompleted, @"completion status");
      @synchronized (queue) { ++completions; }
    }];
    [command commit]; [command waitUntilCompleted];
  }}
  require(completions == 10000, @"10000 completion-owned frames");
  uint8_t bytes[64] = {};
  [texture getBytes:bytes bytesPerRow:16 fromRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0];
  for (NSUInteger pixel=0; pixel<16; ++pixel)
    require(bytes[pixel*4]==191 && bytes[pixel*4+1]==128 &&
            bytes[pixel*4+2]==64 && bytes[pixel*4+3]==255, @"exact stored pixels");
  NSLog(@"presentation resize/timeout-policy/colorspace/attachment/10000-frame conformance passed");
  return 0;
}}
