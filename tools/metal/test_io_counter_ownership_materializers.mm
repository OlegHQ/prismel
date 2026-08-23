#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "metal_io_counter_ownership_materializers.inc"
int main(){@autoreleasepool{NSString*f=nil;if(prismel_counter_descriptor(nil,1,nil,&f)!=nil||!f)return 1;f=nil;if(prismel_blit_pass(nil,0,0,&f)==nil)return 2;id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;if(d.counterSets.count){id<MTLCounterSet>s=d.counterSets[0];MTLCounterSampleBufferDescriptor*x=prismel_counter_descriptor(s,4,@"counter",&f);if(!x||x.counterSet!=s||x.sampleCount!=4||![x.label isEqual:@"counter"]||s.counters.count==0||s.counters[0].name.length==0)return 3;NSError*e=nil;id<MTLCounterSampleBuffer>b=[d newCounterSampleBufferWithDescriptor:x error:&e];if(!b&&e==nil)return 4;}return 0;}}
