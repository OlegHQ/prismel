#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cstddef>
#include <type_traits>
static_assert(std::is_standard_layout_v<MTLIntersectionFunctionBufferArguments>);
static_assert(sizeof(MTLIntersectionFunctionBufferArguments)==24);
static_assert(offsetof(MTLIntersectionFunctionBufferArguments,intersectionFunctionBuffer)==0);
static_assert(offsetof(MTLIntersectionFunctionBufferArguments,intersectionFunctionBufferSize)==8);
static_assert(offsetof(MTLIntersectionFunctionBufferArguments,intersectionFunctionStride)==16);
static bool range(NSInteger start,NSInteger count,NSInteger capacity){return start>=0&&count>=0&&capacity>=0&&start<=capacity&&count<=capacity-start;}
struct Slot{NSArray*values=nil;void replace(NSArray*x){values=[x copy];}void reset(){values=nil;}};
int main(){@autoreleasepool{if(range(-1,1,4)||range(3,2,4)||!range(1,3,4))return 1;MTLIntersectionFunctionBufferArguments value={11,22,33};if(value.intersectionFunctionBuffer!=11||value.intersectionFunctionBufferSize!=22||value.intersectionFunctionStride!=33)return 2;
 Slot slot;__weak NSObject*weak=nil;@autoreleasepool{NSObject*object=[NSObject new];weak=object;NSMutableArray*source=[NSMutableArray arrayWithObject:object];slot.replace(source);[source removeAllObjects];}if(!weak||slot.values.count!=1)return 3;slot.reset();if(weak)return 4;
 id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;id<MTLBuffer>b=[d newBufferWithLength:32 options:MTLResourceStorageModeShared];if(b.device.registryID!=d.registryID||!range(0,1,1))return 5;return 0;}}
