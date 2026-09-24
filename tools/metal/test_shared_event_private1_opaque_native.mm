#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <type_traits>

template <class T, class = void> struct PrismelEventComplete : std::false_type {};
template <class T>
struct PrismelEventComplete<T, std::void_t<decltype(sizeof(T))>>
    : std::true_type {};

static const char *const kIds[] = {"record:MTLSharedEventHandlePrivate"};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 1,
              "SharedEventHandlePrivate1 drift");
static_assert(!PrismelEventComplete<struct MTLSharedEventHandlePrivate>::value,
              "private shared-event record must remain opaque");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  id<MTLSharedEvent> event = [device newSharedEvent]; if (!event) return 77;
  event.label = @"shared-event-private1";
  MTLSharedEventHandle *handle = [event newSharedEventHandle];
  if (!handle || ![handle.label isEqualToString:@"shared-event-private1"])
    return 1;
  id<MTLSharedEvent> reopened = [device newSharedEventWithHandle:handle];
  if (!reopened) return 77;
  if (reopened.device.registryID != device.registryID) return 77;
  event.signaledValue = 41;
  if (![reopened waitUntilSignaledValue:41 timeoutMS:1000] ||
      reopened.signaledValue < 41) return 5;
  reopened.signaledValue = 42;
  if (![event waitUntilSignaledValue:42 timeoutMS:1000] ||
      event.signaledValue < 42) return 6;
  NSError *error = nil;
  NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:handle
    requiringSecureCoding:YES error:&error];
  if (!archive || error) return 77;
  MTLSharedEventHandle *decoded = [NSKeyedUnarchiver
    unarchivedObjectOfClass:[MTLSharedEventHandle class] fromData:archive error:&error];
  if (!decoded || error || ![decoded.label isEqualToString:handle.label]) return 3;
  __weak MTLSharedEventHandle *weak = handle;
  handle = nil; decoded = nil; archive = nil;
  if (weak != nil) return 7;
  return 0;
} }
