#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static bool valid_range(NSUInteger total,NSInteger offset,NSInteger length){return offset>=0&&length>=0&&(NSUInteger)offset<=total&&(NSUInteger)length<=total-(NSUInteger)offset;}
int main(){@autoreleasepool{
 if(valid_range(8,-1,1)||valid_range(8,7,2)||!valid_range(8,2,6))return 1;
 id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;id<MTLCommandQueue>q=[d newCommandQueue];id<MTLCommandBuffer>c=[q commandBuffer];id<MTLBlitCommandEncoder>b=[c blitCommandEncoder];id<MTLBuffer>x=[d newBufferWithLength:16 options:MTLResourceStorageModeShared];id<MTLBuffer>y=[d newBufferWithLength:16 options:MTLResourceStorageModeShared];[b fillBuffer:x range:NSMakeRange(0,16) value:0x5a];[b copyFromBuffer:x sourceOffset:0 toBuffer:y destinationOffset:0 size:16];[b endEncoding];[c commit];[c waitUntilCompleted];for(int i=0;i<16;i++)if(((uint8_t*)y.contents)[i]!=0x5a)return 2;return 0;
}}
