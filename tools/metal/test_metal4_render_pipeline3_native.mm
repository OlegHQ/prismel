#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

int main() { @autoreleasepool {
  if (@available(macOS 26.0, *)) {
    MTL4RenderPipelineBinaryFunctionsDescriptor *metadata =
      [MTL4RenderPipelineBinaryFunctionsDescriptor new];
    MTL4RenderPipelineColorAttachmentDescriptor *attachment =
      [MTL4RenderPipelineColorAttachmentDescriptor new];
    MTL4RenderPipelineDescriptor *pipeline = [MTL4RenderPipelineDescriptor new];
    MTL4RenderPipelineColorAttachmentDescriptorArray *array = pipeline.colorAttachments;
    if (metadata == nil || attachment == nil || array == nil) return 77;
    attachment.pixelFormat = MTLPixelFormatRGBA8Unorm;
    attachment.writeMask = MTLColorWriteMaskRed | MTLColorWriteMaskGreen;
    attachment.blendingState = MTL4BlendStateEnabled;
    [attachment reset];
    if (attachment.pixelFormat != MTLPixelFormatInvalid
        || attachment.writeMask != MTLColorWriteMaskAll
        || attachment.blendingState != MTL4BlendStateDisabled) return 1;
    array[0] = attachment;
    if (array[0] == nil) return 2;
    __weak MTL4RenderPipelineColorAttachmentDescriptor *weak = attachment;
    attachment = nil;
    /* Assignment may copy rather than retain the source descriptor. */
    (void)weak;
    if (array[0] == nil || array[0].pixelFormat != MTLPixelFormatInvalid) return 3;
    [array reset];
    if (array[0] == nil || array[0].pixelFormat != MTLPixelFormatInvalid
        || array[0].writeMask != MTLColorWriteMaskAll
        || array[0].blendingState != MTL4BlendStateDisabled) return 4;
    [array reset];
  }
  return 0;
} }
