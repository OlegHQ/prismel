#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <atomic>
#include <memory>
int main(){@autoreleasepool{
 id<MTLDevice>device=MTLCreateSystemDefaultDevice();if(!device)return 77;id<MTLSharedEvent>event=[device newSharedEvent];if(!event)return 77;event.label=@"event_λ";if(event.device&&event.device.registryID!=device.registryID)return 1;
 dispatch_queue_t queue=dispatch_queue_create("prismel.event14",DISPATCH_QUEUE_SERIAL);MTLSharedEventListener*listener=[[MTLSharedEventListener alloc]initWithDispatchQueue:queue];if(!listener||listener.dispatchQueue!=queue)return 2;
 dispatch_semaphore_t done=dispatch_semaphore_create(0);auto calls=std::make_shared<std::atomic<int>>(0);auto observed=std::make_shared<std::atomic<uint64_t>>(0);[event notifyListener:listener atValue:4 block:^(id<MTLSharedEvent>source,uint64_t value){if(source==event){calls->fetch_add(1);observed->store(value);}dispatch_semaphore_signal(done);}];event.signaledValue=3;if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC))==0)return 3;event.signaledValue=4;if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))!=0)return 4;if(calls->load()!=1||observed->load()<4)return 5;event.signaledValue=5;dispatch_sync(queue,^{});if(calls->load()!=1)return 6;
 MTLSharedEventHandle*handle=[event newSharedEventHandle];if(!handle||![handle.label isEqualToString:@"event_λ"])return 7;NSString*snapshot=[handle.label copy];event.label=nil;if(![snapshot isEqualToString:@"event_λ"])return 8;return 0;}}
