#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <type_traits>
static_assert(std::is_same_v<decltype([MTLAccelerationStructurePassDescriptor accelerationStructurePassDescriptor].sampleBufferAttachments),MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray*>);
static bool valid_attachment(NSUInteger count,NSUInteger start,NSUInteger finish){return start<=finish&&finish<count;}
static bool valid_arrays(NSUInteger heapCount,NSUInteger resourceCount,const bool*devices){for(NSUInteger i=0;i<heapCount+resourceCount;i++)if(!devices[i])return false;return true;}
int main(){@autoreleasepool{
 if(valid_attachment(4,3,2)||valid_attachment(4,0,4)||!valid_attachment(4,1,3))return 1;
 bool mismatch[3]={true,false,true};if(valid_arrays(1,2,mismatch))return 2;
 MTLAccelerationStructurePassDescriptor*d=[MTLAccelerationStructurePassDescriptor accelerationStructurePassDescriptor];if(!d||!d.sampleBufferAttachments)return 3;
 MTLAccelerationStructurePassSampleBufferAttachmentDescriptor*a=d.sampleBufferAttachments[0];a.startOfEncoderSampleIndex=1;a.endOfEncoderSampleIndex=2;if(a.startOfEncoderSampleIndex!=1||a.endOfEncoderSampleIndex!=2)return 4;
 return 0;
}}
