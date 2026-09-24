#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<decltype([MTLLinkedFunctions new]),
                             MTLLinkedFunctions *>);

int main()
{
  __weak MTLLinkedFunctions *weak_linked = nil;
  __weak id<MTLFunction> weak_function = nil;
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    NSError *error = nil;
    id<MTLLibrary> library = [device
        newLibraryWithSource:@"kernel void linked_constructor_kernel(){}"
                     options:nil
                       error:&error];
    if (library == nil) return 77;
    id<MTLFunction> function =
        [library newFunctionWithName:@"linked_constructor_kernel"];
    if (function == nil) return 1;

    @autoreleasepool {
      MTLLinkedFunctions *linked = [MTLLinkedFunctions new];
      if (linked == nil) return 2;
      weak_linked = linked;
      weak_function = function;

      linked.binaryFunctions = @[ function ];
      linked.privateFunctions = @[ function ];
      linked.groups = @{ @"entry" : @[ function ] };
      function = nil;
      library = nil;

      /* Every contained edge is retained by MTLLinkedFunctions. */
      if (weak_function == nil || linked.binaryFunctions.count != 1 ||
          linked.privateFunctions.count != 1 || linked.groups.count != 1)
        return 3;

      /* Clearing all edges releases the graph without destroying its owner. */
      linked.binaryFunctions = nil;
      linked.privateFunctions = nil;
      linked.groups = nil;
      if (linked.binaryFunctions != nil || linked.privateFunctions != nil ||
          linked.groups != nil)
        return 4;
    }
    if (weak_linked != nil) return 5;
  }
  if (weak_function != nil) return 6;
  return 0;
}
