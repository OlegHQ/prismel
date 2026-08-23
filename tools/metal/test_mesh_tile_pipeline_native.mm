#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static void require(bool condition, NSString *message) {
  if (!condition) {
    NSLog(@"FAIL: %@", message);
    exit(1);
  }
}

static id<MTLLibrary> compile(id<MTLDevice> device, NSString *source) {
  NSError *error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
  require(library != nil, [NSString stringWithFormat:@"shader compile: %@", error]);
  return library;
}

static void check_copied_label(id descriptor) {
  NSMutableString *label = [NSMutableString stringWithString:@"qualified"];
  [descriptor setLabel:label];
  [label appendString:@"-mutated"];
  require([[descriptor label] isEqualToString:@"qualified"], @"label must be copied");
}

static NSString *shader_source(void) {
  return @R"metal(
#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
using M = mesh<V, void, 3, 1, topology::triangle>;
[[mesh]] void mesh_main(M out, uint tid [[thread_index_in_threadgroup]]) {
  constexpr float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
  if (tid < 3) { V v; v.position=float4(p[tid],0,1); out.set_vertex(tid,v); out.set_index(tid,tid); }
  if (tid == 0) out.set_primitive_count(1);
}
fragment float4 fragment_main() { return float4(0.25,0.5,0.75,1); }
kernel void tile_main(ushort2 p [[thread_position_in_threadgroup]]) { (void)p; }
)metal";
}

static void qualify_mesh(id<MTLDevice> device, id<MTLLibrary> library) {
  id<MTLFunction> mesh = [library newFunctionWithName:@"mesh_main"];
  id<MTLFunction> fragment = [library newFunctionWithName:@"fragment_main"];
  require(mesh && fragment, @"mesh functions");
  MTLMeshRenderPipelineDescriptor *d = [MTLMeshRenderPipelineDescriptor new];
  check_copied_label(d);
  d.meshFunction = mesh; d.fragmentFunction = fragment;
  d.maxTotalThreadsPerMeshThreadgroup = 3;
  d.requiredThreadsPerMeshThreadgroup = MTLSizeMake(3, 1, 1);
  d.rasterSampleCount = 1;
  d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  d.meshBuffers[2].mutability = MTLMutabilityImmutable;
  NSMutableArray *archives = [NSMutableArray array];
  d.binaryArchives = archives;
  d.objectLinkedFunctions = [MTLLinkedFunctions new];
  d.meshLinkedFunctions = [MTLLinkedFunctions new];
  d.fragmentLinkedFunctions = [MTLLinkedFunctions new];
  require(d.meshFunction == mesh && d.fragmentFunction == fragment, @"functions retained");
  require(d.binaryArchives.count == 0 && d.objectLinkedFunctions != nil &&
              d.meshLinkedFunctions != nil && d.fragmentLinkedFunctions != nil,
          @"mesh ownership containers copied/retained");
  d.binaryArchives = nil; d.objectLinkedFunctions = nil;
  d.meshLinkedFunctions = nil; d.fragmentLinkedFunctions = nil;
  require(d.meshBuffers[2].mutability == MTLMutabilityImmutable, @"buffer array state");
  NSError *error = nil;
  id<MTLRenderPipelineState> pipeline =
      [device newRenderPipelineStateWithMeshDescriptor:d options:MTLPipelineOptionNone
                                            reflection:nil error:&error];
  require(pipeline != nil, [NSString stringWithFormat:@"legacy mesh pipeline: %@", error]);

  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:8 height:8 mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget;
  td.storageMode = MTLStorageModeShared;
  id<MTLTexture> target = [device newTextureWithDescriptor:td];
  MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture = target;
  pass.colorAttachments[0].loadAction = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,1);
  id<MTLCommandQueue> queue = [device newCommandQueue];
  id<MTLCommandBuffer> command = [queue commandBuffer];
  id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
  [encoder setRenderPipelineState:pipeline];
  [encoder drawMeshThreadgroups:MTLSizeMake(1,1,1) threadsPerObjectThreadgroup:MTLSizeMake(1,1,1) threadsPerMeshThreadgroup:MTLSizeMake(3,1,1)];
  [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
  require(command.status == MTLCommandBufferStatusCompleted, @"mesh GPU execution");
  uint8_t pixels[8*8*4] = {};
  [target getBytes:pixels bytesPerRow:32 fromRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0];
  for (NSUInteger i=0; i<64; ++i) {
    require(pixels[i*4]==191 && pixels[i*4+1]==128 && pixels[i*4+2]==64 && pixels[i*4+3]==255,
            @"deterministic mesh pixels");
  }

  [d reset]; require(d.meshFunction == nil && d.fragmentFunction == nil, @"mesh reset");
  d.meshFunction = mesh;
  d.fragmentFunction = fragment;
  d.maxTotalThreadsPerMeshThreadgroup = 4;
  d.requiredThreadsPerMeshThreadgroup = MTLSizeMake(4,1,1);
  d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  d.rasterSampleCount = 3;
  NSError *bad_error = nil;
  id bad = [device newRenderPipelineStateWithMeshDescriptor:d options:0 reflection:nil error:&bad_error];
  require(bad == nil && bad_error != nil, @"mesh failure unwind");
}

