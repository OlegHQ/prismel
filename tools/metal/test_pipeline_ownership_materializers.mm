#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "metal_pipeline_ownership_materializers.inc"
int main(){@autoreleasepool{NSString*f=nil;PrismelRenderPipelineObjects r={};
 if(prismel_materialize_render_pipeline(r,&f)!=nil||f==nil)return 1;
 f=nil;PrismelComputePipelineObjects c={};
 if(prismel_materialize_compute_pipeline(c,&f)!=nil||f==nil)return 2;return 0;}}
