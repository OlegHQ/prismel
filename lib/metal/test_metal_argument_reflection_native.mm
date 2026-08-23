#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <Metal/MTLArgument.h>

#include <cstdio>
#include <cstdlib>
#include <stdexcept>

static void require(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "Metal argument reflection: %s\n", message);
    std::exit(1);
  }
}

/* Compile every planned selector as a statically typed Objective-C call. */
#define PRISMEL_REFLECTION_VALUE(owner, selector, result, major, minor) \
  static result typed_##owner##_##selector(owner *receiver) { return [receiver selector]; }
#define PRISMEL_REFLECTION_OBJECT(owner, selector, result, major, minor) \
  static result *typed_##owner##_##selector(owner *receiver) { return [[receiver selector] retain]; }
#define PRISMEL_REFLECTION_STRING(owner, selector, major, minor) \
  static NSString *typed_##owner##_##selector(owner *receiver) { return [[receiver selector] copy]; }
#define PRISMEL_REFLECTION_ARRAY(owner, selector, element, major, minor) \
  static NSArray<element *> *typed_##owner##_##selector(owner *receiver) { return [[receiver selector] copy]; }
#define PRISMEL_REFLECTION_STRING_ARGUMENT_OBJECT(owner, selector, result, major, minor) \
  static result *typed_##owner##_##selector(owner *receiver, NSString *name) { return [[receiver selector:name] retain]; }
#define PRISMEL_REFLECTION_PROTOCOL_VALUE(owner, selector, result, major, minor) \
  static result typed_##owner##_##selector(id<owner> receiver) { return [receiver selector]; }
#define PRISMEL_REFLECTION_PROTOCOL_OBJECT(owner, selector, result, major, minor) \
  static result *typed_##owner##_##selector(id<owner> receiver) { return [[receiver selector] retain]; }
#include "metal_argument_reflection_generated.inc"
#undef PRISMEL_REFLECTION_VALUE
#undef PRISMEL_REFLECTION_OBJECT
#undef PRISMEL_REFLECTION_STRING
#undef PRISMEL_REFLECTION_ARRAY
#undef PRISMEL_REFLECTION_STRING_ARGUMENT_OBJECT
#undef PRISMEL_REFLECTION_PROTOCOL_VALUE
#undef PRISMEL_REFLECTION_PROTOCOL_OBJECT

struct OwnedObject {
  id value;
  int *live;
  OwnedObject(id value_, int *live_) : value([value_ retain]), live(live_) { ++*live; }
  ~OwnedObject() { [value release]; --*live; }
  OwnedObject(const OwnedObject &) = delete;
};

static void exercise_unwind(NSArray *members) {
  int live = 0;
  @try {
    NSArray *snapshot = [members copy];
    @try {
      for (id member in snapshot) {
        OwnedObject owned(member, &live);
        throw std::runtime_error("injected conversion failure");
      }
    } @finally {
      [snapshot release];
    }
  } @catch (...) {
  }
  require(live == 0, "retained member survived injected failure");
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    require(device != nil, "no Metal device");
    NSString *source =
      @"#include <metal_stdlib>\n"
       "using namespace metal;\n"
       "struct Nested { float4 position; float weights[4]; };\n"
       "kernel void reflect_kernel(device Nested *items [[buffer(0)]], "
       "texture2d<float> image [[texture(0)]], uint tid [[thread_position_in_grid]]) "
       "{ if (tid == 0) items[0].position.x += image.get_width(); }\n";
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    require(library != nil, error.localizedDescription.UTF8String ?: "library compile failed");
    id<MTLFunction> function = [library newFunctionWithName:@"reflect_kernel"];
    require(function != nil, "missing reflected function");
    MTLComputePipelineReflection *reflection = nil;
    id<MTLComputePipelineState> pipeline =
      [device newComputePipelineStateWithFunction:function
                                          options:MTLPipelineOptionArgumentInfo | MTLPipelineOptionBufferTypeInfo
                                       reflection:&reflection error:&error];
    require(pipeline != nil, error.localizedDescription.UTF8String ?: "pipeline compile failed");
    require(reflection.arguments.count >= 2, "reflection omitted arguments");

    MTLArgument *buffer = nil;
    for (MTLArgument *argument in reflection.arguments) {
      NSString *name = typed_MTLArgument_name(argument);
      if ([name isEqualToString:@"items"]) buffer = argument;
      [name release];
      (void)typed_MTLArgument_index(argument);
      (void)typed_MTLArgument_access(argument);
      (void)typed_MTLArgument_isActive(argument);
      (void)typed_MTLArgument_type(argument);
    }
    require(buffer != nil, "buffer reflection missing");
    MTLPointerType *pointer = typed_MTLArgument_bufferPointerType(buffer);
    require(pointer != nil, "pointer reflection missing");
    (void)typed_MTLType_dataType(pointer);
    (void)typed_MTLPointerType_access(pointer);
    (void)typed_MTLPointerType_alignment(pointer);
    (void)typed_MTLPointerType_dataSize(pointer);
    (void)typed_MTLPointerType_elementIsArgumentBuffer(pointer);
    MTLStructType *structure = typed_MTLPointerType_elementStructType(pointer);
    require(structure != nil, "struct reflection missing");
    NSArray<MTLStructMember *> *members = typed_MTLStructType_members(structure);
    require(members.count == 2, "struct member reflection mismatch");
    MTLStructMember *position = typed_MTLStructType_memberByName(structure, @"position");
    require(position != nil, "memberByName reflection mismatch");
    NSString *position_name = typed_MTLStructMember_name(position);
    require([position_name isEqualToString:@"position"], "member name mismatch");
    (void)typed_MTLStructMember_offset(position);
    (void)typed_MTLStructMember_dataType(position);
    exercise_unwind(members);
    [position_name release];
    [position release];
    [members release];
    [structure release];
    [pointer release];
    [pipeline release];
    [function release];
    [library release];
    [device release];
    std::puts("Metal argument reflection native conformance: real pipeline and ownership unwind passed");
  }
  return 0;
}
