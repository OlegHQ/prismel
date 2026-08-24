#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kIds[] = {
  "class:MTL4BinaryFunction", "class:MTLDynamicLibrary",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 2,
              "MTL4LinkingDescriptor2 metadata drift");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  NSError *error = nil;
  MTLCompileOptions *options = [MTLCompileOptions new];
  options.libraryType = MTLLibraryTypeDynamic;
  options.installName = @"prismel-linking2";
  id<MTLLibrary> library = [device newLibraryWithSource:
    @"#include <metal_stdlib>\nusing namespace metal;"
     "[[visible]] float linking2_helper(float x) { return x + 2.0; }"
    options:options error:&error];
  if (!library) return 77;
  id<MTLDynamicLibrary> dynamic = nil;
  @try { dynamic = [device newDynamicLibrary:library error:&error]; }
  @catch (NSException *exception) {
    if (![exception.name isEqualToString:NSInvalidArgumentException]) return 1;
    return 77;
  }
  if (!dynamic || dynamic.device.registryID != device.registryID ||
      ![dynamic.installName isEqualToString:@"prismel-linking2"]) return 2;
  dynamic.label = @"linking2-dynamic";
  if (![dynamic.label isEqualToString:@"linking2-dynamic"]) return 3;
  __weak id<MTLDynamicLibrary> weak = dynamic;
  NSArray<id<MTLDynamicLibrary>> *owned = @[ dynamic ]; dynamic = nil;
  if (weak == nil || owned[0].device.registryID != device.registryID) return 4;

  if (@available(macOS 26.0, *)) {
    Class binary_class = NSClassFromString(@"MTL4BinaryFunction");
    if (binary_class == Nil) return 77;
    /* MTL4BinaryFunction is returned by a Metal4 compiler task and has no
       public constructor.  Class presence proves type availability only. */
  }
  return 0;
} }
