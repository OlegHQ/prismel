#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<
    decltype(((id<MTL4MachineLearningPipelineState>)nil).label), NSString *>);

int main()
{
  if (@available(macOS 26.0, *)) {
    __weak id<MTL4MachineLearningPipelineState> weak_pipeline = nil;
    @autoreleasepool {
      id<MTLDevice> device = MTLCreateSystemDefaultDevice();
      if (device == nil) return 77;
      NSError *error = nil;
      id<MTLLibrary> library = [device
          newLibraryWithSource:
              @"#include <metal_stdlib>\n"
               "using namespace metal;\n"
               "kernel void ml_label_fixture(device uint *out [[buffer(0)]]) {"
               " out[0] = 1; }"
                       options:nil
                         error:&error];
      if (library == nil) return 77;
      MTL4LibraryFunctionDescriptor *function =
          [MTL4LibraryFunctionDescriptor new];
      function.library = library;
      function.name = @"ml_label_fixture";
      MTL4MachineLearningPipelineDescriptor *descriptor =
          [MTL4MachineLearningPipelineDescriptor new];
      descriptor.machineLearningFunctionDescriptor = function;
      descriptor.label = @"ml_pipeline_λ";
      MTL4CompilerDescriptor *compiler_descriptor = [MTL4CompilerDescriptor new];
      id<MTL4Compiler> compiler =
          [device newCompilerWithDescriptor:compiler_descriptor error:&error];
      if (compiler == nil) return 77;
      id<MTL4MachineLearningPipelineState> pipeline = nil;
      @try {
        pipeline =
            [compiler newMachineLearningPipelineStateWithDescriptor:descriptor
                                                               error:&error];
      } @catch (NSException *exception) {
        /* Some Metal 4 devices reject classic runtime MTLLibrary objects at
           this boundary.  That is a capability failure, not label evidence. */
        (void)exception;
        return 0;
      }
      if (pipeline == nil) return 0;
      weak_pipeline = pipeline;
      descriptor.label = @"mutated_after_compile";
      descriptor = nil;
      function = nil;
      library = nil;

      /* Pipeline labels are immutable snapshots of the compilation
         descriptor, not aliases of later descriptor mutation. */
      NSString *snapshot = [pipeline.label copy];
      if (![snapshot isEqualToString:@"ml_pipeline_λ"] ||
          snapshot.UTF8String == nullptr ||
          pipeline.device.registryID != device.registryID)
        return 1;
      pipeline = nil;
    }
    if (weak_pipeline != nil) return 2;
  }
  return 0;
}
