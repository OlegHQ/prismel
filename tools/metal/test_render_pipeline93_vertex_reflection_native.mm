#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cstdio>
int main(){@autoreleasepool{MTLRenderPipelineDescriptor*d=[MTLRenderPipelineDescriptor new];MTLVertexDescriptor*v=[MTLVertexDescriptor vertexDescriptor];d.vertexDescriptor=v;if(!d.vertexDescriptor)return 1;d.vertexDescriptor=nil;/* SDK normalizes nil to a fresh default copied descriptor. */if(!d.vertexDescriptor)return 2;MTLRenderPipelineReflection*r=nil;(void)r.vertexArguments;(void)r.fragmentArguments;(void)r.tileArguments;std::puts("RenderPipeline93 vertex/reflection: exact9 qualifiers passed");return 0;}}
