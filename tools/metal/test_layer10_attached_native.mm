#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

static const char *const kIds[] = {
  "class:CAMetalLayer",
  "method:-[CAMetalLayer developerHUDProperties]",
  "method:-[CAMetalLayer preferredDevice]",
  "method:-[CAMetalLayer residencySet]",
  "method:-[CAMetalLayer setDeveloperHUDProperties:]",
  "property:CAMetalLayer:developerHUDProperties",
  "property:CAMetalLayer:preferredDevice",
  "property:CAMetalLayer:residencySet",
  "protocol:CAMetalDrawable",
  "record:_CAMetalLayerPrivate"
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 10);

static void require(bool condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  require(device != nil, @"device");
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 32, 24)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered defer:NO];
  NSView *view = window.contentView;
  view.wantsLayer = YES;
  CAMetalLayer *layer = [CAMetalLayer layer];
  view.layer = layer;
  layer.device = device;
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  layer.framebufferOnly = NO;
  layer.drawableSize = CGSizeMake(32, 24);
  layer.maximumDrawableCount = 2;
  layer.displaySyncEnabled = NO;
  require(view.layer == layer && layer.device == device &&
          layer.drawableSize.width == 32 && layer.drawableSize.height == 24 &&
          layer.maximumDrawableCount == 2 && !layer.displaySyncEnabled,
          @"attached layer configuration");
  if (@available(macOS 10.15, *))
    require(layer.preferredDevice == nil || layer.preferredDevice.registryID == device.registryID,
            @"preferred device identity");
  if (@available(macOS 13.0, *)) {
    layer.developerHUDProperties = @{};
    require(layer.developerHUDProperties.count == 0, @"HUD copied reset");
  }
  if (@available(macOS 26.0, *)) (void)layer.residencySet;
  require(@protocol(CAMetalDrawable) != nil, @"drawable protocol");
  NSLog(@"CAMetalLayer10 attached capability conformance passed");
  return 0;
}}
