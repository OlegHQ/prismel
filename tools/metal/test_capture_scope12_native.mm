#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <mutex>
#include <unordered_set>
struct BalancedScopes{std::mutex mutex;std::unordered_set<const void*>active;bool step(const void*p,bool begin){std::lock_guard<std::mutex>l(mutex);if(begin)return active.insert(p).second;auto i=active.find(p);if(i==active.end())return false;active.erase(i);return true;}};
int main(){@autoreleasepool{
 int token=0;BalancedScopes state;if(!state.step(&token,true)||state.step(&token,true)||!state.step(&token,false)||state.step(&token,false))return 1;
 id<MTLDevice>device=MTLCreateSystemDefaultDevice();if(!device)return 77;MTLCaptureManager*manager=[MTLCaptureManager sharedCaptureManager];id<MTLCommandQueue>queue=[device newCommandQueue];id<MTLCaptureScope>scope=[manager newCaptureScopeWithCommandQueue:queue];if(!scope)return 2;
 scope.label=@"scope_λ";if(![scope.label isEqualToString:@"scope_λ"]||scope.device.registryID!=device.registryID||scope.commandQueue!=queue)return 3;
 [scope beginScope];[scope endScope];
 if(@available(macOS 26.0,*)){if(scope.mtl4CommandQueue!=nil)return 4;}
 NSString*snapshot=[scope.label copy];scope.label=nil;if(![snapshot isEqualToString:@"scope_λ"]||scope.label!=nil)return 5;
 return 0;}}
