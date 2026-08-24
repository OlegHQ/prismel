#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static void qualify(BOOL run, id<MTLRenderPipelineState> state, id<MTLFunction> fn,
                    id<MTL4BinaryFunction> binary) {
  if (!run) return;
  MTLMeshRenderPipelineDescriptor *mesh = [MTLMeshRenderPipelineDescriptor new];
  NSArray *empty = @[]; MTLLinkedFunctions *linked = [MTLLinkedFunctions new];
  (void)mesh.binaryArchives; (void)mesh.colorAttachments; (void)mesh.fragmentBuffers;
  (void)mesh.fragmentFunction; (void)mesh.fragmentLinkedFunctions; (void)mesh.meshBuffers;
  (void)mesh.meshFunction; (void)mesh.meshLinkedFunctions; (void)mesh.objectBuffers;
  (void)mesh.objectFunction; (void)mesh.objectLinkedFunctions; [mesh reset];
  mesh.binaryArchives=empty; mesh.fragmentFunction=fn; mesh.fragmentLinkedFunctions=linked;
  mesh.meshFunction=fn; mesh.meshLinkedFunctions=linked; mesh.objectFunction=fn;
  mesh.objectLinkedFunctions=linked;
  MTLRenderPipelineDescriptor *render=[MTLRenderPipelineDescriptor new];
  MTLRenderPipelineColorAttachmentDescriptorArray *colors=render.colorAttachments;
  MTLRenderPipelineColorAttachmentDescriptor *color=colors[0]; colors[0]=color;
  (void)render.fragmentBuffers; (void)render.label; render.label=@"typed";
  render.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
  (void)render.vertexBuffers; (void)render.vertexDescriptor;
  MTLRenderPipelineFunctionsDescriptor *functions=[MTLRenderPipelineFunctionsDescriptor new];
  (void)functions.fragmentAdditionalBinaryFunctions; functions.fragmentAdditionalBinaryFunctions=empty;
  functions.tileAdditionalBinaryFunctions=empty; functions.vertexAdditionalBinaryFunctions=empty;
  (void)functions.tileAdditionalBinaryFunctions; (void)functions.vertexAdditionalBinaryFunctions;
  MTLRenderPipelineReflection *reflection=nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  (void)reflection.fragmentArguments; (void)reflection.tileArguments; (void)reflection.vertexArguments;
#pragma clang diagnostic pop
  (void)[state functionHandleWithBinaryFunction:binary stage:MTLRenderStageVertex];
  (void)[state functionHandleWithFunction:fn stage:MTLRenderStageVertex];
  (void)[state functionHandleWithName:@"v" stage:MTLRenderStageVertex];
  (void)[state newIntersectionFunctionTableWithDescriptor:[MTLIntersectionFunctionTableDescriptor new] stage:MTLRenderStageVertex];
  (void)[state newRenderPipelineDescriptorForSpecialization]; NSError *error=nil;
  (void)[state newRenderPipelineStateWithAdditionalBinaryFunctions:functions error:&error];
  (void)[state newRenderPipelineStateWithBinaryFunctions:[MTL4RenderPipelineBinaryFunctionsDescriptor new] error:&error];
  (void)[state newVisibleFunctionTableWithDescriptor:[MTLVisibleFunctionTableDescriptor new] stage:MTLRenderStageVertex];
  (void)state.requiredThreadsPerMeshThreadgroup; (void)state.requiredThreadsPerObjectThreadgroup;
  MTLTileRenderPipelineDescriptor *tile=[MTLTileRenderPipelineDescriptor new];
  (void)tile.binaryArchives; (void)tile.colorAttachments; (void)tile.linkedFunctions;
  (void)tile.preloadedLibraries; [tile reset]; tile.binaryArchives=empty;
  tile.linkedFunctions=linked; tile.preloadedLibraries=empty; tile.tileFunction=fn;
  (void)tile.tileBuffers; (void)tile.tileFunction;
}

int main(void) { @autoreleasepool {
  id<MTLDevice> device=MTLCreateSystemDefaultDevice(); if (!device) return 77;
  NSError *error=nil; NSString *source=@"#include <metal_stdlib>\nusing namespace metal; vertex float4 v(uint i [[vertex_id]]){return float4(i==1?1:-1,i==2?1:-1,0,1);} fragment float4 f(){return float4(1,0,0,1);}";
  id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
  MTLRenderPipelineDescriptor *descriptor=[MTLRenderPipelineDescriptor new];
  descriptor.vertexFunction=[library newFunctionWithName:@"v"]; descriptor.fragmentFunction=[library newFunctionWithName:@"f"];
  descriptor.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
  id<MTLRenderPipelineState> pipeline=[device newRenderPipelineStateWithDescriptor:descriptor error:&error]; if (!pipeline) return 2;
  MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO]; td.usage=MTLTextureUsageRenderTarget;
  id<MTLTexture> texture=[device newTextureWithDescriptor:td]; MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture=texture; pass.colorAttachments[0].loadAction=MTLLoadActionClear; pass.colorAttachments[0].storeAction=MTLStoreActionStore;
  id<MTLCommandBuffer> command=[[device newCommandQueue] commandBuffer]; id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];
  [encoder setRenderPipelineState:pipeline]; [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
  qualify(NO,pipeline,descriptor.vertexFunction,nil); return command.status==MTLCommandBufferStatusCompleted ? 0 : 3;
} }
