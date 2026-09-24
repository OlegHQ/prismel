#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <atomic>
#include <cstddef>
#include <cstring>
#include <memory>

@interface PrismelIOScratch : NSObject <MTLIOScratchBuffer>
@property(nonatomic, strong) id<MTLBuffer> buffer;
@end
@implementation PrismelIOScratch
@end

@interface PrismelIOAllocator : NSObject <MTLIOScratchBufferAllocator>
@property(nonatomic, strong) id<MTLDevice> device;
@property(nonatomic) NSUInteger allocations;
@end
@implementation PrismelIOAllocator
- (id<MTLIOScratchBuffer>)newScratchBufferWithMinimumSize:(NSUInteger)size {
  PrismelIOScratch *scratch = [PrismelIOScratch new];
  scratch.buffer = [self.device newBufferWithLength:size
                                            options:MTLResourceStorageModePrivate];
  self.allocations += 1;
  return scratch;
}
@end

static const char *const kIds[] = {
  "method:-[MTLIOCommandBuffer addBarrier]", "method:-[MTLIOCommandBuffer addCompletedHandler:]",
  "method:-[MTLIOCommandBuffer copyStatusToBuffer:offset:]", "method:-[MTLIOCommandBuffer enqueue]",
  "method:-[MTLIOCommandBuffer error]", "method:-[MTLIOCommandBuffer label]",
  "method:-[MTLIOCommandBuffer loadBytes:size:sourceHandle:sourceHandleOffset:]",
  "method:-[MTLIOCommandBuffer loadTexture:slice:level:size:sourceBytesPerRow:sourceBytesPerImage:destinationOrigin:sourceHandle:sourceHandleOffset:]",
  "method:-[MTLIOCommandBuffer popDebugGroup]", "method:-[MTLIOCommandBuffer pushDebugGroup:]",
  "method:-[MTLIOCommandBuffer setLabel:]", "method:-[MTLIOCommandBuffer signalEvent:value:]",
  "method:-[MTLIOCommandBuffer tryCancel]", "method:-[MTLIOCommandBuffer waitForEvent:value:]",
  "property:MTLIOCommandBuffer:error", "property:MTLIOCommandBuffer:label",
  "property:MTLIOCommandBuffer:status", "typedef:MTLIOCommandBufferHandler",
  "method:-[MTLIOCommandQueue commandBufferWithUnretainedReferences]",
  "method:-[MTLIOCommandQueue enqueueBarrier]", "method:-[MTLIOCommandQueue label]",
  "method:-[MTLIOCommandQueue setLabel:]", "method:-[MTLIOCommandQueueDescriptor scratchBufferAllocator]",
  "method:-[MTLIOCommandQueueDescriptor setScratchBufferAllocator:]", "method:-[MTLIOFileHandle label]",
  "method:-[MTLIOFileHandle setLabel:]", "method:-[MTLIOScratchBuffer buffer]",
  "method:-[MTLIOScratchBufferAllocator newScratchBufferWithMinimumSize:]",
  "property:MTLIOCommandQueue:label", "property:MTLIOCommandQueueDescriptor:scratchBufferAllocator",
  "property:MTLIOFileHandle:label", "property:MTLIOScratchBuffer:buffer",
  "protocol:MTLIOScratchBuffer", "protocol:MTLIOScratchBufferAllocator",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 34, "IO command/queue34 drift");

