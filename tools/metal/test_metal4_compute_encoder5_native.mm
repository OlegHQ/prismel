#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>

#include <type_traits>
#include <vector>

static_assert(std::is_same_v<decltype(((id<MTL4ComputeCommandEncoder>)nil).commandBuffer),
  id<MTL4CommandBuffer>>);
static bool range(NSUInteger total, NSInteger offset, NSInteger length) {
  return offset >= 0 && length > 0 && (NSUInteger)offset <= total
    && (NSUInteger)length <= total - (NSUInteger)offset;
}
static bool slice(const std::vector<NSInteger> &shape,
                  const std::vector<NSInteger> &origin,
                  const std::vector<NSInteger> &dimensions) {
  if (shape.empty() || shape.size() != origin.size() || shape.size() != dimensions.size())
    return false;
  for (size_t i = 0; i < shape.size(); ++i)
    if (shape[i] <= 0 || origin[i] < 0 || dimensions[i] <= 0
        || origin[i] > shape[i] || dimensions[i] > shape[i] - origin[i]) return false;
  return true;
}
struct Retained {
  __strong id source = nil, destination = nil, descriptor = nil, scratch = nil;
  void clear() { source = nil; destination = nil; descriptor = nil; scratch = nil; }
};

int main() { @autoreleasepool {
  if (range(64, -1, 8) || range(64, 60, 8) || !range(64, 8, 56)) return 1;
  if (slice({2, 3}, {0}, {1}) || slice({2, 3}, {1, 2}, {2, 1})
      || !slice({2, 3}, {1, 1}, {1, 2})) return 2;
  Retained retained; __weak NSObject *weak = nil;
  @autoreleasepool { NSObject *object = [NSObject new]; weak = object;
    retained.source = object; retained.destination = object;
    retained.descriptor = object; retained.scratch = object; }
  if (weak == nil) return 3; retained.clear(); if (weak != nil) return 4;
  if (@available(macOS 26.0, *)) {
    Protocol *protocol = NSProtocolFromString(@"MTL4ComputeCommandEncoder");
    if (protocol == nil
        || ![NSObject instancesRespondToSelector:@selector(description)]) return 5;
    struct objc_method_description build = protocol_getMethodDescription(protocol,
      @selector(buildAccelerationStructure:descriptor:scratchBuffer:), YES, YES);
    struct objc_method_description copy = protocol_getMethodDescription(protocol,
      @selector(copyFromTensor:sourceOrigin:sourceDimensions:toTensor:destinationOrigin:destinationDimensions:), YES, YES);
    struct objc_method_description refit = protocol_getMethodDescription(protocol,
      @selector(refitAccelerationStructure:descriptor:destination:scratchBuffer:options:), YES, YES);
    struct objc_method_description compact = protocol_getMethodDescription(protocol,
      @selector(writeCompactedAccelerationStructureSize:toBuffer:), YES, YES);
    if (build.name == nullptr || copy.name == nullptr || refit.name == nullptr
        || compact.name == nullptr) return 6;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (device == nil) return 77;
    id<MTLBuffer> scratch = [device newBufferWithLength:256 options:MTLResourceStorageModeShared];
    if (scratch == nil || scratch.device.registryID != device.registryID
        || !range(scratch.length, 0, 256)) return 7;
  }
  return 0;
} }
