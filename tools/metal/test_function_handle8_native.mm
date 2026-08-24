#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <type_traits>
static_assert(sizeof(MTLResourceID)==sizeof(uint64_t));
static_assert(std::is_same_v<decltype(((id<MTLFunctionHandle>)nil).functionType),MTLFunctionType>);
int main(){__strong NSString*name_snapshot=nil;uint64_t resource_snapshot=0,device_snapshot=0;MTLFunctionType type_snapshot=MTLFunctionTypeKernel;@autoreleasepool{id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;NSError*error=nil;id<MTLLibrary>library=[d newLibraryWithSource:@"kernel void handle_kernel(){}" options:nil error:&error];if(!library)return 77;id<MTLFunction>function=[library newFunctionWithName:@"handle_kernel"];id<MTLComputePipelineState>pipeline=[d newComputePipelineStateWithFunction:function error:&error];if(!pipeline)return 77;id<MTLFunctionHandle>handle=[pipeline functionHandleWithFunction:function];if(!handle)return 77;name_snapshot=[handle.name copy];resource_snapshot=handle.gpuResourceID._impl;device_snapshot=handle.device.registryID;type_snapshot=handle.functionType;if(device_snapshot!=d.registryID||type_snapshot!=MTLFunctionTypeKernel)return 1;}
 if(![name_snapshot isEqualToString:@"handle_kernel"]||resource_snapshot==0||type_snapshot!=MTLFunctionTypeKernel)return 2;return 0;}
