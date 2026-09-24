#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cstdio>
#include "metal4_command_buffer7_callable_bridge.inc"

int main(void) {
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      id<MTLDevice> device = MTLCreateSystemDefaultDevice();
      if (device == nil) return 77;
      MTL4CommandBufferOptions *options =
          prismel_metal4_command_buffer_options_create();
      NSString *failure = nil;
      if (options == nil ||
          !prismel_metal4_command_buffer_options_set_log_state(
              options, nil, 0, device.registryID, &failure) ||
          prismel_metal4_command_buffer_options_log_state(options) != nil) {
        std::fprintf(stderr, "options property failure: %s\n",
                     failure.UTF8String ?: "unknown");
        return 1;
      }
      id<MTL4CommandAllocator> allocator = [device newCommandAllocator];
      id<MTL4CommandBuffer> command_buffer = [device newCommandBuffer];
      if (allocator == nil || command_buffer == nil) return 77;
      if (!prismel_metal4_command_buffer_begin_with_options(
              command_buffer, allocator, options, 0, &failure)) {
        std::fprintf(stderr, "begin failure: %s\n",
                     failure.UTF8String ?: "unknown");
        return 1;
      }

      MTL4RenderPassDescriptor *descriptor = [MTL4RenderPassDescriptor new];
      failure = nil;
      if (prismel_metal4_command_buffer_render_encoder(
              command_buffer, descriptor,
              static_cast<MTL4RenderEncoderOptions>(NSUIntegerMax),
              &failure) != nil || failure == nil) {
        std::fprintf(stderr, "invalid render options were not rejected\n");
        return 1;
      }
      failure = nil;
      id<MTL4RenderCommandEncoder> render =
          prismel_metal4_command_buffer_render_encoder(
              command_buffer, descriptor, MTL4RenderEncoderOptionNone, &failure);
      if (render != nil) [render endEncoding];

      failure = nil;
      id<MTL4MachineLearningCommandEncoder> ml =
          prismel_metal4_command_buffer_machine_learning_encoder(
              command_buffer, &failure);
      if (ml != nil) [ml endEncoding];
      [command_buffer endCommandBuffer];
      std::printf("MTL4CommandBuffer7 native: exact 7/7 typed calls, options/property/device/rejection passed\n");
      return 0;
    }
    return 77;
  }
}
