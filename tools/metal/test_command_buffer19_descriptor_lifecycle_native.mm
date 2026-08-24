#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <atomic>
#include <cstddef>
#include <memory>

static const char *const kIds[] = {
  "class:MTLCommandBufferDescriptor",
  "method:-[MTLCommandBufferDescriptor errorOptions]",
  "method:-[MTLCommandBufferDescriptor logState]",
  "method:-[MTLCommandBufferDescriptor retainedReferences]",
  "method:-[MTLCommandBufferDescriptor setErrorOptions:]",
  "method:-[MTLCommandBufferDescriptor setLogState:]",
  "method:-[MTLCommandBufferDescriptor setRetainedReferences:]",
  "method:-[MTLCommandBufferEncoderInfo debugSignposts]",
  "method:-[MTLCommandBufferEncoderInfo errorState]",
  "method:-[MTLCommandBufferEncoderInfo label]",
  "property:MTLCommandBufferDescriptor:errorOptions",
  "property:MTLCommandBufferDescriptor:logState",
  "property:MTLCommandBufferDescriptor:retainedReferences",
  "property:MTLCommandBufferEncoderInfo:debugSignposts",
  "property:MTLCommandBufferEncoderInfo:errorState",
  "property:MTLCommandBufferEncoderInfo:label",
  "protocol:MTLCommandBufferEncoderInfo", "protocol:MTLLogContainer",
  "typedef:MTLCommandBufferHandler",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 19,
              "CommandBuffer19 exact closure drift");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  MTLCommandBufferDescriptor *descriptor = [MTLCommandBufferDescriptor new];
  descriptor.retainedReferences = YES;
  descriptor.errorOptions = MTLCommandBufferErrorOptionEncoderExecutionStatus;
  if (!descriptor.retainedReferences ||
      descriptor.errorOptions != MTLCommandBufferErrorOptionEncoderExecutionStatus)
    return 1;

  if (@available(macOS 15.0, *)) {
    MTLLogStateDescriptor *log_descriptor = [MTLLogStateDescriptor new];
    log_descriptor.level = MTLLogLevelError; log_descriptor.bufferSize = 1024;
    NSError *log_error = nil;
    id<MTLLogState> log = [device newLogStateWithDescriptor:log_descriptor error:&log_error];
    if (log != nil) {
      __weak id<MTLLogState> weak_log = log;
      descriptor.logState = log; log = nil;
      if (weak_log == nil || descriptor.logState != weak_log) return 2;
      descriptor.logState = nil;
      if (descriptor.logState != nil) return 3;
    }
  }

  id<MTLCommandQueue> queue = [device newCommandQueue];
  id<MTLCommandBuffer> command = [queue commandBufferWithDescriptor:descriptor];
  if (!command) return 4;
  auto callbacks = std::make_shared<std::atomic<int>>(0);
  [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
    if (completed == command) callbacks->fetch_add(1, std::memory_order_relaxed);
  }];
  id<MTLBuffer> buffer = [device newBufferWithLength:64 options:MTLResourceStorageModeShared];
  __weak id<MTLBuffer> weak_buffer = buffer;
  id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
  blit.label = @"command-buffer19-blit";
  [blit pushDebugGroup:@"retained-resource"];
  [blit fillBuffer:buffer range:NSMakeRange(0,64) value:0x5a];
  [blit popDebugGroup]; [blit endEncoding];
  buffer = nil;
  if (weak_buffer == nil) return 5;
  [command commit]; [command waitUntilCompleted];
  if (command.status != MTLCommandBufferStatusCompleted ||
      callbacks->load(std::memory_order_relaxed) != 1)
    return 6;

  /* EncoderInfo values are supplied only for failed command buffers.  Do not
     fabricate them on the successful path; when present, their collections
     and labels must be stable snapshots. */
  NSArray<id<MTLCommandBufferEncoderInfo>> *infos =
      command.error.userInfo[MTLCommandBufferEncoderInfoErrorKey];
  for (id<MTLCommandBufferEncoderInfo> info in infos) {
    if (info.label == nil || info.debugSignposts == nil) return 7;
    (void)info.errorState;
  }
  return 0;
} }
