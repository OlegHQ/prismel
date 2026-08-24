#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <cstdint>

static const char *const kIds[] = {
  "class:MTL4CounterHeapDescriptor", "protocol:MTL4CounterHeap",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 2,
              "MTL4Counters2 metadata drift");

int main() { @autoreleasepool {
  (void)kIds;
  if (@available(macOS 26.0, *)) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
    MTL4CounterHeapDescriptor *descriptor = [MTL4CounterHeapDescriptor new];
    descriptor.type = MTL4CounterHeapTypeTimestamp;
    descriptor.count = 4;
    MTL4CounterHeapDescriptor *copy = [descriptor copy];
    descriptor.type = MTL4CounterHeapTypeInvalid; descriptor.count = 1;
    if (copy.type != MTL4CounterHeapTypeTimestamp || copy.count != 4) return 1;
    NSError *error = nil;
    id<MTL4CounterHeap> heap = nil;
    @try { heap = [device newCounterHeapWithDescriptor:copy error:&error]; }
    @catch (NSException *exception) {
      if (![exception.name isEqualToString:NSInvalidArgumentException]) return 2;
      return 77;
    }
    if (!heap) return 77;
    if (heap.type != MTL4CounterHeapTypeTimestamp || heap.count != 4) return 3;
    NSMutableString *label = [NSMutableString stringWithString:@"counter2"];
    heap.label = label; [label appendString:@"-mutated"];
    if (![heap.label isEqualToString:@"counter2"]) return 4;
    [heap invalidateCounterRange:NSMakeRange(0,4)];
    NSData *resolved = [heap resolveCounterRange:NSMakeRange(0,4)];
    if (!resolved || resolved.length != 4 * sizeof(MTL4TimestampHeapEntry)) return 5;
    const MTL4TimestampHeapEntry *entries =
      static_cast<const MTL4TimestampHeapEntry *>(resolved.bytes);
    for (NSUInteger index=0; index<4; ++index)
      if (entries[index].timestamp != 0) return 6;
  }
  return 0;
} }
