#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "metal_io_counter_ownership_materializers.inc"
int main(){@autoreleasepool{NSString*f=nil;if(prismel_counter_descriptor(nil,1,nil,&f)!=nil||!f)return 1;f=nil;if(prismel_blit_pass(nil,0,0,&f)==nil)return 2;return 0;}}
