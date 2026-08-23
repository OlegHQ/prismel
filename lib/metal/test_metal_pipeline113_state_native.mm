#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wunused-function"
#include "../../tools/metal/metal_pipeline_header_mechanical_generated.mm"
#pragma clang diagnostic pop

static void require(bool condition, NSString *message) {
  if (!condition) {
    @throw [NSException exceptionWithName:@"Pipeline113"
                                   reason:message
                                 userInfo:nil];
  }
}

static bool has(id object, SEL selector) {
  return [object respondsToSelector:selector];
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;

    NSError *error = nil;
    NSString *source =
        @"#include <metal_stdlib>\n"
         "using namespace metal;\n"
         "kernel void k(device uint *out [[buffer(0)]], uint i [[thread_position_in_grid]]) { out[i] = i; }\n"
         "struct V { float4 p [[position]]; };\n"
         "vertex V v(uint i [[vertex_id]]) { float2 q[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)}; return {float4(q[i],0,1)}; }\n"
         "fragment float4 f() { return float4(0,1,0,1); }";
    id<MTLLibrary> library = [device newLibraryWithSource:source
                                                  options:nil
                                                    error:&error];
    require(library != nil, error.localizedDescription ?: @"library creation");

    id<MTLFunction> kernel = [library newFunctionWithName:@"k"];
    id<MTLComputePipelineState> compute =
        [device newComputePipelineStateWithFunction:kernel error:&error];
    require(compute != nil, error.localizedDescription ?: @"compute pipeline");

    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = [library newFunctionWithName:@"v"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"f"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    id<MTLRenderPipelineState> render =
        [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    require(render != nil, error.localizedDescription ?: @"render pipeline");

    NSUInteger exercised = 0;
#define CHECK(OBJECT, SELECTOR, EXPRESSION) \
    do { if (has((OBJECT), @selector(SELECTOR))) { (void)(EXPRESSION); ++exercised; } } while (0)
    CHECK(compute, gpuResourceID,
          prismel_pipeline_mtlcomputepipelinestate_gpuresourceid(compute)._impl);
    CHECK(compute, requiredThreadsPerThreadgroup,
          prismel_pipeline_mtlcomputepipelinestate_requiredthreadsperthreadgroup(compute));
    CHECK(compute, shaderValidation,
          prismel_pipeline_mtlcomputepipelinestate_shadervalidation(compute));
    CHECK(compute, supportIndirectCommandBuffers,
          prismel_pipeline_mtlcomputepipelinestate_supportindirectcommandbuffers(compute));
    CHECK(compute, imageblockMemoryLengthForDimensions:,
          prismel_pipeline_mtlcomputepipelinestate_imageblockmemorylengthfordimensions_(compute, MTLSizeMake(1, 1, 1)));
    CHECK(render, gpuResourceID,
          prismel_pipeline_mtlrenderpipelinestate_gpuresourceid(render)._impl);
    CHECK(render, imageblockSampleLength,
          prismel_pipeline_mtlrenderpipelinestate_imageblocksamplelength(render));
    CHECK(render, requiredThreadsPerMeshThreadgroup,
          prismel_pipeline_mtlrenderpipelinestate_requiredthreadspermeshthreadgroup(render));
    CHECK(render, requiredThreadsPerObjectThreadgroup,
          prismel_pipeline_mtlrenderpipelinestate_requiredthreadsperobjectthreadgroup(render));
    CHECK(render, requiredThreadsPerTileThreadgroup,
          prismel_pipeline_mtlrenderpipelinestate_requiredthreadspertilethreadgroup(render));
    CHECK(render, shaderValidation,
          prismel_pipeline_mtlrenderpipelinestate_shadervalidation(render));
    CHECK(render, supportIndirectCommandBuffers,
          prismel_pipeline_mtlrenderpipelinestate_supportindirectcommandbuffers(render));
    CHECK(render, imageblockMemoryLengthForDimensions:,
          prismel_pipeline_mtlrenderpipelinestate_imageblockmemorylengthfordimensions_(render, MTLSizeMake(1, 1, 1)));
#undef CHECK

    require(exercised >= 5, @"expected baseline pipeline state selectors");
    NSLog(@"pipeline113 state native: %lu/13 selectors exercised; remaining capability-gated",
          (unsigned long)exercised);
    return 0;
  }
}