static void qualify_tile(id<MTLDevice> device, id<MTLLibrary> library) {
  id<MTLFunction> tile = [library newFunctionWithName:@"tile_main"];
  require(tile != nil, @"tile function");
  MTLTileRenderPipelineDescriptor *d = [MTLTileRenderPipelineDescriptor new];
  check_copied_label(d); d.tileFunction = tile; d.rasterSampleCount = 1;
  d.threadgroupSizeMatchesTileSize = NO; d.maxTotalThreadsPerThreadgroup = 1;
  d.requiredThreadsPerThreadgroup = MTLSizeMake(1,1,1);
  d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  d.tileBuffers[4].mutability = MTLMutabilityMutable;
  require(d.tileFunction == tile && d.tileBuffers[4].mutability == MTLMutabilityMutable,
          @"tile ownership and buffer array");
  NSError *error = nil;
  id<MTLRenderPipelineState> pipeline =
      [device newRenderPipelineStateWithTileDescriptor:d options:MTLPipelineOptionNone reflection:nil error:&error];
  require(pipeline != nil, [NSString stringWithFormat:@"legacy tile pipeline: %@", error]);
  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModeShared;
  id<MTLTexture> target = [device newTextureWithDescriptor:td];
  MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture = target;
  pass.colorAttachments[0].loadAction = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  id<MTLCommandQueue> queue = [device newCommandQueue];
  id<MTLCommandBuffer> command = [queue commandBuffer];
  id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
  [encoder setRenderPipelineState:pipeline];
  [encoder dispatchThreadsPerTile:MTLSizeMake(1,1,1)]; [encoder endEncoding];
  [command commit]; [command waitUntilCompleted];
  uint8_t pixel[4] = {};
  [target getBytes:pixel bytesPerRow:4 fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];
  require(command.status == MTLCommandBufferStatusCompleted && pixel[0] == 0 &&
              pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255,
          @"deterministic tile GPU execution and stored attachment");
  MTLTileRenderPipelineDescriptor *reset_fixture = [MTLTileRenderPipelineDescriptor new];
  reset_fixture.tileFunction = tile; [reset_fixture reset];
  require(reset_fixture.tileFunction == nil, @"tile reset");
}

int main(void) { @autoreleasepool {
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); require(device != nil, @"Metal device");
  require([device supportsFamily:MTLGPUFamilyApple7], @"M1/Apple7 qualification device");
  id<MTLLibrary> library = compile(device, shader_source());
  qualify_mesh(device, library); qualify_tile(device, library);
  NSLog(@"legacy mesh/tile pipeline ownership, unwind, and GPU conformance passed");
  return 0;
}}
