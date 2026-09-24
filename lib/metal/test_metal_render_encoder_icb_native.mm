#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cassert>
#include <cstring>

static id<MTLRenderPipelineState> make_pipeline(id<MTLDevice> d) {
  NSError *error=nil;
  NSString *s=@"#include <metal_stdlib>\nusing namespace metal; vertex float4 v(uint i [[vertex_id]]){float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return float4(p[i],0,1);} fragment float4 f(){return float4(1,0,0,1);}";
  id<MTLLibrary> l=[d newLibraryWithSource:s options:nil error:&error]; assert(l && !error);
  MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];
  pd.vertexFunction=[l newFunctionWithName:@"v"]; pd.fragmentFunction=[l newFunctionWithName:@"f"];
  pd.supportIndirectCommandBuffers=YES;
  pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
  id<MTLRenderPipelineState> p=[d newRenderPipelineStateWithDescriptor:pd error:&error]; assert(p && !error); return p;
}

int main(){ @autoreleasepool {
  id<MTLDevice> d=MTLCreateSystemDefaultDevice(); assert(d);
  MTLIndirectCommandBufferDescriptor *idc=[MTLIndirectCommandBufferDescriptor new];
  idc.commandTypes=MTLIndirectCommandTypeDraw; idc.inheritPipelineState=YES; idc.inheritBuffers=YES;
  id<MTLIndirectCommandBuffer> icb=[d newIndirectCommandBufferWithDescriptor:idc maxCommandCount:1 options:0];
  if(!icb) return 0;
  [[icb indirectRenderCommandAtIndex:0] drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:1 baseInstance:0];
  MTLIndirectCommandBufferExecutionRange range={0,1};
  id<MTLBuffer> rb=[d newBufferWithLength:sizeof(range) options:MTLResourceStorageModeShared];
  std::memcpy(rb.contents,&range,sizeof(range));
  MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:2 mipmapped:NO];
  td.usage=MTLTextureUsageRenderTarget; td.storageMode=MTLStorageModeShared;
  id<MTLTexture> target=[d newTextureWithDescriptor:td];
  MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture=target; pass.colorAttachments[0].storeAction=MTLStoreActionStore;
  id<MTLCommandBuffer> cb=[[d newCommandQueue] commandBuffer];
  id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];
  [e setRenderPipelineState:make_pipeline(d)];
  [e executeCommandsInBuffer:icb withRange:NSMakeRange(0,1)];
  // The indirect-range overload is exercised in a separate command buffer below.
  [e endEncoding]; [cb commit]; [cb waitUntilCompleted]; assert(cb.status==MTLCommandBufferStatusCompleted);
  uint8_t pixel[4]={}; [target getBytes:pixel bytesPerRow:4 fromRegion:MTLRegionMake2D(1,1,1,1) mipmapLevel:0];
  assert(pixel[0]==255 && pixel[1]==0 && pixel[2]==0 && pixel[3]==255);
  id<MTLCommandBuffer> cb2=[[d newCommandQueue] commandBuffer];
  id<MTLRenderCommandEncoder> e2=[cb2 renderCommandEncoderWithDescriptor:pass];
  [e2 setRenderPipelineState:make_pipeline(d)];
  [e2 executeCommandsInBuffer:icb indirectBuffer:rb indirectBufferOffset:0];
  [e2 endEncoding]; [cb2 commit]; [cb2 waitUntilCompleted]; assert(cb2.status==MTLCommandBufferStatusCompleted);
} return 0; }
