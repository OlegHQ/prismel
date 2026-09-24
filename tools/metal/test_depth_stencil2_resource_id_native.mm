#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kIds[] = {
  "method:-[MTLDepthStencilState gpuResourceID]",
  "property:MTLDepthStencilState:gpuResourceID",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 2,
              "DepthStencil2 exact closure drift");

static id<MTLRenderPipelineState> pipeline(id<MTLDevice> device,
                                            id<MTLLibrary> library,
                                            NSString *vertex,
                                            NSString *fragment) {
  MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
  descriptor.vertexFunction = [library newFunctionWithName:vertex];
  descriptor.fragmentFunction = [library newFunctionWithName:fragment];
  descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
  NSError *error = nil;
  return [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
}

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  MTLDepthStencilDescriptor *descriptor = [MTLDepthStencilDescriptor new];
  descriptor.depthCompareFunction = MTLCompareFunctionLess;
  descriptor.depthWriteEnabled = YES;
  id<MTLDepthStencilState> depth = [device newDepthStencilStateWithDescriptor:descriptor];
  if (!depth) return 1;
  NSError *error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:
    @"#include <metal_stdlib>\nusing namespace metal;"
     "vertex float4 far_v(uint i [[vertex_id]]) { float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(p[i],0.8,1); }"
     "vertex float4 near_v(uint i [[vertex_id]]) { float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(p[i],0.2,1); }"
     "fragment float4 red_f(){return float4(1,0,0,1);}"
     "fragment float4 green_f(){return float4(0,1,0,1);}"
    options:nil error:&error];
  if (!library) return 77;
  id<MTLRenderPipelineState> far = pipeline(device,library,@"far_v",@"red_f");
  id<MTLRenderPipelineState> near = pipeline(device,library,@"near_v",@"green_f");
  if (!far || !near) return 77;
  MTLTextureDescriptor *color_descriptor = [MTLTextureDescriptor
    texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
  color_descriptor.usage = MTLTextureUsageRenderTarget;
  color_descriptor.storageMode = MTLStorageModeShared;
  id<MTLTexture> color = [device newTextureWithDescriptor:color_descriptor];
  MTLTextureDescriptor *depth_descriptor = [MTLTextureDescriptor
    texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:4 height:4 mipmapped:NO];
  depth_descriptor.usage = MTLTextureUsageRenderTarget;
  depth_descriptor.storageMode = MTLStorageModePrivate;
  id<MTLTexture> depth_texture = [device newTextureWithDescriptor:depth_descriptor];
  MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture=color; pass.colorAttachments[0].loadAction=MTLLoadActionClear;
  pass.colorAttachments[0].storeAction=MTLStoreActionStore;
  pass.depthAttachment.texture=depth_texture; pass.depthAttachment.loadAction=MTLLoadActionClear;
  pass.depthAttachment.storeAction=MTLStoreActionDontCare; pass.depthAttachment.clearDepth=1.0;
  id<MTLCommandBuffer> command = [[device newCommandQueue] commandBuffer];
  id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
  [encoder setDepthStencilState:depth]; [encoder setRenderPipelineState:far];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [encoder setRenderPipelineState:near];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
  uint8_t pixel[4]={}; [color getBytes:pixel bytesPerRow:4
    fromRegion:MTLRegionMake2D(2,2,1,1) mipmapLevel:0];
  if (command.status != MTLCommandBufferStatusCompleted || pixel[1] < 250 || pixel[3] != 255)
    return 2;
  @try {
    MTLResourceID first = depth.gpuResourceID;
    MTLResourceID second = depth.gpuResourceID;
    if (first._impl == 0 || first._impl != second._impl) return 3;
  } @catch (NSException *exception) {
    if (![exception.name isEqualToString:NSInvalidArgumentException]) return 4;
    /* macOS 26 SDK availability is insufficient: current M1 AGX depth-state
       implementations can lack the selector.  The safe API must expose an
       Unsupported result instead of forwarding this exception. */
    return 77;
  }
  return 0;
} }
