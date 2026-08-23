#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "metal_mesh_tile_ownership_materializers.inc"
int main(){ @autoreleasepool {
  NSString *failure=nil; PrismelMeshTileObjects empty={};
  if(prismel_materialize_mesh_descriptor(empty,&failure)!=nil||failure==nil)return 1;
  failure=nil;if(prismel_materialize_tile_descriptor(empty,&failure)!=nil||failure==nil)return 2;
  MTLRenderPipelineColorAttachmentDescriptorArray *a=[MTLRenderPipelineColorAttachmentDescriptorArray new];
  if(prismel_mesh_tile_set_attachment(a,8,nil,&failure))return 3;
  return 0;
}}
