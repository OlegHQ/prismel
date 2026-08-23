#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
extern "C" void prismel_mtl_pipeline_buffer_set_mutability(MTLPipelineBufferDescriptor*,MTLMutability);
extern "C" void prismel_mtl_color_attachment_set_mechanical(MTLRenderPipelineColorAttachmentDescriptor*,MTLPixelFormat,MTLBlendFactor,MTLBlendFactor,MTLBlendOperation,MTLBlendFactor,MTLBlendFactor,MTLBlendOperation,MTLColorWriteMask);
extern "C" NSUInteger prismel_mtl_mesh_tile_mechanical_id_count(void);
extern "C" void prismel_mtl_mesh_descriptor_set_mechanical(MTLMeshRenderPipelineDescriptor*,NSString*,MTLPixelFormat,MTLPixelFormat,MTLSize,MTLSize);
extern "C" void prismel_mtl_tile_descriptor_set_mechanical(MTLTileRenderPipelineDescriptor*,NSString*,MTLSize);
int main(void){@autoreleasepool{
  MTLPipelineBufferDescriptor *buffer=[MTLPipelineBufferDescriptor new];
  prismel_mtl_pipeline_buffer_set_mutability(buffer,MTLMutabilityImmutable);
  if(buffer.mutability!=MTLMutabilityImmutable)return 1;
  MTLRenderPipelineColorAttachmentDescriptor *color=[MTLRenderPipelineColorAttachmentDescriptor new];
  prismel_mtl_color_attachment_set_mechanical(color,MTLPixelFormatBGRA8Unorm,
    MTLBlendFactorOne,MTLBlendFactorZero,MTLBlendOperationAdd,MTLBlendFactorOne,
    MTLBlendFactorZero,MTLBlendOperationAdd,MTLColorWriteMaskAll);
  if(color.pixelFormat!=MTLPixelFormatBGRA8Unorm||prismel_mtl_mesh_tile_mechanical_id_count()!=48)return 2;
  MTLMeshRenderPipelineDescriptor *mesh=[MTLMeshRenderPipelineDescriptor new];
  MTLTileRenderPipelineDescriptor *tile=[MTLTileRenderPipelineDescriptor new];
  prismel_mtl_mesh_descriptor_set_mechanical(mesh,nil,MTLPixelFormatInvalid,MTLPixelFormatInvalid,MTLSizeMake(1,1,1),MTLSizeMake(1,1,1));
  prismel_mtl_tile_descriptor_set_mechanical(tile,nil,MTLSizeMake(1,1,1));
  if(mesh.label!=nil||tile.label!=nil)return 3;
  NSLog(@"mesh/tile 48-ID contained mechanical native roundtrip passed"); return 0;
}}
