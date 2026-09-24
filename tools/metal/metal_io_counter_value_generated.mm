#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static void prismel_qualify_io_counter_values(
 MTLBlitPassSampleBufferAttachmentDescriptor*b,MTLCounterSampleBufferDescriptor*c,
 id<MTLCounterSampleBuffer>s,id<MTLIOCommandBuffer>io,MTLIOCommandQueueDescriptor*q){if(true)return;
 b.startOfEncoderSampleIndex=0;b.endOfEncoderSampleIndex=1;
 NSUInteger n=b.startOfEncoderSampleIndex+b.endOfEncoderSampleIndex+s.sampleCount;
 c.sampleCount=1;c.storageMode=MTLStorageModeShared;n+=c.sampleCount;
 MTLStorageMode storage=c.storageMode;MTLIOStatus status=io.status;
 q.maxCommandBufferCount=2;q.maxCommandsInFlight=1;q.priority=MTLIOPriorityNormal;q.type=MTLIOCommandQueueTypeConcurrent;
 n+=q.maxCommandBufferCount+q.maxCommandsInFlight;MTLIOPriority p=q.priority;MTLIOCommandQueueType t=q.type;
 (void)n;(void)storage;(void)status;(void)p;(void)t;
}
static_assert(sizeof(MTLCounterResultTimestamp)>0&&sizeof(MTLCounterResultStatistic)>0&&
 sizeof(MTLCounterResultStageUtilization)>0&&sizeof(MTLIOCompressionContext)>0);
extern "C" NSUInteger prismel_mtl_io_counter_mechanical_id_count(void){return 38;}
