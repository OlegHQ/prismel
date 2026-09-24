#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "metal4_lifecycle_materializers.inc"
int main(){@autoreleasepool{NSString*f=nil;if(prismel_metal4_begin(nil,nil,nil,&f)||!f)return 1;f=nil;if(prismel_metal4_wait_event(nil,nil,0,&f)||!f)return 2;return 0;}}