int main() { @autoreleasepool {
  (void)kIds;
  if (@available(macOS 13.0, *)) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
    PrismelIOAllocator *allocator = [PrismelIOAllocator new]; allocator.device = device;
    id<MTLIOScratchBuffer> direct = [allocator newScratchBufferWithMinimumSize:4096];
    if (!direct || direct.buffer.length < 4096 || allocator.allocations != 1) return 1;
    MTLIOCommandQueueDescriptor *qd = [MTLIOCommandQueueDescriptor new];
    qd.type = MTLIOCommandQueueTypeConcurrent; qd.maxCommandBufferCount = 4;
    qd.scratchBufferAllocator = allocator;
    if (qd.scratchBufferAllocator != allocator) return 2;
    NSError *error = nil;
    id<MTLIOCommandQueue> queue = [device newIOCommandQueueWithDescriptor:qd error:&error];
    if (!queue) return 77;
    queue.label = @"prismel-io34";
    if (![queue.label isEqualToString:@"prismel-io34"]) return 3;
    [queue enqueueBarrier];

    uint8_t payload[64]; for (NSUInteger i=0;i<sizeof(payload);++i) payload[i]=(uint8_t)i;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
      [[NSUUID UUID].UUIDString stringByAppendingString:@".raw"]];
    if (![[NSData dataWithBytes:payload length:sizeof(payload)] writeToFile:path atomically:YES]) return 4;
    id<MTLIOFileHandle> file = [device newIOFileHandleWithURL:[NSURL fileURLWithPath:path] error:&error];
    if (!file) return 77;
    file.label = @"prismel-source"; if (![file.label isEqualToString:@"prismel-source"]) return 5;

    char loaded[sizeof(payload)] = {};
    id<MTLBuffer> status = [device newBufferWithLength:64 options:MTLResourceStorageModeShared];
    MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    td.storageMode = MTLStorageModePrivate;
    id<MTLTexture> texture = [device newTextureWithDescriptor:td];
    if (!texture) return 6;
    id<MTLSharedEvent> event = [device newSharedEvent]; event.signaledValue = 1;
    id<MTLIOCommandBuffer> command = [queue commandBufferWithUnretainedReferences];
    if (!command) return 6;
    command.label = @"prismel-command";
    [command pushDebugGroup:@"load"]; [command addBarrier];
    [command waitForEvent:event value:1];
    [command loadBytes:loaded size:sizeof(loaded) sourceHandle:file sourceHandleOffset:0];
    [command loadTexture:texture slice:0 level:0 size:MTLSizeMake(4,4,1)
        sourceBytesPerRow:16 sourceBytesPerImage:64 destinationOrigin:MTLOriginMake(0,0,0)
        sourceHandle:file sourceHandleOffset:0];
    [command copyStatusToBuffer:status offset:0];
    [command signalEvent:event value:2]; [command popDebugGroup];
    auto callbacks = std::make_shared<std::atomic<int>>(0);
    [command addCompletedHandler:^(id<MTLIOCommandBuffer> completed) {
      if (completed == command) callbacks->fetch_add(1, std::memory_order_relaxed);
    }];
    [command enqueue]; [command commit]; [command waitUntilCompleted];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    if (command.status != MTLIOStatusComplete || command.error != nil ||
        ![command.label isEqualToString:@"prismel-command"] ||
        callbacks->load(std::memory_order_relaxed) != 1 || event.signaledValue < 2 ||
        std::memcmp(loaded,payload,sizeof(payload)) != 0) return 7;
    id<MTLBuffer> texture_readback =
      [device newBufferWithLength:sizeof(payload) options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> read = [[device newCommandQueue] commandBuffer];
    id<MTLBlitCommandEncoder> reader = [read blitCommandEncoder];
    [reader copyFromTexture:texture sourceSlice:0 sourceLevel:0
      sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(4,4,1)
      toBuffer:texture_readback destinationOffset:0 destinationBytesPerRow:16
      destinationBytesPerImage:64];
    [reader endEncoding]; [read commit]; [read waitUntilCompleted];
    if (read.status != MTLCommandBufferStatusCompleted ||
        std::memcmp(texture_readback.contents,payload,sizeof(payload)) != 0) return 8;

    id<MTLIOCommandBuffer> cancelled = [queue commandBufferWithUnretainedReferences];
    [cancelled tryCancel]; [cancelled commit]; [cancelled waitUntilCompleted];
    if (cancelled.status != MTLIOStatusCancelled && cancelled.status != MTLIOStatusComplete)
      return 9;
  }
  return 0;
} }
