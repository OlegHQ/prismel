#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <type_traits>
#include <unistd.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#include "../../tools/metal/metal_io_counter_ownership_materializers.inc"
#pragma clang diagnostic pop

using LoadBufferSignature = bool (*)(id<MTLIOCommandBuffer>, id<MTLBuffer>,
                                     NSUInteger, NSUInteger,
                                     id<MTLIOFileHandle>, NSUInteger,
                                     NSString **);
static_assert(std::is_same_v<decltype(&prismel_io_load_buffer),
                             LoadBufferSignature>);

static void require(bool condition, NSString *message) {
  if (!condition) {
    @throw [NSException exceptionWithName:@"IOLoadBuffer"
                                   reason:message
                                 userInfo:nil];
  }
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    if (@available(macOS 13.0, *)) {
      const unsigned char expected[16] =
          {0x50,0x52,0x49,0x53,0x4d,0x45,0x4c,0x2d,
           0x49,0x4f,0x2d,0x43,0x48,0x41,0x49,0x4e};
      NSString *path = [NSTemporaryDirectory()
          stringByAppendingPathComponent:[NSString
              stringWithFormat:@"prismel-metal-io-%d.bin", getpid()]];
      NSError *error = nil;
      NSData *payload = [NSData dataWithBytes:expected length:sizeof(expected)];
      require([payload writeToFile:path options:NSDataWritingAtomic error:&error],
              error.localizedDescription ?: @"temporary IO fixture");

      MTLIOCommandQueueDescriptor *descriptor = [MTLIOCommandQueueDescriptor new];
      descriptor.type = MTLIOCommandQueueTypeSerial;
      descriptor.maxCommandBufferCount = 1;
      descriptor.maxCommandsInFlight = 4;
      id<MTLIOCommandQueue> queue =
          [device newIOCommandQueueWithDescriptor:descriptor error:&error];
      id<MTLIOFileHandle> file = queue == nil ? nil :
          [device newIOFileHandleWithURL:[NSURL fileURLWithPath:path]
                                   error:&error];
      if (queue == nil || file == nil) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return 77;
      }
      queue.label = @"io-load-buffer-queue";
      file.label = @"io-load-buffer-file";

      id<MTLBuffer> destination =
          [device newBufferWithLength:sizeof(expected)
                              options:MTLResourceStorageModeShared];
      require(destination != nil, @"destination buffer");
      id<MTLIOCommandBuffer> commands = [queue commandBuffer];
      require(commands != nil, @"IO command buffer");
      [commands loadBuffer:destination offset:0 size:sizeof(expected)
              sourceHandle:file sourceHandleOffset:0];
      [commands commit];
      [commands waitUntilCompleted];
      const bool completed = commands.status == MTLIOStatusComplete;
      const bool bytes_match =
          memcmp(destination.contents, expected, sizeof(expected)) == 0;
      [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
      require(completed, commands.error.localizedDescription ?: @"IO completion");
      require(bytes_match, @"IO load exact bytes");
      NSLog(@"IO load buffer: real queue/file/command chain and exact bytes green");
      return 0;
    }

    return 77;

  }
}
