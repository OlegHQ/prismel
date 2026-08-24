#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <type_traits>

template <class T, class = void> struct PrismelComplete : std::false_type {};
template <class T>
struct PrismelComplete<T, std::void_t<decltype(sizeof(T))>> : std::true_type {};

static const char *const kIds[] = {"record:MTLSharedTextureHandlePrivate"};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 1,
              "SharedTextureHandlePrivate1 drift");
static_assert(!PrismelComplete<struct MTLSharedTextureHandlePrivate>::value,
              "private shared-texture record must remain opaque");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  MTLTextureDescriptor *descriptor = [MTLTextureDescriptor
    texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
  descriptor.storageMode = MTLStorageModeShared;
  id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
  if (!texture) return 77;
  uint8_t source[64]; for (NSUInteger i=0;i<64;++i) source[i]=(uint8_t)(i+1);
  [texture replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0
               withBytes:source bytesPerRow:16];
  MTLSharedTextureHandle *handle = [texture newSharedTextureHandle];
  if (!handle) return 77;
  if (handle.device.registryID != device.registryID) return 1;
  NSString *label_snapshot = [handle.label copy];
  (void)label_snapshot;
  id<MTLTexture> reopened = [device newSharedTextureWithHandle:handle];
  if (!reopened || reopened.device.registryID != device.registryID) return 3;
  uint8_t copy[64] = {};
  [reopened getBytes:copy bytesPerRow:16 fromRegion:MTLRegionMake2D(0,0,4,4)
            mipmapLevel:0];
  if (__builtin_memcmp(source,copy,sizeof(source)) != 0) return 4;

  NSError *error = nil;
  NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:handle
                                         requiringSecureCoding:YES error:&error];
  if (!archive || error) return 5;
  MTLSharedTextureHandle *decoded = [NSKeyedUnarchiver
    unarchivedObjectOfClass:[MTLSharedTextureHandle class] fromData:archive error:&error];
  if (!decoded || error || decoded.device.registryID != device.registryID) return 6;
  id<MTLTexture> decoded_texture = [device newSharedTextureWithHandle:decoded];
  if (!decoded_texture) return 7;
  return 0;
} }
