#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cmath>

static bool valid_position(double value) {
  return std::isfinite(value) && value >= 0.0 && value <= 1.0;
}

int main() { @autoreleasepool {
  if (valid_position(NAN) || valid_position(-0.1) || valid_position(1.1)
      || !valid_position(0.5)) return 1;
  if (@available(macOS 26.0, *)) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (device == nil) return 77;
    MTL4RenderPassDescriptor *pass = [MTL4RenderPassDescriptor new];
    MTLRenderPassDepthAttachmentDescriptor *depth =
      [MTLRenderPassDepthAttachmentDescriptor new];
    MTLRenderPassStencilAttachmentDescriptor *stencil =
      [MTLRenderPassStencilAttachmentDescriptor new];
    if (pass == nil || depth == nil || stencil == nil) return 2;
    MTLSamplePosition positions[2] = {
      MTLSamplePositionMake(0.25f, 0.25f), MTLSamplePositionMake(0.75f, 0.75f) };
    [pass setSamplePositions:positions count:2];
    MTLSamplePosition copied[2] = {};
    if ([pass getSamplePositions:copied count:2] != 2
        || copied[1].x != positions[1].x) return 3;
    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
      width:8 height:8 mipmapped:NO];
    textureDescriptor.textureType = MTLTextureType2DMultisample;
    textureDescriptor.sampleCount = 2; textureDescriptor.usage = MTLTextureUsageRenderTarget;
    depth.texture = [device newTextureWithDescriptor:textureDescriptor];
    if (depth.texture == nil) return 77;
    pass.depthAttachment = depth; pass.stencilAttachment = stencil;
    if (pass.depthAttachment.texture.device.registryID != device.registryID
        || pass.depthAttachment.texture.sampleCount != 2) return 4;
    if ([device supportsRasterizationRateMapWithLayerCount:1]) {
      MTLSize counts = MTLSizeMake(1, 1, 0); float rate = 1.0f;
      MTLRasterizationRateLayerDescriptor *layer =
        [[MTLRasterizationRateLayerDescriptor alloc] initWithSampleCount:counts
          horizontal:&rate vertical:&rate];
      MTLRasterizationRateMapDescriptor *mapDescriptor =
        [MTLRasterizationRateMapDescriptor
          rasterizationRateMapDescriptorWithScreenSize:MTLSizeMake(8, 8, 0) layer:layer];
      id<MTLRasterizationRateMap> map =
        [device newRasterizationRateMapWithDescriptor:mapDescriptor];
      if (map == nil) return 77;
      __weak id<MTLRasterizationRateMap> weak = map;
      pass.rasterizationRateMap = map; map = nil;
      if (weak == nil || pass.rasterizationRateMap.device.registryID != device.registryID)
        return 5;
    }
    pass.depthAttachment = nil; pass.stencilAttachment = nil;
    if (pass.depthAttachment == nil || pass.stencilAttachment == nil) return 6;
  }
  return 0;
} }
