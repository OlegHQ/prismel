#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdio>

static int fail(const char *message) {
  std::fprintf(stderr,"RenderPipeline93 linked graph: %s\n",message);
  return 1;
}

int main() {
  @autoreleasepool {
    MTLLinkedFunctions *object = [MTLLinkedFunctions new];
    MTLLinkedFunctions *mesh = [MTLLinkedFunctions new];
    MTLLinkedFunctions *fragment = [MTLLinkedFunctions new];
    object.groups = @{ @"object" : @[] };
    mesh.groups = @{ @"mesh" : @[] };
    fragment.groups = @{ @"fragment" : @[] };
    MTLMeshRenderPipelineDescriptor *mesh_descriptor =
        [MTLMeshRenderPipelineDescriptor new];
    mesh_descriptor.objectLinkedFunctions = object;
    mesh_descriptor.meshLinkedFunctions = mesh;
    mesh_descriptor.fragmentLinkedFunctions = fragment;
    if (mesh_descriptor.objectLinkedFunctions == nil ||
        mesh_descriptor.meshLinkedFunctions == nil ||
        mesh_descriptor.fragmentLinkedFunctions == nil)
      return fail("mesh copied graph disappeared");
    mesh_descriptor.objectLinkedFunctions = nil;
    mesh_descriptor.meshLinkedFunctions = nil;
    mesh_descriptor.fragmentLinkedFunctions = nil;
    if (mesh_descriptor.objectLinkedFunctions.groups != nil ||
        mesh_descriptor.meshLinkedFunctions.groups != nil ||
        mesh_descriptor.fragmentLinkedFunctions.groups != nil)
      return fail("mesh nil reset drift");

    MTLTileRenderPipelineDescriptor *tile_descriptor =
        [MTLTileRenderPipelineDescriptor new];
    tile_descriptor.linkedFunctions = object;
    if (tile_descriptor.linkedFunctions == nil)
      return fail("tile copied graph disappeared");
    tile_descriptor.linkedFunctions = nil;
    if (tile_descriptor.linkedFunctions.groups != nil)
      return fail("tile nil reset drift");

    std::puts("RenderPipeline93 linked graph: exact12 copy/reset passed");
    return 0;
  }
}
