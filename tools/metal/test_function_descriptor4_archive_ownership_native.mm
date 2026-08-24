#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kIds[] = {
  "class:MTLIntersectionFunctionDescriptor",
  "method:-[MTLFunctionDescriptor binaryArchives]",
  "method:-[MTLFunctionDescriptor setBinaryArchives:]",
  "property:MTLFunctionDescriptor:binaryArchives",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 4,
              "FunctionDescriptor4 exact closure drift");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  NSError *error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:
    @"#include <metal_stdlib>\nusing namespace metal; kernel void fd4() {}"
    options:nil error:&error];
  if (!library) return 77;
  MTLBinaryArchiveDescriptor *archive_descriptor = [MTLBinaryArchiveDescriptor new];
  id<MTLBinaryArchive> archive =
    [device newBinaryArchiveWithDescriptor:archive_descriptor error:&error];
  if (!archive) return 77;
  MTLFunctionDescriptor *seed = [MTLFunctionDescriptor functionDescriptor];
  seed.name = @"fd4";
  if (![archive addFunctionWithDescriptor:seed library:library error:&error]) return 1;

  MTLFunctionDescriptor *descriptor = [MTLFunctionDescriptor functionDescriptor];
  descriptor.name = @"fd4";
  NSMutableArray<id<MTLBinaryArchive>> *source = [NSMutableArray arrayWithObject:archive];
  descriptor.binaryArchives = source;
  if (descriptor.binaryArchives.count != 1 || descriptor.binaryArchives[0] != archive)
    return 2;
  [source removeAllObjects];
  if (descriptor.binaryArchives.count != 1) return 3;
  __weak id<MTLBinaryArchive> weak_archive = archive; archive = nil;
  if (weak_archive == nil) return 4;
  id<MTLFunction> function = [library newFunctionWithDescriptor:descriptor error:&error];
  if (!function || ![function.name isEqualToString:@"fd4"]) return 5;
  descriptor.binaryArchives = nil;
  if (descriptor.binaryArchives != nil && descriptor.binaryArchives.count != 0)
    return 6;
  descriptor = nil;
  if (weak_archive != nil) return 7;

  MTLIntersectionFunctionDescriptor *intersection =
    [MTLIntersectionFunctionDescriptor new];
  intersection.name = @"missing-intersection";
  intersection.constantValues = [MTLFunctionConstantValues new];
  if (!intersection || ![intersection.name isEqualToString:@"missing-intersection"] ||
      intersection.constantValues == nil) return 8;
  return 0;
} }
