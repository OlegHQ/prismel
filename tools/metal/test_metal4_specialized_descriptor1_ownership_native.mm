#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kIds[] = {
  "class:MTL4SpecializedFunctionDescriptor",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 1,
              "MTL4SpecializedFunctionDescriptor1 drift");

int main() { @autoreleasepool {
  (void)kIds;
  if (@available(macOS 26.0, *)) {
    MTL4LibraryFunctionDescriptor *base = [MTL4LibraryFunctionDescriptor new];
    base.name = @"base-function";
    MTLFunctionConstantValues *constants = [MTLFunctionConstantValues new];
    uint32_t value = 17;
    [constants setConstantValue:&value type:MTLDataTypeUInt atIndex:0];
    MTL4SpecializedFunctionDescriptor *specialized =
      [MTL4SpecializedFunctionDescriptor new];
    NSMutableString *name = [NSMutableString stringWithString:@"specialized"];
    specialized.functionDescriptor = base;
    specialized.specializedName = name;
    specialized.constantValues = constants;
    MTL4FunctionDescriptor *stored_base = specialized.functionDescriptor;
    MTLFunctionConstantValues *stored_constants = specialized.constantValues;
    if (!stored_base || stored_base == base || !stored_constants ||
        stored_constants == constants ||
        ![specialized.specializedName isEqualToString:@"specialized"])
      return 1;
    [name appendString:@"-mutated"];
    base.name = @"mutated-base";
    value = 99;
    [constants setConstantValue:&value type:MTLDataTypeUInt atIndex:0];
    if (![specialized.specializedName isEqualToString:@"specialized"] ||
        ![((MTL4LibraryFunctionDescriptor *)stored_base).name
          isEqualToString:@"base-function"]) return 2;
    base = nil; constants = nil; name = nil;
    if (specialized.functionDescriptor != stored_base ||
        specialized.constantValues != stored_constants) return 3;
    specialized.functionDescriptor = nil;
    specialized.specializedName = nil;
    specialized.constantValues = nil;
    if (specialized.functionDescriptor || specialized.specializedName ||
        specialized.constantValues) return 4;
  }
  return 0;
} }
