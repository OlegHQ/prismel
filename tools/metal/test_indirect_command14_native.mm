#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
struct RetentionSlot{__strong id object=nil;bool reset=false;void bind(id x){if(!reset)object=x;}void clear(){object=nil;reset=true;}};
static bool range(NSUInteger total,NSInteger offset,NSInteger bytes){return offset>=0&&bytes>=0&&(NSUInteger)offset<=total&&(NSUInteger)bytes<=total-(NSUInteger)offset;}
int main(){@autoreleasepool{
 if(range(8,-1,1)||range(8,7,2)||!range(8,2,6))return 1;
 RetentionSlot slot;__weak id weak=nil;@autoreleasepool{id x=[NSObject new];weak=x;slot.bind(x);}if(!weak)return 2;slot.clear();if(weak)return 3;
 id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;
 MTLIndirectCommandBufferDescriptor*desc=[MTLIndirectCommandBufferDescriptor new];desc.commandTypes=MTLIndirectCommandTypeDraw;desc.inheritBuffers=NO;desc.inheritPipelineState=YES;desc.maxVertexBufferBindCount=2;
 id<MTLIndirectCommandBuffer>icb=[d newIndirectCommandBufferWithDescriptor:desc maxCommandCount:1 options:0];if(!icb)return 77;id<MTLIndirectRenderCommand>c=[icb indirectRenderCommandAtIndex:0];id<MTLBuffer>b=[d newBufferWithLength:32 options:MTLResourceStorageModeShared];[c setVertexBuffer:b offset:0 atIndex:0];[c drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:1 baseInstance:0];[c reset];
 return 0;}}
