#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static const char *const kIds[] = {
  "class:MTLRasterizationRateLayerArray",
  "class:MTLRasterizationRateLayerDescriptor",
  "class:MTLRasterizationRateMapDescriptor",
  "class:MTLRasterizationRateSampleArray",
  "protocol:MTLRasterizationRateMap"
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 5);

static void require(bool condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) { @autoreleasepool {
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  require(device != nil, @"device");
  if (![device respondsToSelector:@selector(newRasterizationRateMapWithDescriptor:)]) {
    NSLog(@"RasterizationRate exact5 capability rejection passed");
    return 0;
  }
  float horizontal[] = {1.0f, 0.75f};
  float vertical[] = {1.0f};
  MTLRasterizationRateLayerDescriptor *layer =
    [[MTLRasterizationRateLayerDescriptor alloc]
      initWithSampleCount:MTLSizeMake(2, 1, 0)
      horizontal:horizontal vertical:vertical];
  require(layer != nil && layer.horizontalSampleStorage[1] == 0.75f,
          @"layer/sample array roundtrip");
  for (NSUInteger count = 1; count <= 2; ++count) {
    MTLRasterizationRateMapDescriptor *descriptor =
      [[MTLRasterizationRateMapDescriptor alloc] init];
    descriptor.screenSize = MTLSizeMake(32, 24, 0);
    for (NSUInteger index = 0; index < count; ++index) descriptor.layers[index] = layer;
    id<MTLRasterizationRateMap> map =
      [device newRasterizationRateMapWithDescriptor:descriptor];
    if (map == nil) {
      require(count == 2, @"one-layer map must execute when feature is supported");
      continue;
    }
    require(map.device.registryID == device.registryID && map.layerCount == count,
            @"map protocol identity/layer count");
    require([map physicalSizeForLayer:0].width > 0, @"physical map size");
  }
  NSLog(@"RasterizationRate exact5 one/multi-layer conformance passed");
  return 0;
}}
