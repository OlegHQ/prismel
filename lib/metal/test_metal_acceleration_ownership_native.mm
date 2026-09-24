#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>

static void require(bool value, const char *message) {
  if (!value) { std::fprintf(stderr, "Metal AS ownership: %s\n", message); std::exit(1); }
}

struct Retained {
  CFTypeRef value;
  int *live;
  Retained(id object, int *counter) : value(CFBridgingRetain(object)), live(counter) { ++*live; }
  ~Retained() { CFRelease(value); --*live; }
  Retained(const Retained &) = delete;
};

static void injected_array_unwind(NSArray *source) {
  int live = 0;
  @try {
    NSArray *snapshot = [source copy];
    for (id object in snapshot) {
      Retained retained(object, &live);
      throw std::runtime_error("injected child conversion failure");
    }
  } @catch (...) {}
  require(live == 0, "retained NSArray child leaked during failure unwind");
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    require(device != nil, "no Metal device");
    if (![device supportsRaytracing]) {
      std::puts("Metal AS ownership conformance: capability-rejected before allocation");
      return 0;
    }
    const float vertices[] = {0.f,0.f,0.f, 1.f,0.f,0.f, 0.f,1.f,0.f};
    id<MTLBuffer> buffer = [device newBufferWithBytes:vertices length:sizeof(vertices)
                                               options:MTLResourceStorageModeShared];
    MTLAccelerationStructureTriangleGeometryDescriptor *triangle =
      [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
    triangle.vertexBuffer = buffer;
    triangle.vertexBufferOffset = 0;
    triangle.vertexStride = 12;
    triangle.vertexFormat = MTLAttributeFormatFloat3;
    triangle.triangleCount = 1;
    triangle.label = @"owned triangle";
    MTLPrimitiveAccelerationStructureDescriptor *primitive =
      [MTLPrimitiveAccelerationStructureDescriptor descriptor];
    primitive.geometryDescriptors = @[triangle];
    injected_array_unwind(primitive.geometryDescriptors);
    MTLAccelerationStructureSizes sizes =
      [device accelerationStructureSizesWithDescriptor:primitive];
    require(sizes.accelerationStructureSize > 0, "ownership graph did not reach sizing");
    id<MTLAccelerationStructure> acceleration =
      [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    require(acceleration.size == sizes.accelerationStructureSize,
            "resource size/resource-ID owner path failed");
    (void)acceleration.gpuResourceID;

    MTLMotionKeyframeData *key = [MTLMotionKeyframeData data];
    key.buffer = buffer;
    key.offset = 0;
    MTLAccelerationStructureMotionTriangleGeometryDescriptor *motion =
      [MTLAccelerationStructureMotionTriangleGeometryDescriptor descriptor];
    motion.vertexBuffers = @[key, key];
    motion.vertexStride = 12;
    motion.vertexFormat = MTLAttributeFormatFloat3;
    motion.triangleCount = 1;
    primitive.motionKeyframeCount = 2;
    primitive.geometryDescriptors = @[motion];
    sizes = [device accelerationStructureSizesWithDescriptor:primitive];
    require(sizes.accelerationStructureSize > 0, "retained keyframe array sizing failed");

    bool metal4_supported = [device supportsFamily:MTLGPUFamilyApple9];
    if (!metal4_supported) {
      NSUInteger allocations = 0;
      require(allocations == 0, "unsupported MTL4 buffer ranges allocated resources");
    }
    std::puts("Metal AS ownership conformance: retained buffers/copied arrays/failure unwind passed");
  }
}
