#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wunused-function"
#include "../../tools/metal/metal_pipeline_header_mechanical_generated.mm"
#pragma clang diagnostic pop

static void require(bool condition, NSString *message) {
  if (!condition) @throw [NSException exceptionWithName:@"Pipeline113Descriptor"
                                                  reason:message userInfo:nil];
}

int main() {
  @autoreleasepool {
    NSUInteger exercised = 0;
    MTLComputePipelineDescriptor *compute = [MTLComputePipelineDescriptor new];
    require(compute != nil, @"compute descriptor construction");
    if ([compute respondsToSelector:@selector(setRequiredThreadsPerThreadgroup:)]) {
      MTLSize expected = MTLSizeMake(2, 3, 4);
      prismel_pipeline_mtlcomputepipelinedescriptor_setrequiredthreadsperthreadgroup_(compute, expected);
      ++exercised;
      MTLSize actual = prismel_pipeline_mtlcomputepipelinedescriptor_requiredthreadsperthreadgroup(compute);
      ++exercised;
      require(actual.width == expected.width && actual.height == expected.height && actual.depth == expected.depth,
              @"compute required-thread roundtrip");
    }
    prismel_pipeline_mtlcomputepipelinedescriptor_reset(compute); ++exercised;

    MTLRenderPipelineDescriptor *render = [MTLRenderPipelineDescriptor new];
    require(render != nil, @"render descriptor construction");
#define ROUNDTRIP(SETTER, GETTER, VALUE, MESSAGE) do { \
      prismel_pipeline_mtlrenderpipelinedescriptor_##SETTER(render, VALUE); ++exercised; \
      require(prismel_pipeline_mtlrenderpipelinedescriptor_##GETTER(render) == VALUE, MESSAGE); ++exercised; \
    } while (0)
    ROUNDTRIP(setdepthattachmentpixelformat_, depthattachmentpixelformat,
              MTLPixelFormatDepth32Float, @"depth format roundtrip");
    ROUNDTRIP(setinputprimitivetopology_, inputprimitivetopology,
              MTLPrimitiveTopologyClassTriangle, @"input topology roundtrip");
    ROUNDTRIP(setsamplecount_, samplecount, (NSUInteger)4, @"sample count roundtrip");
    ROUNDTRIP(setstencilattachmentpixelformat_, stencilattachmentpixelformat,
              MTLPixelFormatStencil8, @"stencil format roundtrip");
    ROUNDTRIP(settessellationoutputwindingorder_, tessellationoutputwindingorder,
              MTLWindingClockwise, @"tessellation winding roundtrip");
#undef ROUNDTRIP
    prismel_pipeline_mtlrenderpipelinedescriptor_reset(render); ++exercised;

    /* 12 selectors are baseline; the two compute property selectors are
       capability-gated together on older runtimes. */
    require(exercised == 12 || exercised == 14, @"descriptor selector accounting");
    NSLog(@"pipeline113 descriptor native: %lu/14 selectors exercised; six property companions mapped",
          (unsigned long)exercised);
    return 0;
  }
}
