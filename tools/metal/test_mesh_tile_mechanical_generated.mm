#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
extern "C" void prismel_mtl_pipeline_buffer_set_mutability(MTLPipelineBufferDescriptor*,MTLMutability);
extern "C" void prismel_mtl_color_attachment_set_mechanical(MTLRenderPipelineColorAttachmentDescriptor*,MTLPixelFormat,MTLBlendFactor,MTLBlendFactor,MTLBlendOperation,MTLBlendFactor,MTLBlendFactor,MTLBlendOperation,MTLColorWriteMask);
extern "C" NSUInteger prismel_mtl_mesh_tile_mechanical_id_count(void);
int main(void){@autoreleasepool{
  MTLPipelineBufferDescriptor *buffer=[MTLPipelineBufferDescriptor new];
  prismel_mtl_pipeline_buffer_set_mutability(buffer,MTLMutabilityImmutable);
  if(buffer.mutability!=MTLMutabilityImmutable)return 1;
  MTLRenderPipelineColorAttachmentDescriptor *color=[MTLRenderPipelineColorAttachmentDescriptor new];
  prismel_mtl_color_attachment_set_mechanical(color,MTLPixelFormatBGRA8Unorm,
    MTLBlendFactorOne,MTLBlendFactorZero,MTLBlendOperationAdd,MTLBlendFactorOne,
    MTLBlendFactorZero,MTLBlendOperationAdd,MTLColorWriteMaskAll);
  if(color.pixelFormat!=MTLPixelFormatBGRA8Unorm||prismel_mtl_mesh_tile_mechanical_id_count()!=48)return 2;
  NSLog(@"mesh/tile 48-ID contained mechanical native roundtrip passed"); return 0;
}}
