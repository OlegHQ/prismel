#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<decltype(((id<MTLTexture>)nil).gpuResourceID),
                             MTLResourceID>);

int main()
{
  if (@available(macOS 26.0, *)) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil || ![device supportsFamily:MTLGPUFamilyMetal4]) return 0;
    NSError *error = nil;
    MTL4ArgumentTableDescriptor *descriptor =
        [MTL4ArgumentTableDescriptor new];
    descriptor.maxBufferBindCount = 1;
    descriptor.initializeBindings = YES;
    id<MTL4ArgumentTable> table =
        [device newArgumentTableWithDescriptor:descriptor error:&error];
    if (table == nil) return 77;
    __weak id<MTLTexture> weak_texture = nil;
    @autoreleasepool {
      MTLTextureDescriptor *texture_descriptor =
          [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                             width:4 height:4 mipmapped:NO];
      id<MTLTexture> texture = [device newTextureWithDescriptor:texture_descriptor];
      if (texture == nil || texture.gpuResourceID._impl == 0) return 1;
      weak_texture = texture;
      @try {
        [table setResource:texture.gpuResourceID atBufferIndex:0];
      } @catch (NSException *exception) {
        (void)exception;
        return 2;
      }
      if (weak_texture == nil) return 3;
      texture = nil;
    }
    /* setResource stores only MTLResourceID.  It does not own the source
       object, proving that the safe binding must retain it explicitly. */
    if (weak_texture != nil) return 4;
  }
  return 0;
}
