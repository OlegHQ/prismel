#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "metal4_encoder_resource_materializers.inc"
int main(){@autoreleasepool{NSString*f=nil;if(prismel_metal4_copy_buffer(nil,nil,0,nil,0,4,4,&f)||!f)return 1;f=nil;if(prismel_metal4_queue_drawable(nil,nil,true,&f)||!f)return 2;f=nil;if(prismel_metal4_compile_render(nil,nil,nil,^(id<MTLRenderPipelineState>,NSError*){},&f)||!f)return 3;return 0;}}
