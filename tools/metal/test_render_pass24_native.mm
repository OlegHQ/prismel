#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kIds[] = {
  "class:MTLRenderPassDescriptor",
  "class:MTLRenderPassSampleBufferAttachmentDescriptor",
  "class:MTLRenderPassSampleBufferAttachmentDescriptorArray",
  "method:-[MTLRenderPassAttachmentDescriptor resolveTexture]",
  "method:-[MTLRenderPassAttachmentDescriptor setResolveTexture:]",
  "method:-[MTLRenderPassColorAttachmentDescriptorArray setObject:atIndexedSubscript:]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptor endOfFragmentSampleIndex]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptor endOfVertexSampleIndex]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptor sampleBuffer]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptor setEndOfFragmentSampleIndex:]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptor setEndOfVertexSampleIndex:]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptor setSampleBuffer:]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptor setStartOfFragmentSampleIndex:]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptor setStartOfVertexSampleIndex:]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptor startOfFragmentSampleIndex]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptor startOfVertexSampleIndex]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptorArray objectAtIndexedSubscript:]",
  "method:-[MTLRenderPassSampleBufferAttachmentDescriptorArray setObject:atIndexedSubscript:]",
  "property:MTLRenderPassAttachmentDescriptor:resolveTexture",
  "property:MTLRenderPassSampleBufferAttachmentDescriptor:endOfFragmentSampleIndex",
  "property:MTLRenderPassSampleBufferAttachmentDescriptor:endOfVertexSampleIndex",
  "property:MTLRenderPassSampleBufferAttachmentDescriptor:sampleBuffer",
  "property:MTLRenderPassSampleBufferAttachmentDescriptor:startOfFragmentSampleIndex",
  "property:MTLRenderPassSampleBufferAttachmentDescriptor:startOfVertexSampleIndex",
};
static_assert(sizeof(kIds)/sizeof(kIds[0])==24,"RenderPass24 closure drift");

int main(){@autoreleasepool{
  id<MTLDevice>device=MTLCreateSystemDefaultDevice();if(!device)return 77;
  MTLTextureDescriptor*msaa=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
  msaa.textureType=MTLTextureType2DMultisample;msaa.sampleCount=4;msaa.usage=MTLTextureUsageRenderTarget;
  MTLTextureDescriptor*resolved=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
  resolved.usage=MTLTextureUsageRenderTarget;
  id<MTLTexture>color=[device newTextureWithDescriptor:msaa],resolve=[device newTextureWithDescriptor:resolved];
  if(!color||!resolve)return 77;
  MTLRenderPassDescriptor*pass=[MTLRenderPassDescriptor renderPassDescriptor];
  MTLRenderPassColorAttachmentDescriptor*source=[MTLRenderPassColorAttachmentDescriptor new];
  source.texture=color;source.resolveTexture=resolve;source.loadAction=MTLLoadActionClear;source.storeAction=MTLStoreActionMultisampleResolve;
  [pass.colorAttachments setObject:source atIndexedSubscript:0];
  MTLRenderPassColorAttachmentDescriptor*stored=pass.colorAttachments[0];
  if(!stored||stored==source||stored.resolveTexture!=resolve)return 1;
  [pass.sampleBufferAttachments setObject:nil atIndexedSubscript:0];
  MTLRenderPassSampleBufferAttachmentDescriptor*reset=pass.sampleBufferAttachments[0];
  if(!reset||reset.sampleBuffer!=nil)return 2;
  id<MTLCommandBuffer>command=[[device newCommandQueue]commandBuffer];
  id<MTLRenderCommandEncoder>encoder=[command renderCommandEncoderWithDescriptor:pass];
  if(!encoder)return 3;[encoder endEncoding];[command commit];[command waitUntilCompleted];
  if(command.status!=MTLCommandBufferStatusCompleted)return 4;
  return 0;
}}
