#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "metal_shader_graph_ownership_materializers.inc"
int main(){@autoreleasepool{NSString*f=nil;PrismelShaderNode n={};if(prismel_shader_node(n,&f)!=nil||!f)return 1;f=nil;PrismelShaderGraph g={};if(prismel_shader_graph(g,&f)!=nil||!f)return 2;return 0;}}
