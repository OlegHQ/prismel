#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<decltype(((id<MTLCaptureScope>)nil).device),
                             id<MTLDevice>>);

int main()
{
  __weak id<MTLCaptureScope> weak_scope = nil;
  __weak id<MTLCommandQueue> weak_queue = nil;
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    MTLCaptureManager *manager = [MTLCaptureManager sharedCaptureManager];
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCaptureScope> scope =
        [manager newCaptureScopeWithCommandQueue:queue];
    if (manager == nil || queue == nil || scope == nil) return 1;
    weak_scope = scope;
    weak_queue = queue;
    scope.label = @"scope_λ";
    queue = nil;

    /* A queue-backed scope preserves its source queue and exact device. */
    if (weak_queue == nil || scope.commandQueue != weak_queue ||
        scope.device.registryID != device.registryID ||
        ![scope.label isEqualToString:@"scope_λ"])
      return 2;
    if (@available(macOS 26.0, *))
      if (scope.mtl4CommandQueue != nil) return 3;

    [scope beginScope];
    [scope endScope];
    NSString *snapshot = [scope.label copy];
    scope.label = nil;
    if (![snapshot isEqualToString:@"scope_λ"] || scope.label != nil)
      return 4;

    /* The manager's defaultScope edge owns the scope until explicitly
       cleared, independently of the caller's strong reference. */
    manager.defaultCaptureScope = scope;
    scope = nil;
    if (weak_scope == nil || manager.defaultCaptureScope != weak_scope)
      return 5;
    manager.defaultCaptureScope = nil;
    if (manager.defaultCaptureScope != nil) return 6;

    id<MTLCaptureScope> device_scope =
        [manager newCaptureScopeWithDevice:device];
    if (device_scope == nil || device_scope.commandQueue != nil ||
        device_scope.device.registryID != device.registryID)
      return 7;
  }
  if (weak_scope != nil || weak_queue != nil) return 8;
  return 0;
}
