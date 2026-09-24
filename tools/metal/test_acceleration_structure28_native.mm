#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cstddef>
#include <cstring>
#include <type_traits>
static_assert(std::is_standard_layout_v<MTLAccelerationStructureInstanceDescriptor>);
static_assert(std::is_standard_layout_v<MTLAccelerationStructureUserIDInstanceDescriptor>);
static_assert(std::is_standard_layout_v<MTLAccelerationStructureMotionInstanceDescriptor>);
static_assert(std::is_standard_layout_v<MTLIndirectAccelerationStructureInstanceDescriptor>);
static_assert(std::is_standard_layout_v<MTLIndirectAccelerationStructureMotionInstanceDescriptor>);
static_assert(sizeof(MTLAccelerationStructureInstanceDescriptor)==64);
static_assert(sizeof(MTLAccelerationStructureUserIDInstanceDescriptor)==68);
static_assert(sizeof(MTLAccelerationStructureMotionInstanceDescriptor)==44);
static_assert(sizeof(MTLIndirectAccelerationStructureInstanceDescriptor)==72);
static_assert(sizeof(MTLIndirectAccelerationStructureMotionInstanceDescriptor)==48);
static bool range(NSUInteger total,NSInteger offset,NSInteger count,NSInteger stride,NSInteger element){if(offset<0||count<0||stride<element||stride<=0)return false;if(count==0)return (NSUInteger)offset<=total;NSUInteger n=(NSUInteger)count;if(n-1>(NSUIntegerMax-(NSUInteger)element)/(NSUInteger)stride)return false;NSUInteger bytes=(n-1)*(NSUInteger)stride+(NSUInteger)element;return (NSUInteger)offset<=total&&bytes<=total-(NSUInteger)offset;}
static bool triangle_format(MTLAttributeFormat format,NSUInteger stride){return format==MTLAttributeFormatFloat3&&stride>=12&&stride%4==0;}
int main(){@autoreleasepool{
 if(range(64,-1,1,12,12)||range(64,0,2,4,12)||range(16,0,2,12,12)||!range(64,4,3,16,12))return 1;if(triangle_format(MTLAttributeFormatFloat2,12)||triangle_format(MTLAttributeFormatFloat3,10)||!triangle_format(MTLAttributeFormatFloat3,16))return 2;
 MTLAccelerationStructureTriangleGeometryDescriptor*t=[MTLAccelerationStructureTriangleGeometryDescriptor descriptor];MTLAccelerationStructureBoundingBoxGeometryDescriptor*b=[MTLAccelerationStructureBoundingBoxGeometryDescriptor descriptor];MTLAccelerationStructureCurveGeometryDescriptor*c=[MTLAccelerationStructureCurveGeometryDescriptor descriptor];MTLAccelerationStructureMotionTriangleGeometryDescriptor*mt=[MTLAccelerationStructureMotionTriangleGeometryDescriptor descriptor];MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor*mb=[MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor descriptor];MTLAccelerationStructureMotionCurveGeometryDescriptor*mc=[MTLAccelerationStructureMotionCurveGeometryDescriptor descriptor];MTLInstanceAccelerationStructureDescriptor*i=[MTLInstanceAccelerationStructureDescriptor descriptor];MTLIndirectInstanceAccelerationStructureDescriptor*ii=[MTLIndirectInstanceAccelerationStructureDescriptor descriptor];MTLMotionKeyframeData*k=[MTLMotionKeyframeData data];MTLPrimitiveAccelerationStructureDescriptor*p=[MTLPrimitiveAccelerationStructureDescriptor descriptor];if(!t||!b||!c||!mt||!mb||!mc||!i||!ii||!k||!p)return 3;
 id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;id<MTLBuffer>vertices=[d newBufferWithLength:64 options:MTLResourceStorageModeShared];t.vertexBuffer=vertices;t.vertexBufferOffset=4;t.vertexStride=16;t.triangleCount=1;t.vertexFormat=MTLAttributeFormatFloat3;if(t.vertexBuffer.device.registryID!=d.registryID||!range(t.vertexBuffer.length,t.vertexBufferOffset,3,t.vertexStride,12))return 4;
 p.geometryDescriptors=@[t];if(p.geometryDescriptors.count!=1)return 5;id<MTLBuffer>instances=[d newBufferWithLength:128 options:MTLResourceStorageModeShared];i.instanceCount=2;i.instanceDescriptorBuffer=instances;i.instanceDescriptorStride=sizeof(MTLAccelerationStructureInstanceDescriptor);if(!range(instances.length,0,i.instanceCount,i.instanceDescriptorStride,sizeof(MTLAccelerationStructureInstanceDescriptor)))return 6;k.buffer=vertices;k.offset=8;if(k.buffer.device.registryID!=d.registryID||k.offset!=8)return 7;
 MTLAccelerationStructureInstanceDescriptor value={};value.mask=0x7f;value.accelerationStructureIndex=3;value.intersectionFunctionTableOffset=5;MTLAccelerationStructureInstanceDescriptor copy;memcpy(&copy,&value,sizeof(value));if(memcmp(&copy,&value,sizeof(value))||copy.mask!=0x7f||copy.accelerationStructureIndex!=3)return 8;
 MTLAccelerationStructureMotionInstanceDescriptor motion={};motion.mask=9;motion.motionTransformsCount=2;motion.motionStartTime=0.25f;motion.motionEndTime=0.75f;MTLAccelerationStructureMotionInstanceDescriptor motion_copy;memcpy(&motion_copy,&motion,sizeof(motion));if(memcmp(&motion,&motion_copy,sizeof(motion))||motion_copy.motionTransformsCount!=2)return 9;
 if(vertices.device.registryID==d.registryID+1)return 10;return 0;}}
