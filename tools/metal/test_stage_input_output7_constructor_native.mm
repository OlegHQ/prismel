#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<
    decltype([MTLStageInputOutputDescriptor stageInputOutputDescriptor]),
    MTLStageInputOutputDescriptor *>);
static_assert(std::is_same_v<
    decltype(((MTLStageInputOutputDescriptor *)nil).attributes),
    MTLAttributeDescriptorArray *>);
static_assert(std::is_same_v<
    decltype(((MTLStageInputOutputDescriptor *)nil).layouts),
    MTLBufferLayoutDescriptorArray *>);

int main()
{
  __weak MTLStageInputOutputDescriptor *weak_parent = nil;
  __weak MTLAttributeDescriptorArray *weak_attributes = nil;
  __weak MTLBufferLayoutDescriptorArray *weak_layouts = nil;
  @autoreleasepool {
    MTLStageInputOutputDescriptor *parent =
        [MTLStageInputOutputDescriptor stageInputOutputDescriptor];
    if (parent == nil || parent.attributes == nil || parent.layouts == nil)
      return 1;
    weak_parent = parent;
    weak_attributes = parent.attributes;
    weak_layouts = parent.layouts;

    MTLBufferLayoutDescriptor *layout = parent.layouts[3];
    MTLAttributeDescriptor *attribute = parent.attributes[5];
    if (layout == nil || attribute == nil) return 2;
    layout.stride = 32;
    attribute.format = MTLAttributeFormatFloat4;
    attribute.offset = 8;
    attribute.bufferIndex = 3;
    if (parent.layouts[3].stride != 32 ||
        parent.attributes[5].format != MTLAttributeFormatFloat4 ||
        parent.attributes[5].offset != 8 ||
        parent.attributes[5].bufferIndex != 3)
      return 3;

    /* Child arrays are parent-owned, stable identities for the lifetime of
       the descriptor, and reset mutates their contained descriptor values. */
    if (parent.attributes != weak_attributes || parent.layouts != weak_layouts)
      return 4;
    [parent reset];
    if (parent.attributes != weak_attributes || parent.layouts != weak_layouts ||
        parent.attributes[5].format != MTLAttributeFormatInvalid ||
        parent.attributes[5].offset != 0 ||
        parent.attributes[5].bufferIndex != 0 ||
        parent.layouts[3].stride != 0)
      return 5;
  }
  if (weak_parent != nil || weak_attributes != nil || weak_layouts != nil)
    return 6;
  return 0;
}
