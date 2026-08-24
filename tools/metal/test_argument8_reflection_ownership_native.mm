#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static const char *const kIds[] = {
  "class:MTLArgument", "class:MTLArrayType", "class:MTLPointerType",
  "class:MTLStructMember", "class:MTLStructType", "class:MTLTensorReferenceType",
  "class:MTLType", "protocol:MTLTensorBinding",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 8,
              "Argument8 exact closure drift");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  NSError *error = nil;
  NSString *source =
    @"#include <metal_stdlib>\nusing namespace metal;\n"
     "struct Inner { float4 color; };\n"
     "struct Args { device uint *pointer; Inner values[2]; };\n"
     "kernel void argument8(device Args &args [[buffer(0)]], uint i [[thread_position_in_grid]]) { args.pointer[i] = uint(args.values[0].color.x); }";
  id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
  if (!library) return 77;
  MTLComputePipelineDescriptor *descriptor = [MTLComputePipelineDescriptor new];
  descriptor.computeFunction = [library newFunctionWithName:@"argument8"];
  MTLComputePipelineReflection *reflection = nil;
  id<MTLComputePipelineState> pipeline =
    [device newComputePipelineStateWithDescriptor:descriptor
      options:MTLPipelineOptionArgumentInfo reflection:&reflection error:&error];
  if (!pipeline || !reflection) return 77;
  MTLArgument *argument = nil;
  for (MTLArgument *candidate in reflection.arguments)
    if (candidate.index == 0 && candidate.type == MTLArgumentTypeBuffer) argument = candidate;
  if (!argument || argument.bufferDataType != MTLDataTypeStruct) return 1;
  MTLStructType *structure = argument.bufferStructType;
  if (!structure || structure.members.count != 2) return 2;
  MTLStructMember *pointer_member = [structure memberByName:@"pointer"];
  MTLStructMember *array_member = [structure memberByName:@"values"];
  if (!pointer_member || !array_member ||
      pointer_member.dataType != MTLDataTypePointer ||
      array_member.dataType != MTLDataTypeArray) return 3;
  MTLPointerType *pointer = pointer_member.pointerType;
  MTLArrayType *array = array_member.arrayType;
  if (!pointer || pointer.elementType != MTLDataTypeUInt || !array ||
      array.arrayLength != 2 || array.elementType != MTLDataTypeStruct ||
      array.stride == 0 || array.elementStructType == nil) return 4;

  /* Reflection children remain valid when their parent reflection and
     pipeline wrappers are released by the caller. */
  reflection = nil; pipeline = nil; descriptor = nil; library = nil;
  if (![pointer_member.name isEqualToString:@"pointer"] ||
      ![array_member.name isEqualToString:@"values"] ||
      array.elementStructType.members.count != 1) return 5;

  Class tensor_type = NSClassFromString(@"MTLTensorReferenceType");
  Protocol *tensor_binding = NSProtocolFromString(@"MTLTensorBinding");
  if (@available(macOS 26.0, *)) {
    if (tensor_type == Nil || tensor_binding == nil) return 6;
  }
  return 0;
} }

#pragma clang diagnostic pop
