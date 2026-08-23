#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

#include <array>
#include <cstdio>

static bool render_once(id<MTLDevice> device) {
  NSError *error = nil;
  NSString *source =
      @"#include <metal_stdlib>\n"
       "using namespace metal;\n"
       "struct V { float4 position [[position]]; float4 color; };\n"
       "vertex V vmain(uint i [[vertex_id]], constant float4 *p [[buffer(0)]]) {\n"
       "  V o; o.position=p[i]; o.color=float4(0.2,0.4,0.8,1); return o;\n"
       "}\n"
       "fragment float4 fmain(V in [[stage_in]], constant float4 &t [[buffer(0)]]) {\n"
       "  return in.color*t;\n"
       "}\n";
  id<MTLLibrary> library = [device newLibraryWithSource:source
                                                options:nil
                                                  error:&error];
  if (library == nil || error != nil)
    return false;
  MTLRenderPipelineDescriptor *pipeline_descriptor =
      [MTLRenderPipelineDescriptor new];
  pipeline_descriptor.vertexFunction = [library newFunctionWithName:@"vmain"];
  pipeline_descriptor.fragmentFunction = [library newFunctionWithName:@"fmain"];
  pipeline_descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  id<MTLRenderPipelineState> pipeline =
      [device newRenderPipelineStateWithDescriptor:pipeline_descriptor
                                             error:&error];
  if (pipeline == nil || error != nil)
    return false;

  MTLTextureDescriptor *texture_descriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                        width:16
                                                       height:16
                                                    mipmapped:NO];
  texture_descriptor.storageMode = MTLStorageModeShared;
  texture_descriptor.usage = MTLTextureUsageRenderTarget;
  id<MTLTexture> texture = [device newTextureWithDescriptor:texture_descriptor];
  id<MTLCommandQueue> queue = [device newCommandQueue];
  id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
  MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture = texture;
  pass.colorAttachments[0].loadAction = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
  id<MTLRenderCommandEncoder> encoder =
      [command_buffer renderCommandEncoderWithDescriptor:pass];
  if (encoder == nil)
    return false;

  const std::array<vector_float4, 3> positions = {
      vector_float4{-1.f, -1.f, 0.f, 1.f},
      vector_float4{3.f, -1.f, 0.f, 1.f},
      vector_float4{-1.f, 3.f, 0.f, 1.f},
  };
  const vector_float4 tint = {1.f, 0.5f, 0.25f, 1.f};
  id<MTLBuffer> positions_buffer =
      [device newBufferWithBytes:positions.data()
                         length:sizeof(positions)
                        options:MTLResourceStorageModeShared];
  id<MTLBuffer> tint_buffer =
      [device newBufferWithBytes:&tint
                         length:sizeof(tint)
                        options:MTLResourceStorageModeShared];
  __weak id<MTLBuffer> weak_positions = positions_buffer;
  __weak id<MTLBuffer> weak_tint = tint_buffer;
  [encoder setRenderPipelineState:pipeline];
  [encoder setViewport:MTLViewport{0, 0, 16, 16, 0, 1}];
  [encoder setScissorRect:MTLScissorRect{0, 0, 16, 16}];
  [encoder setCullMode:MTLCullModeNone];
  [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
  [encoder setTriangleFillMode:MTLTriangleFillModeFill];
  [encoder setBlendColorRed:0 green:0 blue:0 alpha:0];
  [encoder setDepthBias:0 slopeScale:0 clamp:0];
  [encoder setStencilReferenceValue:0];
  [encoder setVertexBytes:positions.data()
                      length:sizeof(positions)
                     atIndex:0];
  [encoder setFragmentBytes:&tint length:sizeof(tint) atIndex:0];
  [encoder setVertexBuffer:positions_buffer offset:0 atIndex:0];
  [encoder setFragmentBuffer:tint_buffer offset:0 atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle
              vertexStart:0
              vertexCount:3
            instanceCount:1];
  [encoder endEncoding];
  positions_buffer = nil;
  tint_buffer = nil;
  if (weak_positions == nil || weak_tint == nil)
    return false;
  [command_buffer commit];
  [command_buffer waitUntilCompleted];
  if (command_buffer.status != MTLCommandBufferStatusCompleted ||
      command_buffer.error != nil)
    return false;

  std::array<unsigned char, 16 * 16 * 4> pixels{};
  [texture getBytes:pixels.data()
        bytesPerRow:16 * 4
         fromRegion:MTLRegionMake2D(0, 0, 16, 16)
        mipmapLevel:0];
  const std::size_t center = (8 * 16 + 8) * 4;
  const bool pixels_match = pixels[center] == 51 && pixels[center + 1] == 51 &&
         pixels[center + 2] == 51 && pixels[center + 3] == 255;
  encoder = nil;
  pass = nil;
  command_buffer = nil;
  return pixels_match && weak_positions == nil && weak_tint == nil;
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) {
      std::fprintf(stderr, "Metal render encoder skipped: no device\n");
      return 77;
    }
    if (!render_once(device)) {
      std::fprintf(stderr, "Metal render encoder deterministic render failed\n");
      return 1;
    }
    std::printf("Metal render encoder deterministic M1 render passed\n");
  }
  return 0;
}
