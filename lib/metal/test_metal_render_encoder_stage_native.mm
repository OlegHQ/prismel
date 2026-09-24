#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cassert>
#include <cstdint>

static id<MTLRenderPipelineState> pipeline(id<MTLDevice> device) {
  NSError *error = nil;
  NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
    "vertex float4 v(uint i [[vertex_id]], constant float2 *p [[buffer(0)]]) { "
    "float2 q[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(q[i]+p[0],0,1); }\n"
    "fragment float4 f(constant float4 *c [[buffer(0)]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) { return c[0] + t.sample(s,float2(.5)); }";
  id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
  assert(library != nil && error == nil);
  MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
  descriptor.vertexFunction = [library newFunctionWithName:@"v"];
  descriptor.fragmentFunction = [library newFunctionWithName:@"f"];
  descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  id<MTLRenderPipelineState> result = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
  assert(result != nil && error == nil);
  return result;
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    assert(device != nil);
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    td.storageMode = MTLStorageModeShared;
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    id<MTLTexture> target = [device newTextureWithDescriptor:td];
    id<MTLTexture> sampled = [device newTextureWithDescriptor:td];
    uint8_t zero[64] = {};
    [sampled replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 withBytes:zero bytesPerRow:16];
    MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
    id<MTLSamplerState> sampler = [device newSamplerStateWithDescriptor:sd];
    id<MTLBuffer> buffer = [device newBufferWithLength:64 options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = [[device newCommandQueue] commandBuffer];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:pass];
    [e setRenderPipelineState:pipeline(device)];
    float offset[2] = {0,0}; float color[4] = {0.25f,0.5f,0.75f,1};
    [e setVertexBytes:&offset length:sizeof(offset) atIndex:0];
    [e setFragmentBytes:&color length:sizeof(color) atIndex:0];
    [e setVertexBuffer:buffer offset:0 atIndex:1];
    [e setVertexBufferOffset:16 atIndex:1];
    [e setFragmentBuffer:buffer offset:0 atIndex:1];
    [e setFragmentBufferOffset:16 atIndex:1];
    id<MTLBuffer> buffers[] = {buffer}; NSUInteger offsets[] = {0};
    [e setVertexBuffers:buffers offsets:offsets withRange:NSMakeRange(1,1)];
    [e setFragmentBuffers:buffers offsets:offsets withRange:NSMakeRange(1,1)];
    [e setVertexTexture:sampled atIndex:0]; [e setFragmentTexture:sampled atIndex:0];
    id<MTLTexture> textures[] = {sampled};
    [e setVertexTextures:textures withRange:NSMakeRange(0,1)];
    [e setFragmentTextures:textures withRange:NSMakeRange(0,1)];
    [e setVertexSamplerState:sampler atIndex:0];
    [e setFragmentSamplerState:sampler atIndex:0];
    [e setVertexSamplerState:sampler lodMinClamp:0 lodMaxClamp:0 atIndex:0];
    [e setFragmentSamplerState:sampler lodMinClamp:0 lodMaxClamp:0 atIndex:0];
    id<MTLSamplerState> samplers[] = {sampler}; float mins[] = {0}, maxs[] = {0};
    [e setVertexSamplerStates:samplers withRange:NSMakeRange(0,1)];
    [e setFragmentSamplerStates:samplers withRange:NSMakeRange(0,1)];
    [e setVertexSamplerStates:samplers lodMinClamps:mins lodMaxClamps:maxs withRange:NSMakeRange(0,1)];
    [e setFragmentSamplerStates:samplers lodMinClamps:mins lodMaxClamps:maxs withRange:NSMakeRange(0,1)];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
    assert(cb.status == MTLCommandBufferStatusCompleted);
    uint8_t pixel[4] = {}; [target getBytes:pixel bytesPerRow:4 fromRegion:MTLRegionMake2D(2,2,1,1) mipmapLevel:0];
    assert(pixel[0] == 64 && pixel[1] == 128 && pixel[2] == 191 && pixel[3] == 255);
  }
  return 0;
}
