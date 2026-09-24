#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <type_traits>
static_assert(std::is_same_v<decltype([MTLCompileOptions new].preprocessorMacros),NSDictionary<NSString*,NSObject*>*>);
static_assert(std::is_same_v<decltype([MTLFunctionReflection new].bindings),NSArray<id<MTLBinding>>*>);
int main(){@autoreleasepool{
 MTLCompileOptions*options=[MTLCompileOptions new];options.preprocessorMacros=@{@"COUNT":@"4"};if(![[options.preprocessorMacros[@"COUNT"] description]isEqual:@"4"])return 1;
 if(@available(macOS 26.0,*)){options.requiredThreadsPerThreadgroup=MTLSizeMake(8,4,1);if(options.requiredThreadsPerThreadgroup.width!=8)return 2;}
 id<MTLDevice>device=MTLCreateSystemDefaultDevice();if(!device)return 77;NSError*error=nil;id<MTLLibrary>library=[device newLibraryWithSource:@"kernel void k(device uint*x[[buffer(0)]]){x[0]=1;}" options:nil error:&error];if(!library)return 3;
 MTLFunctionDescriptor*descriptor=[MTLFunctionDescriptor functionDescriptor];descriptor.name=@"k";id<MTLFunction>function=[library newFunctionWithDescriptor:descriptor error:&error];if(!function)return 4;
 dispatch_semaphore_t done=dispatch_semaphore_create(0);__block int calls=0;[library newFunctionWithDescriptor:descriptor completionHandler:^(id<MTLFunction>f,NSError*e){if(f&&!e)calls++;dispatch_semaphore_signal(done);}];if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))||calls!=1)return 5;
 if(@available(macOS 26.0,*)){MTLFunctionReflection*reflection=[library reflectionForFunctionWithName:@"k"];if(reflection&&reflection.bindings==nil)return 6;}
 return 0;
}}
