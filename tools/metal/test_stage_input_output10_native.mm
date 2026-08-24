#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<decltype([MTLStageInputOutputDescriptor
  stageInputOutputDescriptor].attributes), MTLAttributeDescriptorArray *>);
static_assert(std::is_same_v<decltype([MTLStageInputOutputDescriptor
  stageInputOutputDescriptor].layouts), MTLBufferLayoutDescriptorArray *>);

int main() { @autoreleasepool {
  MTLStageInputOutputDescriptor *descriptor =
    [MTLStageInputOutputDescriptor stageInputOutputDescriptor];
  if (descriptor == nil || descriptor.attributes == nil || descriptor.layouts == nil)
    return 1;
  MTLAttributeDescriptor *attribute = descriptor.attributes[2];
  MTLBufferLayoutDescriptor *layout = descriptor.layouts[1];
  if (attribute == nil || layout == nil) return 2;
  layout.stride = 16;
  attribute.format = MTLAttributeFormatFloat3;
  attribute.offset = 4;
  attribute.bufferIndex = 1;
  if (descriptor.attributes[2] != attribute || descriptor.layouts[1] != layout)
    return 3;
  __weak MTLAttributeDescriptor *weak = nil;
  @autoreleasepool {
    MTLAttributeDescriptor *replacement = [MTLAttributeDescriptor new];
    replacement.format = MTLAttributeFormatFloat4;
    replacement.offset = 0;
    replacement.bufferIndex = 1;
    weak = replacement;
    descriptor.attributes[2] = replacement;
  }
  if (weak == nil || descriptor.attributes[2].format != MTLAttributeFormatFloat4)
    return 4;
  [descriptor reset];
  if (descriptor.attributes[2].format != MTLAttributeFormatInvalid
      || descriptor.layouts[1].stride != 0)
    return 5;
  return 0;
} }
