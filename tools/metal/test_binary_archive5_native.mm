#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static bool same_device(uint64_t archive, uint64_t descriptor, uint64_t library,
                        BOOL needsLibrary) {
  return archive == descriptor && (!needsLibrary || archive == library);
}

int main() { @autoreleasepool {
  if (same_device(1, 2, 1, NO) || same_device(1, 1, 2, YES)
      || !same_device(1, 1, 2, NO) || !same_device(1, 1, 1, YES)) return 1;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (device == nil) return 77;
  MTLBinaryArchiveDescriptor *archiveDescriptor = [MTLBinaryArchiveDescriptor new];
  NSError *error = nil;
  id<MTLBinaryArchive> archive = [device newBinaryArchiveWithDescriptor:archiveDescriptor error:&error];
  if (archive == nil) return 77;
  id<MTLLibrary> library = [device newLibraryWithSource:
    @"vertex float4 v(){return 0;} fragment float4 f(){return 1;} kernel void k(){}"
    options:nil error:&error];
  if (library == nil) return 77;
  MTLFunctionDescriptor *functionDescriptor = [MTLFunctionDescriptor functionDescriptor];
  functionDescriptor.name = @"k";
  if (![archive addFunctionWithDescriptor:functionDescriptor library:library error:&error]) return 2;
  MTLRenderPipelineDescriptor *render = [MTLRenderPipelineDescriptor new];
  render.vertexFunction = [library newFunctionWithName:@"v"];
  render.fragmentFunction = [library newFunctionWithName:@"f"];
  render.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  if (![archive addRenderPipelineFunctionsWithDescriptor:render error:&error]) return 3;
  MTLStitchedLibraryDescriptor *stitched = [MTLStitchedLibraryDescriptor new];
  MTLMeshRenderPipelineDescriptor *mesh = [MTLMeshRenderPipelineDescriptor new];
  MTLTileRenderPipelineDescriptor *tile = [MTLTileRenderPipelineDescriptor new];
  if (stitched == nil || mesh == nil || tile == nil
      || ![archive respondsToSelector:@selector(addLibraryWithDescriptor:error:)]
      || ![archive respondsToSelector:@selector(addMeshRenderPipelineFunctionsWithDescriptor:error:)]
      || ![archive respondsToSelector:@selector(addTileRenderPipelineFunctionsWithDescriptor:error:)])
    return 4;
  /* Invalid mesh/tile descriptors trigger SDK assertions rather than NSError;
     execution is capability-gated until a device-specific valid shader exists. */
  __strong id<MTLLibrary> retainedLibrary = library;
  __weak id<MTLLibrary> weak = library; library = nil;
  if (retainedLibrary == nil || weak == nil) return 7;
  retainedLibrary = nil;
  return 0;
} }
