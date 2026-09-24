#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<decltype(((id<MTLBinaryArchive>)nil).device),
                             id<MTLDevice>>);

int main()
{
  __weak id<MTLBinaryArchive> weak_archive = nil;
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    NSError *error = nil;
    MTLBinaryArchiveDescriptor *archive_descriptor =
        [MTLBinaryArchiveDescriptor new];
    id<MTLBinaryArchive> archive =
        [device newBinaryArchiveWithDescriptor:archive_descriptor error:&error];
    if (archive == nil || archive.device.registryID != device.registryID)
      return 77;
    weak_archive = archive;

    id<MTLLibrary> library = [device
        newLibraryWithSource:
            @"vertex float4 archive_vertex(){return float4(0); }"
             "fragment float4 archive_fragment(){return float4(1); }"
             "kernel void archive_kernel(){}"
                     options:nil
                       error:&error];
    if (library == nil) return 77;
    @autoreleasepool {
      MTLFunctionDescriptor *function =
          [MTLFunctionDescriptor functionDescriptor];
      function.name = @"archive_kernel";
      if (![archive addFunctionWithDescriptor:function
                                       library:library
                                         error:&error])
        return 1;

      MTLRenderPipelineDescriptor *render =
          [MTLRenderPipelineDescriptor new];
      render.vertexFunction = [library newFunctionWithName:@"archive_vertex"];
      render.fragmentFunction =
          [library newFunctionWithName:@"archive_fragment"];
      render.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
      if (![archive addRenderPipelineFunctionsWithDescriptor:render error:&error])
        return 2;
    }
    /* Successful additions are archive-owned snapshots; caller descriptors
       may leave scope before serialization. */
    NSString *filename = [NSString
        stringWithFormat:@"prismel-binary-archive-%@.metallib",
                         NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    if (![archive serializeToURL:url error:&error]) return 3;
    NSNumber *size = nil;
    if (![url getResourceValue:&size forKey:NSURLFileSizeKey error:&error] ||
        size.unsignedLongLongValue == 0)
      return 4;

    MTLBinaryArchiveDescriptor *reopen_descriptor =
        [MTLBinaryArchiveDescriptor new];
    reopen_descriptor.url = url;
    id<MTLBinaryArchive> reopened =
        [device newBinaryArchiveWithDescriptor:reopen_descriptor error:&error];
    if (reopened == nil || reopened.device.registryID != device.registryID)
      return 5;
    reopened = nil;
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    archive = nil;
  }
  if (weak_archive != nil) return 6;
  return 0;
}
