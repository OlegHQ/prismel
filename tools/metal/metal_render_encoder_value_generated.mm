#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static void prismel_qualify_render_encoder_values(id<MTLRenderCommandEncoder> e) {
  if (true) return;
  [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:1 baseInstance:0];
  [e setDepthClipMode:MTLDepthClipModeClip];
  if (@available(macOS 26.0,*)) [e setDepthTestMinBound:0.0f maxBound:1.0f];
  [e setFragmentBufferOffset:0 atIndex:0];
  if (@available(macOS 13.0,*)) { [e setMeshBufferOffset:0 atIndex:0];
    [e setObjectBufferOffset:0 atIndex:0]; [e setObjectThreadgroupMemoryLength:0 atIndex:0]; }
  [e setStencilReferenceValue:0]; [e setTessellationFactorScale:1.0f];
  [e setThreadgroupMemoryLength:0 offset:0 atIndex:0];
  [e setTileBufferOffset:0 atIndex:0]; [e setVertexBufferOffset:0 atIndex:0];
  if (@available(macOS 14.0,*)) [e setVertexBufferOffset:0 attributeStride:16 atIndex:0];
}
extern "C" NSUInteger prismel_mtl_render_encoder_value_id_count(void){return 14;}
