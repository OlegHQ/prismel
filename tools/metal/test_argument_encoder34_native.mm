#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <type_traits>
static_assert(MTLAttributeStrideStatic == NSUIntegerMax);
static_assert(std::is_same_v<decltype(((id<MTLArgumentEncoder>)nil).encodedLength),NSUInteger>);
static bool valid_cardinality(NSUInteger objects,NSUInteger offsets,NSRange range,bool buffers){return range.length==objects&&(buffers?offsets==objects:offsets==0);}
int main(){@autoreleasepool{
 if(valid_cardinality(2,1,NSMakeRange(0,2),true))return 1;
 if(valid_cardinality(2,0,NSMakeRange(0,1),false))return 2;
 if(!valid_cardinality(2,2,NSMakeRange(3,2),true))return 3;
 id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;
 NSError*e=nil;id<MTLLibrary>l=[d newLibraryWithSource:@"struct A{device uint*x;};kernel void k(device A&a[[buffer(0)]]){}" options:nil error:&e];if(!l)return 4;id<MTLFunction>f=[l newFunctionWithName:@"k"];if(!f)return 5;id<MTLArgumentEncoder>a=[f newArgumentEncoderWithBufferIndex:0];if(!a)return 77;
 a.label=@"argument34";if(![a.label isEqual:@"argument34"]||a.device!=d||a.encodedLength==0||a.alignment==0)return 6;
 id<MTLBuffer>b=[d newBufferWithLength:a.encodedLength options:MTLResourceStorageModeShared];[a setArgumentBuffer:b offset:0];
 return 0;
}}
