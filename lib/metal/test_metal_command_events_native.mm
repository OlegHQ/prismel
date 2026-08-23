#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static void require(bool condition, NSString *message) {
  if (!condition) {
    @throw [NSException exceptionWithName:@"CommandEvents"
                                   reason:message
                                 userInfo:nil];
  }
}

static void require_identity_if_reported(id<MTLEvent> event,
                                         id<MTLDevice> source) {
  if (event.device != nil) {
    require(event.device.registryID == source.registryID,
            @"event reports another device");
  }
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    require(device.registryID != 0, @"source device registry ID");

    id<MTLEvent> event = [device newEvent];
    require(event != nil, @"newEvent");
    require_identity_if_reported(event, device);
    event.label = @"command-event";
    require([event.label isEqualToString:@"command-event"],
            @"event label roundtrip");

    id<MTLSharedEvent> shared = [device newSharedEvent];
    require(shared != nil, @"newSharedEvent");
    require_identity_if_reported(shared, device);
    shared.label = @"command-shared-event";
    shared.signaledValue = 9;
    require([shared.label isEqualToString:@"command-shared-event"] &&
            shared.signaledValue == 9,
            @"shared event state roundtrip");

    NSLog(@"command events: typed construction/device identity/state green");
    return 0;
  }
}
