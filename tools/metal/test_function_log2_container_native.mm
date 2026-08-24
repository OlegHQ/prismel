#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kIds[] = {
  "protocol:MTLFunctionLog", "protocol:MTLFunctionLogDebugLocation",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 2,
              "FunctionLog2 exact protocol closure drift");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  MTLCommandBufferDescriptor *descriptor = [MTLCommandBufferDescriptor new];
  descriptor.errorOptions = MTLCommandBufferErrorOptionEncoderExecutionStatus;
  id<MTLCommandQueue> queue = [device newCommandQueue];
  id<MTLCommandBuffer> command = [queue commandBufferWithDescriptor:descriptor];
  id<MTLBlitCommandEncoder> encoder = [command blitCommandEncoder];
  encoder.label = @"function-log2-success";
  [encoder insertDebugSignpost:@"real-log-container"];
  [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
  if (command.status != MTLCommandBufferStatusCompleted || command.error != nil)
    return 1;

  id<MTLLogContainer> logs = command.logs;
  if (logs == nil) return 77;
  NSUInteger count = 0;
  for (id<MTLFunctionLog> log in logs) {
    ++count;
    if (![log conformsToProtocol:@protocol(MTLFunctionLog)]) return 3;
    if (log.type != MTLFunctionLogTypeValidation) return 4;
    id<MTLFunctionLogDebugLocation> location = log.debugLocation;
    if (location != nil) {
      if (![location conformsToProtocol:@protocol(MTLFunctionLogDebugLocation)])
        return 5;
      NSString *function_name = [location.functionName copy];
      NSURL *url = [location.URL copy];
      NSUInteger line = location.line, column = location.column;
      (void)function_name; (void)url; (void)line; (void)column;
    }
    NSString *encoder_label = [log.encoderLabel copy];
    id<MTLFunction> function = log.function;
    (void)encoder_label; (void)function;
  }
  /* A successful command normally has zero entries.  Real FunctionLog values
     are diagnostics owned by a failed command; absence is not a fake object. */
  if (count != 0) return 6;
  return 0;
} }
