#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <atomic>
#include <cstddef>
#include <memory>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static const char *const kIds[] = {
  "class:MTLAttribute", "class:MTLFunctionReflection", "class:MTLVertexAttribute",
  "typedef:MTLAutoreleasedArgument",
  "typedef:MTLAutoreleasedComputePipelineReflection",
  "typedef:MTLAutoreleasedRenderPipelineReflection",
  "typedef:MTLNewComputePipelineStateWithReflectionCompletionHandler",
  "typedef:MTLNewRenderPipelineStateWithReflectionCompletionHandler",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 8,
              "Library8 metadata closure drift");

int main() { @autoreleasepool {
  (void)kIds;
  MTLAutoreleasedArgument autoreleased_argument = nil;
  MTLAutoreleasedComputePipelineReflection compute_out = nil;
  MTLAutoreleasedRenderPipelineReflection render_out = nil;
  (void)autoreleased_argument; (void)compute_out; (void)render_out;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  NSError *error = nil;
  NSString *source =
    @"#include <metal_stdlib>\nusing namespace metal;\n"
     "struct V { float4 p [[attribute(0)]]; };\n"
     "vertex float4 lib8_vertex(V in [[stage_in]]) { return in.p; }\n"
     "fragment float4 lib8_fragment() { return float4(1); }\n"
     "kernel void lib8_compute(device uint *out [[buffer(0)]]) { out[0] = 8; }";
  id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
  if (!library) return 77;
  id<MTLFunction> vertex = [library newFunctionWithName:@"lib8_vertex"];
  id<MTLFunction> fragment = [library newFunctionWithName:@"lib8_fragment"];
  id<MTLFunction> compute = [library newFunctionWithName:@"lib8_compute"];
  if (!vertex || !fragment || !compute) return 1;
  MTLAttribute *stage = vertex.stageInputAttributes.firstObject;
  MTLVertexAttribute *legacy = vertex.vertexAttributes.firstObject;
  if (!stage || stage.attributeIndex != 0 || ![stage.name isEqualToString:@"p"])
    return 2;
  if (legacy && (legacy.attributeIndex != 0 || ![legacy.name isEqualToString:@"p"]))
    return 3;

  dispatch_group_t group = dispatch_group_create();
  auto callbacks = std::make_shared<std::atomic<int>>(0);
  auto successes = std::make_shared<std::atomic<int>>(0);
  MTLComputePipelineDescriptor *cp = [MTLComputePipelineDescriptor new];
  cp.computeFunction = compute;
  dispatch_group_enter(group);
  MTLNewComputePipelineStateWithReflectionCompletionHandler compute_handler =
    ^(id<MTLComputePipelineState> state, MTLComputePipelineReflection *reflection,
      NSError *failure) {
      callbacks->fetch_add(1);
      if (state && !failure) successes->fetch_add(1);
      if (reflection && !state) successes->store(-100);
      dispatch_group_leave(group);
    };
  [device newComputePipelineStateWithDescriptor:cp options:MTLPipelineOptionArgumentInfo
    completionHandler:compute_handler];

  MTLRenderPipelineDescriptor *rp = [MTLRenderPipelineDescriptor new];
  rp.vertexFunction = vertex; rp.fragmentFunction = fragment;
  rp.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  rp.vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
  rp.vertexDescriptor.attributes[0].format = MTLVertexFormatFloat4;
  rp.vertexDescriptor.attributes[0].bufferIndex = 0;
  rp.vertexDescriptor.layouts[0].stride = 4 * sizeof(float);
  dispatch_group_enter(group);
  MTLNewRenderPipelineStateWithReflectionCompletionHandler render_handler =
    ^(id<MTLRenderPipelineState> state, MTLRenderPipelineReflection *reflection,
      NSError *failure) {
      callbacks->fetch_add(1);
      if (state && !failure) successes->fetch_add(1);
      if (reflection && !state) successes->store(-100);
      dispatch_group_leave(group);
    };
  [device newRenderPipelineStateWithDescriptor:rp options:MTLPipelineOptionArgumentInfo
    completionHandler:render_handler];
  if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 30*NSEC_PER_SEC)) != 0)
    return 4;
  if (callbacks->load() != 2 || successes->load() != 2) return 5;

  if (@available(macOS 26.0, *)) {
    MTLFunctionReflection *reflection =
      [library reflectionForFunctionWithName:@"lib8_compute"];
    if (!reflection || reflection.bindings.count == 0) return 6;
  }
  return 0;
} }

#pragma clang diagnostic pop
