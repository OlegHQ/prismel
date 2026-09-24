#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

int main() { @autoreleasepool {
  if (@available(macOS 26.0, *)) {
    NSArray *concrete = @[
      [MTL4AccelerationStructureBoundingBoxGeometryDescriptor new],
      [MTL4AccelerationStructureCurveGeometryDescriptor new],
      [MTL4AccelerationStructureMotionBoundingBoxGeometryDescriptor new],
      [MTL4AccelerationStructureMotionCurveGeometryDescriptor new],
      [MTL4AccelerationStructureMotionTriangleGeometryDescriptor new],
      [MTL4AccelerationStructureTriangleGeometryDescriptor new],
      [MTL4IndirectInstanceAccelerationStructureDescriptor new],
      [MTL4InstanceAccelerationStructureDescriptor new],
      [MTL4PrimitiveAccelerationStructureDescriptor new] ];
    if (concrete.count != 9) return 1;
    for (id object in concrete)
      if (![object isKindOfClass:[MTL4AccelerationStructureDescriptor class]]
          && ![object isKindOfClass:[MTL4AccelerationStructureGeometryDescriptor class]])
        return 2;
    MTL4AccelerationStructureTriangleGeometryDescriptor *triangle = concrete[5];
    MTL4PrimitiveAccelerationStructureDescriptor *primitive = concrete[8];
    triangle.triangleCount = 3; triangle.vertexFormat = MTLAttributeFormatFloat3;
    __weak MTL4AccelerationStructureTriangleGeometryDescriptor *weak = triangle;
    primitive.geometryDescriptors = @[triangle]; triangle = nil;
    if (primitive.geometryDescriptors.count != 1
        || ((MTL4AccelerationStructureTriangleGeometryDescriptor *)
              primitive.geometryDescriptors[0]).triangleCount != 3) return 3;
    /* Descriptor arrays may copy or retain concrete descriptors. */
    (void)weak;
    primitive.geometryDescriptors = @[];
    if (primitive.geometryDescriptors.count != 0) return 4;
    if (NSClassFromString(@"MTL4AccelerationStructureDescriptor") == nil
        || NSClassFromString(@"MTL4AccelerationStructureGeometryDescriptor") == nil)
      return 5;
  }
  return 0;
} }
