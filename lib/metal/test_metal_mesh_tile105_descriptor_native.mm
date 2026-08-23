#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#include "../../tools/metal/metal_mesh_tile_ownership_materializers.inc"
#pragma clang diagnostic pop

static void require(bool condition, NSString *message) {
  if (!condition) {
    @throw [NSException exceptionWithName:@"MeshTile105"
                                   reason:message
                                 userInfo:nil];
  }
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    NSError *error = nil;
    NSString *source =
        @"#include <metal_stdlib>\n"
         "using namespace metal;\n"
         "struct O { float4 p [[position]]; };\n"
         "vertex O vertex_main(uint i [[vertex_id]]) { float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)}; return {float4(p[i],0,1)}; }\n"
         "fragment float4 fragment_main() { return float4(1); }\n"
         "kernel void kernel_main(device uint *out [[buffer(0)]]) { out[0] = 1; }";
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    require(library != nil, error.localizedDescription ?: @"library");
    id<MTLFunction> vertex = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragment = [library newFunctionWithName:@"fragment_main"];
    id<MTLFunction> kernel = [library newFunctionWithName:@"kernel_main"];
    require(vertex != nil && fragment != nil && kernel != nil, @"functions");

    NSString *failure = nil;
    PrismelMeshTileObjects mesh = {};
    mesh.meshFunction = vertex;
    mesh.fragmentFunction = fragment;
    mesh.binaryArchives = @[];
    MTLMeshRenderPipelineDescriptor *meshDescriptor =
        prismel_materialize_mesh_descriptor(mesh, &failure);
    require(meshDescriptor != nil && failure == nil, failure ?: @"mesh descriptor");
    require(meshDescriptor.meshFunction == vertex &&
            meshDescriptor.fragmentFunction == fragment &&
            meshDescriptor.binaryArchives.count == 0,
            @"mesh descriptor ownership/schema");

    failure = nil;
    PrismelMeshTileObjects tile = {};
    tile.tileFunction = kernel;
    tile.binaryArchives = @[];
    tile.preloadedLibraries = @[];
    MTLTileRenderPipelineDescriptor *tileDescriptor =
        prismel_materialize_tile_descriptor(tile, &failure);
    require(tileDescriptor != nil && failure == nil, failure ?: @"tile descriptor");
    require(tileDescriptor.tileFunction == kernel &&
            tileDescriptor.binaryArchives.count == 0 &&
            tileDescriptor.preloadedLibraries.count == 0,
            @"tile descriptor ownership/schema");

    PrismelMeshTileObjects missing = {};
    failure = nil;
    require(prismel_materialize_mesh_descriptor(missing, &failure) == nil &&
            failure != nil, @"mesh required-function rejection");
    failure = nil;
    require(prismel_materialize_tile_descriptor(missing, &failure) == nil &&
            failure != nil, @"tile required-function rejection");

    NSLog(@"mesh-tile105 descriptors: schema/retention/rejection green; pipeline compilation capability-gated");
    return 0;
  }
}
