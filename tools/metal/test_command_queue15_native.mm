#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static bool valid_max(NSInteger value) { return value > 0; }
int main(void) { @autoreleasepool {
  if (valid_max(0) || valid_max(-1) || !valid_max(1)) return 1;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (device == nil) return 77;
  MTLCommandQueueDescriptor *queueDescriptor = [MTLCommandQueueDescriptor new];
  queueDescriptor.maxCommandBufferCount = 3; queueDescriptor.logState = nil;
  if (queueDescriptor.maxCommandBufferCount != 3 || queueDescriptor.logState != nil) return 2;
  id<MTLCommandQueue> queue = nil;
  if (@available(macOS 15.0, *)) queue = [device newCommandQueueWithDescriptor:queueDescriptor];
  else queue = [device newCommandQueue];
  if (queue == nil) return 3;
  queue.label = @"queue_λ";
  if (![queue.label isEqualToString:@"queue_λ"] ||
      queue.device.registryID != device.registryID) return 4;
  __strong id<MTLCommandBuffer> unretained = [queue commandBufferWithUnretainedReferences];
  if (unretained == nil) return 5;
  MTLCommandBufferDescriptor *bufferDescriptor = [MTLCommandBufferDescriptor new];
  bufferDescriptor.retainedReferences = YES; bufferDescriptor.errorOptions = 0;
  bufferDescriptor.logState = nil;
  id<MTLCommandBuffer> described = [queue commandBufferWithDescriptor:bufferDescriptor];
  if (described == nil || !bufferDescriptor.retainedReferences) return 6;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [queue insertDebugCaptureBoundary];
#pragma clang diagnostic pop
  [unretained commit]; [described commit];
  [unretained waitUntilCompleted]; [described waitUntilCompleted];
  if (unretained.status == MTLCommandBufferStatusError ||
      described.status == MTLCommandBufferStatusError) return 7;
  queue.label = nil; if (queue.label != nil) return 8;
  return 0;
} }
