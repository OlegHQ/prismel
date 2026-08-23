#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <type_traits>

/* Isolated compile-time qualification TU. Calls are deliberately unreachable;
   clang still type-checks every direct Objective-C selector and result type. */
static void prismel_qualify_resource_selectors(
    id<MTLDevice> device, id<MTLBuffer> buffer, id<MTLTexture> texture,
    id<MTLHeap> heap, id<MTLResource> resource,
    id<MTLResourceStateCommandEncoder> state_encoder, id<MTLFence> fence,
    id<MTLResourceViewPool> pool, id<MTLTextureViewPool> texture_pool,
    MTLBufferLayoutDescriptorArray *layouts,
    MTLAccelerationStructureDescriptor *acceleration_descriptor) {
  if (true) return;
  MTLBufferLayoutDescriptor *layout = [MTLBufferLayoutDescriptor new];
  layout.stride = 16; layout.stepRate = 1; layout.stepFunction = MTLStepFunctionPerVertex;
  NSUInteger stride = layout.stride, rate = layout.stepRate;
  MTLStepFunction step = layout.stepFunction;
  MTLBufferLayoutDescriptor *indexed_layout = layouts[0]; layouts[0] = indexed_layout;
  (void)stride; (void)rate; (void)step;
  [buffer addDebugMarker:@"generated" range:NSMakeRange(0, 0)];
  [buffer removeAllDebugMarkers];
  id<MTLBuffer> remote_buffer = buffer.remoteStorageBuffer;
  id<MTLBuffer> remote_buffer_view = [buffer newRemoteBufferViewForDevice:device];
  (void)remote_buffer; (void)remote_buffer_view;
  MTLSize tile = [device sparseTileSizeWithTextureType:MTLTextureType2D
                                           pixelFormat:MTLPixelFormatRGBA8Unorm
                                           sampleCount:1];
  (void)tile;
  id<MTLDevice> heap_device = heap.device;
  MTLResourceOptions heap_options = heap.resourceOptions;
  (void)heap_device; (void)heap_options;
  id<MTLAccelerationStructure> acceleration0 =
      [heap newAccelerationStructureWithDescriptor:acceleration_descriptor];
  id<MTLAccelerationStructure> acceleration1 =
      [heap newAccelerationStructureWithDescriptor:acceleration_descriptor offset:0];
  id<MTLAccelerationStructure> acceleration2 =
      [heap newAccelerationStructureWithSize:256];
  id<MTLAccelerationStructure> acceleration3 =
      [heap newAccelerationStructureWithSize:256 offset:0];
  (void)acceleration0; (void)acceleration1; (void)acceleration2; (void)acceleration3;
  NSUInteger allocated = resource.allocatedSize;
  id<MTLDevice> resource_device = resource.device;
  id<MTLHeap> parent_heap = resource.heap;
  MTLResourceOptions options = resource.resourceOptions;
  (void)allocated; (void)resource_device; (void)parent_heap; (void)options;
  if (@available(macOS 14.4, *)) {
    task_id_token_t token = {};
    kern_return_t owner_result = [resource setOwnerWithIdentity:token];
    (void)owner_result;
  }
  [state_encoder updateFence:fence]; [state_encoder waitForFence:fence];
  MTLResourceStatePassDescriptor *pass = [MTLResourceStatePassDescriptor resourceStatePassDescriptor];
  MTLResourceStatePassSampleBufferAttachmentDescriptorArray *samples = pass.sampleBufferAttachments;
  MTLResourceStatePassSampleBufferAttachmentDescriptor *sample = samples[0];
  sample.startOfEncoderSampleIndex = 0; sample.endOfEncoderSampleIndex = 1;
  id<MTLCounterSampleBuffer> sample_buffer = sample.sampleBuffer;
  sample.sampleBuffer = sample_buffer; samples[0] = sample;
  if (@available(macOS 26.0, *)) {
    MTLResourceViewPoolDescriptor *pool_descriptor = [MTLResourceViewPoolDescriptor new];
    pool_descriptor.label = @"generated"; pool_descriptor.resourceViewCount = 4;
    NSString *pool_label = pool.label; NSUInteger count = pool.resourceViewCount;
    id<MTLDevice> pool_device = pool.device; MTLResourceID base = pool.baseResourceID;
    MTLResourceID copied = [pool copyResourceViewsFromPool:pool sourceRange:NSMakeRange(0, 1)
                                          destinationIndex:0];
    (void)pool_descriptor; (void)pool_label; (void)count; (void)pool_device;
    (void)base; (void)copied;
    MTLResourceID view0 = [texture_pool setTextureView:texture atIndex:0];
    MTLTextureViewDescriptor *view_descriptor = [MTLTextureViewDescriptor new];
    MTLResourceID view1 = [texture_pool setTextureView:texture descriptor:view_descriptor atIndex:1];
    MTLTextureDescriptor *buffer_texture = [MTLTextureDescriptor
      textureBufferDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4
      resourceOptions:MTLResourceStorageModeShared usage:MTLTextureUsageShaderRead];
    MTLResourceID view2 = [texture_pool setTextureViewFromBuffer:buffer descriptor:buffer_texture
      offset:0 bytesPerRow:256 atIndex:2];
    NSError *pool_error = nil;
    id<MTLTextureViewPool> created_pool =
        [device newTextureViewPoolWithDescriptor:pool_descriptor error:&pool_error];
    MTLTensorDescriptor *tensor_descriptor = [MTLTensorDescriptor new];
    NSError *tensor_error = nil;
    id<MTLTensor> tensor = [buffer newTensorWithDescriptor:tensor_descriptor
                                                    offset:0 error:&tensor_error];
    Class texture_reference_type = [MTLTextureReferenceType class];
    (void)view0; (void)view1; (void)view2;
    (void)created_pool; (void)pool_error; (void)tensor; (void)tensor_error;
    (void)texture_reference_type;
  }
  BOOL framebuffer_only = texture.framebufferOnly;
  id<MTLBuffer> texture_buffer = texture.buffer;
  NSUInteger row = texture.bufferBytesPerRow, offset = texture.bufferOffset;
  id<MTLTexture> remote_texture = texture.remoteStorageTexture;
  id<MTLTexture> remote_texture_view = [texture newRemoteTextureViewForDevice:device];
  id<MTLResource> root = texture.rootResource;
  (void)framebuffer_only; (void)texture_buffer; (void)row; (void)offset;
  (void)remote_texture; (void)remote_texture_view; (void)root;
  MTLTextureDescriptor *d2 = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
    MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
  MTLTextureDescriptor *dc = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:
    MTLPixelFormatRGBA8Unorm size:4 mipmapped:NO];
  (void)d2; (void)dc;
}

static_assert(MTLResourceOptionCPUCacheModeDefault ==
              (MTLResourceOptions)(MTLCPUCacheModeDefaultCache << MTLResourceCPUCacheModeShift));
static_assert(MTLResourceOptionCPUCacheModeWriteCombined ==
              (MTLResourceOptions)(MTLCPUCacheModeWriteCombined << MTLResourceCPUCacheModeShift));
static_assert(MTLResourceStorageModeMemoryless ==
              (MTLResourceOptions)(MTLStorageModeMemoryless << MTLResourceStorageModeShift));

extern "C" NSUInteger prismel_metal_resource_generated_qualified_id_count(void) {
  return 92;
}
