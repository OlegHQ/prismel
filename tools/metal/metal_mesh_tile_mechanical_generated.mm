#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

extern "C" void prismel_mtl_pipeline_buffer_set_mutability(
    MTLPipelineBufferDescriptor *value, MTLMutability mutability) { value.mutability=mutability; }
extern "C" void prismel_mtl_color_attachment_set_mechanical(
    MTLRenderPipelineColorAttachmentDescriptor *v, MTLPixelFormat pixel,
    MTLBlendFactor src_rgb, MTLBlendFactor dst_rgb, MTLBlendOperation rgb,
    MTLBlendFactor src_alpha, MTLBlendFactor dst_alpha, MTLBlendOperation alpha,
    MTLColorWriteMask mask) {
  v.pixelFormat=pixel; v.sourceRGBBlendFactor=src_rgb; v.destinationRGBBlendFactor=dst_rgb;
  v.rgbBlendOperation=rgb; v.sourceAlphaBlendFactor=src_alpha;
  v.destinationAlphaBlendFactor=dst_alpha; v.alphaBlendOperation=alpha; v.writeMask=mask;
}
extern "C" void prismel_mtl_mesh_descriptor_set_mechanical(
    MTLMeshRenderPipelineDescriptor *v, NSString *label, MTLPixelFormat depth,
    MTLPixelFormat stencil, MTLSize mesh_threads, MTLSize object_threads) {
  v.label=label; v.depthAttachmentPixelFormat=depth; v.stencilAttachmentPixelFormat=stencil;
  if (@available(macOS 26.0,*)) { v.requiredThreadsPerMeshThreadgroup=mesh_threads;
    v.requiredThreadsPerObjectThreadgroup=object_threads; }
}
extern "C" void prismel_mtl_tile_descriptor_set_mechanical(
    MTLTileRenderPipelineDescriptor *v, NSString *label, MTLSize threads) {
  v.label=label; if (@available(macOS 26.0,*)) v.requiredThreadsPerThreadgroup=threads;
}
extern "C" NSUInteger prismel_mtl_mesh_tile_mechanical_id_count(void) { return 48; }
