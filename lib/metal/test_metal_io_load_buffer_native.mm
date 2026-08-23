#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <type_traits>

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
    id<MTLBuffer> destination = [device newBufferWithLength:32
                                                   options:MTLResourceStorageModeShared];
    require(destination != nil, @"destination buffer");

    NSString *failure = nil;
    require(!prismel_io_load_buffer(nil, destination, 0, 16, nil, 0,
                                    &failure) && failure != nil,
            @"missing IO command/file rejection");
    require(prismel_io_range(32, 0, 32), @"full destination range");
    require(!prismel_io_range(32, 24, 16), @"overflowing destination range");
    require(!prismel_io_range(32, NSUIntegerMax, 1),
            @"wrapped destination offset rejection");

    NSLog(@"IO load buffer: exact ABI and typed rejection/range lanes green; constructible IO handles unavailable in current raw API");
    return 0;
  }
}
