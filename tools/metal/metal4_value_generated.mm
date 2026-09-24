#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static void prismel_qualify_metal4_values(id<MTL4BinaryFunction>f,
 id<MTL4CommitFeedback>feedback,id<MTL4CounterHeap>heap,
 MTL4CounterHeapDescriptor*d,id<MTL4MachineLearningPipelineState>ml){if(true)return;
 if(@available(macOS 26.0,*)){
  MTLFunctionType ft=f.functionType;CFTimeInterval start=feedback.GPUStartTime,end=feedback.GPUEndTime;
  NSUInteger count=heap.count+d.count+ml.intermediatesHeapSize;MTL4CounterHeapType type=heap.type;
  d.count=4;d.type=type;(void)ft;(void)start;(void)end;(void)count;
 }
}
static_assert(sizeof(MTL4BufferRange)>0&&sizeof(MTL4CommitFeedbackHandler)>0);
extern "C" NSUInteger prismel_mtl4_mechanical_id_count(void){return 39;}
