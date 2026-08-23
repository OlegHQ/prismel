#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "metal_io_counter_ownership_materializers.inc"
int main(){@autoreleasepool{
 NSString*f=nil;if(prismel_counter_descriptor(nil,1,nil,&f)!=nil||!f)return 1;
 f=nil;if(prismel_blit_pass(nil,0,0,&f)==nil)return 2;
 id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;
 if(d.counterSets.count){id<MTLCounterSet>s=d.counterSets[0];MTLCounterSampleBufferDescriptor*x=prismel_counter_descriptor(s,4,@"counter",&f);if(!x||x.counterSet!=s||x.sampleCount!=4||![x.label isEqual:@"counter"]||s.counters.count==0||s.counters[0].name.length==0)return 3;NSError*e=nil;id<MTLCounterSampleBuffer>b=[d newCounterSampleBufferWithDescriptor:x error:&e];if(!b&&e==nil)return 4;}
 if(@available(macOS 13.0,*)){
  MTLIOCommandQueueDescriptor*qdesc=[MTLIOCommandQueueDescriptor new];qdesc.type=MTLIOCommandQueueTypeConcurrent;qdesc.maxCommandBufferCount=2;qdesc.maxCommandsInFlight=1;NSError*e=nil;id<MTLIOCommandQueue>q=[d newIOCommandQueueWithDescriptor:qdesc error:&e];
  if(q){q.label=@"io-queue";if(![q.label isEqual:@"io-queue"])return 5;[q enqueueBarrier];id<MTLIOCommandBuffer>c=[q commandBufferWithUnretainedReferences];if(!c)return 6;c.label=@"io-command";if(![c.label isEqual:@"io-command"]||c.error!=nil)return 7;[c pushDebugGroup:@"io-test"];[c popDebugGroup];[c addBarrier];id<MTLBuffer>status=[d newBufferWithLength:sizeof(MTLIOStatus) options:MTLResourceStorageModeShared];if(!status)return 8;[c copyStatusToBuffer:status offset:0];__block int completed=0;[c addCompletedHandler:^(id<MTLIOCommandBuffer>done){if(done==c)completed++;}];[c commit];[c waitUntilCompleted];if(c.status!=MTLIOStatusComplete||completed!=1)return 9;
   const char payload[]="prismel";NSString*sourcePath=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".raw"]];if(![[NSData dataWithBytes:payload length:sizeof(payload)]writeToFile:sourcePath atomically:YES])return 10;id<MTLIOFileHandle>source=[d newIOFileHandleWithURL:[NSURL fileURLWithPath:sourcePath] error:&e];if(!source)return 11;char loaded[sizeof(payload)]={0};id<MTLIOCommandBuffer>load=[q commandBuffer];[load loadBytes:loaded size:sizeof(loaded) sourceHandle:source sourceHandleOffset:0];[load commit];[load waitUntilCompleted];[[NSFileManager defaultManager]removeItemAtPath:sourcePath error:nil];if(load.status!=MTLIOStatusComplete||memcmp(loaded,payload,sizeof(payload)))return 12;
  }else if(!e)return 13;
  NSString*path=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".mtlio"]];MTLIOCompressionContext z=MTLIOCreateCompressionContext(path.fileSystemRepresentation,MTLIOCompressionMethodZlib,MTLIOCompressionContextDefaultChunkSize());if(!z)return 14;const char payload[]="prismel";MTLIOCompressionContextAppendData(z,payload,sizeof(payload));if(MTLIOFlushAndDestroyCompressionContext(z)!=MTLIOCompressionStatusComplete)return 15;[[NSFileManager defaultManager]removeItemAtPath:path error:nil];
 }
 return 0;
}}
