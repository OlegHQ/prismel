#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kIds[] = {
    "class:MTLAccelerationStructureBoundingBoxGeometryDescriptor",
    "class:MTLAccelerationStructureCurveGeometryDescriptor",
    "class:MTLAccelerationStructureDescriptor",
    "class:MTLAccelerationStructureGeometryDescriptor",
    "class:MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor",
    "class:MTLAccelerationStructureMotionCurveGeometryDescriptor",
    "class:MTLAccelerationStructureMotionTriangleGeometryDescriptor",
    "class:MTLAccelerationStructureTriangleGeometryDescriptor",
    "class:MTLIndirectInstanceAccelerationStructureDescriptor",
    "class:MTLInstanceAccelerationStructureDescriptor",
    "class:MTLMotionKeyframeData",
    "class:MTLPrimitiveAccelerationStructureDescriptor",
    "method:+[MTLAccelerationStructureBoundingBoxGeometryDescriptor descriptor]",
    "method:+[MTLAccelerationStructureCurveGeometryDescriptor descriptor]",
    "method:+[MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor descriptor]",
    "method:+[MTLAccelerationStructureMotionCurveGeometryDescriptor descriptor]",
    "method:+[MTLAccelerationStructureMotionTriangleGeometryDescriptor descriptor]",
    "method:+[MTLAccelerationStructureTriangleGeometryDescriptor descriptor]",
    "method:+[MTLIndirectInstanceAccelerationStructureDescriptor descriptor]",
    "method:+[MTLInstanceAccelerationStructureDescriptor descriptor]",
    "method:+[MTLMotionKeyframeData data]",
    "method:+[MTLPrimitiveAccelerationStructureDescriptor descriptor]",
    "protocol:MTLAccelerationStructure",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 23,
              "AccelerationStructure23 exact closure drift");

int main() {
  @autoreleasepool {
    (void)kIds;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    id<MTLBuffer> buffer =
        [device newBufferWithLength:4096 options:MTLResourceStorageModeShared];
    if (buffer == nil) return 77;

    MTLAccelerationStructureBoundingBoxGeometryDescriptor *box =
        [MTLAccelerationStructureBoundingBoxGeometryDescriptor descriptor];
    MTLAccelerationStructureCurveGeometryDescriptor *curve =
        [MTLAccelerationStructureCurveGeometryDescriptor descriptor];
    MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor *motion_box =
        [MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor descriptor];
    MTLAccelerationStructureMotionCurveGeometryDescriptor *motion_curve =
        [MTLAccelerationStructureMotionCurveGeometryDescriptor descriptor];
    MTLAccelerationStructureMotionTriangleGeometryDescriptor *motion_triangle =
        [MTLAccelerationStructureMotionTriangleGeometryDescriptor descriptor];
    MTLAccelerationStructureTriangleGeometryDescriptor *triangle =
        [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
    MTLIndirectInstanceAccelerationStructureDescriptor *indirect =
        [MTLIndirectInstanceAccelerationStructureDescriptor descriptor];
    MTLInstanceAccelerationStructureDescriptor *instances =
        [MTLInstanceAccelerationStructureDescriptor descriptor];
    MTLMotionKeyframeData *keyframe = [MTLMotionKeyframeData data];
    MTLPrimitiveAccelerationStructureDescriptor *primitive =
        [MTLPrimitiveAccelerationStructureDescriptor descriptor];
    if (!box || !curve || !motion_box || !motion_curve || !motion_triangle ||
        !triangle || !indirect || !instances || !keyframe || !primitive)
      return 1;

    triangle.vertexBuffer = buffer;
    triangle.vertexStride = 3 * sizeof(float);
    triangle.vertexFormat = MTLAttributeFormatFloat3;
    triangle.triangleCount = 1;
    primitive.geometryDescriptors = @[ triangle ];
    __weak MTLAccelerationStructureTriangleGeometryDescriptor *weak_triangle =
        triangle;
    triangle = nil;
    if (weak_triangle == nil || primitive.geometryDescriptors.count != 1)
      return 2;

    keyframe.buffer = buffer;
    keyframe.offset = 16;
    instances.instanceDescriptorBuffer = buffer;
    instances.instanceCount = 1;
    instances.instanceDescriptorStride =
        sizeof(MTLAccelerationStructureInstanceDescriptor);
    indirect.instanceDescriptorBuffer = buffer;
    indirect.instanceCountBuffer = buffer;
    if (keyframe.buffer != buffer || instances.instanceDescriptorBuffer != buffer ||
        indirect.instanceDescriptorBuffer != buffer ||
        indirect.instanceCountBuffer != buffer)
      return 3;

    if ([device supportsRaytracing]) {
      MTLAccelerationStructureSizes sizes =
          [device accelerationStructureSizesWithDescriptor:primitive];
      if (sizes.accelerationStructureSize == 0 ||
          sizes.buildScratchBufferSize == 0)
        return 4;
      id<MTLAccelerationStructure> structure =
          [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
      if (structure == nil || structure.device.registryID != device.registryID ||
          structure.size == 0)
        return 5;
    }
  }
  return 0;
}
