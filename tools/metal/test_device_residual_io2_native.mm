#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

int main()
{
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    if (@available(macOS 13.0, *)) {
      NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      id<MTLIOFileHandle> file = [device
          newIOHandleWithURL:[NSURL fileURLWithPath:@"/prismel/missing.bin"]
          error:&error];
#pragma clang diagnostic pop
      if (file != nil || error == nil) return 1;
    }
  }
  return 0;
}
