#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cstddef>
#include <type_traits>
static_assert(std::is_standard_layout_v<MTL4CopySparseBufferMappingOperation>);static_assert(sizeof(MTL4CopySparseBufferMappingOperation)==24);static_assert(std::is_standard_layout_v<MTL4CopySparseTextureMappingOperation>);static_assert(sizeof(MTL4CopySparseTextureMappingOperation)==104);
static bool range(NSUInteger total,NSInteger offset,NSInteger length){return offset>=0&&length>0&&(NSUInteger)offset<=total&&(NSUInteger)length<=total-(NSUInteger)offset;}
int main(){@autoreleasepool{if(range(8,-1,1)||range(8,7,2)||!range(8,2,6))return 1;MTL4CopySparseBufferMappingOperation b={NSMakeRange(2,4),8};if(b.sourceRange.location!=2||b.sourceRange.length!=4||b.destinationOffset!=8)return 2;MTL4CopySparseTextureMappingOperation t={MTLRegionMake2D(1,2,3,4),0,0,MTLOriginMake(5,6,0),1,0};if(t.sourceRegion.size.width!=3||t.destinationOrigin.x!=5||t.destinationLevel!=1)return 3;if(@available(macOS 26.0,*)){id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;id<MTL4CommandQueue>q=[d newMTL4CommandQueue];if(!q)return 77;if(q.device.registryID!=d.registryID)return 4;id<MTLSharedEvent>event=[d newSharedEvent];if(!event)return 77;[q signalEvent:event value:1];[q waitForEvent:event value:1];}return 0;}}
