#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <atomic>
#include <memory>

int main()
{
  __weak MTLSharedEventListener *weak_listener = nil;
  __weak MTLSharedEventHandle *weak_handle = nil;
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    id<MTLSharedEvent> event = [device newSharedEvent];
    if (event == nil) return 77;
    event.label = @"event_λ";
    dispatch_queue_t queue =
        dispatch_queue_create("prismel.event10.ownership", DISPATCH_QUEUE_SERIAL);
    MTLSharedEventListener *listener =
        [[MTLSharedEventListener alloc] initWithDispatchQueue:queue];
    if (listener == nil || listener.dispatchQueue != queue) return 1;
    weak_listener = listener;

    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    auto calls = std::make_shared<std::atomic<unsigned>>(0);
    auto observed = std::make_shared<std::atomic<uint64_t>>(0);
    [event notifyListener:listener atValue:7
                    block:^(id<MTLSharedEvent> source, uint64_t value) {
      if (source == event) {
        calls->fetch_add(1);
        observed->store(value);
      }
      dispatch_semaphore_signal(completed);
    }];
    listener = nil;
    queue = nil;
    /* Pending notification owns enough listener/queue state to deliver after
       caller references are released. */
    if (weak_listener == nil) return 2;
    event.signaledValue = 6;
    if (dispatch_semaphore_wait(
            completed, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC)) == 0)
      return 3;
    event.signaledValue = 7;
    if (dispatch_semaphore_wait(
            completed, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) != 0)
      return 4;
    if (calls->load() != 1 || observed->load() < 7) return 5;
    event.signaledValue = 8;
    if (dispatch_semaphore_wait(
            completed, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC)) == 0)
      return 6;

    MTLSharedEventHandle *handle = [event newSharedEventHandle];
    if (handle == nil || ![handle.label isEqualToString:@"event_λ"])
      return 7;
    weak_handle = handle;
    event.label = nil;
    if (![handle.label isEqualToString:@"event_λ"] ||
        event.device.registryID != device.registryID)
      return 8;
    handle = nil;
  }
  if (weak_listener != nil || weak_handle != nil) return 9;
  return 0;
}
