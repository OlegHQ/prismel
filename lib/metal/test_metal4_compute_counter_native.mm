#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#include "../../tools/metal/metal4_compute_owner_generated.inc"
#pragma clang diagnostic pop
static void need(bool x,NSString*m){if(!x)@throw[NSException exceptionWithName:@"Metal4Callable" reason:m userInfo:nil];}
int main(){@autoreleasepool{
 id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;
 if(@available(macOS 26.0,*)){
  if(![d supportsFamily:MTLGPUFamilyMetal4])return 77;
  MTL4RenderPipelineBinaryFunctionsDescriptor*binary=[MTL4RenderPipelineBinaryFunctionsDescriptor new];
  binary.vertexAdditionalBinaryFunctions=@[];binary.fragmentAdditionalBinaryFunctions=@[];
  binary.tileAdditionalBinaryFunctions=@[];binary.objectAdditionalBinaryFunctions=@[];
  binary.meshAdditionalBinaryFunctions=@[];
  need(binary.vertexAdditionalBinaryFunctions.count==0&&binary.meshAdditionalBinaryFunctions.count==0,@"binary descriptor roundtrip");[binary reset];
  MTL4MachineLearningPipelineDescriptor*ml=[MTL4MachineLearningPipelineDescriptor new];ml.label=@"ml";NSInteger dims[]={2,3};MTLTensorExtents*ext=[[MTLTensorExtents alloc]initWithRank:2 values:dims];[ml setInputDimensions:ext atBufferIndex:0];MTLTensorExtents*stored=[ml inputDimensionsAtBufferIndex:0];need([ml.label isEqual:@"ml"]&&stored.rank==2&&[stored extentAtDimensionIndex:1]==3,@"ML descriptor/extents roundtrip");[ml reset];
  MTL4SpecializedFunctionDescriptor*specialized=[MTL4SpecializedFunctionDescriptor new];specialized.specializedName=@"specialized";specialized.constantValues=[MTLFunctionConstantValues new];need([specialized.specializedName isEqual:@"specialized"]&&specialized.constantValues!=nil,@"specialized descriptor roundtrip");
  MTL4CounterHeapDescriptor*hd=[MTL4CounterHeapDescriptor new];hd.type=MTL4CounterHeapTypeTimestamp;hd.count=8;
  need(hd.type==MTL4CounterHeapTypeTimestamp&&hd.count==8,@"counter descriptor roundtrip");
  NSError*error=nil;id<MTL4CounterHeap>heap=[d newCounterHeapWithDescriptor:hd error:&error];need(heap!=nil,error.localizedDescription?:@"counter heap");heap.label=@"m4-counter";need(heap.count==8&&heap.type==MTL4CounterHeapTypeTimestamp&&[heap.label isEqual:@"m4-counter"],@"counter properties");[heap invalidateCounterRange:NSMakeRange(0,1)];
  MTL4CommandAllocatorDescriptor*ad=[MTL4CommandAllocatorDescriptor new];id<MTL4CommandAllocator>a=[d newCommandAllocatorWithDescriptor:ad error:&error];need(a!=nil,error.localizedDescription?:@"allocator");
  id<MTL4CommandBuffer>b=[d newCommandBuffer];[b beginCommandBufferWithAllocator:a];[b pushDebugGroup:@"buffer"];[b popDebugGroup];id<MTL4ComputeCommandEncoder>e=b.computeCommandEncoder;need(e!=nil,@"compute encoder");
  [e pushDebugGroup:@"callable"];[e insertDebugSignpost:@"compute"];
  id<MTLBuffer>x=[d newBufferWithLength:1024 options:MTLResourceStorageModeShared];id<MTLBuffer>y=[d newBufferWithLength:1024 options:MTLResourceStorageModeShared];
  MTL4AccelerationStructureTriangleGeometryDescriptor*geometry=[MTL4AccelerationStructureTriangleGeometryDescriptor new];geometry.vertexBuffer=MTL4BufferRangeMake(x.gpuAddress,36);geometry.vertexFormat=MTLAttributeFormatFloat3;geometry.vertexStride=12;geometry.triangleCount=1;MTL4PrimitiveAccelerationStructureDescriptor*accel=[MTL4PrimitiveAccelerationStructureDescriptor new];accel.geometryDescriptors=@[geometry];need(accel.geometryDescriptors.count==1,@"owned acceleration descriptor graph");
  prismel_metal4_compute_fillbuffer_range_value_(e,x,NSMakeRange(0,256),7);
  prismel_metal4_compute_copyfrombuffer_sourceoffset_tobuffer_destinationoffset_size_(e,x,0,y,0,256);
  MTLTextureDescriptor*td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:YES];td.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;id<MTLTexture>t0=[d newTextureWithDescriptor:td];id<MTLTexture>t1=[d newTextureWithDescriptor:td];
  prismel_metal4_compute_copyfromtexture_totexture_(e,t0,t1);
  prismel_metal4_compute_copyfromtexture_sourceslice_sourcelevel_sourceorigin_sourcesize_totexture_destinationslice_destinationlevel_destinationorigin_(e,t0,0,0,MTLOriginMake(0,0,0),MTLSizeMake(4,4,1),t1,0,0,MTLOriginMake(0,0,0));
  prismel_metal4_compute_generatemipmapsfortexture_(e,t0);prismel_metal4_compute_optimizecontentsforgpuaccess_(e,t0);prismel_metal4_compute_optimizecontentsforcpuaccess_(e,t0);
  (void)prismel_metal4_compute_stages(e);prismel_metal4_compute_writetimestampwithgranularity_intoheap_atindex_(e,MTL4TimestampGranularityRelaxed,heap,0);
  id<MTLFence>f=[d newFence];[e updateFence:f afterEncoderStages:MTLStageBlit];[e barrierAfterEncoderStages:MTLStageBlit beforeEncoderStages:MTLStageBlit visibilityOptions:MTL4VisibilityOptionNone];[e popDebugGroup];[e endEncoding];[b endCommandBuffer];
  MTL4CommandQueueDescriptor*qd=[MTL4CommandQueueDescriptor new];id<MTL4CommandQueue>q=[d newMTL4CommandQueueWithDescriptor:qd error:&error];need(q!=nil,error.localizedDescription?:@"queue");MTLResidencySetDescriptor*rd=[MTLResidencySetDescriptor new];rd.initialCapacity=1;id<MTLResidencySet>rs=[d newResidencySetWithDescriptor:rd error:&error];need(rs!=nil,error.localizedDescription?:@"residency");id<MTLResidencySet>sets[]={rs};[q addResidencySets:sets count:1];[q removeResidencySet:rs];[q addResidencySet:rs];[q removeResidencySets:sets count:1];
  NSLog(@"Metal4 callable native: compute/resource/counter/command lanes exercised");return 0;
 }return 77;
}}
