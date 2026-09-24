#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <atomic>
#include <cstddef>
#include <memory>

static const char *const kIds[] = {
  "method:-[MTL4Compiler newMachineLearningPipelineStateWithDescriptor:completionHandler:]",
  "typedef:MTL4NewMachineLearningPipelineStateCompletionHandler",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 2,
              "MTL4Compiler ML callback2 drift");

int main() { @autoreleasepool {
  (void)kIds;
  if (@available(macOS 26.0, *)) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:
      @"#include <metal_stdlib>\nusing namespace metal;"
       "kernel void ml2(device uint *out [[buffer(0)]]) { out[0]=2; }"
      options:nil error:&error];
    if (!library) return 77;
    /* Current M1 classic runtime libraries lack the internal executable
       representation the Metal4 ML compiler requires.  Invoking the async
       selector anyway throws on Metal's worker queue and terminates the
       process, beyond the caller's @try scope. */
    SEL executable_selector = NSSelectorFromString(@"executableWithDeviceSelection:");
    if (![library respondsToSelector:executable_selector]) return 77;
    MTL4LibraryFunctionDescriptor *function = [MTL4LibraryFunctionDescriptor new];
    function.library = library; function.name = @"ml2";
    MTL4MachineLearningPipelineDescriptor *descriptor =
      [MTL4MachineLearningPipelineDescriptor new];
    descriptor.machineLearningFunctionDescriptor = function;
    MTL4CompilerDescriptor *compiler_descriptor = [MTL4CompilerDescriptor new];
    id<MTL4Compiler> compiler =
      [device newCompilerWithDescriptor:compiler_descriptor error:&error];
    if (!compiler) return 77;

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    auto calls = std::make_shared<std::atomic<int>>(0);
    auto valid = std::make_shared<std::atomic<bool>>(false);
    MTL4NewMachineLearningPipelineStateCompletionHandler handler =
      ^(id<MTL4MachineLearningPipelineState> pipeline, NSError *failure) {
        calls->fetch_add(1);
        valid->store((pipeline != nil) != (failure != nil));
        if (pipeline && pipeline.device.registryID != device.registryID)
          valid->store(false);
        dispatch_semaphore_signal(done);
      };
    id<MTL4CompilerTask> task = nil;
    @try {
      task = [compiler newMachineLearningPipelineStateWithDescriptor:descriptor
                                                   completionHandler:handler];
    } @catch (NSException *exception) {
      if (![exception.name isEqualToString:NSInvalidArgumentException]) return 1;
      return 77;
    }
    if (!task) return 2;
    if (dispatch_semaphore_wait(done,
          dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)) != 0) return 3;
    if (calls->load() != 1 || !valid->load()) return 4;
    /* Completion is one-shot even when the classic-library ML graph is
       rejected asynchronously with an NSError. */
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW,
          20 * NSEC_PER_MSEC)) == 0) return 5;
  }
  return 0;
} }
