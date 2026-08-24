#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <atomic>
#include <memory>
struct Once{std::atomic<int>state{0};bool fire(){int expected=0;return state.compare_exchange_strong(expected,1);}bool cancel(){int expected=0;return state.compare_exchange_strong(expected,2);}};
int main(){@autoreleasepool{
 Once delivered;if(!delivered.fire()||delivered.fire()||delivered.cancel())return 1;Once cancelled;if(!cancelled.cancel()||cancelled.fire()||cancelled.cancel())return 2;
 __strong NSString*sub_snapshot=nil;__strong NSString*category_snapshot=nil;__strong NSString*message_snapshot=nil;@autoreleasepool{NSString*sub=@"sub_λ",*category=nil,*message=@"message_λ";sub_snapshot=[sub copy];category_snapshot=[category copy];message_snapshot=[message copy];}if(![sub_snapshot isEqualToString:@"sub_λ"]||category_snapshot!=nil||![message_snapshot isEqualToString:@"message_λ"])return 3;
 if(@available(macOS 15.0,*)){MTLLogStateDescriptor*d=[MTLLogStateDescriptor new];if(!d)return 4;d.level=MTLLogLevelNotice;d.bufferSize=4096;if(d.level!=MTLLogLevelNotice||d.bufferSize!=4096)return 5;id<MTLDevice>device=MTLCreateSystemDefaultDevice();if(!device)return 77;NSError*error=nil;id<MTLLogState>state=[device newLogStateWithDescriptor:d error:&error];if(!state)return error?77:6;auto calls=std::make_shared<std::atomic<int>>(0);[state addLogHandler:^(NSString*,NSString*,MTLLogLevel,NSString*){calls->fetch_add(1);}];}
 return 0;}}
