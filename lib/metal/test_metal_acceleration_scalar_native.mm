#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdio>
#include <cstdlib>

static void require(bool condition, const char *message) {
  if (!condition) { std::fprintf(stderr, "Metal acceleration scalar: %s\n", message); std::exit(1); }
}

static bool simulated_create(bool supported, NSUInteger *allocations) {
  if (!supported) return false;
  ++*allocations;
  return true;
}

static void require_sizes(id<MTLDevice> device,
                          MTLAccelerationStructureDescriptor *descriptor,
                          const char *owner) {
  MTLAccelerationStructureSizes sizes =
    [device accelerationStructureSizesWithDescriptor:descriptor];
  if (sizes.accelerationStructureSize == 0 || sizes.buildScratchBufferSize == 0) {
    std::fprintf(stderr, "Metal acceleration scalar: %s produced no size path\n", owner);
    std::exit(1);
  }
}

int main() {
  @autoreleasepool {
    NSUInteger simulated_allocations = 0;
    require(!simulated_create(false, &simulated_allocations), "unsupported family accepted");
    require(simulated_allocations == 0, "unsupported family allocated a descriptor graph");

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    require(device != nil, "no Metal device");
    if (![device supportsRaytracing]) {
      std::puts("Metal acceleration scalar native conformance: capability-rejected with zero partial graph");
      return 0;
    }
    const float vertices[] = { 0.f, 0.f, 0.f, 1.f, 0.f, 0.f, 0.f, 1.f, 0.f };
    id<MTLBuffer> vertex_buffer =
      [device newBufferWithBytes:vertices length:sizeof(vertices)
                         options:MTLResourceStorageModeShared];
    require(vertex_buffer != nil, "vertex buffer allocation failed");
    MTLAccelerationStructureTriangleGeometryDescriptor *triangle =
      [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
    triangle.vertexBuffer = vertex_buffer;
    triangle.vertexBufferOffset = 0;
    triangle.vertexStride = 3 * sizeof(float);
    triangle.vertexFormat = MTLAttributeFormatFloat3;
    triangle.indexType = MTLIndexTypeUInt32;
    triangle.triangleCount = 1;
    triangle.indexBufferOffset = 0;
    triangle.transformationMatrixBufferOffset = 0;
    triangle.transformationMatrixLayout = MTLMatrixLayoutColumnMajor;
    require(triangle.indexBufferOffset == 0 &&
            triangle.indexType == MTLIndexTypeUInt32 &&
            triangle.transformationMatrixBufferOffset == 0 &&
            triangle.transformationMatrixLayout == MTLMatrixLayoutColumnMajor &&
            triangle.triangleCount == 1 && triangle.vertexBufferOffset == 0 &&
            triangle.vertexFormat == MTLAttributeFormatFloat3 &&
            triangle.vertexStride == 12,
            "triangle scalar round-trip failed");

    MTLPrimitiveAccelerationStructureDescriptor *primitive =
      [MTLPrimitiveAccelerationStructureDescriptor descriptor];
    primitive.geometryDescriptors = @[ triangle ];
    primitive.usage = MTLAccelerationStructureUsageRefit;
    primitive.motionStartTime = 0.f;
    primitive.motionEndTime = 1.f;
    primitive.motionStartBorderMode = MTLMotionBorderModeClamp;
    primitive.motionEndBorderMode = MTLMotionBorderModeClamp;
    primitive.motionKeyframeCount = 1;
    require(primitive.usage == MTLAccelerationStructureUsageRefit &&
            primitive.motionStartTime == 0.f && primitive.motionEndTime == 1.f &&
            primitive.motionStartBorderMode == MTLMotionBorderModeClamp &&
            primitive.motionEndBorderMode == MTLMotionBorderModeClamp &&
            primitive.motionKeyframeCount == 1,
            "primitive scalar round-trip failed");
    MTLAccelerationStructureSizes sizes =
      [device accelerationStructureSizesWithDescriptor:primitive];
    require(sizes.accelerationStructureSize > 0 && sizes.buildScratchBufferSize > 0,
            "invalid acceleration-structure sizes");
    id<MTLAccelerationStructure> source =
      [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    id<MTLBuffer> scratch =
      [device newBufferWithLength:MAX(sizes.buildScratchBufferSize,
                                      sizes.refitScratchBufferSize)
                         options:MTLResourceStorageModePrivate];
    require(source != nil && scratch != nil, "acceleration resource allocation failed");
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLAccelerationStructureCommandEncoder> encoder =
      [command accelerationStructureCommandEncoder];
    [encoder buildAccelerationStructure:source descriptor:primitive
                           scratchBuffer:scratch scratchBufferOffset:0];
    [encoder refitAccelerationStructure:source descriptor:primitive
                             destination:source scratchBuffer:scratch
                     scratchBufferOffset:0];
    id<MTLAccelerationStructure> copy =
      [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    [encoder copyAccelerationStructure:source toAccelerationStructure:copy];
    [encoder endEncoding];
    [command commit];
    [command waitUntilCompleted];
    require(command.status == MTLCommandBufferStatusCompleted,
            command.error.localizedDescription.UTF8String ?: "AS command failed");
    require(source.size > 0 && copy.size > 0, "AS copy produced an invalid resource");

    /* Every remaining legacy geometry owner reaches the real device sizing
       path with a minimally valid object graph.  The triangle path above then
       proves build/refit/copy resource behavior shared by those descriptors. */
    const float boxes[] = { -1.f, -1.f, -1.f, 1.f, 1.f, 1.f };
    id<MTLBuffer> box_buffer = [device newBufferWithBytes:boxes length:sizeof(boxes)
                                                  options:MTLResourceStorageModeShared];
    MTLAccelerationStructureBoundingBoxGeometryDescriptor *box =
      [MTLAccelerationStructureBoundingBoxGeometryDescriptor descriptor];
    box.boundingBoxBuffer = box_buffer;
    box.boundingBoxBufferOffset = 0;
    box.boundingBoxStride = sizeof(boxes);
    box.boundingBoxCount = 1;
    primitive.geometryDescriptors = @[ box ];
    require_sizes(device, primitive, "MTLAccelerationStructureBoundingBoxGeometryDescriptor");

    const float curve_points[] = { 0.f,0.f,0.f, 0.3f,0.7f,0.f,
                                   0.7f,0.7f,0.f, 1.f,0.f,0.f };
    const float radii[] = { .05f, .05f, .05f, .05f };
    id<MTLBuffer> point_buffer = [device newBufferWithBytes:curve_points
                                                    length:sizeof(curve_points)
                                                   options:MTLResourceStorageModeShared];
    id<MTLBuffer> radius_buffer = [device newBufferWithBytes:radii length:sizeof(radii)
                                                     options:MTLResourceStorageModeShared];
    MTLAccelerationStructureCurveGeometryDescriptor *curve =
      [MTLAccelerationStructureCurveGeometryDescriptor descriptor];
    curve.controlPointBuffer = point_buffer;
    curve.controlPointCount = 4;
    curve.controlPointFormat = MTLAttributeFormatFloat3;
    curve.controlPointStride = 12;
    curve.radiusBuffer = radius_buffer;
    curve.radiusFormat = MTLAttributeFormatFloat;
    curve.radiusStride = 4;
    curve.segmentCount = 1;
    curve.segmentControlPointCount = 4;
    curve.curveType = MTLCurveTypeRound;
    curve.curveBasis = MTLCurveBasisBezier;
    curve.curveEndCaps = MTLCurveEndCapsDisk;
    primitive.geometryDescriptors = @[ curve ];
    require_sizes(device, primitive, "MTLAccelerationStructureCurveGeometryDescriptor");

    MTLMotionKeyframeData *vertex_key = [MTLMotionKeyframeData data];
    vertex_key.buffer = vertex_buffer;
    vertex_key.offset = 0;
    MTLAccelerationStructureMotionTriangleGeometryDescriptor *motion_triangle =
      [MTLAccelerationStructureMotionTriangleGeometryDescriptor descriptor];
    motion_triangle.vertexBuffers = @[ vertex_key, vertex_key ];
    motion_triangle.vertexStride = 12;
    motion_triangle.vertexFormat = MTLAttributeFormatFloat3;
    motion_triangle.triangleCount = 1;
    primitive.motionKeyframeCount = 2;
    primitive.geometryDescriptors = @[ motion_triangle ];
    require_sizes(device, primitive, "MTLAccelerationStructureMotionTriangleGeometryDescriptor");

    MTLMotionKeyframeData *box_key = [MTLMotionKeyframeData data];
    box_key.buffer = box_buffer;
    box_key.offset = 0;
    MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor *motion_box =
      [MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor descriptor];
    motion_box.boundingBoxBuffers = @[ box_key, box_key ];
    motion_box.boundingBoxStride = sizeof(boxes);
    motion_box.boundingBoxCount = 1;
    primitive.geometryDescriptors = @[ motion_box ];
    require_sizes(device, primitive, "MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor");

    MTLAccelerationStructureMotionCurveGeometryDescriptor *motion_curve =
      [MTLAccelerationStructureMotionCurveGeometryDescriptor descriptor];
    MTLMotionKeyframeData *point_key = [MTLMotionKeyframeData data];
    point_key.buffer = point_buffer;
    point_key.offset = 0;
    motion_curve.controlPointBuffers = @[ point_key, point_key ];
    motion_curve.controlPointCount = 4;
    motion_curve.controlPointFormat = MTLAttributeFormatFloat3;
    motion_curve.controlPointStride = 12;
    motion_curve.radiusBuffers = @[ box_key, box_key ];
    motion_curve.radiusFormat = MTLAttributeFormatFloat;
    motion_curve.radiusStride = 4;
    motion_curve.segmentCount = 1;
    motion_curve.segmentControlPointCount = 4;
    motion_curve.curveType = MTLCurveTypeRound;
    motion_curve.curveBasis = MTLCurveBasisBezier;
    motion_curve.curveEndCaps = MTLCurveEndCapsDisk;
    primitive.geometryDescriptors = @[ motion_curve ];
    require_sizes(device, primitive, "MTLAccelerationStructureMotionCurveGeometryDescriptor");

    MTLInstanceAccelerationStructureDescriptor *instances =
      [MTLInstanceAccelerationStructureDescriptor descriptor];
    instances.instancedAccelerationStructures = @[ source ];
    instances.instanceCount = 0;
    require_sizes(device, instances, "MTLInstanceAccelerationStructureDescriptor");

    MTLIndirectInstanceAccelerationStructureDescriptor *indirect =
      [MTLIndirectInstanceAccelerationStructureDescriptor descriptor];
    indirect.maxInstanceCount = 1;
    indirect.maxMotionTransformCount = 0;
    require_sizes(device, indirect, "MTLIndirectInstanceAccelerationStructureDescriptor");

    /* Metal 4 acceleration descriptors require the M3+/Apple9 lane in this
       migration.  The M1 lane rejects every one of its ten owners before any
       descriptor or resource allocation. */
    bool metal4_as_supported = [device supportsFamily:MTLGPUFamilyApple9];
    if (!metal4_as_supported) {
      NSUInteger allocations = 0;
      const char *owners[] = {
        "MTL4AccelerationStructureGeometryDescriptor",
        "MTL4AccelerationStructureTriangleGeometryDescriptor",
        "MTL4AccelerationStructureBoundingBoxGeometryDescriptor",
        "MTL4AccelerationStructureCurveGeometryDescriptor",
        "MTL4AccelerationStructureMotionTriangleGeometryDescriptor",
        "MTL4AccelerationStructureMotionBoundingBoxGeometryDescriptor",
        "MTL4AccelerationStructureMotionCurveGeometryDescriptor",
        "MTL4PrimitiveAccelerationStructureDescriptor",
        "MTL4InstanceAccelerationStructureDescriptor",
        "MTL4IndirectInstanceAccelerationStructureDescriptor" };
      for (const char *owner : owners) {
        require(!simulated_create(false, &allocations), owner);
      }
      require(allocations == 0, "Metal4 rejected owners allocated partial graphs");
    }
    std::puts("Metal acceleration scalar native conformance: triangle build/refit/copy passed");
  }
  return 0;
}
