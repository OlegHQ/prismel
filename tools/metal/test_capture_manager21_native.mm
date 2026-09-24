#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <mutex>
struct CaptureState{std::mutex mutex;bool active=false;bool begin(bool succeeds){std::lock_guard<std::mutex>l(mutex);if(active)return false;if(!succeeds){active=false;return false;}active=true;return true;}void stop(){std::lock_guard<std::mutex>l(mutex);active=false;}};
int main(){@autoreleasepool{
 CaptureState state;if(state.begin(false)||state.active)return 1;if(!state.begin(true)||state.begin(true))return 2;state.stop();if(!state.begin(true))return 3;state.stop();
 MTLCaptureDescriptor*d=[MTLCaptureDescriptor new];d.destination=MTLCaptureDestinationGPUTraceDocument;d.outputURL=[NSURL fileURLWithPath:@"/tmp/prismel.gputrace"];if(d.destination!=2||!d.outputURL)return 4;
 MTLCaptureManager*m=[MTLCaptureManager sharedCaptureManager];id<MTLDevice>device=MTLCreateSystemDefaultDevice();if(!device)return 77;id<MTLCaptureScope>scope=[m newCaptureScopeWithDevice:device];if(!scope)return 5;m.defaultCaptureScope=scope;if(m.defaultCaptureScope!=scope)return 6;m.defaultCaptureScope=nil;
 return 0;
}}
