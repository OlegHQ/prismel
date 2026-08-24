#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static bool has_defaults(MTL4RenderPipelineColorAttachmentDescriptor *value) {
  return value != nil && value.pixelFormat == MTLPixelFormatInvalid &&
         value.blendingState == MTL4BlendStateDisabled &&
         value.sourceRGBBlendFactor == MTLBlendFactorOne &&
         value.destinationRGBBlendFactor == MTLBlendFactorZero &&
         value.rgbBlendOperation == MTLBlendOperationAdd &&
         value.sourceAlphaBlendFactor == MTLBlendFactorOne &&
         value.destinationAlphaBlendFactor == MTLBlendFactorZero &&
         value.alphaBlendOperation == MTLBlendOperationAdd &&
         value.writeMask == MTLColorWriteMaskAll;
}

static void configure_nondefaults(
    MTL4RenderPipelineColorAttachmentDescriptor *value, NSUInteger index) {
  value.pixelFormat = (index & 1) == 0 ? MTLPixelFormatRGBA8Unorm
                                       : MTLPixelFormatBGRA8Unorm;
  value.blendingState = MTL4BlendStateEnabled;
  value.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
  value.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  value.rgbBlendOperation = MTLBlendOperationSubtract;
  value.sourceAlphaBlendFactor = MTLBlendFactorDestinationAlpha;
  value.destinationAlphaBlendFactor = MTLBlendFactorOneMinusDestinationAlpha;
  value.alphaBlendOperation = MTLBlendOperationReverseSubtract;
  value.writeMask = MTLColorWriteMaskRed | MTLColorWriteMaskBlue;
}

int main() {
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      MTL4RenderPipelineColorAttachmentDescriptor *attachment =
          [MTL4RenderPipelineColorAttachmentDescriptor new];
      if (!has_defaults(attachment)) return 1;
      configure_nondefaults(attachment, 0);
      [attachment reset];
      if (!has_defaults(attachment)) return 2;
      [attachment reset];
      if (!has_defaults(attachment)) return 3;

      MTL4RenderPipelineDescriptor *pipeline = [MTL4RenderPipelineDescriptor new];
      MTL4RenderPipelineColorAttachmentDescriptorArray *array =
          pipeline.colorAttachments;
      if (array == nil) return 4;
      for (NSUInteger index = 0; index < 8; ++index) {
        MTL4RenderPipelineColorAttachmentDescriptor *source =
            [MTL4RenderPipelineColorAttachmentDescriptor new];
        configure_nondefaults(source, index);
        __weak MTL4RenderPipelineColorAttachmentDescriptor *weak_source = source;
        array[index] = source;
        MTL4RenderPipelineColorAttachmentDescriptor *stored = array[index];
        if (stored == nil || stored == source || has_defaults(stored)) return 5;
        source.pixelFormat = MTLPixelFormatR8Unorm;
        if (stored.pixelFormat == MTLPixelFormatR8Unorm) return 6;
        source = nil;
        if (weak_source != nil) return 7;
      }

      MTL4RenderPipelineColorAttachmentDescriptorArray *copy = [array copy];
      if (copy == nil || copy == array) return 8;
      [array reset];
      for (NSUInteger index = 0; index < 8; ++index) {
        if (!has_defaults(array[index])) return 9;
        if (has_defaults(copy[index])) return 10;
      }
      [copy reset];
      for (NSUInteger index = 0; index < 8; ++index)
        if (!has_defaults(copy[index])) return 11;
      [copy reset];
    }
  }
  return 0;
}
