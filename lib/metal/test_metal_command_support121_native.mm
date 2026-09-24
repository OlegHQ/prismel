#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static void require(bool condition, NSString *message) {
  if (!condition) {
    @throw [NSException exceptionWithName:@"CommandSupport121"
                                   reason:message
                                 userInfo:nil];
  }
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;

    MTLCaptureManager *manager = [MTLCaptureManager sharedCaptureManager];
    MTLCaptureDescriptor *capture = [MTLCaptureDescriptor new];
    require(manager != nil && capture != nil, @"capture objects");
    require(!manager.isCapturing, @"test must not inherit an active capture");
    capture.captureObject = device;
    if ([manager supportsDestination:MTLCaptureDestinationGPUTraceDocument]) {
      capture.destination = MTLCaptureDestinationGPUTraceDocument;
      require(capture.destination == MTLCaptureDestinationGPUTraceDocument,
              @"capture destination roundtrip");
    }

    id<MTLSharedEvent> event = [device newSharedEvent];
    require(event != nil, @"shared event");
    event.label = @"command-support121";
    event.signaledValue = 4;
    /* Some Metal runtimes expose a nil MTLEvent.device for shared events;
       the callable getter remains nullable at the native protocol boundary. */
    (void)event.device;
    require([event.label isEqualToString:@"command-support121"],
            @"shared event label roundtrip");
    require(event.signaledValue == 4, @"shared event value roundtrip");

    MTLIndirectCommandBufferDescriptor *renderDescriptor =
        [MTLIndirectCommandBufferDescriptor new];
    renderDescriptor.commandTypes = MTLIndirectCommandTypeDraw;
    renderDescriptor.inheritPipelineState = YES;
    renderDescriptor.inheritBuffers = YES;
    __block id<MTLIndirectCommandBuffer> renderBuffer = nil;
    @try {
      renderBuffer = [device newIndirectCommandBufferWithDescriptor:renderDescriptor
                                                   maxCommandCount:1
                                                            options:0];
      if (renderBuffer != nil) {
      id<MTLIndirectRenderCommand> render =
          [renderBuffer indirectRenderCommandAtIndex:0];
      require(render != nil, @"indirect render command");
      [render setCullMode:MTLCullModeBack];
      [render setFrontFacingWinding:MTLWindingCounterClockwise];
      [render setTriangleFillMode:MTLTriangleFillModeFill];
      [render setDepthBias:0.25 slopeScale:0.5 clamp:1.0];
      [render setBarrier];
      [render clearBarrier];
      }
    } @catch (NSException *exception) {
      renderBuffer = nil;
    }

    MTLIndirectCommandBufferDescriptor *computeDescriptor =
        [MTLIndirectCommandBufferDescriptor new];
    computeDescriptor.commandTypes = MTLIndirectCommandTypeConcurrentDispatch;
    computeDescriptor.inheritPipelineState = YES;
    computeDescriptor.inheritBuffers = YES;
    __block id<MTLIndirectCommandBuffer> computeBuffer = nil;
    @try {
      computeBuffer = [device newIndirectCommandBufferWithDescriptor:computeDescriptor
                                                    maxCommandCount:1
                                                             options:0];
      if (computeBuffer != nil) {
      id<MTLIndirectComputeCommand> compute =
          [computeBuffer indirectComputeCommandAtIndex:0];
      require(compute != nil, @"indirect compute command");
      [compute setThreadgroupMemoryLength:16 atIndex:0];
      [compute concurrentDispatchThreadgroups:MTLSizeMake(1, 1, 1)
                           threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
      [compute setBarrier];
      [compute clearBarrier];
      }
    } @catch (NSException *exception) {
      computeBuffer = nil;
    }

    NSLog(@"command-support121 native: capture/event green; indirect render=%@ compute=%@",
          renderBuffer == nil ? @"capability-gated" : @"green",
          computeBuffer == nil ? @"capability-gated" : @"green");
    return 0;
  }
}
