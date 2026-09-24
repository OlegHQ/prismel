#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cassert>

static void require(bool value, NSString *message) { if (!value) @throw [NSException exceptionWithName:@"Resource100" reason:message userInfo:nil]; }
int main(){@autoreleasepool{
 id<MTLDevice> device=MTLCreateSystemDefaultDevice();if(!device)return 77;
 for(NSUInteger i=0;i<10000;i++){@autoreleasepool{
  MTLBufferLayoutDescriptor *layout=[MTLBufferLayoutDescriptor new];layout.stride=16;layout.stepRate=1;layout.stepFunction=MTLStepFunctionPerVertex;
  require(layout.stride==16&&layout.stepRate==1&&layout.stepFunction==MTLStepFunctionPerVertex,@"layout round trip");
  MTLResourceStatePassSampleBufferAttachmentDescriptor *sample=[MTLResourceStatePassSampleBufferAttachmentDescriptor new];sample.startOfEncoderSampleIndex=MTLCounterDontSample;sample.endOfEncoderSampleIndex=MTLCounterDontSample;require(sample.sampleBuffer==nil,@"nullable sample buffer");
 }}
 id<MTLBuffer> buffer=[device newBufferWithLength:4096 options:MTLResourceStorageModeShared];require(buffer!=nil,@"buffer allocation");
 require(buffer.device.registryID==device.registryID,@"buffer device identity");
 id<MTLBuffer> remote=[buffer newRemoteBufferViewForDevice:device];if(remote){require(remote.length==buffer.length,@"remote buffer metadata");require(remote.storageMode==buffer.storageMode,@"remote buffer storage");}
 MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:8 height:8 mipmapped:NO];td.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;id<MTLTexture> texture=[device newTextureWithDescriptor:td];require(texture!=nil,@"texture allocation");
 id<MTLTexture> view=[texture newTextureViewWithPixelFormat:texture.pixelFormat];require(view!=nil,@"texture view");require(view.width==8&&view.height==8&&view.rootResource!=nil,@"texture/root metadata");
 MTLTextureDescriptor *bufferTD=[MTLTextureDescriptor textureBufferDescriptorWithPixelFormat:MTLPixelFormatR32Uint width:16 resourceOptions:MTLResourceStorageModeShared usage:MTLTextureUsageShaderRead];id<MTLTexture> bufferTexture=[buffer newTextureWithDescriptor:bufferTD offset:64 bytesPerRow:256];require(bufferTexture!=nil&&bufferTexture.buffer==buffer&&bufferTexture.bufferOffset==64&&bufferTexture.bufferBytesPerRow==256,@"buffer-backed texture graph");
 id<MTLCommandQueue> queue=[device newCommandQueue];id<MTLCommandBuffer> commands=[queue commandBuffer];MTLResourceStatePassDescriptor *pass=[MTLResourceStatePassDescriptor resourceStatePassDescriptor];id<MTLResourceStateCommandEncoder> encoder=[commands resourceStateCommandEncoderWithDescriptor:pass];require(encoder!=nil,@"state encoder");[encoder endEncoding];[commands commit];[commands waitUntilCompleted];require(commands.status==MTLCommandBufferStatusCompleted,@"state completion");
 if(@available(macOS 26.0,*)){MTLResourceViewPoolDescriptor *pd=[MTLResourceViewPoolDescriptor new];pd.resourceViewCount=4;NSError*error=nil;id<MTLTextureViewPool>pool=[device newTextureViewPoolWithDescriptor:pd error:&error];require(pool!=nil||error!=nil,@"view-pool nullable/error contract");}
 NSLog(@"resource100 native: descriptor/view/root/state/availability/10k passed");return 0;
}}
