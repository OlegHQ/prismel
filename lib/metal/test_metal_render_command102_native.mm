#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static void require(bool ok, NSString *message) {
  if (!ok) @throw [NSException exceptionWithName:@"RenderCommand102" reason:message userInfo:nil];
}
int main(){@autoreleasepool{
 id<MTLDevice> device=MTLCreateSystemDefaultDevice();if(!device)return 77;
 NSError *error=nil;NSString *source=@"#include <metal_stdlib>\nusing namespace metal; struct O{float4 p[[position]];}; vertex O v(uint i[[vertex_id]]){float2 q[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return{float4(q[i],0,1)};} fragment float4 f(){return float4(1,0,0,1);}";
 id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];require(library!=nil,error.localizedDescription?:@"library");
 MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[library newFunctionWithName:@"v"];pd.fragmentFunction=[library newFunctionWithName:@"f"];pd.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
 id<MTLRenderPipelineState> pipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error];require(pipeline!=nil,error.localizedDescription?:@"pipeline");
 MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:8 height:8 mipmapped:NO];td.storageMode=MTLStorageModeShared;td.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;id<MTLTexture> target=[device newTextureWithDescriptor:td];require(target!=nil,@"target");
 MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
 MTLRenderPassSampleBufferAttachmentDescriptor *sample=[MTLRenderPassSampleBufferAttachmentDescriptor new];sample.startOfVertexSampleIndex=MTLCounterDontSample;sample.endOfFragmentSampleIndex=MTLCounterDontSample;require(sample.sampleBuffer==nil,@"sample nullability");
 id<MTLCommandBuffer> commands=[[device newCommandQueue] commandBuffer];id<MTLRenderCommandEncoder> encoder=[commands renderCommandEncoderWithDescriptor:pass];require(encoder!=nil,@"encoder");[encoder setRenderPipelineState:pipeline];[encoder setViewport:(MTLViewport){0,0,8,8,0,1}];[encoder setScissorRect:(MTLScissorRect){0,0,8,8}];[encoder setVertexBytes:"abcd" length:4 atIndex:0];[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[encoder endEncoding];[commands commit];[commands waitUntilCompleted];require(commands.status==MTLCommandBufferStatusCompleted,commands.error.localizedDescription?:@"completion");
 unsigned char pixel[4]={0};[target getBytes:pixel bytesPerRow:32 fromRegion:MTLRegionMake2D(4,4,1,1) mipmapLevel:0];require(pixel[2]>200&&pixel[3]>200,@"deterministic red draw");
 NSLog(@"render-command102 native: pipeline/stage/state/draw/sample/completion green");return 0;
}}
