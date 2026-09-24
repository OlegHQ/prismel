#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <type_traits>

static_assert(std::is_same_v<decltype(((id<MTLDrawable>)nil).drawableID),
                             NSUInteger>);
static_assert(std::is_same_v<decltype(((id<MTLDrawable>)nil).presentedTime),
                             CFTimeInterval>);

int main()
{
  __weak CAMetalLayer *weak_layer = nil;
  __weak id<CAMetalDrawable> weak_drawable = nil;
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.device = device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.drawableSize = CGSizeMake(16, 16);
    layer.framebufferOnly = NO;
    layer.allowsNextDrawableTimeout = YES;
    layer.displaySyncEnabled = NO;
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (drawable == nil || drawable.texture == nil) return 77;
    if (drawable.layer != layer || drawable.texture.device != device) return 1;
    weak_layer = layer;
    weak_drawable = drawable;
    NSUInteger identifier = drawable.drawableID;

    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    __block NSUInteger handler_count = 0;
    __block NSUInteger callback_identifier = NSUIntegerMax;
    __block CFTimeInterval callback_time = -1.0;
    [drawable addPresentedHandler:^(id<MTLDrawable> presented) {
      ++handler_count;
      callback_identifier = presented.drawableID;
      callback_time = presented.presentedTime;
      dispatch_semaphore_signal(completed);
    }];

    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    if (queue == nil || command == nil) return 2;
    [command presentDrawable:drawable];
    /* The command buffer and drawable keep the presentation graph alive after
       the caller drops its strong parent-layer reference. */
    layer = nil;
    if (weak_layer == nil || weak_drawable == nil) return 3;
    [command commit];
    [command waitUntilCompleted];
    if (command.status != MTLCommandBufferStatusCompleted) return 4;
    if (dispatch_semaphore_wait(
            completed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0)
      return 5;
    if (handler_count != 1 || callback_identifier != identifier ||
        callback_time < 0.0 || drawable.presentedTime != callback_time)
      return 6;
    /* Waiting again proves the registered handler was a one-shot callback. */
    if (dispatch_semaphore_wait(
            completed, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC)) == 0)
      return 7;
    command = nil;
    drawable = nil;
  }
  if (weak_drawable != nil || weak_layer != nil) return 8;
  return 0;
}
