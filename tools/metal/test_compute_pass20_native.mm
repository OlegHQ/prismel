#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static bool valid_sample(NSUInteger count,NSInteger start,NSInteger finish){return start>=0&&finish>=start&&(NSUInteger)finish<count;}
int main(){@autoreleasepool{
 if(valid_sample(4,-1,1)||valid_sample(4,3,2)||valid_sample(4,0,4)||!valid_sample(4,1,3))return 1;
 MTLComputePassDescriptor*d=[MTLComputePassDescriptor computePassDescriptor];if(!d||!d.sampleBufferAttachments)return 2;d.dispatchType=MTLDispatchTypeConcurrent;if(d.dispatchType!=MTLDispatchTypeConcurrent)return 3;
 MTLComputePassSampleBufferAttachmentDescriptor*a=d.sampleBufferAttachments[0];a.sampleBuffer=nil;a.startOfEncoderSampleIndex=1;a.endOfEncoderSampleIndex=2;if(a.sampleBuffer||a.startOfEncoderSampleIndex!=1||a.endOfEncoderSampleIndex!=2)return 4;
 d.sampleBufferAttachments[0]=a;if(d.sampleBufferAttachments[0]!=a)return 5;
 return 0;
}}
