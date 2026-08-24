#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

int main()
{
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    NSError *error = nil;
    NSString *source =
        @"#include <metal_stdlib>\nusing namespace metal;\n"
         "vertex float4 icb_vertex(uint id [[vertex_id]]) {"
         " float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};"
         " return float4(p[id],0,1); }"
         "fragment float4 icb_fragment(){return float4(1,0,0,1);}";
    id<MTLLibrary> library =
        [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) return 77;
    MTLRenderPipelineDescriptor *pipeline_descriptor =
        [MTLRenderPipelineDescriptor new];
    pipeline_descriptor.vertexFunction =
        [library newFunctionWithName:@"icb_vertex"];
    pipeline_descriptor.fragmentFunction =
        [library newFunctionWithName:@"icb_fragment"];
    pipeline_descriptor.colorAttachments[0].pixelFormat =
        MTLPixelFormatRGBA8Unorm;
    pipeline_descriptor.supportIndirectCommandBuffers = YES;
    id<MTLRenderPipelineState> pipeline =
        [device newRenderPipelineStateWithDescriptor:pipeline_descriptor error:&error];
    if (pipeline == nil || !pipeline.supportIndirectCommandBuffers) return 77;

    MTLIndirectCommandBufferDescriptor *descriptor =
        [MTLIndirectCommandBufferDescriptor new];
    descriptor.commandTypes = MTLIndirectCommandTypeDraw;
    descriptor.inheritBuffers = NO;
    descriptor.inheritPipelineState = NO;
    descriptor.maxVertexBufferBindCount = 1;
    id<MTLIndirectCommandBuffer> icb =
        [device newIndirectCommandBufferWithDescriptor:descriptor
                                       maxCommandCount:1
                                                 options:0];
    if (icb == nil) return 77;
    id<MTLIndirectRenderCommand> command = [icb indirectRenderCommandAtIndex:0];
    id<MTLBuffer> retained_buffer =
        [device newBufferWithLength:64 options:MTLResourceStorageModeShared];
    if (command == nil || retained_buffer == nil) return 1;
    [command setRenderPipelineState:pipeline];
    [command setVertexBuffer:retained_buffer
                      offset:0
             attributeStride:16
                     atIndex:0];
    [command drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0 vertexCount:3 instanceCount:1 baseInstance:0];

    MTLTextureDescriptor *texture_descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:4 height:4 mipmapped:NO];
    texture_descriptor.storageMode = MTLStorageModeShared;
    texture_descriptor.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> texture = [device newTextureWithDescriptor:texture_descriptor];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> submission = [queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder =
        [submission renderCommandEncoderWithDescriptor:pass];
    if (texture == nil || queue == nil || submission == nil || encoder == nil)
      return 77;
    [encoder executeCommandsInBuffer:icb withRange:NSMakeRange(0, 1)];
    [encoder endEncoding];
    [submission commit];
    [submission waitUntilCompleted];
    if (submission.status != MTLCommandBufferStatusCompleted) return 2;
    uint8_t pixels[64] = {};
    [texture getBytes:pixels bytesPerRow:16
           fromRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:0];
    bool red = false;
    for (NSUInteger index = 0; index < 16; ++index)
      red = red || (pixels[index * 4] == 255 && pixels[index * 4 + 1] == 0 &&
                    pixels[index * 4 + 2] == 0 && pixels[index * 4 + 3] == 255);
    if (!red) return 3;

    [command reset];
    [icb resetWithRange:NSMakeRange(0, 1)];
    return 0;
  }
}
