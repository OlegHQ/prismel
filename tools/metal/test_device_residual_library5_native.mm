#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<
    decltype([(id<MTLDevice>)nil newDefaultLibrary]), id<MTLLibrary>>);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static_assert(std::is_same_v<
    decltype([(id<MTLDevice>)nil newLibraryWithFile:(NSString *)nil
                                             error:(NSError **)nil]),
    id<MTLLibrary>>);
#pragma clang diagnostic pop

int main()
{
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    id<MTLLibrary> library = [device newDefaultLibrary];
    /* Applications need not ship a default metallib; nil is the documented
       capability/result lane, and must not be converted into an invalid
       handle.  Exercise deterministic error ownership for a missing file. */
    (void)library;
    NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    id<MTLLibrary> missing =
        [device newLibraryWithFile:@"/prismel/does/not/exist.metallib"
                             error:&error];
#pragma clang diagnostic pop
    if (missing != nil || error == nil) return 1;
  }
  return 0;
}
