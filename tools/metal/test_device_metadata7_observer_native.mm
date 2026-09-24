#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <Metal/MTLRenderPipeline.h>
#include <atomic>
#include <memory>

static const char *const ids[] = {
  "class:MTLTilePipelineColorAttachmentDescriptor",
  "function:MTLCopyAllDevicesWithObserver", "function:MTLRemoveDeviceObserver",
  "protocol:MTLIndirectComputeCommandEncoder", "protocol:MTLIndirectRenderCommandEncoder",
  "typedef:MTLDeviceNotificationHandler", "typedef:MTLDeviceNotificationName"};
static_assert(sizeof(ids)/sizeof(ids[0])==7,"Device metadata7 drift");

int main(){@autoreleasepool{
  (void)ids;
  MTLTilePipelineColorAttachmentDescriptor*d=nil;(void)d;
  auto calls=std::make_shared<std::atomic<unsigned>>(0);id observer=nil;
  NSArray<id<MTLDevice>>*devices=MTLCopyAllDevicesWithObserver(&observer,
    ^(id<MTLDevice>device,MTLDeviceNotificationName name){
      if(device&&name)calls->fetch_add(1,std::memory_order_relaxed);
    });
  if(!devices||!observer)return 2;
  for(id<MTLDevice>device in devices)if(device.registryID==0)return 3;
  MTLRemoveDeviceObserver(observer);observer=nil;
  (void)calls;
  return 0;
}}
