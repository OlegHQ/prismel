#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <cstddef>
#include <type_traits>

template <class T, class = void> struct PrismelLayerComplete : std::false_type {};
template <class T>
struct PrismelLayerComplete<T, std::void_t<decltype(sizeof(T))>>
    : std::true_type {};

static const char *const kIds[] = {"record:_CAMetalLayerPrivate"};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 1,
              "CAMetalLayerPrivate1 exact closure drift");
static_assert(!PrismelLayerComplete<struct _CAMetalLayerPrivate>::value,
              "CAMetalLayer private state must remain opaque");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  CAMetalLayer *layer = [CAMetalLayer layer]; if (!layer) return 1;
  layer.device = device;
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  layer.framebufferOnly = YES;
  layer.drawableSize = CGSizeMake(320, 200);
  layer.maximumDrawableCount = 3;
  layer.displaySyncEnabled = YES;
  if (layer.device.registryID != device.registryID ||
      layer.pixelFormat != MTLPixelFormatBGRA8Unorm || !layer.framebufferOnly ||
      layer.drawableSize.width != 320 || layer.drawableSize.height != 200 ||
      layer.maximumDrawableCount != 3 || !layer.displaySyncEnabled) return 2;
  CALayer *presentation = [layer presentationLayer];
  (void)presentation;
  /* nextDrawable requires attachment to a real window/layer tree.  Calling it
     here would turn occlusion/window state into a false capability result. */
  return 0;
} }
