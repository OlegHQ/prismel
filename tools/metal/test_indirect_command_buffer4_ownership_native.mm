#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kIds[] = {
  "method:-[MTLIndirectCommandBuffer gpuResourceID]",
  "method:-[MTLIndirectCommandBuffer indirectRenderCommandAtIndex:]",
  "property:MTLIndirectCommandBuffer:gpuResourceID",
  "protocol:MTLIndirectCommandBuffer",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 4,
              "IndirectCommandBuffer4 exact closure drift");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  NSError *error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:
    @"#include <metal_stdlib>\nusing namespace metal;"
     "vertex float4 i4v(uint i [[vertex_id]]) { float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(p[i],0,1); }"
     "fragment float4 i4f() { return float4(0,1,0,1); }"
    options:nil error:&error];
  if (!library) return 77;
  MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
  pd.vertexFunction = [library newFunctionWithName:@"i4v"];
  pd.fragmentFunction = [library newFunctionWithName:@"i4f"];
  pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  pd.supportIndirectCommandBuffers = YES;
  id<MTLRenderPipelineState> pipeline =
    [device newRenderPipelineStateWithDescriptor:pd error:&error];
  if (!pipeline) return 77;
  MTLIndirectCommandBufferDescriptor *descriptor =
    [MTLIndirectCommandBufferDescriptor new];
  descriptor.commandTypes = MTLIndirectCommandTypeDraw;
  descriptor.inheritPipelineState = NO;
  descriptor.inheritBuffers = YES;
  id<MTLIndirectCommandBuffer> icb =
    [device newIndirectCommandBufferWithDescriptor:descriptor maxCommandCount:2 options:0];
  if (!icb || icb.gpuResourceID._impl == 0 ||
      icb.gpuResourceID._impl != icb.gpuResourceID._impl) return 1;
  id<MTLIndirectRenderCommand> first = [icb indirectRenderCommandAtIndex:0];
  id<MTLIndirectRenderCommand> second = [icb indirectRenderCommandAtIndex:1];
  if (!first || !second || first == second) return 2;
  [first setRenderPipelineState:pipeline];
  [first drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3
             instanceCount:1 baseInstance:0];
  [second reset];

  MTLTextureDescriptor *td = [MTLTextureDescriptor
    texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModeShared;
  id<MTLTexture> texture = [device newTextureWithDescriptor:td];
  MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture = texture;
  pass.colorAttachments[0].loadAction = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  id<MTLCommandBuffer> command = [[device newCommandQueue] commandBuffer];
  id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
  [encoder executeCommandsInBuffer:icb withRange:NSMakeRange(0,1)];
  [encoder endEncoding];
  __weak id<MTLIndirectCommandBuffer> weak_icb = icb; icb = nil;
  if (weak_icb == nil) return 3;
  [command commit]; [command waitUntilCompleted];
  uint8_t pixel[4] = {};
  [texture getBytes:pixel bytesPerRow:4 fromRegion:MTLRegionMake2D(2,2,1,1)
          mipmapLevel:0];
  if (command.status != MTLCommandBufferStatusCompleted || pixel[1] < 250 ||
      pixel[3] != 255) return 4;
  return 0;
} }
