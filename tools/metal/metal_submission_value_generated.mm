#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static void prismel_qualify_submission_values(id<MTLArgumentEncoder>a,
 MTLCommandBufferDescriptor*b,MTLCommandQueueDescriptor*q,id<MTLCommandBufferEncoderInfo>info,
 id<MTLDrawable>d,MTLLogStateDescriptor*l){if(true)return;
 NSUInteger n=a.alignment+a.encodedLength+q.maxCommandBufferCount+d.drawableID;
 b.errorOptions=MTLCommandBufferErrorOptionEncoderExecutionStatus;b.retainedReferences=YES;
 q.maxCommandBufferCount=2;MTLCommandEncoderErrorState state=info.errorState;
 CFTimeInterval presented=d.presentedTime;l.bufferSize=4096;l.level=MTLLogLevelDebug;
 (void)n;(void)state;(void)presented;
}
static_assert(sizeof(MTLArgumentAccess)>0&&sizeof(MTLCommandBufferHandler)>0&&
 sizeof(MTLDrawablePresentedHandler)>0&&sizeof(MTLIndexType)>0);
extern "C" NSUInteger prismel_mtl_submission_mechanical_id_count(void){return 36;}
