#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

struct CheckedEncoderState { bool ended; NSUInteger debugDepth; };
static bool debug_transition(CheckedEncoderState *state, int operation) {
  if (state->ended) return false;
  if (operation == 1) { ++state->debugDepth; return true; }
  if (operation == 2) { if (state->debugDepth == 0) return false;
    --state->debugDepth; return true; }
  return operation == 0;
}
static bool finish(CheckedEncoderState *state) {
  if (state->ended || state->debugDepth != 0) return false;
  state->ended = true; return true;
}

int main(void) { @autoreleasepool {
  CheckedEncoderState state = {false, 0};
  if (debug_transition(&state, 2) || !debug_transition(&state, 1) ||
      finish(&state) || !debug_transition(&state, 2) || !finish(&state) ||
      debug_transition(&state, 0)) return 1;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (device == nil) return 77;
  id<MTLCommandQueue> queue = [device newCommandQueue];
  id<MTLCommandBuffer> command = [queue commandBuffer];
  id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
  if (encoder == nil || encoder.device.registryID != device.registryID) return 2;
  encoder.label = @"compute_λ";
  if (![encoder.label isEqualToString:@"compute_λ"]) return 3;
  [encoder insertDebugSignpost:@"signpost"];
  [encoder pushDebugGroup:@"balanced"];
  [encoder popDebugGroup];
  if ([encoder respondsToSelector:@selector(barrierAfterQueueStages:beforeStages:)])
    [encoder barrierAfterQueueStages:MTLStageDispatch beforeStages:MTLStageDispatch];
  encoder.label = nil;
  if (encoder.label != nil) return 4;
  [encoder endEncoding];
  [command commit]; [command waitUntilCompleted];
  if (command.status == MTLCommandBufferStatusError) return 5;
  return 0;
} }
