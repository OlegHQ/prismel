#import <Foundation/Foundation.h>
extern "C" NSUInteger prismel_metal_resource_generated_qualified_id_count(void);
int main(void) { @autoreleasepool {
  if (prismel_metal_resource_generated_qualified_id_count() != 92) return 1;
  NSLog(@"92 isolated resource selector IDs compiled with direct typed calls");
  return 0;
}}
