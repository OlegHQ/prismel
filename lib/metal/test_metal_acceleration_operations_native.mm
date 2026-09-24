#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdio>
#include <cstdlib>

static void require(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "%s\n", message);
    std::abort();
  }
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    require(device != nil, "no Metal device");

    MTLVisibleFunctionTableDescriptor *visible_descriptor =
        [MTLVisibleFunctionTableDescriptor visibleFunctionTableDescriptor];
    MTLIntersectionFunctionTableDescriptor *intersection_descriptor =
        [MTLIntersectionFunctionTableDescriptor intersectionFunctionTableDescriptor];
    visible_descriptor.functionCount = 4;
    intersection_descriptor.functionCount = 4;
    require(visible_descriptor.functionCount == 4 &&
                intersection_descriptor.functionCount == 4,
            "function-table descriptor round trip failed");

    NSError *error = nil;
    NSString *source =
        @"#include <metal_stdlib>\n"
         "using namespace metal;\n"
         "kernel void prismel_table_kernel(device uint *out [[buffer(0)]], "
         "uint i [[thread_position_in_grid]]) { out[i] = i; }\n";
    id<MTLLibrary> library = [device newLibraryWithSource:source
                                                  options:nil
                                                    error:&error];
    require(library != nil, "function-table library compilation failed");
    id<MTLFunction> function = [library newFunctionWithName:@"prismel_table_kernel"];
    require(function != nil, "function-table kernel lookup failed");
    id<MTLComputePipelineState> pipeline =
        [device newComputePipelineStateWithFunction:function error:&error];
    require(pipeline != nil, "function-table pipeline compilation failed");

    if ([pipeline respondsToSelector:
                     @selector(newVisibleFunctionTableWithDescriptor:)] &&
        [pipeline respondsToSelector:
                     @selector(newIntersectionFunctionTableWithDescriptor:)]) {
      id<MTLVisibleFunctionTable> visible =
          [pipeline newVisibleFunctionTableWithDescriptor:visible_descriptor];
      id<MTLIntersectionFunctionTable> intersection =
          [pipeline newIntersectionFunctionTableWithDescriptor:intersection_descriptor];
      require(visible != nil && intersection != nil,
              "supported function-table allocation failed");
      id<MTLFunctionHandle> empty_functions[1] = { nil };
      [visible setFunction:nil atIndex:0];
      [visible setFunctions:empty_functions withRange:NSMakeRange(1, 0)];
      [intersection setFunction:nil atIndex:0];
      [intersection setFunctions:empty_functions withRange:NSMakeRange(1, 0)];
      [intersection setBuffer:nil offset:0 atIndex:0];
      [intersection setVisibleFunctionTable:visible atBufferIndex:0];
      [intersection setOpaqueTriangleIntersectionFunctionWithSignature:
                        MTLIntersectionFunctionSignatureNone
                                                               atIndex:1];
      require(visible.gpuResourceID._impl != 0 &&
                  intersection.gpuResourceID._impl != 0,
              "function-table resource IDs are empty");
    } else {
      require(![pipeline respondsToSelector:
                           @selector(newVisibleFunctionTableWithDescriptor:)],
              "partial function-table capability must reject atomically");
    }

    MTLAccelerationStructurePassDescriptor *pass =
        [MTLAccelerationStructurePassDescriptor accelerationStructurePassDescriptor];
    MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *attachment =
        pass.sampleBufferAttachments[0];
    attachment.startOfEncoderSampleIndex = 2;
    attachment.endOfEncoderSampleIndex = 3;
    attachment.sampleBuffer = nil;
    pass.sampleBufferAttachments[1] = nil;
    require(attachment.startOfEncoderSampleIndex == 2 &&
                attachment.endOfEncoderSampleIndex == 3 &&
                attachment.sampleBuffer == nil,
            "acceleration pass attachment round trip failed");

    require([device respondsToSelector:
                       @selector(accelerationStructureSizesWithDescriptor:)] &&
                [device respondsToSelector:
                       @selector(newAccelerationStructureWithSize:)],
            "M1 acceleration operations unexpectedly unavailable");
  }
  std::puts("Metal acceleration operations: tables/pass/device execute-or-reject passed");
  return 0;
}
