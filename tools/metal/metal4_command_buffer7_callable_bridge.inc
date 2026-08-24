/* Isolated callable shard for the exact MTL4CommandBuffer7 residual family.
   The eventual CAML bridge owns an MTL4CommandBufferOptions handle and retains
   it, its optional log state, and the allocator until endCommandBuffer. */
#import <Metal/Metal.h>

API_AVAILABLE(macos(26.0))
static MTL4CommandBufferOptions * _Nonnull
prismel_metal4_command_buffer_options_create(void) {
  return [MTL4CommandBufferOptions new];
}

API_AVAILABLE(macos(26.0))
static bool prismel_metal4_command_buffer_options_set_log_state(
    MTL4CommandBufferOptions * _Nonnull options,
    id<MTLLogState> _Nullable log_state,
    uint64_t log_state_registry_id,
    uint64_t expected_registry_id,
    NSString * _Nullable * _Nonnull failure) {
  if (log_state != nil && log_state_registry_id != expected_registry_id) {
    *failure = @"MTL4 command-buffer log state belongs to another device";
    return false;
  }
  @try {
    options.logState = log_state;
    if (options.logState != log_state) {
      *failure = @"Metal changed the MTL4 command-buffer log state";
      return false;
    }
    return true;
  } @catch (NSException *exception) {
    *failure = exception.reason;
    return false;
  }
}

API_AVAILABLE(macos(26.0))
static id<MTLLogState> _Nullable
prismel_metal4_command_buffer_options_log_state(
    MTL4CommandBufferOptions * _Nonnull options) {
  return options.logState;
}

API_AVAILABLE(macos(26.0))
static bool prismel_metal4_command_buffer_begin_with_options(
    id<MTL4CommandBuffer> _Nonnull command_buffer,
    id<MTL4CommandAllocator> _Nonnull allocator,
    MTL4CommandBufferOptions * _Nonnull options,
    uint64_t log_state_registry_id,
    NSString * _Nullable * _Nonnull failure) {
  if (command_buffer.device.registryID != allocator.device.registryID) {
    *failure = @"MTL4 command allocator belongs to another device";
    return false;
  }
  id<MTLLogState> log_state = options.logState;
  if (log_state != nil &&
      log_state_registry_id != command_buffer.device.registryID) {
    *failure = @"MTL4 command-buffer log state belongs to another device";
    return false;
  }
  @try {
    [command_buffer beginCommandBufferWithAllocator:allocator options:options];
    return true;
  } @catch (NSException *exception) {
    *failure = exception.reason;
    return false;
  }
}

API_AVAILABLE(macos(26.0))
static id<MTL4RenderCommandEncoder> _Nullable
prismel_metal4_command_buffer_render_encoder(
    id<MTL4CommandBuffer> _Nonnull command_buffer,
    MTL4RenderPassDescriptor * _Nonnull descriptor,
    MTL4RenderEncoderOptions options,
    NSString * _Nullable * _Nonnull failure) {
  const MTL4RenderEncoderOptions supported =
      MTL4RenderEncoderOptionSuspending | MTL4RenderEncoderOptionResuming;
  if ((options & ~supported) != 0) {
    *failure = @"invalid MTL4 render encoder options";
    return nil;
  }
  @try {
    id<MTL4RenderCommandEncoder> encoder =
        [command_buffer renderCommandEncoderWithDescriptor:descriptor
                                                   options:options];
    if (encoder == nil) *failure = @"Metal failed to create an MTL4 render encoder";
    return encoder;
  } @catch (NSException *exception) {
    *failure = exception.reason;
    return nil;
  }
}

API_AVAILABLE(macos(26.0))
static id<MTL4MachineLearningCommandEncoder> _Nullable
prismel_metal4_command_buffer_machine_learning_encoder(
    id<MTL4CommandBuffer> _Nonnull command_buffer,
    NSString * _Nullable * _Nonnull failure) {
  @try {
    id<MTL4MachineLearningCommandEncoder> encoder =
        command_buffer.machineLearningCommandEncoder;
    if (encoder == nil) *failure = @"Metal failed to create an MTL4 machine-learning encoder";
    return encoder;
  } @catch (NSException *exception) {
    *failure = exception.reason;
    return nil;
  }
}
