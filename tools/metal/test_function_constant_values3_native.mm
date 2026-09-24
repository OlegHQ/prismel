#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static bool cardinality(size_t bytes, size_t width, NSInteger start, NSInteger count) {
  return width > 0 && start >= 0 && count > 0
    && (size_t)count <= SIZE_MAX / width && bytes == (size_t)count * width;
}

int main() { @autoreleasepool {
  if (cardinality(8, 4, -1, 2) || cardinality(7, 4, 0, 2)
      || cardinality(4, 0, 0, 1) || !cardinality(8, 4, 3, 2)) return 1;
  MTLFunctionConstantValues *values = [MTLFunctionConstantValues new];
  if (values == nil) return 2;
  float scalar = 1.25f; int32_t integers[2] = { 7, 11 }; bool flag = true;
  [values setConstantValue:&scalar type:MTLDataTypeFloat atIndex:0];
  [values setConstantValues:integers type:MTLDataTypeInt withRange:NSMakeRange(1, 2)];
  [values setConstantValue:&flag type:MTLDataTypeBool atIndex:3];
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (device == nil) return 77;
  NSError *error = nil;
  NSString *source = @"constant float f [[function_constant(0)]]; "
    "constant int a [[function_constant(1)]]; constant int b [[function_constant(2)]]; "
    "constant bool enabled [[function_constant(3)]]; "
    "kernel void constants_kernel() { if (enabled && f > 0.0 && a + b > 0) {} }";
  id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
  if (library == nil) return 77;
  id<MTLFunction> function = [library newFunctionWithName:@"constants_kernel"
    constantValues:values error:&error];
  if (function == nil) return 3;
  [values reset];
  [values setConstantValue:&scalar type:MTLDataTypeFloat atIndex:0];
  [values setConstantValues:integers type:MTLDataTypeInt withRange:NSMakeRange(1, 2)];
  [values setConstantValue:&flag type:MTLDataTypeBool atIndex:3];
  id<MTLFunction> rebuilt = [library newFunctionWithName:@"constants_kernel"
    constantValues:values error:&error];
  if (rebuilt == nil) return 4;
  return 0;
} }
