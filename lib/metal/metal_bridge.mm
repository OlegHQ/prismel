#define CAML_NAME_SPACE

#include <algorithm>
#include <array>
#include <deque>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <limits>
#include <mutex>
#include <memory>
#include <unordered_set>
#include <vector>

#include <sys/mman.h>
#include <unistd.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/threads.h>

#include <mach/mach.h>

#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceObjC.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
// The shared token header supplies C linkage when included from Objective-C++.
#include "../native_layer_token/native_layer_token.h"

@interface PrismelMetalExternalMemory : NSObject
@property(nonatomic, readonly) void *bytes;
@property(nonatomic, readonly) NSUInteger length;
@property(nonatomic, readonly) NSUInteger alignment;
- (nullable instancetype)initWithLength:(NSUInteger)length
                              alignment:(NSUInteger)alignment;
@end

@implementation PrismelMetalExternalMemory {
  void *_bytes;
  NSUInteger _length;
  NSUInteger _alignment;
}

- (nullable instancetype)initWithLength:(NSUInteger)length
                              alignment:(NSUInteger)alignment {
  self = [super init];
  if (self != nil) {
    if (length == 0 || alignment == 0) {
      return nil;
    }
    void *bytes = mmap(nullptr, length, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANON, -1, 0);
    if (bytes == MAP_FAILED) {
      return nil;
    }
    _bytes = bytes;
    _length = length;
    _alignment = alignment;
  }
  return self;
}

- (void)dealloc {
  if (_bytes != nullptr) {
    (void)munmap(_bytes, _length);
  }
}

- (void *)bytes { return _bytes; }
- (NSUInteger)length { return _length; }
- (NSUInteger)alignment { return _alignment; }

@end

typedef NS_ENUM(NSUInteger, PrismelMetalXpcResourceKind) {
  PrismelMetalXpcResourceKindSharedTexture = 0,
  PrismelMetalXpcResourceKindIoSurface = 1,
};

static NSString *PrismelMetalXpcResourceName(
    PrismelMetalXpcResourceKind kind) {
  switch (kind) {
  case PrismelMetalXpcResourceKindSharedTexture:
    return @"shared-texture";
  case PrismelMetalXpcResourceKindIoSurface:
    return @"IOSurface";
  }
}

static BOOL PrismelMetalXpcResourceMatchesKind(
    id resource, PrismelMetalXpcResourceKind kind) {
  switch (kind) {
  case PrismelMetalXpcResourceKindSharedTexture:
    return [resource isKindOfClass:[MTLSharedTextureHandle class]];
  case PrismelMetalXpcResourceKindIoSurface:
    return [resource isKindOfClass:[IOSurface class]];
  }
}

@protocol PrismelMetalResourceXpc
- (void)exchangeOperation:(NSString *)operation
                 resource:(id)resource
                 metadata:(NSData *)metadata
                     data:(NSData *)data
                withReply:(void (^)(id, NSData *, NSData *, NSString *))reply;
@end

using PrismelMetalXpcReply =
    void (^)(id, NSData *, NSData *, NSString *);

static thread_local bool prismel_metal_xpc_main_executor = false;

API_AVAILABLE(macos(26.0))
@interface PrismelMetalCheckedComputeRequest : NSObject
@property(nonatomic, strong) MTL4ComputePipelineDescriptor *descriptor;
@property(nonatomic, strong, nullable)
    MTL4PipelineStageDynamicLinkingDescriptor *dynamicLinking;
@property(nonatomic, strong, nullable) MTL4CompilerTaskOptions *taskOptions;
@property(nonatomic, copy, nullable) NSString *label;
@property(nonatomic) BOOL reflectionRequested;
@end

@implementation PrismelMetalCheckedComputeRequest
@end

API_AVAILABLE(macos(26.0))
@interface PrismelMetalCheckedRenderRequest : NSObject
@property(nonatomic, strong) MTL4PipelineDescriptor *descriptor;
@property(nonatomic, strong, nullable)
    MTL4RenderPipelineDynamicLinkingDescriptor *dynamicLinking;
@property(nonatomic, strong, nullable) MTL4CompilerTaskOptions *taskOptions;
@property(nonatomic, copy, nullable) NSString *label;
@property(nonatomic) BOOL reflectionRequested;
@end

@implementation PrismelMetalCheckedRenderRequest
@end

API_AVAILABLE(macos(26.0))
@interface PrismelMetalPipelineArchiveState : NSObject
@property(nonatomic, strong, readonly) id<MTL4Archive> archive;
@property(nonatomic, strong, readonly) id<MTLDevice> device;
@property(nonatomic, strong, readonly) id<MTL4Compiler> compiler;
- (instancetype)initWithArchive:(id<MTL4Archive>)archive
                         device:(id<MTLDevice>)device
                       compiler:(id<MTL4Compiler>)compiler;
@end

@implementation PrismelMetalPipelineArchiveState
- (instancetype)initWithArchive:(id<MTL4Archive>)archive
                         device:(id<MTLDevice>)device
                       compiler:(id<MTL4Compiler>)compiler {
  self = [super init];
  if (self != nil) { _archive = archive; _device = device; _compiler = compiler; }
  return self;
}
@end

API_AVAILABLE(macos(26.0))
@interface PrismelMetal4CommandBufferState : NSObject
@property(nonatomic, strong, readonly) id<MTL4CommandBuffer> commandBuffer;
@property(nonatomic, strong, readonly) id<MTL4CommandAllocator> allocator;
- (instancetype)initWithCommandBuffer:(id<MTL4CommandBuffer>)commandBuffer
                             allocator:(id<MTL4CommandAllocator>)allocator;
- (void)retainEncodedObject:(id)object;
- (void)releaseEncodedObjects;
@end

@implementation PrismelMetal4CommandBufferState {
  id<MTL4CommandBuffer> _commandBuffer;
  id<MTL4CommandAllocator> _allocator;
  NSHashTable *_encodedObjects;
}

- (instancetype)initWithCommandBuffer:(id<MTL4CommandBuffer>)commandBuffer
                             allocator:(id<MTL4CommandAllocator>)allocator {
  self = [super init];
  if (self != nil) {
    _commandBuffer = commandBuffer;
    _allocator = allocator;
    _encodedObjects = [NSHashTable
        hashTableWithOptions:NSPointerFunctionsStrongMemory |
                             NSPointerFunctionsObjectPointerPersonality];
  }
  return self;
}

- (id<MTL4CommandBuffer>)commandBuffer { return _commandBuffer; }
- (id<MTL4CommandAllocator>)allocator { return _allocator; }

- (void)retainEncodedObject:(id)object {
  if (object != nil && ![_encodedObjects containsObject:object]) {
    [_encodedObjects addObject:object];
  }
}

- (void)releaseEncodedObjects { [_encodedObjects removeAllObjects]; }

@end

API_AVAILABLE(macos(26.0))
@interface PrismelMetal4ArgumentTableState : NSObject
@property(nonatomic, strong, readonly) id<MTL4ArgumentTable> argumentTable;
@property(nonatomic, readonly) NSUInteger maxBufferBindCount;
@property(nonatomic, readonly) NSUInteger maxTextureBindCount;
@property(nonatomic, readonly) NSUInteger maxSamplerStateBindCount;
@property(nonatomic, readonly) BOOL supportAttributeStrides;
- (instancetype)initWithArgumentTable:(id<MTL4ArgumentTable>)argumentTable
                       maxBufferCount:(NSUInteger)maxBufferCount
                      maxTextureCount:(NSUInteger)maxTextureCount
                      maxSamplerCount:(NSUInteger)maxSamplerCount
               supportAttributeStrides:(BOOL)supportAttributeStrides;
- (void)setBoundBuffer:(nullable id<MTLBuffer>)buffer
                atIndex:(NSUInteger)index;
- (void)setBoundTexture:(nullable id<MTLTexture>)texture
                 atIndex:(NSUInteger)index;
- (void)setBoundSampler:(nullable id<MTLSamplerState>)sampler
                 atIndex:(NSUInteger)index;
- (void)retainBoundObjectsInCommandBuffer:
    (PrismelMetal4CommandBufferState *)commandBuffer;
@end

@implementation PrismelMetal4ArgumentTableState {
  id<MTL4ArgumentTable> _argumentTable;
  NSMutableArray *_buffers;
  NSMutableArray *_textures;
  NSMutableArray *_samplers;
  BOOL _supportAttributeStrides;
}

- (instancetype)initWithArgumentTable:(id<MTL4ArgumentTable>)argumentTable
                       maxBufferCount:(NSUInteger)maxBufferCount
                      maxTextureCount:(NSUInteger)maxTextureCount
                      maxSamplerCount:(NSUInteger)maxSamplerCount
               supportAttributeStrides:(BOOL)supportAttributeStrides {
  self = [super init];
  if (self != nil) {
    _argumentTable = argumentTable;
    _buffers = [[NSMutableArray alloc] initWithCapacity:maxBufferCount];
    _textures = [[NSMutableArray alloc] initWithCapacity:maxTextureCount];
    _samplers = [[NSMutableArray alloc] initWithCapacity:maxSamplerCount];
    for (NSUInteger index = 0; index < maxBufferCount; ++index) {
      [_buffers addObject:NSNull.null];
    }
    for (NSUInteger index = 0; index < maxTextureCount; ++index) {
      [_textures addObject:NSNull.null];
    }
    for (NSUInteger index = 0; index < maxSamplerCount; ++index) {
      [_samplers addObject:NSNull.null];
    }
    _supportAttributeStrides = supportAttributeStrides;
  }
  return self;
}

- (id<MTL4ArgumentTable>)argumentTable { return _argumentTable; }
- (NSUInteger)maxBufferBindCount { return _buffers.count; }
- (NSUInteger)maxTextureBindCount { return _textures.count; }
- (NSUInteger)maxSamplerStateBindCount { return _samplers.count; }
- (BOOL)supportAttributeStrides { return _supportAttributeStrides; }

- (void)setBoundObject:(id)object
                inArray:(NSMutableArray *)objects
                 atIndex:(NSUInteger)index {
  objects[index] = object == nil ? NSNull.null : object;
}

- (void)setBoundBuffer:(id<MTLBuffer>)buffer atIndex:(NSUInteger)index {
  [self setBoundObject:buffer inArray:_buffers atIndex:index];
}

- (void)setBoundTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index {
  [self setBoundObject:texture inArray:_textures atIndex:index];
}

- (void)setBoundSampler:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index {
  [self setBoundObject:sampler inArray:_samplers atIndex:index];
}

- (void)retainObjects:(NSArray *)objects
    inCommandBuffer:(PrismelMetal4CommandBufferState *)commandBuffer {
  for (id object in objects) {
    if (object != NSNull.null) {
      [commandBuffer retainEncodedObject:object];
    }
  }
}

- (void)retainBoundObjectsInCommandBuffer:
    (PrismelMetal4CommandBufferState *)commandBuffer {
  [self retainObjects:_buffers inCommandBuffer:commandBuffer];
  [self retainObjects:_textures inCommandBuffer:commandBuffer];
  [self retainObjects:_samplers inCommandBuffer:commandBuffer];
}

@end

API_AVAILABLE(macos(26.0))
@interface PrismelMetal4SubmissionState : NSObject
- (instancetype)initWithQueue:(id<MTL4CommandQueue>)queue
                       buffers:(NSArray<PrismelMetal4CommandBufferState *> *)buffers;
- (void)finishWithFeedback:(id<MTL4CommitFeedback>)feedback;
- (BOOL)isCompleted;
- (nullable NSError *)waitUntilCompleted;
- (double)startTime;
- (double)endTime;
@end

@implementation PrismelMetal4SubmissionState {
  id<MTL4CommandQueue> _queue;
  NSArray<PrismelMetal4CommandBufferState *> *_buffers;
  NSCondition *_condition;
  NSError *_error;
  double _startTime;
  double _endTime;
  BOOL _completed;
}

- (instancetype)initWithQueue:(id<MTL4CommandQueue>)queue
                       buffers:(NSArray<PrismelMetal4CommandBufferState *> *)buffers {
  self = [super init];
  if (self != nil) {
    _queue = queue;
    _buffers = [buffers copy];
    _condition = [[NSCondition alloc] init];
    _completed = NO;
  }
  return self;
}

- (void)finishWithFeedback:(id<MTL4CommitFeedback>)feedback {
  [_condition lock];
  if (!_completed) {
    _error = feedback.error;
    _startTime = feedback.GPUStartTime;
    _endTime = feedback.GPUEndTime;
    for (PrismelMetal4CommandBufferState *buffer in _buffers) {
      [buffer releaseEncodedObjects];
    }
    _buffers = nil;
    _completed = YES;
    [_condition broadcast];
  }
  [_condition unlock];
}

- (double)startTime { [_condition lock]; double v = _startTime; [_condition unlock]; return v; }
- (double)endTime { [_condition lock]; double v = _endTime; [_condition unlock]; return v; }
- (BOOL)isCompleted { [_condition lock]; BOOL v = _completed; [_condition unlock]; return v; }

- (NSError *)waitUntilCompleted {
  [_condition lock];
  while (!_completed) {
    [_condition wait];
  }
  NSError *error = _error;
  [_condition unlock];
  return error;
}

@end

@interface PrismelMetalXpcRequest : NSObject
@property(nonatomic, readonly) NSString *operation;
@property(nonatomic, readonly) id resource;
@property(nonatomic, readonly) PrismelMetalXpcResourceKind resourceKind;
@property(nonatomic, readonly) NSData *metadata;
@property(nonatomic, readonly) NSData *data;
@property(nonatomic, readonly, getter=isFinished) BOOL finished;
- (instancetype)initWithOperation:(NSString *)operation
                         resource:(id)resource
                     resourceKind:(PrismelMetalXpcResourceKind)resourceKind
                         metadata:(NSData *)metadata
                             data:(NSData *)data
                            reply:(PrismelMetalXpcReply)reply;
- (BOOL)replyWithResource:(id)resource
                 metadata:(NSData *)metadata
                     data:(NSData *)data;
- (BOOL)rejectWithMessage:(NSString *)message;
@end

@implementation PrismelMetalXpcRequest {
  NSString *_operation;
  id _resource;
  PrismelMetalXpcResourceKind _resourceKind;
  NSData *_metadata;
  NSData *_data;
  PrismelMetalXpcReply _reply;
  std::mutex _replyMutex;
  BOOL _finished;
}

- (instancetype)initWithOperation:(NSString *)operation
                         resource:(id)resource
                     resourceKind:(PrismelMetalXpcResourceKind)resourceKind
                         metadata:(NSData *)metadata
                             data:(NSData *)data
                            reply:(PrismelMetalXpcReply)reply {
  self = [super init];
  if (self != nil) {
    _operation = [operation copy];
    _resource = resource;
    _resourceKind = resourceKind;
    _metadata = [metadata copy];
    _data = [data copy];
    _reply = [reply copy];
    _finished = NO;
  }
  return self;
}

- (NSString *)operation { return _operation; }
- (id)resource { return _resource; }
- (PrismelMetalXpcResourceKind)resourceKind { return _resourceKind; }
- (NSData *)metadata { return _metadata; }
- (NSData *)data { return _data; }

- (BOOL)isFinished {
  std::lock_guard<std::mutex> lock(_replyMutex);
  return _finished;
}

- (PrismelMetalXpcReply)takeReply {
  std::lock_guard<std::mutex> lock(_replyMutex);
  if (_finished || _reply == nil) {
    return nil;
  }
  _finished = YES;
  PrismelMetalXpcReply reply = _reply;
  _reply = nil;
  return reply;
}

- (BOOL)replyWithResource:(id)resource
                 metadata:(NSData *)metadata
                     data:(NSData *)data {
  if (!PrismelMetalXpcResourceMatchesKind(resource, _resourceKind)) {
    return NO;
  }
  PrismelMetalXpcReply reply = [self takeReply];
  if (reply == nil) {
    return NO;
  }
  reply(resource, metadata, data, nil);
  return YES;
}

- (BOOL)rejectWithMessage:(NSString *)message {
  PrismelMetalXpcReply reply = [self takeReply];
  if (reply == nil) {
    return NO;
  }
  reply(nil, [NSData data], [NSData data], message);
  return YES;
}

- (void)dealloc {
  (void)[self rejectWithMessage:
                  [NSString stringWithFormat:@"%@ XPC request was abandoned",
                                             PrismelMetalXpcResourceName(
                                                 _resourceKind)]];
}

@end

static NSXPCInterface *PrismelMetalResourceInterface(void) {
  NSXPCInterface *interface =
      [NSXPCInterface interfaceWithProtocol:@protocol(PrismelMetalResourceXpc)];
  NSSet *resourceClasses = [NSSet setWithObjects:
                                      [MTLSharedTextureHandle class],
                                      [IOSurface class], nil];
  SEL selector =
      @selector(exchangeOperation:resource:metadata:data:withReply:);
  [interface setClasses:resourceClasses
             forSelector:selector
           argumentIndex:1
                 ofReply:NO];
  [interface setClasses:resourceClasses
             forSelector:selector
           argumentIndex:0
                 ofReply:YES];
  return interface;
}

using PrismelMetalXpcHandler = void (^)(PrismelMetalXpcRequest *);

@interface PrismelMetalXpcService
    : NSObject <NSXPCListenerDelegate, PrismelMetalResourceXpc>
@property(nonatomic, readonly) PrismelMetalXpcResourceKind resourceKind;
- (instancetype)initWithResourceKind:(PrismelMetalXpcResourceKind)resourceKind
                            capacity:(NSUInteger)capacity
                  maxPayloadBytes:(NSUInteger)maxPayloadBytes;
- (void)setRequestHandler:(PrismelMetalXpcHandler)handler;
- (void)run;
@end

@implementation PrismelMetalXpcService {
  PrismelMetalXpcResourceKind _resourceKind;
  NSUInteger _capacity;
  NSUInteger _activeRequests;
  NSUInteger _maxPayloadBytes;
  NSXPCListener *_listener;
  NSHashTable<NSXPCConnection *> *_connections;
  std::mutex _mutex;
  BOOL _closed;
  PrismelMetalXpcHandler _handler;
}

- (instancetype)initWithResourceKind:(PrismelMetalXpcResourceKind)resourceKind
                            capacity:(NSUInteger)capacity
                  maxPayloadBytes:(NSUInteger)maxPayloadBytes {
  self = [super init];
  if (self != nil) {
    _resourceKind = resourceKind;
    _capacity = capacity;
    _activeRequests = 0;
    _maxPayloadBytes = maxPayloadBytes;
    _connections = [NSHashTable weakObjectsHashTable];
    _closed = NO;
    _listener = [NSXPCListener serviceListener];
    _listener.delegate = self;
  }
  return self;
}

- (void)setRequestHandler:(PrismelMetalXpcHandler)handler {
  std::lock_guard<std::mutex> lock(_mutex);
  _handler = [handler copy];
}

- (PrismelMetalXpcResourceKind)resourceKind { return _resourceKind; }

- (void)run { [_listener resume]; }

- (BOOL)listener:(NSXPCListener *)listener
    shouldAcceptNewConnection:(NSXPCConnection *)connection {
  (void)listener;
  {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_closed || connection.effectiveUserIdentifier != geteuid()) {
      return NO;
    }
    [_connections addObject:connection];
  }
  connection.exportedInterface = PrismelMetalResourceInterface();
  connection.exportedObject = self;
  [connection activate];
  return YES;
}

- (void)exchangeOperation:(NSString *)operation
                 resource:(id)resource
                 metadata:(NSData *)metadata
                     data:(NSData *)data
                withReply:(PrismelMetalXpcReply)reply {
  NSString *validationError = nil;
  NSString *resourceName = PrismelMetalXpcResourceName(_resourceKind);
  const NSUInteger operationBytes =
      [operation lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  if (operation == nil || operation.length == 0 || operationBytes == 0 ||
      operationBytes > 256) {
    validationError = [NSString
        stringWithFormat:@"%@ XPC operation must contain 1-256 UTF-8 bytes",
                         resourceName];
  } else {
    for (NSUInteger index = 0; index < operation.length; ++index) {
      if ([operation characterAtIndex:index] == 0) {
        validationError = [NSString
            stringWithFormat:@"%@ XPC operation contains a NUL character",
                             resourceName];
        break;
      }
    }
  }
  if (validationError == nil &&
      !PrismelMetalXpcResourceMatchesKind(resource, _resourceKind)) {
    validationError = [NSString
        stringWithFormat:@"%@ XPC request has the wrong resource type",
                         resourceName];
  }
  if (validationError == nil &&
      (metadata == nil || metadata.length == 0 || metadata.length > 4096)) {
    validationError = [NSString
        stringWithFormat:@"%@ XPC metadata is malformed", resourceName];
  }
  if (validationError == nil &&
      (data == nil || data.length > _maxPayloadBytes)) {
    validationError = [NSString
        stringWithFormat:@"%@ XPC payload exceeds its configured bound",
                         resourceName];
  }
  if (validationError != nil) {
    reply(nil, [NSData data], [NSData data], validationError);
    return;
  }
  PrismelMetalXpcRequest *request =
      [[PrismelMetalXpcRequest alloc] initWithOperation:operation
                                              resource:resource
                                          resourceKind:_resourceKind
                                              metadata:metadata
                                                  data:data
                                                 reply:reply];
  PrismelMetalXpcHandler handler = nil;
  {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_closed) {
      validationError = [NSString stringWithFormat:@"%@ XPC service is closed",
                                                    resourceName];
    } else if (_activeRequests >= _capacity) {
      validationError = [NSString
          stringWithFormat:@"%@ XPC request capacity is exhausted",
                           resourceName];
    } else {
      handler = _handler;
      if (handler == nil) {
        validationError = [NSString
            stringWithFormat:@"%@ XPC service has no request handler",
                             resourceName];
      } else {
        ++_activeRequests;
      }
    }
  }
  if (validationError != nil) {
    (void)[request rejectWithMessage:validationError];
    return;
  }
  if ([NSThread isMainThread]) {
    handler(request);
  } else {
    dispatch_sync(dispatch_get_main_queue(), ^{
      handler(request);
    });
  }
  if (!request.finished) {
    (void)[request rejectWithMessage:[NSString
        stringWithFormat:@"%@ XPC handler returned without a reply",
                         resourceName]];
  }
  {
    std::lock_guard<std::mutex> lock(_mutex);
    --_activeRequests;
  }
}

- (void)shutdown {
  NSArray<NSXPCConnection *> *connections = nil;
  {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_closed) {
      return;
    }
    _closed = YES;
    connections = _connections.allObjects;
  }
  [_listener invalidate];
  for (NSXPCConnection *connection in connections) {
    [connection invalidate];
  }
}

- (void)dealloc { [self shutdown]; }

@end

@interface PrismelMetalXpcConnection : NSObject
@property(nonatomic, readonly) NSXPCConnection *connection;
@property(nonatomic, readonly) NSUInteger maxPayloadBytes;
@property(nonatomic, readonly) PrismelMetalXpcResourceKind resourceKind;
- (instancetype)initWithResourceKind:(PrismelMetalXpcResourceKind)resourceKind
                         serviceName:(NSString *)serviceName
                     maxPayloadBytes:(NSUInteger)maxPayloadBytes;
- (void)shutdown;
@end

@implementation PrismelMetalXpcConnection {
  PrismelMetalXpcResourceKind _resourceKind;
  NSXPCConnection *_connection;
  NSUInteger _maxPayloadBytes;
}

- (instancetype)initWithResourceKind:(PrismelMetalXpcResourceKind)resourceKind
                         serviceName:(NSString *)serviceName
                     maxPayloadBytes:(NSUInteger)maxPayloadBytes {
  self = [super init];
  if (self != nil) {
    _resourceKind = resourceKind;
    _maxPayloadBytes = maxPayloadBytes;
    _connection =
        [[NSXPCConnection alloc] initWithServiceName:serviceName];
    _connection.remoteObjectInterface = PrismelMetalResourceInterface();
    [_connection activate];
  }
  return self;
}

- (NSXPCConnection *)connection { return _connection; }
- (NSUInteger)maxPayloadBytes { return _maxPayloadBytes; }
- (PrismelMetalXpcResourceKind)resourceKind { return _resourceKind; }
- (void)shutdown { [_connection invalidate]; }
- (void)dealloc { [self shutdown]; }

@end

@interface PrismelMetalXpcCallState : NSObject
@property(nonatomic, readonly) id resource;
@property(nonatomic, readonly) NSData *metadata;
@property(nonatomic, readonly) NSData *data;
@property(nonatomic, readonly) NSString *errorMessage;
- (void)completeWithResource:(id)resource
                  metadata:(NSData *)metadata
                      data:(NSData *)data
                     error:(NSString *)errorMessage;
- (BOOL)waitForMilliseconds:(NSUInteger)milliseconds;
@end

@implementation PrismelMetalXpcCallState {
  NSCondition *_condition;
  BOOL _completed;
  id _resource;
  NSData *_metadata;
  NSData *_data;
  NSString *_errorMessage;
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _condition = [[NSCondition alloc] init];
    _completed = NO;
  }
  return self;
}

- (void)completeWithResource:(id)resource
                  metadata:(NSData *)metadata
                      data:(NSData *)data
                     error:(NSString *)errorMessage {
  [_condition lock];
  if (!_completed) {
    _completed = YES;
    _resource = resource;
    _metadata = [metadata copy];
    _data = [data copy];
    _errorMessage = [errorMessage copy];
    [_condition broadcast];
  }
  [_condition unlock];
}

- (BOOL)waitForMilliseconds:(NSUInteger)milliseconds {
  NSDate *deadline =
      [NSDate dateWithTimeIntervalSinceNow:(double)milliseconds / 1000.0];
  [_condition lock];
  while (!_completed && [_condition waitUntilDate:deadline]) {
  }
  BOOL completed = _completed;
  [_condition unlock];
  return completed;
}

- (id)resource { return _resource; }
- (NSData *)metadata { return _metadata; }
- (NSData *)data { return _data; }
- (NSString *)errorMessage { return _errorMessage; }

@end

API_AVAILABLE(macos(15.0))
@interface PrismelMetalLogStateState : NSObject
@property(nonatomic, strong) id<MTLLogState> state;
@property(nonatomic) uint64_t registryID;
@end
@implementation PrismelMetalLogStateState
@end

API_AVAILABLE(macos(15.0))
@interface PrismelMetalCommandQueueDescriptorState : NSObject
@property(nonatomic, strong) MTLCommandQueueDescriptor *descriptor;
@property(nonatomic, strong, nullable) PrismelMetalLogStateState *logState;
@end
@implementation PrismelMetalCommandQueueDescriptorState
@end

namespace {

enum class Handle_kind : std::uint32_t {
  Device = 1,
  Heap,
  Buffer,
  Texture,
  Sampler,
  Library,
  Function,
  Function_descriptor,
  Dynamic_library,
  Binary_archive,
  Compute_pipeline,
  Command_queue,
  Command_queue_descriptor,
  Log_state,
  Log_state_descriptor,
  Command_buffer,
  Compute_encoder,
  Render_encoder,
  Resource_state_encoder,
  Blit_encoder,
  Residency_set,
  External_memory,
  Io_surface,
  Shared_texture_handle,
  Xpc_connection,
  Xpc_service,
  Xpc_request,
  Placement_mapping_queue,
  Pipeline_dataset,
  Pipeline_archive,
  Compiler,
  Binary_function,
  Render_pipeline,
  Command_allocator4,
  Command_queue4,
  Command_buffer4,
  Command_buffer_options4,
  Render_encoder4,
  Submission4,
  Argument_table4,
  Compute_encoder4,
  Counter_heap4,
  Acceleration_descriptor4,
  Acceleration4_bbox_descriptor,
  Acceleration4_curve_descriptor,
  Acceleration4_motion_bbox_descriptor,
  Acceleration4_motion_curve_descriptor,
  Acceleration4_motion_triangle_descriptor,
  Acceleration4_triangle_descriptor,
  Acceleration4_indirect_instance_descriptor,
  Acceleration4_instance_descriptor,
  Acceleration4_primitive_descriptor,
  Binary_functions_descriptor4,
  Function_constant_values,
  Render_pass_descriptor4,
  Depth_stencil,
  Indirect_command_buffer,
  Indirect_render_command,
  Indirect_compute_command,
  Acceleration_structure,
  Acceleration_bbox_descriptor,
  Acceleration_curve_descriptor,
  Acceleration_motion_bbox_descriptor,
  Acceleration_motion_curve_descriptor,
  Acceleration_motion_triangle_descriptor,
  Acceleration_triangle_owned_descriptor,
  Acceleration_indirect_instance_descriptor,
  Acceleration_instance_descriptor,
  Acceleration_motion_keyframe,
  Acceleration_primitive_descriptor,
  Acceleration_encoder,
  Acceleration_pass_descriptor,
  Acceleration_sample_attachment,
  Acceleration_sample_attachment_array,
  Compute_pass_descriptor,
  Compute_sample_attachment,
  Compute_sample_attachment_array,
  Function_handle,
  Visible_function_table,
  Intersection_function_table,
  Fence,
  Metal_layer,
  Metal_drawable,
  Render_pass_descriptor,
  Buffer_layout_descriptor,
  Buffer_layout_descriptor_array,
  Resource_state_pass_descriptor,
  Resource_state_sample_attachment_descriptor,
  Resource_state_sample_attachment_array,
  Resource_view_pool_descriptor,
  Texture_view_pool,
  Tensor_descriptor,
  Tensor,
  Tensor_extents,
  Acceleration_descriptor,
  Counter_sample_buffer,
  Texture_view_descriptor,
  Texture_descriptor,
  Render_sample_attachment_descriptor,
  Render_sample_attachment_array,
  Logical_to_physical_color_attachment_map,
  Shader_attribute,
  Shader_vertex_attribute,
  Shader_attribute_descriptor,
  Shader_attribute_descriptor_array,
  Shader_stage_descriptor,
  Shader_argument_encoder,
  Compile_options,
  Function_reflection,
  Render_pipeline_reflection,
  Render_pipeline_functions_descriptor,
  Vertex_descriptor,
  Pipeline_descriptor4,
  Mesh_pipeline_descriptor,
  Tile_pipeline_descriptor,
  Fx_spatial_scaler,
  Linked_functions,
  Counter_set,
  Counter,
  Counter_descriptor,
  Blit_pass_descriptor,
  Blit_sample_attachment,
  Blit_sample_attachment_array,
  Shared_event,
  Pipeline_buffer_descriptor,
  Color_attachment_descriptor,
  Color_attachment_descriptor4,
  Color_attachment_array4,
  Render_pipeline_descriptor,
  Compute_pipeline_descriptor,
};

struct Handle {
  void *object;
  std::uint64_t generation;
  Handle_kind kind;
};

// Unbounded on purpose: a finalizer must never leak a Metal object because
// the main domain has not drained yet. Drained every frame on the main domain.
std::deque<void *> release_queue;
std::mutex release_mutex;
std::mutex handle_mutex;
std::atomic<std::uint64_t> next_generation{1};
;
std::atomic<std::uint64_t> live_handle_count{0};
std::atomic<std::uint64_t> total_created_count{0};
std::atomic<std::uint64_t> total_released_count{0};
std::atomic<std::uint64_t> external_deallocation_count{0};
std::atomic<std::uint64_t> external_deallocation_mismatch_count{0};
;

Handle *handle_of_value(value raw) {
  return static_cast<Handle *>(Data_custom_val(raw));
}

void *take_pointer(Handle *handle) {
  std::lock_guard<std::mutex> lock(handle_mutex);
  void *pointer = handle->object;
  handle->object = nullptr;
  return pointer;
}

void enqueue_release(void *pointer) {
  if (pointer == nullptr) {
    return;
  }
  std::lock_guard<std::mutex> lock(release_mutex);
  release_queue.push_back(pointer);
}

void finalize_handle(value raw) {
  enqueue_release(take_pointer(handle_of_value(raw)));
}

struct custom_operations handle_operations = {
    const_cast<char *>("prismel.metal.handle.v1"),
    finalize_handle,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default,
};

value allocate_handle(id object, Handle_kind kind) {
  CAMLparam0();
  CAMLlocal1(raw);
  if (object == nil) {
    caml_failwith("attempted to allocate a nil Metal handle");
  }
  raw = caml_alloc_custom_mem(&handle_operations, sizeof(Handle), sizeof(Handle));
  auto *handle = handle_of_value(raw);
  handle->object = (__bridge_retained void *)object;
  handle->generation = next_generation.fetch_add(1, std::memory_order_relaxed);
  handle->kind = kind;
  live_handle_count.fetch_add(1, std::memory_order_relaxed);
  total_created_count.fetch_add(1, std::memory_order_relaxed);
  CAMLreturn(raw);
}

id object_of_handle(value raw, Handle_kind expected) {
  auto *handle = handle_of_value(raw);
  std::lock_guard<std::mutex> lock(handle_mutex);
  if (handle->kind != expected) {
    caml_failwith("Metal custom handle kind mismatch");
  }
  if (handle->object == nullptr) {
    caml_failwith("Metal custom handle is destroyed");
  }
  return (__bridge id)handle->object;
}

id<MTLResource> resource_of_handle(value raw,
                                   Handle_kind *actual_kind = nullptr) {
  auto *handle = handle_of_value(raw);
  std::lock_guard<std::mutex> lock(handle_mutex);
  if (handle->kind != Handle_kind::Buffer &&
      handle->kind != Handle_kind::Texture &&
      handle->kind != Handle_kind::Visible_function_table &&
      handle->kind != Handle_kind::Intersection_function_table) {
    caml_failwith("Metal custom handle is not a resource");
  }
  if (handle->object == nullptr) {
    caml_failwith("Metal custom handle is destroyed");
  }
  if (actual_kind != nullptr) {
    *actual_kind = handle->kind;
  }
  return (__bridge id<MTLResource>)handle->object;
}

API_AVAILABLE(macos(15.0))
id<MTLAllocation> allocation_of_handle(value raw) {
  auto *handle = handle_of_value(raw);
  std::lock_guard<std::mutex> lock(handle_mutex);
  if (handle->kind != Handle_kind::Heap &&
      handle->kind != Handle_kind::Buffer &&
      handle->kind != Handle_kind::Texture) {
    caml_failwith("Metal custom handle is not an allocation");
  }
  if (handle->object == nullptr) {
    caml_failwith("Metal custom handle is destroyed");
  }
  return (__bridge id<MTLAllocation>)handle->object;
}

API_AVAILABLE(macos(26.0))
PrismelMetal4ArgumentTableState *argument_table4_state_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Argument_table4);
}

API_AVAILABLE(macos(15.0))
std::vector<id<MTLAllocation>> allocations_of_array(value raw_array) {
  const mlsize_t count = Wosize_val(raw_array);
  std::vector<id<MTLAllocation>> allocations;
  allocations.reserve(count);
  for (mlsize_t index = 0; index < count; ++index) {
    allocations.push_back(allocation_of_handle(Field(raw_array, index)));
  }
  return allocations;
}

API_AVAILABLE(macos(15.0))
std::vector<id<MTLResidencySet>> residency_sets_of_array(value raw_array) {
  const mlsize_t count = Wosize_val(raw_array);
  std::vector<id<MTLResidencySet>> residency_sets;
  residency_sets.reserve(count);
  for (mlsize_t index = 0; index < count; ++index) {
    residency_sets.push_back(object_of_handle(Field(raw_array, index),
                                               Handle_kind::Residency_set));
  }
  return residency_sets;
}

std::vector<id<MTLFunction>> functions_of_array(value raw_array) {
  const mlsize_t count = Wosize_val(raw_array);
  std::vector<id<MTLFunction>> functions;
  functions.reserve(count);
  for (mlsize_t index = 0; index < count; ++index) {
    functions.push_back(
        object_of_handle(Field(raw_array, index), Handle_kind::Function));
  }
  return functions;
}

std::vector<id<MTLDynamicLibrary>> dynamic_libraries_of_array(
    value raw_array) {
  const mlsize_t count = Wosize_val(raw_array);
  std::vector<id<MTLDynamicLibrary>> libraries;
  libraries.reserve(count);
  for (mlsize_t index = 0; index < count; ++index) {
    libraries.push_back(object_of_handle(Field(raw_array, index),
                                         Handle_kind::Dynamic_library));
  }
  return libraries;
}

std::vector<id<MTLBinaryArchive>> binary_archives_of_array(value raw_array) {
  const mlsize_t count = Wosize_val(raw_array);
  std::vector<id<MTLBinaryArchive>> archives;
  archives.reserve(count);
  for (mlsize_t index = 0; index < count; ++index) {
    archives.push_back(object_of_handle(Field(raw_array, index),
                                        Handle_kind::Binary_archive));
  }
  return archives;
}

API_AVAILABLE(macos(26.0))
PrismelMetalPipelineArchiveState *pipeline_archive_state(value raw) {
  return object_of_handle(raw, Handle_kind::Pipeline_archive);
}

API_AVAILABLE(macos(26.0))
std::vector<id<MTL4Archive>> pipeline_archives_of_array(value raw_array) {
  const mlsize_t count = Wosize_val(raw_array);
  std::vector<id<MTL4Archive>> archives;
  archives.reserve(count);
  for (mlsize_t index = 0; index < count; ++index) {
    archives.push_back(pipeline_archive_state(Field(raw_array, index)).archive);
  }
  return archives;
}

API_AVAILABLE(macos(26.0))
std::vector<id<MTL4BinaryFunction>> binary_functions_of_array(
    value raw_array) {
  const mlsize_t count = Wosize_val(raw_array);
  std::vector<id<MTL4BinaryFunction>> functions;
  functions.reserve(count);
  for (mlsize_t index = 0; index < count; ++index) {
    functions.push_back(object_of_handle(Field(raw_array, index),
                                         Handle_kind::Binary_function));
  }
  return functions;
}

constexpr NSUInteger reflection_max_depth = 32;
constexpr NSUInteger reflection_max_members = 65'536;

value copy_reflected_type(MTLType *type, NSUInteger depth,
                          NSUInteger *remaining_members);

value copy_optional_reflected_type(MTLType *type, NSUInteger depth,
                                   NSUInteger *remaining_members) {
  CAMLparam0();
  CAMLlocal2(option, copied);
  if (type == nil) CAMLreturn(Val_none);
  copied = copy_reflected_type(type, depth, remaining_members);
  option = caml_alloc(1, 0);
  Store_field(option, 0, copied);
  CAMLreturn(option);
}

value copy_reflection_member(MTLStructMember *member, NSUInteger depth,
                             NSUInteger *remaining_members) {
  CAMLparam0();
  CAMLlocal4(result, name, offset, nested);
  result = caml_alloc_tuple(5);
  name = caml_copy_string(member.name.UTF8String ?: "");
  Store_field(result, 0, name);
  offset = caml_copy_int64(static_cast<std::int64_t>(member.offset));
  Store_field(result, 1, offset);
  offset = caml_copy_int64(static_cast<std::int64_t>(member.argumentIndex));
  Store_field(result, 2, offset);
  Store_field(result, 3, Val_long(static_cast<intnat>(member.dataType)));
  MTLType *child = member.arrayType;
  if (child == nil) child = member.pointerType;
  if (child == nil) child = member.structType;
  if (@available(macOS 26.0, *)) {
    if (child == nil) child = member.tensorReferenceType;
  }
  if (child == nil) child = member.textureReferenceType;
  nested = copy_optional_reflected_type(child, depth, remaining_members);
  Store_field(result, 4, nested);
  CAMLreturn(result);
}

value copy_reflected_type(MTLType *type, NSUInteger depth,
                          NSUInteger *remaining_members) {
  CAMLparam0();
  CAMLlocal5(result, item, list, option, dimensions);
  if (depth > reflection_max_depth)
    caml_failwith("Metal reflection exceeded max_depth");
  MTLDataType data_type = type.dataType;
  if ([type isKindOfClass:[MTLArrayType class]]) {
    MTLArrayType *array = (MTLArrayType *)type;
    result = caml_alloc(5, 1);
    Store_field(result, 0, Val_long(static_cast<intnat>(data_type)));
    item = caml_copy_int64(static_cast<std::int64_t>(array.arrayLength));
    Store_field(result, 1, item);
    item = caml_copy_int64(static_cast<std::int64_t>(array.stride));
    Store_field(result, 2, item);
    item = caml_copy_int64(static_cast<std::int64_t>(array.argumentIndexStride));
    Store_field(result, 3, item);
    MTLType *element = array.elementArrayType;
    if (element == nil) element = array.elementPointerType;
    if (element == nil) element = array.elementStructType;
    if (@available(macOS 26.0, *)) {
      if (element == nil) element = array.elementTensorReferenceType;
    }
    if (element == nil) element = array.elementTextureReferenceType;
    (void)array.elementType;
    option = copy_optional_reflected_type(element, depth + 1, remaining_members);
    Store_field(result, 4, option);
    CAMLreturn(result);
  }
  if ([type isKindOfClass:[MTLPointerType class]]) {
    MTLPointerType *pointer = (MTLPointerType *)type;
    result = caml_alloc(6, 2);
    Store_field(result, 0, Val_long(static_cast<intnat>(data_type)));
    Store_field(result, 1, Val_long(static_cast<intnat>(pointer.access)));
    item = caml_copy_int64(static_cast<std::int64_t>(pointer.alignment));
    Store_field(result, 2, item);
    item = caml_copy_int64(static_cast<std::int64_t>(pointer.dataSize));
    Store_field(result, 3, item);
    Store_field(result, 4, Val_bool(pointer.elementIsArgumentBuffer));
    MTLType *element = pointer.elementArrayType;
    if (element == nil) element = pointer.elementStructType;
    (void)pointer.elementType;
    option = copy_optional_reflected_type(element, depth + 1, remaining_members);
    Store_field(result, 5, option);
    CAMLreturn(result);
  }
  if ([type isKindOfClass:[MTLStructType class]]) {
    MTLStructType *structure = (MTLStructType *)type;
    NSArray<MTLStructMember *> *members = structure.members;
    if (members.count > *remaining_members) {
      caml_failwith("Metal reflection exceeded max_members");
    }
    *remaining_members -= members.count;
    list = Val_emptylist;
    for (NSUInteger index = members.count; index > 0; --index) {
      MTLStructMember *member = members[index - 1];
      MTLStructMember *lookup = [structure memberByName:member.name];
      if (lookup != member) {
        caml_failwith("Metal reflection memberByName mismatch");
      }
      item = copy_reflection_member(member, depth + 1, remaining_members);
      option = caml_alloc(2, 0);
      Store_field(option, 0, item);
      Store_field(option, 1, list);
      list = option;
    }
    result = caml_alloc(1, 3);
    Store_field(result, 0, list);
    CAMLreturn(result);
  }
  if ([type isKindOfClass:[MTLTextureReferenceType class]]) {
    MTLTextureReferenceType *texture = (MTLTextureReferenceType *)type;
    result = caml_alloc(4, 4);
    Store_field(result, 0, Val_long(static_cast<intnat>(data_type)));
    Store_field(result, 1, Val_long(static_cast<intnat>(texture.access)));
    Store_field(result, 2, Val_long(static_cast<intnat>(texture.textureType)));
    Store_field(result, 3, Val_bool(texture.isDepthTexture));
    (void)texture.textureDataType;
    CAMLreturn(result);
  }
  if (@available(macOS 26.0, *)) {
    if ([type isKindOfClass:[MTLTensorReferenceType class]]) {
      MTLTensorReferenceType *tensor = (MTLTensorReferenceType *)type;
      result = caml_alloc(5, 5);
      Store_field(result, 0, Val_long(static_cast<intnat>(data_type)));
      Store_field(result, 1, Val_long(static_cast<intnat>(tensor.access)));
      Store_field(result, 2,
                  Val_long(static_cast<intnat>(tensor.tensorDataType)));
      Store_field(result, 3, Val_long(static_cast<intnat>(tensor.indexType)));
      MTLTensorExtents *extents = tensor.dimensions;
      if (extents == nil) {
        dimensions = Val_none;
      } else {
        list = Val_emptylist;
        for (NSUInteger index = extents.rank; index > 0; --index) {
          NSInteger extent = [extents extentAtDimensionIndex:index - 1];
          item = caml_copy_int64(static_cast<std::int64_t>(extent));
          option = caml_alloc(2, 0);
          Store_field(option, 0, item);
          Store_field(option, 1, list);
          list = option;
        }
        dimensions = caml_alloc(1, 0);
        Store_field(dimensions, 0, list);
      }
      Store_field(result, 4, dimensions);
      CAMLreturn(result);
    }
  }
  result = caml_alloc(1, 0);
  item = caml_copy_int64(static_cast<std::int64_t>(data_type));
  Store_field(result, 0, item);
  CAMLreturn(result);
}

value copy_bindings(NSArray<id<MTLBinding>> *bindings) {
  CAMLparam0();
  CAMLlocal5(array, tuple, name, item, reflected_type);
  if (bindings.count > static_cast<NSUInteger>(Max_wosize)) {
    caml_failwith("Metal pipeline reflection exceeds OCaml limits");
  }
  array = caml_alloc(static_cast<mlsize_t>(bindings.count), 0);
  for (NSUInteger index = 0; index < bindings.count; ++index) {
    id<MTLBinding> binding = bindings[index];
    NSUInteger buffer_alignment = 0;
    NSUInteger buffer_data_size = 0;
    MTLDataType buffer_data_type = MTLDataTypeNone;
    MTLTextureType texture_type = MTLTextureType1D;
    MTLDataType texture_data_type = MTLDataTypeNone;
    BOOL depth = NO;
    NSUInteger array_length = 0;
    NSUInteger threadgroup_alignment = 0;
    NSUInteger threadgroup_data_size = 0;
    NSUInteger object_alignment = 0;
    NSUInteger object_data_size = 0;
    switch (binding.type) {
    case MTLBindingTypeBuffer: {
      id<MTLBufferBinding> buffer = (id<MTLBufferBinding>)binding;
      buffer_alignment = buffer.bufferAlignment;
      buffer_data_size = buffer.bufferDataSize;
      buffer_data_type = buffer.bufferDataType;
      break;
    }
    case MTLBindingTypeThreadgroupMemory: {
      id<MTLThreadgroupBinding> threadgroup =
          (id<MTLThreadgroupBinding>)binding;
      threadgroup_alignment = threadgroup.threadgroupMemoryAlignment;
      threadgroup_data_size = threadgroup.threadgroupMemoryDataSize;
      break;
    }
    case MTLBindingTypeTexture: {
      id<MTLTextureBinding> texture = (id<MTLTextureBinding>)binding;
      texture_type = texture.textureType;
      texture_data_type = texture.textureDataType;
      depth = texture.depthTexture;
      array_length = texture.arrayLength;
      break;
    }
    case MTLBindingTypeObjectPayload: {
      id<MTLObjectPayloadBinding> object =
          (id<MTLObjectPayloadBinding>)binding;
      object_alignment = object.objectPayloadAlignment;
      object_data_size = object.objectPayloadDataSize;
      break;
    }
    default:
      break;
    }
    const NSUInteger unsigned_values[] = {
        binding.index,
        buffer_alignment,
        buffer_data_size,
        array_length,
        threadgroup_alignment,
        threadgroup_data_size,
        object_alignment,
        object_data_size,
    };
    for (NSUInteger value : unsigned_values) {
      if (value > static_cast<NSUInteger>(
                      std::numeric_limits<std::int64_t>::max())) {
        caml_failwith("Metal reflected binding value exceeds int64");
      }
    }
    tuple = caml_alloc_tuple(18);
    name = caml_copy_string(binding.name.UTF8String ?: "");
    Store_field(tuple, 0, name);
    Store_field(tuple, 1, Val_long(static_cast<intnat>(binding.type)));
    Store_field(tuple, 2, Val_long(static_cast<intnat>(binding.access)));
    item = caml_copy_int64(static_cast<std::int64_t>(binding.index));
    Store_field(tuple, 3, item);
    Store_field(tuple, 4, Val_bool(binding.used));
    Store_field(tuple, 5, Val_bool(binding.argument));
    item = caml_copy_int64(static_cast<std::int64_t>(buffer_alignment));
    Store_field(tuple, 6, item);
    item = caml_copy_int64(static_cast<std::int64_t>(buffer_data_size));
    Store_field(tuple, 7, item);
    Store_field(tuple, 8,
                Val_long(static_cast<intnat>(buffer_data_type)));
    Store_field(tuple, 9, Val_long(static_cast<intnat>(texture_type)));
    Store_field(tuple, 10,
                Val_long(static_cast<intnat>(texture_data_type)));
    Store_field(tuple, 11, Val_bool(depth));
    item = caml_copy_int64(static_cast<std::int64_t>(array_length));
    Store_field(tuple, 12, item);
    item = caml_copy_int64(static_cast<std::int64_t>(threadgroup_alignment));
    Store_field(tuple, 13, item);
    item = caml_copy_int64(static_cast<std::int64_t>(threadgroup_data_size));
    Store_field(tuple, 14, item);
    item = caml_copy_int64(static_cast<std::int64_t>(object_alignment));
    Store_field(tuple, 15, item);
    item = caml_copy_int64(static_cast<std::int64_t>(object_data_size));
    Store_field(tuple, 16, item);
    MTLType *root_type = nil;
    if (binding.type == MTLBindingTypeBuffer) {
      id<MTLBufferBinding> buffer = (id<MTLBufferBinding>)binding;
      root_type = buffer.bufferPointerType;
      if (root_type == nil) root_type = buffer.bufferStructType;
    }
    NSUInteger remaining_members = reflection_max_members;
    reflected_type = copy_optional_reflected_type(
        root_type, 0, &remaining_members);
    Store_field(tuple, 17, reflected_type);
    Store_field(array, static_cast<mlsize_t>(index), tuple);
  }
  CAMLreturn(array);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static void prismel_validate_legacy_render_arguments(
    NSArray<MTLArgument *> *arguments) {
  for (MTLArgument *argument in arguments ?: @[]) {
    if (argument.name == nil || argument.name.UTF8String == nullptr)
      @throw [NSException exceptionWithName:@"PrismelMetalReflection"
                                     reason:@"render reflection returned an invalid argument name"
                                   userInfo:nil];
  }
}

value copy_render_reflection(MTLRenderPipelineReflection *reflection) {
  CAMLparam0();
  CAMLlocal5(vertex, fragment, tile, object, mesh);
  CAMLlocal1(result);
  vertex = copy_bindings(reflection.vertexBindings);
  fragment = copy_bindings(reflection.fragmentBindings);
  tile = copy_bindings(reflection.tileBindings);
  object = copy_bindings(reflection.objectBindings);
  mesh = copy_bindings(reflection.meshBindings);
  /* Preserve safe modern MTLBinding snapshots while also executing and
     validating the three deprecated MTLArgument selector families represented
     by RenderPipeline93. */
  prismel_validate_legacy_render_arguments(reflection.vertexArguments);
  prismel_validate_legacy_render_arguments(reflection.fragmentArguments);
  prismel_validate_legacy_render_arguments(reflection.tileArguments);
  result = caml_alloc_tuple(5);
  Store_field(result, 0, vertex);
  Store_field(result, 1, fragment);
  Store_field(result, 2, tile);
  Store_field(result, 3, object);
  Store_field(result, 4, mesh);
  CAMLreturn(result);
}
#pragma clang diagnostic pop

void release_pointer(void *pointer) {
  if (pointer == nullptr) {
    return;
  }
  @autoreleasepool {
    id object = (__bridge_transfer id)pointer;
    (void)object;
  }
  live_handle_count.fetch_sub(1, std::memory_order_relaxed);
  total_released_count.fetch_add(1, std::memory_order_relaxed);
}

value result_ok(value payload) {
  CAMLparam1(payload);
  CAMLlocal1(result);
  result = caml_alloc(1, 0);
  Store_field(result, 0, payload);
  CAMLreturn(result);
}

value result_error_text(const char *message) {
  CAMLparam0();
  CAMLlocal2(result, text);
  text = caml_copy_string(message == nullptr ? "unknown Metal error" : message);
  result = caml_alloc(1, 1);
  Store_field(result, 0, text);
  CAMLreturn(result);
}

value result_error(NSString *message) {
  const char *utf8 = message == nil ? nullptr : message.UTF8String;
  return result_error_text(utf8);
}

NSString *error_description(NSError *error, NSString *fallback) {
  if (error == nil) {
    return fallback;
  }
  return [NSString
      stringWithFormat:@"%@ (domain=%@ code=%ld userInfo=%@)",
                       error.localizedDescription ?: error.description,
                       error.domain, static_cast<long>(error.code),
                       error.userInfo ?: @{}];
}

NSString *labeled_error_description(NSString *label, NSError *error,
                                    NSString *fallback) {
  NSString *description = error_description(error, fallback);
  if (label == nil) {
    return description;
  }
  return [NSString stringWithFormat:@"%@: %@", label, description];
}

NSString *string_from_ocaml(value text) {
  return [[NSString alloc]
      initWithBytes:String_val(text)
             length:caml_string_length(text)
           encoding:NSUTF8StringEncoding];
}

bool valid_absolute_path(NSString *path) {
  if (path == nil || path.length == 0 || !path.isAbsolutePath) {
    return false;
  }
  for (NSUInteger index = 0; index < path.length; ++index) {
    if ([path characterAtIndex:index] == 0) {
      return false;
    }
  }
  return true;
}

bool nsuinteger_from_ocaml_int64(value raw, NSUInteger *result) {
  const std::int64_t signed_value = Int64_val(raw);
  if (signed_value < 0 ||
      static_cast<std::uint64_t>(signed_value) >
          static_cast<std::uint64_t>(NSUIntegerMax)) {
    return false;
  }
  *result = static_cast<NSUInteger>(signed_value);
  return true;
}

value copy_optional_string(NSString *text) {
  CAMLparam0();
  CAMLlocal2(option, contents);
  if (text == nil) {
    CAMLreturn(Val_none);
  }
  const char *utf8 = text.UTF8String;
  if (utf8 == nullptr) {
    CAMLreturn(Val_none);
  }
  contents = caml_copy_string(utf8);
  option = caml_alloc(1, 0);
  Store_field(option, 0, contents);
  CAMLreturn(option);
}

value result_unit() { return result_ok(Val_unit); }

MTLResourceOptions resource_options(int options) {
  const int cache = options & 0xf;
  const int storage = (options >> 4) & 0xf;
  const int hazard = (options >> 8) & 0x3;
  if ((options & ~0x3ff) != 0 || cache > 1 || storage > 2 || hazard > 2) {
    caml_invalid_argument("invalid Metal resource options");
  }
  return static_cast<MTLResourceOptions>(options);
}

bool valid_sparse_page_size(int page_size) {
  return page_size == MTLSparsePageSize16 ||
         page_size == MTLSparsePageSize64 ||
         page_size == MTLSparsePageSize256;
}

bool device_supports_sparse_textures(id<MTLDevice> device) {
  if (@available(macOS 13.0, *)) {
    return [device supportsFamily:MTLGPUFamilyApple6] &&
           [device respondsToSelector:
               @selector(sparseTileSizeInBytesForSparsePageSize:)] &&
           [device respondsToSelector:
               @selector(sparseTileSizeWithTextureType:pixelFormat:sampleCount:sparsePageSize:)] &&
           [MTLHeapDescriptor instancesRespondToSelector:
               @selector(setSparsePageSize:)] &&
           device.sparseTileSizeInBytes > 0;
  }
  return false;
}

bool device_supports_placement_sparse(id<MTLDevice> device) {
  if (@available(macOS 26.4, *)) {
    return [device respondsToSelector:@selector(supportsPlacementSparse)] &&
           device.supportsPlacementSparse &&
           [device respondsToSelector:
               @selector(newBufferWithLength:options:placementSparsePageSize:)] &&
           [device respondsToSelector:
               @selector(sparseTileSizeInBytesForSparsePageSize:)] &&
           [device respondsToSelector:
               @selector(sparseTileSizeWithTextureType:pixelFormat:sampleCount:sparsePageSize:)] &&
           [MTLTextureDescriptor instancesRespondToSelector:
               @selector(setPlacementSparsePageSize:)] &&
           [MTLHeapDescriptor instancesRespondToSelector:
               @selector(setMaxCompatiblePlacementSparsePageSize:)] &&
           [device respondsToSelector:@selector(newCommandAllocator)] &&
           [device respondsToSelector:@selector(newMTL4CommandQueue)] &&
           [device respondsToSelector:
               @selector(newMTL4CommandQueueWithDescriptor:error:)] &&
           [device respondsToSelector:@selector(newCommandBuffer)] &&
           [device respondsToSelector:@selector(newSharedEvent)];
  }
  return false;
}

bool device_supports_metal4_compiler(id<MTLDevice> device) {
  if (@available(macOS 26.0, *)) {
    return [device supportsFamily:MTLGPUFamilyMetal4] &&
           [device respondsToSelector:
               @selector(newCompilerWithDescriptor:error:)] &&
           [device respondsToSelector:
               @selector(newArchiveWithURL:error:)] &&
           [device respondsToSelector:
               @selector(newPipelineDataSetSerializerWithDescriptor:)];
  }
  return false;
}

API_AVAILABLE(macos(26.0))
MTL4CompilerTaskOptions *checked_compiler_task_options(
    NSArray<id<MTL4Archive>> *lookup_archives,
    NSString *__autoreleasing *failure) {
  if (lookup_archives.count == 0) {
    return nil;
  }
  MTL4CompilerTaskOptions *options = [[MTL4CompilerTaskOptions alloc] init];
  options.lookupArchives = lookup_archives;
  if (options.lookupArchives.count != lookup_archives.count) {
    *failure = @"Metal changed checked compiler-task lookup archives";
    return nil;
  }
  return options;
}

API_AVAILABLE(macos(26.0))
MTL4CompilerTaskOptions *checked_pipeline_task_options(
    value raw_archives, NSString *pipeline_kind,
    NSString *__autoreleasing *failure) {
  std::vector<id<MTL4Archive>> lookup_archives =
      pipeline_archives_of_array(raw_archives);
  NSMutableArray<id<MTL4Archive>> *archive_array =
      [NSMutableArray arrayWithCapacity:lookup_archives.size()];
  NSMutableSet<id<MTL4Archive>> *archive_set = [NSMutableSet set];
  for (id<MTL4Archive> archive : lookup_archives) {
    if ([archive_set containsObject:archive]) {
      *failure = [NSString
          stringWithFormat:@"Metal 4 %@ lookup archive is duplicated",
                           pipeline_kind];
      return nil;
    }
    [archive_set addObject:archive];
    [archive_array addObject:archive];
  }
  MTL4CompilerTaskOptions *options =
      checked_compiler_task_options(archive_array, failure);
  if (archive_array.count != 0 && options == nil && *failure == nil) {
    *failure = [NSString
        stringWithFormat:@"Metal 4 %@ lookup archives produced no task options",
                         pipeline_kind];
  }
  return options;
}

API_AVAILABLE(macos(26.0))
NSArray<MTL4FunctionDescriptor *> *checked_static_function_descriptors(
    value raw_functions, id<MTLDevice> device, NSString *category,
    NSString *__autoreleasing *failure) {
  const mlsize_t count = Wosize_val(raw_functions);
  NSMutableArray<MTL4FunctionDescriptor *> *descriptors =
      [NSMutableArray arrayWithCapacity:count];
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  for (mlsize_t index = 0; index < count; ++index) {
    value raw_function = Field(raw_functions, index);
    id<MTLLibrary> library =
        object_of_handle(Field(raw_function, 0), Handle_kind::Library);
    if (library.device.registryID != device.registryID) {
      *failure = [NSString
          stringWithFormat:@"%@ function is incompatible with the compiler",
                           category];
      return nil;
    }
    NSString *name = string_from_ocaml(Field(raw_function, 1));
    if (name == nil || name.length == 0) {
      *failure = [NSString
          stringWithFormat:@"%@ function name is not valid nonempty UTF-8",
                           category];
      return nil;
    }
    if ([names containsObject:name]) {
      *failure = [NSString
          stringWithFormat:@"%@ function name is duplicated", category];
      return nil;
    }
    [names addObject:name];
    MTL4LibraryFunctionDescriptor *descriptor =
        [[MTL4LibraryFunctionDescriptor alloc] init];
    descriptor.library = library;
    descriptor.name = name;
    if (descriptor.library != library ||
        ![descriptor.name isEqualToString:name]) {
      *failure = [NSString
          stringWithFormat:@"Metal changed checked %@ function properties",
                           category];
      return nil;
    }
    [descriptors addObject:descriptor];
  }
  return [descriptors copy];
}

API_AVAILABLE(macos(26.0))
bool checked_stored_static_function_descriptors(
    NSArray<MTL4FunctionDescriptor *> *stored,
    NSArray<MTL4FunctionDescriptor *> *expected, NSString *category,
    NSString *__autoreleasing *failure);

API_AVAILABLE(macos(26.0))
MTL4StaticLinkingDescriptor *checked_static_linking_descriptor(
    value raw_option, id<MTLDevice> device, bool supports_public_linking,
    NSString *__autoreleasing *failure) {
  if (!Is_block(raw_option)) {
    return nil;
  }
  value raw_descriptor = Field(raw_option, 0);
  NSArray<MTL4FunctionDescriptor *> *functions =
      checked_static_function_descriptors(
          Field(raw_descriptor, 0), device, @"public static-linked", failure);
  if (functions == nil) {
    return nil;
  }
  NSArray<MTL4FunctionDescriptor *> *private_functions =
      checked_static_function_descriptors(
          Field(raw_descriptor, 1), device, @"private static-linked", failure);
  if (private_functions == nil) {
    return nil;
  }
  value raw_groups = Field(raw_descriptor, 2);
  const mlsize_t group_count = Wosize_val(raw_groups);
  NSMutableDictionary<NSString *, NSArray<MTL4FunctionDescriptor *> *> *groups =
      [NSMutableDictionary dictionaryWithCapacity:group_count];
  for (mlsize_t index = 0; index < group_count; ++index) {
    value raw_group = Field(raw_groups, index);
    NSString *name = string_from_ocaml(Field(raw_group, 0));
    if (name == nil || name.length == 0) {
      *failure = @"Metal 4 static-link group name is not valid nonempty UTF-8";
      return nil;
    }
    if (groups[name] != nil) {
      *failure = @"Metal 4 static-link group name is duplicated";
      return nil;
    }
    NSArray<MTL4FunctionDescriptor *> *group_functions =
        checked_static_function_descriptors(
            Field(raw_group, 1), device,
            [@"static-link group " stringByAppendingString:name], failure);
    if (group_functions == nil) {
      return nil;
    }
    if (group_functions.count == 0) {
      *failure = @"Metal 4 static-link group contains no functions";
      return nil;
    }
    groups[name] = group_functions;
  }
  if (functions.count == 0 && private_functions.count == 0 &&
      groups.count == 0) {
    *failure = @"Metal 4 static-linking descriptor contains no functions";
    return nil;
  }
  if ((functions.count != 0 || groups.count != 0) &&
      !supports_public_linking) {
    *failure = @"Metal 4 public static linking requires function pointers";
    return nil;
  }
  NSMutableSet<NSString *> *public_names = [NSMutableSet set];
  for (MTL4LibraryFunctionDescriptor *function in functions) {
    [public_names addObject:function.name];
  }
  for (MTL4LibraryFunctionDescriptor *function in private_functions) {
    if ([public_names containsObject:function.name]) {
      *failure =
          @"Metal 4 static-linked function cannot be public and private";
      return nil;
    }
  }
  MTL4StaticLinkingDescriptor *descriptor =
      [[MTL4StaticLinkingDescriptor alloc] init];
  descriptor.functionDescriptors =
      functions.count == 0 ? nil : functions;
  descriptor.privateFunctionDescriptors =
      private_functions.count == 0 ? nil : private_functions;
  descriptor.groups = groups.count == 0 ? nil : groups;
  if (!checked_stored_static_function_descriptors(
          descriptor.functionDescriptors, functions,
          @"public static-linked", failure) ||
      !checked_stored_static_function_descriptors(
          descriptor.privateFunctionDescriptors, private_functions,
          @"private static-linked", failure) ||
      descriptor.groups.count != groups.count) {
    if (*failure != nil) {
      return nil;
    }
    *failure = @"Metal changed checked static-linking descriptor properties";
    return nil;
  }
  for (NSString *name in groups) {
    if (descriptor.groups[name] == nil ||
        !checked_stored_static_function_descriptors(
            descriptor.groups[name], groups[name],
            [@"static-link group " stringByAppendingString:name], failure)) {
      return nil;
    }
  }
  return descriptor;
}

API_AVAILABLE(macos(26.0))
MTL4StaticLinkingDescriptor *checked_render_static_linking_descriptor(
    value raw_option, id<MTLDevice> device,
    NSString *__autoreleasing *failure) {
  return checked_static_linking_descriptor(
      raw_option, device, device.supportsFunctionPointersFromRender, failure);
}

API_AVAILABLE(macos(26.0))
bool checked_stored_static_function_descriptors(
    NSArray<MTL4FunctionDescriptor *> *stored,
    NSArray<MTL4FunctionDescriptor *> *expected, NSString *category,
    NSString *__autoreleasing *failure) {
  if (stored.count != expected.count) {
    *failure = [NSString
        stringWithFormat:@"Metal changed checked %@ function count", category];
    return false;
  }
  for (NSUInteger index = 0; index < expected.count; ++index) {
    MTL4FunctionDescriptor *stored_function = stored[index];
    MTL4FunctionDescriptor *expected_function = expected[index];
    if (![stored_function
            isKindOfClass:[MTL4LibraryFunctionDescriptor class]] ||
        ![expected_function
            isKindOfClass:[MTL4LibraryFunctionDescriptor class]]) {
      *failure = [NSString
          stringWithFormat:@"Metal changed checked %@ function type", category];
      return false;
    }
    MTL4LibraryFunctionDescriptor *stored_library_function =
        static_cast<MTL4LibraryFunctionDescriptor *>(stored_function);
    MTL4LibraryFunctionDescriptor *expected_library_function =
        static_cast<MTL4LibraryFunctionDescriptor *>(expected_function);
    if (stored_library_function.library !=
            expected_library_function.library ||
        ![stored_library_function.name
            isEqualToString:expected_library_function.name]) {
      *failure = [NSString
          stringWithFormat:@"Metal changed checked %@ function identity",
                           category];
      return false;
    }
  }
  return true;
}

API_AVAILABLE(macos(26.0))
bool checked_stored_static_linking_descriptor(
    MTL4StaticLinkingDescriptor *stored,
    MTL4StaticLinkingDescriptor *expected, NSString *stage,
    NSString *__autoreleasing *failure) {
  if (expected == nil) {
    if (stored != nil &&
        (stored.functionDescriptors.count != 0 ||
         stored.privateFunctionDescriptors.count != 0 ||
         stored.groups.count != 0)) {
      *failure = [NSString
          stringWithFormat:@"Metal changed absent %@ static-linking descriptor",
                           stage];
      return false;
    }
    return true;
  }
  if (stored == nil ||
      !checked_stored_static_function_descriptors(
          stored.functionDescriptors, expected.functionDescriptors,
          [NSString stringWithFormat:@"%@ public static-linked", stage],
          failure) ||
      !checked_stored_static_function_descriptors(
          stored.privateFunctionDescriptors,
          expected.privateFunctionDescriptors,
          [NSString stringWithFormat:@"%@ private static-linked", stage],
          failure) ||
      stored.groups.count != expected.groups.count) {
    if (*failure == nil) {
      *failure = [NSString
          stringWithFormat:@"Metal changed checked %@ static-linking descriptor",
                           stage];
    }
    return false;
  }
  for (NSString *name in expected.groups) {
    NSArray<MTL4FunctionDescriptor *> *stored_group = stored.groups[name];
    NSArray<MTL4FunctionDescriptor *> *expected_group = expected.groups[name];
    if (stored_group == nil ||
        !checked_stored_static_function_descriptors(
            stored_group, expected_group,
            [NSString stringWithFormat:@"%@ static-link group %@", stage,
                                       name],
            failure)) {
      return false;
    }
  }
  return true;
}

bool device_supports_sampler_reduction(id<MTLDevice> device) {
  if (@available(macOS 26.0, *)) {
    return [device supportsFamily:MTLGPUFamilyApple10] &&
           [MTLSamplerDescriptor instancesRespondToSelector:
                @selector(reductionMode)] &&
           [MTLSamplerDescriptor instancesRespondToSelector:
                @selector(setReductionMode:)] &&
           [MTLSamplerDescriptor instancesRespondToSelector:
                @selector(lodBias)] &&
           [MTLSamplerDescriptor instancesRespondToSelector:
                @selector(setLodBias:)];
  }
  return false;
}

bool device_supports_lossy_texture_compression(id<MTLDevice> device) {
  if (@available(macOS 12.5, *)) {
    return [device supportsFamily:MTLGPUFamilyApple8] &&
           [MTLTextureDescriptor instancesRespondToSelector:
               @selector(compressionType)] &&
           [MTLTextureDescriptor instancesRespondToSelector:
               @selector(setCompressionType:)];
  }
  return false;
}

int texture_sparse_tier_or_unavailable(id<MTLTexture> texture) {
  if (@available(macOS 26.0, *)) {
    @try {
      if ([texture respondsToSelector:@selector(sparseTextureTier)]) {
        return static_cast<int>(texture.sparseTextureTier);
      }
    } @catch (NSException *exception) {
      (void)exception;
    }
  }
  return -1;
}

bool texture_is_sparse_resource(id<MTLTexture> texture) {
  return texture.isSparse || texture_sparse_tier_or_unavailable(texture) > 0;
}

std::size_t positive_dimension(value fields, mlsize_t index) {
  const intnat dimension = Long_val(Field(fields, index));
  if (dimension <= 0) {
    caml_invalid_argument("Metal dimensions must be positive");
  }
  return static_cast<std::size_t>(dimension);
}

MTLTextureSwizzle texture_swizzle(value raw_descriptor, mlsize_t index) {
  const intnat raw = Long_val(Field(raw_descriptor, index));
  if (raw < MTLTextureSwizzleZero || raw > MTLTextureSwizzleAlpha) {
    caml_invalid_argument("invalid Metal texture swizzle");
  }
  return static_cast<MTLTextureSwizzle>(raw);
}

MTLTextureSwizzleChannels texture_swizzle_channels(value raw_descriptor,
                                                    mlsize_t offset) {
  return MTLTextureSwizzleChannelsMake(
      texture_swizzle(raw_descriptor, offset),
      texture_swizzle(raw_descriptor, offset + 1),
      texture_swizzle(raw_descriptor, offset + 2),
      texture_swizzle(raw_descriptor, offset + 3));
}

bool texture_swizzles_equal(MTLTextureSwizzleChannels left,
                            MTLTextureSwizzleChannels right) {
  return left.red == right.red && left.green == right.green &&
         left.blue == right.blue && left.alpha == right.alpha;
}

MTLTextureDescriptor *texture_descriptor(value raw_descriptor) {
  const MTLTextureType texture_type =
      static_cast<MTLTextureType>(Long_val(Field(raw_descriptor, 0)));
  const MTLPixelFormat pixel_format =
      static_cast<MTLPixelFormat>(Long_val(Field(raw_descriptor, 1)));
  const std::size_t width = positive_dimension(raw_descriptor, 2);
  const std::size_t height = positive_dimension(raw_descriptor, 3);
  const std::size_t depth = positive_dimension(raw_descriptor, 4);
  const std::size_t mip_levels = positive_dimension(raw_descriptor, 5);
  const std::size_t sample_count = positive_dimension(raw_descriptor, 6);
  const std::size_t array_length = positive_dimension(raw_descriptor, 7);
  const MTLStorageMode storage_mode =
      static_cast<MTLStorageMode>(Long_val(Field(raw_descriptor, 8)));
  const MTLCPUCacheMode cpu_cache_mode =
      static_cast<MTLCPUCacheMode>(Long_val(Field(raw_descriptor, 9)));
  const MTLHazardTrackingMode hazard_tracking_mode =
      static_cast<MTLHazardTrackingMode>(Long_val(Field(raw_descriptor, 10)));
  const MTLTextureUsage usage =
      static_cast<MTLTextureUsage>(Long_val(Field(raw_descriptor, 11)));
  const bool allow_gpu_optimized_contents =
      Bool_val(Field(raw_descriptor, 12));
  const intnat compression_type = Long_val(Field(raw_descriptor, 13));
  if (compression_type < MTLTextureCompressionTypeLossless ||
      compression_type > MTLTextureCompressionTypeLossy) {
    caml_invalid_argument("invalid Metal texture compression type");
  }
  const MTLTextureSwizzleChannels swizzle =
      texture_swizzle_channels(raw_descriptor, 14);
  const bool writable =
      (usage & (MTLTextureUsageShaderWrite | MTLTextureUsageShaderAtomic)) != 0;
  if (writable &&
      !texture_swizzles_equal(swizzle, MTLTextureSwizzleChannelsDefault)) {
    caml_invalid_argument(
        "Metal writable textures cannot use a non-default swizzle");
  }
  if (compression_type == MTLTextureCompressionTypeLossy &&
      (storage_mode != MTLStorageModePrivate ||
       !allow_gpu_optimized_contents || writable ||
       (usage & MTLTextureUsagePixelFormatView) != 0 ||
       texture_type == MTLTextureType1D ||
       texture_type == MTLTextureType1DArray ||
       texture_type == MTLTextureTypeTextureBuffer)) {
    caml_invalid_argument("invalid Metal lossy texture descriptor");
  }
  MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
  descriptor.textureType = texture_type;
  descriptor.pixelFormat = pixel_format;
  descriptor.width = width;
  descriptor.height = height;
  descriptor.depth = depth;
  descriptor.mipmapLevelCount = mip_levels;
  descriptor.sampleCount = sample_count;
  descriptor.arrayLength = array_length;
  descriptor.storageMode = storage_mode;
  descriptor.cpuCacheMode = cpu_cache_mode;
  descriptor.hazardTrackingMode = hazard_tracking_mode;
  descriptor.usage = usage;
  descriptor.allowGPUOptimizedContents = allow_gpu_optimized_contents;
  descriptor.compressionType =
      static_cast<MTLTextureCompressionType>(compression_type);
  descriptor.swizzle = swizzle;
  return descriptor;
}

value copy_size_and_align(MTLSizeAndAlign size_and_align) {
  CAMLparam0();
  CAMLlocal3(result, size, alignment);
  result = caml_alloc_tuple(2);
  size = caml_copy_int64(static_cast<std::int64_t>(size_and_align.size));
  alignment = caml_copy_int64(static_cast<std::int64_t>(size_and_align.align));
  Store_field(result, 0, size);
  Store_field(result, 1, alignment);
  CAMLreturn(result);
}

NSUInteger texture_slice_count(id<MTLTexture> texture) {
  switch (texture.textureType) {
  case MTLTextureType1DArray:
  case MTLTextureType2DArray:
  case MTLTextureType2DMultisampleArray:
    return texture.arrayLength;
  case MTLTextureTypeCube:
    return 6;
  case MTLTextureTypeCubeArray:
    return texture.arrayLength * 6;
  default:
    return 1;
  }
}

struct Texture_format_layout {
  NSUInteger block_width;
  NSUInteger block_height;
  NSUInteger bytes_per_block;
};

Texture_format_layout texture_format_layout(MTLPixelFormat format) {
  switch (format) {
  case MTLPixelFormatA8Unorm:
  case MTLPixelFormatR8Unorm:
  case MTLPixelFormatR8Unorm_sRGB:
  case MTLPixelFormatR8Snorm:
  case MTLPixelFormatR8Uint:
  case MTLPixelFormatR8Sint:
  case MTLPixelFormatStencil8:
    return {1, 1, 1};
  case MTLPixelFormatR16Unorm:
  case MTLPixelFormatR16Snorm:
  case MTLPixelFormatR16Uint:
  case MTLPixelFormatR16Sint:
  case MTLPixelFormatR16Float:
  case MTLPixelFormatRG8Unorm:
  case MTLPixelFormatRG8Unorm_sRGB:
  case MTLPixelFormatRG8Snorm:
  case MTLPixelFormatRG8Uint:
  case MTLPixelFormatRG8Sint:
  case MTLPixelFormatB5G6R5Unorm:
  case MTLPixelFormatA1BGR5Unorm:
  case MTLPixelFormatABGR4Unorm:
  case MTLPixelFormatBGR5A1Unorm:
  case MTLPixelFormatDepth16Unorm:
    return {1, 1, 2};
  case MTLPixelFormatR32Uint:
  case MTLPixelFormatR32Sint:
  case MTLPixelFormatR32Float:
  case MTLPixelFormatRG16Unorm:
  case MTLPixelFormatRG16Snorm:
  case MTLPixelFormatRG16Uint:
  case MTLPixelFormatRG16Sint:
  case MTLPixelFormatRG16Float:
  case MTLPixelFormatRGBA8Unorm:
  case MTLPixelFormatRGBA8Unorm_sRGB:
  case MTLPixelFormatRGBA8Snorm:
  case MTLPixelFormatRGBA8Uint:
  case MTLPixelFormatRGBA8Sint:
  case MTLPixelFormatBGRA8Unorm:
  case MTLPixelFormatBGRA8Unorm_sRGB:
  case MTLPixelFormatRGB10A2Unorm:
  case MTLPixelFormatRGB10A2Uint:
  case MTLPixelFormatRG11B10Float:
  case MTLPixelFormatRGB9E5Float:
  case MTLPixelFormatBGR10A2Unorm:
  case MTLPixelFormatBGR10_XR:
  case MTLPixelFormatBGR10_XR_sRGB:
  case MTLPixelFormatBGRA10_XR:
  case MTLPixelFormatBGRA10_XR_sRGB:
  case MTLPixelFormatDepth32Float:
  case MTLPixelFormatDepth24Unorm_Stencil8:
  case MTLPixelFormatX24_Stencil8:
    return {1, 1, 4};
  case MTLPixelFormatRG32Uint:
  case MTLPixelFormatRG32Sint:
  case MTLPixelFormatRG32Float:
  case MTLPixelFormatRGBA16Unorm:
  case MTLPixelFormatRGBA16Snorm:
  case MTLPixelFormatRGBA16Uint:
  case MTLPixelFormatRGBA16Sint:
  case MTLPixelFormatRGBA16Float:
  case MTLPixelFormatDepth32Float_Stencil8:
  case MTLPixelFormatX32_Stencil8:
    return {1, 1, 8};
  case MTLPixelFormatRGBA32Uint:
  case MTLPixelFormatRGBA32Sint:
  case MTLPixelFormatRGBA32Float:
    return {1, 1, 16};
  case MTLPixelFormatBC1_RGBA:
  case MTLPixelFormatBC1_RGBA_sRGB:
  case MTLPixelFormatBC4_RUnorm:
  case MTLPixelFormatBC4_RSnorm:
  case MTLPixelFormatEAC_R11Unorm:
  case MTLPixelFormatEAC_R11Snorm:
  case MTLPixelFormatETC2_RGB8:
  case MTLPixelFormatETC2_RGB8_sRGB:
  case MTLPixelFormatETC2_RGB8A1:
  case MTLPixelFormatETC2_RGB8A1_sRGB:
    return {4, 4, 8};
  case MTLPixelFormatBC2_RGBA:
  case MTLPixelFormatBC2_RGBA_sRGB:
  case MTLPixelFormatBC3_RGBA:
  case MTLPixelFormatBC3_RGBA_sRGB:
  case MTLPixelFormatBC5_RGUnorm:
  case MTLPixelFormatBC5_RGSnorm:
  case MTLPixelFormatBC6H_RGBFloat:
  case MTLPixelFormatBC6H_RGBUfloat:
  case MTLPixelFormatBC7_RGBAUnorm:
  case MTLPixelFormatBC7_RGBAUnorm_sRGB:
  case MTLPixelFormatEAC_RG11Unorm:
  case MTLPixelFormatEAC_RG11Snorm:
  case MTLPixelFormatEAC_RGBA8:
  case MTLPixelFormatEAC_RGBA8_sRGB:
  case MTLPixelFormatASTC_4x4_sRGB:
  case MTLPixelFormatASTC_4x4_LDR:
  case MTLPixelFormatASTC_4x4_HDR:
    return {4, 4, 16};
  case MTLPixelFormatASTC_5x4_sRGB:
  case MTLPixelFormatASTC_5x4_LDR:
  case MTLPixelFormatASTC_5x4_HDR:
    return {5, 4, 16};
  case MTLPixelFormatASTC_5x5_sRGB:
  case MTLPixelFormatASTC_5x5_LDR:
  case MTLPixelFormatASTC_5x5_HDR:
    return {5, 5, 16};
  case MTLPixelFormatASTC_6x5_sRGB:
  case MTLPixelFormatASTC_6x5_LDR:
  case MTLPixelFormatASTC_6x5_HDR:
    return {6, 5, 16};
  case MTLPixelFormatASTC_6x6_sRGB:
  case MTLPixelFormatASTC_6x6_LDR:
  case MTLPixelFormatASTC_6x6_HDR:
    return {6, 6, 16};
  case MTLPixelFormatASTC_8x5_sRGB:
  case MTLPixelFormatASTC_8x5_LDR:
  case MTLPixelFormatASTC_8x5_HDR:
    return {8, 5, 16};
  case MTLPixelFormatASTC_8x6_sRGB:
  case MTLPixelFormatASTC_8x6_LDR:
  case MTLPixelFormatASTC_8x6_HDR:
    return {8, 6, 16};
  case MTLPixelFormatASTC_8x8_sRGB:
  case MTLPixelFormatASTC_8x8_LDR:
  case MTLPixelFormatASTC_8x8_HDR:
    return {8, 8, 16};
  case MTLPixelFormatASTC_10x5_sRGB:
  case MTLPixelFormatASTC_10x5_LDR:
  case MTLPixelFormatASTC_10x5_HDR:
    return {10, 5, 16};
  case MTLPixelFormatASTC_10x6_sRGB:
  case MTLPixelFormatASTC_10x6_LDR:
  case MTLPixelFormatASTC_10x6_HDR:
    return {10, 6, 16};
  case MTLPixelFormatASTC_10x8_sRGB:
  case MTLPixelFormatASTC_10x8_LDR:
  case MTLPixelFormatASTC_10x8_HDR:
    return {10, 8, 16};
  case MTLPixelFormatASTC_10x10_sRGB:
  case MTLPixelFormatASTC_10x10_LDR:
  case MTLPixelFormatASTC_10x10_HDR:
    return {10, 10, 16};
  case MTLPixelFormatASTC_12x10_sRGB:
  case MTLPixelFormatASTC_12x10_LDR:
  case MTLPixelFormatASTC_12x10_HDR:
    return {12, 10, 16};
  case MTLPixelFormatASTC_12x12_sRGB:
  case MTLPixelFormatASTC_12x12_LDR:
  case MTLPixelFormatASTC_12x12_HDR:
    return {12, 12, 16};
  case MTLPixelFormatGBGR422:
  case MTLPixelFormatBGRG422:
    return {2, 1, 4};
  default:
    return {0, 0, 0};
  }
}

bool texture_transfer_range(id<MTLTexture> texture, value raw_transfer,
                            MTLRegion *region, NSUInteger *level,
                            NSUInteger *slice, intnat *source_offset,
                            intnat *bytes_per_row, intnat *bytes_per_image,
                            intnat *total_bytes) {
  value raw_region = Field(raw_transfer, 0);
  const intnat x = Long_val(Field(raw_region, 0));
  const intnat y = Long_val(Field(raw_region, 1));
  const intnat z = Long_val(Field(raw_region, 2));
  const intnat width = Long_val(Field(raw_region, 3));
  const intnat height = Long_val(Field(raw_region, 4));
  const intnat depth = Long_val(Field(raw_region, 5));
  const intnat signed_level = Long_val(Field(raw_transfer, 1));
  const intnat signed_slice = Long_val(Field(raw_transfer, 2));
  *source_offset = Long_val(Field(raw_transfer, 3));
  *bytes_per_row = Long_val(Field(raw_transfer, 4));
  *bytes_per_image = Long_val(Field(raw_transfer, 5));
  if (x < 0 || y < 0 || z < 0 || width <= 0 || height <= 0 || depth <= 0 ||
      signed_level < 0 || signed_slice < 0 || *source_offset < 0 ||
      *bytes_per_row <= 0 || *bytes_per_image <= 0) {
    return false;
  }
  *level = static_cast<NSUInteger>(signed_level);
  *slice = static_cast<NSUInteger>(signed_slice);
  if (*level >= texture.mipmapLevelCount || *slice >= texture_slice_count(texture)) {
    return false;
  }
  const NSUInteger mip_width = std::max<NSUInteger>(1, texture.width >> *level);
  const NSUInteger mip_height = std::max<NSUInteger>(1, texture.height >> *level);
  const NSUInteger mip_depth = std::max<NSUInteger>(1, texture.depth >> *level);
  const auto ux = static_cast<NSUInteger>(x);
  const auto uy = static_cast<NSUInteger>(y);
  const auto uz = static_cast<NSUInteger>(z);
  const auto uw = static_cast<NSUInteger>(width);
  const auto uh = static_cast<NSUInteger>(height);
  const auto ud = static_cast<NSUInteger>(depth);
  if (ux > mip_width || uw > mip_width - ux || uy > mip_height ||
      uh > mip_height - uy || uz > mip_depth || ud > mip_depth - uz) {
    return false;
  }
  const Texture_format_layout layout =
      texture_format_layout(texture.pixelFormat);
  if (layout.block_width == 0 || layout.block_height == 0 ||
      layout.bytes_per_block == 0 || ux % layout.block_width != 0 ||
      uy % layout.block_height != 0 ||
      (uw % layout.block_width != 0 && ux + uw != mip_width) ||
      (uh % layout.block_height != 0 && uy + uh != mip_height)) {
    return false;
  }
  const NSUInteger row_blocks =
      uw / layout.block_width + (uw % layout.block_width == 0 ? 0 : 1);
  const NSUInteger image_block_rows =
      uh / layout.block_height + (uh % layout.block_height == 0 ? 0 : 1);
  if (row_blocks > static_cast<NSUInteger>(Max_long) /
                       layout.bytes_per_block) {
    return false;
  }
  const intnat minimum_row =
      static_cast<intnat>(row_blocks * layout.bytes_per_block);
  if (*bytes_per_row < minimum_row ||
      *bytes_per_row % static_cast<intnat>(layout.bytes_per_block) != 0 ||
      image_block_rows > static_cast<NSUInteger>(Max_long) ||
      *bytes_per_row >
          Max_long / static_cast<intnat>(image_block_rows)) {
    return false;
  }
  const intnat minimum_image =
      *bytes_per_row * static_cast<intnat>(image_block_rows);
  if (*bytes_per_image < minimum_image || *bytes_per_image > Max_long / depth) {
    return false;
  }
  *total_bytes = *bytes_per_image * depth;
  *region = MTLRegionMake3D(ux, uy, uz, uw, uh, ud);
  return true;
}

} // namespace

extern "C" CAMLprim value caml_prismel_metal_is_main_thread(value unit) {
  CAMLparam1(unit);
  CAMLreturn(Val_bool(pthread_main_np() != 0 ||
                      prismel_metal_xpc_main_executor));
}

extern "C" CAMLprim value caml_prismel_metal_generation(value raw) {
  CAMLparam1(raw);
  CAMLreturn(caml_copy_int64(
      static_cast<std::int64_t>(handle_of_value(raw)->generation)));
}

extern "C" CAMLprim value caml_prismel_metal_destroy(value raw) {
  CAMLparam1(raw);
  void *pointer = take_pointer(handle_of_value(raw));
  if (pointer != nullptr) {
    release_pointer(pointer);
  }
  CAMLreturn(Val_bool(pointer != nullptr));
}

extern "C" CAMLprim value caml_prismel_metal_drain_releases(value unit) {
  CAMLparam1(unit);
  std::size_t drained = 0;
  for (;;) {
    void *pointer = nullptr;
    {
      std::lock_guard<std::mutex> lock(release_mutex);
      if (release_queue.empty()) {
        break;
      }
      pointer = release_queue.front();
      release_queue.pop_front();
    }
    release_pointer(pointer);
    ++drained;
  }
  CAMLreturn(Val_long(drained));
}

extern "C" CAMLprim value caml_prismel_metal_pending_releases(value unit) {
  CAMLparam1(unit);
  std::size_t pending = 0;
  {
    std::lock_guard<std::mutex> lock(release_mutex);
    pending = release_queue.size();
  }
  CAMLreturn(Val_long(pending));
}

extern "C" CAMLprim value caml_prismel_metal_live_handles(value unit) {
  CAMLparam1(unit);
  CAMLreturn(Val_long(live_handle_count.load(std::memory_order_relaxed)));
}

extern "C" CAMLprim value caml_prismel_metal_total_created(value unit) {
  CAMLparam1(unit);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(
      total_created_count.load(std::memory_order_relaxed))));
}

extern "C" CAMLprim value caml_prismel_metal_total_released(value unit) {
  CAMLparam1(unit);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(
      total_released_count.load(std::memory_order_relaxed))));
}

extern "C" CAMLprim value caml_prismel_metal_external_deallocations(
    value unit) {
  CAMLparam1(unit);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(
      external_deallocation_count.load(std::memory_order_relaxed))));
}

extern "C" CAMLprim value
caml_prismel_metal_external_deallocation_mismatches(value unit) {
  CAMLparam1(unit);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(
      external_deallocation_mismatch_count.load(std::memory_order_relaxed))));
}

extern "C" CAMLprim value caml_prismel_metal_resident_bytes(value unit) {
  CAMLparam1(unit);
  mach_task_basic_info_data_t information{};
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  const kern_return_t status = task_info(
      mach_task_self(), MACH_TASK_BASIC_INFO,
      reinterpret_cast<task_info_t>(&information), &count);
  if (status != KERN_SUCCESS) {
    CAMLreturn(caml_copy_int64(-1));
  }
  CAMLreturn(caml_copy_int64(
      static_cast<std::int64_t>(information.resident_size)));
}

extern "C" CAMLprim value caml_prismel_metal_default_device(value unit) {
  CAMLparam1(unit);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) {
      CAMLreturn(result_error_text("Metal has no system default device"));
    }
    raw = allocate_handle(device, Handle_kind::Device);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_residency_sets(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  bool supported = false;
  if (@available(macOS 15.0, *)) {
    supported =
        [device respondsToSelector:@selector(newResidencySetWithDescriptor:error:)];
  }
  CAMLreturn(Val_bool(supported));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_sparse_textures(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device_supports_sparse_textures(device)));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_placement_sparse(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device_supports_placement_sparse(device)));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_sampler_reduction(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device_supports_sampler_reduction(device)));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_lossy_texture_compression(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device_supports_lossy_texture_compression(device)));
}

extern "C" CAMLprim value
caml_prismel_metal_device_sparse_tile_size_in_bytes(value raw,
                                                     value raw_page_size) {
  CAMLparam2(raw, raw_page_size);
  CAMLlocal2(result, copied_size);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
      const int page_size = Int_val(raw_page_size);
      if (!valid_sparse_page_size(page_size)) {
        CAMLreturn(result_error_text("invalid sparse page size"));
      }
      if (!device_supports_sparse_textures(device)) {
        CAMLreturn(result_error_text(
            "device does not support sparse textures"));
      }
      const NSUInteger bytes = [device
          sparseTileSizeInBytesForSparsePageSize:
              static_cast<MTLSparsePageSize>(page_size)];
      if (bytes == 0 || bytes > static_cast<NSUInteger>(INT64_MAX)) {
        CAMLreturn(result_error_text(
            "Metal returned an invalid sparse tile byte size"));
      }
      copied_size = caml_copy_int64(static_cast<std::int64_t>(bytes));
      result = result_ok(copied_size);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value
caml_prismel_metal_device_sparse_texture_tile_size(
    value raw, value raw_kind, value raw_format, value raw_sample_count,
    value raw_page_size) {
  CAMLparam5(raw, raw_kind, raw_format, raw_sample_count, raw_page_size);
  CAMLlocal2(result, copied_size);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
      const int page_size = Int_val(raw_page_size);
      const intnat sample_count = Long_val(raw_sample_count);
      if (!valid_sparse_page_size(page_size) || sample_count <= 0 ||
          (!device_supports_sparse_textures(device) &&
           !device_supports_placement_sparse(device))) {
        CAMLreturn(result_error_text(
            "sparse texture tile query is unsupported"));
      }
      const MTLSize size = [device
          sparseTileSizeWithTextureType:
              static_cast<MTLTextureType>(Long_val(raw_kind))
                              pixelFormat:
              static_cast<MTLPixelFormat>(Long_val(raw_format))
                              sampleCount:static_cast<NSUInteger>(sample_count)
                           sparsePageSize:
              static_cast<MTLSparsePageSize>(page_size)];
      if (size.width == 0 || size.height == 0 || size.depth == 0 ||
          size.width > static_cast<NSUInteger>(Max_long) ||
          size.height > static_cast<NSUInteger>(Max_long) ||
          size.depth > static_cast<NSUInteger>(Max_long)) {
        CAMLreturn(result_error_text(
            "Metal does not support the sparse texture layout"));
      }
      copied_size = caml_alloc_tuple(3);
      Store_field(copied_size, 0, Val_long(size.width));
      Store_field(copied_size, 1, Val_long(size.height));
      Store_field(copied_size, 2, Val_long(size.depth));
      result = result_ok(copied_size);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_buffer_create(
    value raw_device, value raw_length, value raw_options) {
  CAMLparam3(raw_device, raw_length, raw_options);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    const std::int64_t signed_length = Int64_val(raw_length);
    if (signed_length <= 0) {
      CAMLreturn(result_error_text("buffer length must be positive"));
    }
    id<MTLBuffer> buffer = [device
        newBufferWithLength:static_cast<NSUInteger>(signed_length)
                   options:resource_options(Int_val(raw_options))];
    if (buffer == nil) {
      CAMLreturn(result_error_text("Metal failed to allocate the buffer"));
    }
    raw = allocate_handle(buffer, Handle_kind::Buffer);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_buffer_info(value raw) {
  CAMLparam1(raw);
  CAMLlocal3(result, length, heap_offset);
  id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
  result = caml_alloc_tuple(5);
  length = caml_copy_int64(static_cast<std::int64_t>(buffer.length));
  heap_offset =
      caml_copy_int64(static_cast<std::int64_t>(buffer.heapOffset));
  Store_field(result, 0, length);
  Store_field(result, 1, Val_int(static_cast<int>(buffer.storageMode)));
  Store_field(result, 2, Val_int(static_cast<int>(buffer.cpuCacheMode)));
  Store_field(result, 3, Val_int(static_cast<int>(buffer.hazardTrackingMode)));
  Store_field(result, 4, heap_offset);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_buffer_set_label(
    value raw, value raw_label) {
  CAMLparam2(raw, raw_label);
  @autoreleasepool {
    id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
    NSString *label = string_from_ocaml(raw_label);
    if (label == nil) {
      CAMLreturn(result_error_text("buffer label is not valid UTF-8"));
    }
    buffer.label = label;
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_buffer_write(
    value raw, value raw_offset, value source, value raw_source_offset,
    value raw_length) {
  CAMLparam5(raw, raw_offset, source, raw_source_offset, raw_length);
  id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
  const std::int64_t signed_offset = Int64_val(raw_offset);
  const intnat source_offset = Long_val(raw_source_offset);
  const intnat length = Long_val(raw_length);
  if (signed_offset < 0 || source_offset < 0 || length < 0 ||
      source_offset > static_cast<intnat>(caml_string_length(source)) ||
      length > static_cast<intnat>(caml_string_length(source)) - source_offset ||
      static_cast<std::uint64_t>(signed_offset) > buffer.length ||
      static_cast<std::uint64_t>(length) >
          buffer.length - static_cast<std::uint64_t>(signed_offset)) {
    CAMLreturn(result_error_text("buffer write range is invalid"));
  }
  void *contents = buffer.contents;
  if (contents == nullptr) {
    CAMLreturn(result_error_text("buffer storage is not CPU-accessible"));
  }
  std::memcpy(static_cast<std::uint8_t *>(contents) + signed_offset,
              reinterpret_cast<const std::uint8_t *>(Bytes_val(source)) +
                  source_offset,
              static_cast<std::size_t>(length));
  if (buffer.storageMode == MTLStorageModeManaged && length > 0) {
    [buffer didModifyRange:NSMakeRange(static_cast<NSUInteger>(signed_offset),
                                       static_cast<NSUInteger>(length))];
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_buffer_read(
    value raw, value raw_offset, value raw_length) {
  CAMLparam3(raw, raw_offset, raw_length);
  CAMLlocal2(contents_value, result);
  id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
  const std::int64_t signed_offset = Int64_val(raw_offset);
  const intnat length = Long_val(raw_length);
  if (signed_offset < 0 || length < 0 ||
      static_cast<std::uint64_t>(signed_offset) > buffer.length ||
      static_cast<std::uint64_t>(length) >
          buffer.length - static_cast<std::uint64_t>(signed_offset)) {
    CAMLreturn(result_error_text("buffer read range is invalid"));
  }
  const void *contents = buffer.contents;
  if (contents == nullptr) {
    CAMLreturn(result_error_text("buffer storage is not CPU-accessible"));
  }
  contents_value = caml_alloc_string(static_cast<mlsize_t>(length));
  std::memcpy(Bytes_val(contents_value),
              static_cast<const std::uint8_t *>(contents) + signed_offset,
              static_cast<std::size_t>(length));
  result = result_ok(contents_value);
  CAMLreturn(result);
}

extern "C" CAMLprim value
caml_prismel_metal_resource_make_aliasable(value raw) {
  CAMLparam1(raw);
  @autoreleasepool {
    @try {
      Handle_kind kind = Handle_kind::Buffer;
      id<MTLResource> resource = resource_of_handle(raw, &kind);
      if (resource.heap == nil) {
        CAMLreturn(result_error_text(
            "only heap-backed resources can become aliasable"));
      }
      if (kind == Handle_kind::Texture) {
        id<MTLTexture> texture = static_cast<id<MTLTexture>>(resource);
        if (texture.parentTexture != nil) {
          CAMLreturn(result_error_text(
              "heap-backed texture views cannot become aliasable"));
        }
      }
      [resource makeAliasable];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value
caml_prismel_metal_resource_is_aliasable(value raw) {
  CAMLparam1(raw);
  id<MTLResource> resource = resource_of_handle(raw);
  CAMLreturn(Val_bool(resource.isAliasable));
}

extern "C" CAMLprim value caml_prismel_metal_heap_buffer_size_and_align(
    value raw_device, value raw_length, value raw_options) {
  CAMLparam3(raw_device, raw_length, raw_options);
  id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
  const std::int64_t length = Int64_val(raw_length);
  if (length <= 0) {
    caml_invalid_argument("heap buffer length must be positive");
  }
  const MTLSizeAndAlign result = [device
      heapBufferSizeAndAlignWithLength:static_cast<NSUInteger>(length)
                               options:resource_options(Int_val(raw_options))];
  CAMLreturn(copy_size_and_align(result));
}

extern "C" CAMLprim value caml_prismel_metal_heap_texture_size_and_align(
    value raw_device, value raw_descriptor) {
  CAMLparam2(raw_device, raw_descriptor);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    MTLTextureDescriptor *descriptor = texture_descriptor(raw_descriptor);
    const MTLSizeAndAlign result =
        [device heapTextureSizeAndAlignWithDescriptor:descriptor];
    CAMLreturn(copy_size_and_align(result));
  }
}

extern "C" CAMLprim value caml_prismel_metal_heap_create(
    value raw_device, value raw_descriptor, value raw_label) {
  CAMLparam3(raw_device, raw_descriptor, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    const std::int64_t size = Int64_val(Field(raw_descriptor, 0));
    if (size <= 0) {
      CAMLreturn(result_error_text("heap size must be positive"));
    }
    MTLHeapDescriptor *descriptor = [[MTLHeapDescriptor alloc] init];
    descriptor.size = static_cast<NSUInteger>(size);
    descriptor.storageMode =
        static_cast<MTLStorageMode>(Long_val(Field(raw_descriptor, 1)));
    descriptor.cpuCacheMode =
        static_cast<MTLCPUCacheMode>(Long_val(Field(raw_descriptor, 2)));
    descriptor.hazardTrackingMode =
        static_cast<MTLHazardTrackingMode>(Long_val(Field(raw_descriptor, 3)));
    const auto heap_type =
        static_cast<MTLHeapType>(Long_val(Field(raw_descriptor, 4)));
    const int sparse_page_size = Int_val(Field(raw_descriptor, 5));
    descriptor.type = heap_type;
    if (heap_type == MTLHeapTypeSparse) {
      if (!device_supports_sparse_textures(device)) {
        CAMLreturn(result_error_text(
            "device does not support sparse textures"));
      }
      if (!valid_sparse_page_size(sparse_page_size)) {
        CAMLreturn(result_error_text(
            "sparse heaps require a valid sparse page size"));
      }
      if (descriptor.storageMode != MTLStorageModePrivate ||
          descriptor.cpuCacheMode != MTLCPUCacheModeDefaultCache) {
        CAMLreturn(result_error_text(
            "sparse heaps require private default-cache storage"));
      }
      const NSUInteger page_bytes = [device
          sparseTileSizeInBytesForSparsePageSize:
              static_cast<MTLSparsePageSize>(sparse_page_size)];
      if (page_bytes == 0 || descriptor.size % page_bytes != 0) {
        CAMLreturn(result_error_text(
            "sparse heap size is not a whole number of sparse pages"));
      }
      descriptor.sparsePageSize =
          static_cast<MTLSparsePageSize>(sparse_page_size);
    } else if (heap_type == MTLHeapTypePlacement && sparse_page_size != 0) {
      if (!device_supports_placement_sparse(device)) {
        CAMLreturn(result_error_text(
            "device does not support placement sparse resources"));
      }
      if (!valid_sparse_page_size(sparse_page_size)) {
        CAMLreturn(result_error_text(
            "placement heaps require a valid maximum sparse page size"));
      }
      if (@available(macOS 26.0, *)) {
        const NSUInteger page_bytes = [device
            sparseTileSizeInBytesForSparsePageSize:
                static_cast<MTLSparsePageSize>(sparse_page_size)];
        if (page_bytes == 0 || descriptor.size % page_bytes != 0) {
          CAMLreturn(result_error_text(
              "placement heap size is not a whole number of sparse pages"));
        }
        descriptor.maxCompatiblePlacementSparsePageSize =
            static_cast<MTLSparsePageSize>(sparse_page_size);
        if (descriptor.maxCompatiblePlacementSparsePageSize !=
            static_cast<MTLSparsePageSize>(sparse_page_size)) {
          CAMLreturn(result_error_text(
              "Metal changed the placement heap's maximum sparse page size"));
        }
      } else {
        CAMLreturn(result_error_text(
            "placement sparse heaps require macOS 26"));
      }
    } else if (sparse_page_size != 0) {
      CAMLreturn(result_error_text(
          "only sparse or placement heaps accept a sparse page size"));
    }
    id<MTLHeap> heap = [device newHeapWithDescriptor:descriptor];
    if (heap == nil) {
      CAMLreturn(result_error_text("Metal rejected the heap descriptor"));
    }
    if (Is_block(raw_label)) {
      NSString *label = string_from_ocaml(Field(raw_label, 0));
      if (label == nil) {
        CAMLreturn(result_error_text("heap label is not valid UTF-8"));
      }
      heap.label = label;
    }
    raw = allocate_handle(heap, Handle_kind::Heap);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_heap_info(value raw) {
  CAMLparam1(raw);
  CAMLlocal2(result, item);
  id<MTLHeap> heap = object_of_handle(raw, Handle_kind::Heap);
  result = caml_alloc(7, 0);
  item = caml_copy_int64(static_cast<std::int64_t>(heap.size));
  Store_field(result, 0, item);
  item = caml_copy_int64(static_cast<std::int64_t>(heap.usedSize));
  Store_field(result, 1, item);
  item = caml_copy_int64(static_cast<std::int64_t>(heap.currentAllocatedSize));
  Store_field(result, 2, item);
  item = caml_copy_int64(static_cast<std::int64_t>(heap.storageMode));
  Store_field(result, 3, item);
  item = caml_copy_int64(static_cast<std::int64_t>(heap.cpuCacheMode));
  Store_field(result, 4, item);
  item = caml_copy_int64(static_cast<std::int64_t>(heap.hazardTrackingMode));
  Store_field(result, 5, item);
  item = caml_copy_int64(static_cast<std::int64_t>(heap.type));
  Store_field(result, 6, item);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_heap_max_available_size(
    value raw, value raw_alignment) {
  CAMLparam2(raw, raw_alignment);
  id<MTLHeap> heap = object_of_handle(raw, Handle_kind::Heap);
  const std::int64_t alignment = Int64_val(raw_alignment);
  if (alignment < 0) {
    caml_invalid_argument("heap alignment must be nonnegative");
  }
  const NSUInteger result = [heap
      maxAvailableSizeWithAlignment:static_cast<NSUInteger>(alignment)];
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(result)));
}

extern "C" CAMLprim value caml_prismel_metal_heap_buffer_create(
    value raw_heap, value raw_length, value raw_options, value raw_offset) {
  CAMLparam4(raw_heap, raw_length, raw_options, raw_offset);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLHeap> heap = object_of_handle(raw_heap, Handle_kind::Heap);
    const std::int64_t length = Int64_val(raw_length);
    if (length <= 0) {
      CAMLreturn(result_error_text("heap buffer length must be positive"));
    }
    const MTLResourceOptions options = resource_options(Int_val(raw_options));
    id<MTLBuffer> buffer = nil;
    if (Is_block(raw_offset)) {
      const std::int64_t offset = Int64_val(Field(raw_offset, 0));
      if (offset < 0) {
        CAMLreturn(result_error_text("heap buffer offset is negative"));
      }
      buffer = [heap newBufferWithLength:static_cast<NSUInteger>(length)
                                 options:options
                                  offset:static_cast<NSUInteger>(offset)];
    } else {
      buffer = [heap newBufferWithLength:static_cast<NSUInteger>(length)
                                 options:options];
    }
    if (buffer == nil) {
      CAMLreturn(result_error_text("Metal failed to allocate the heap buffer"));
    }
    raw = allocate_handle(buffer, Handle_kind::Buffer);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_heap_texture_create(
    value raw_heap, value raw_descriptor, value raw_offset, value raw_label) {
  CAMLparam4(raw_heap, raw_descriptor, raw_offset, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
    id<MTLHeap> heap = object_of_handle(raw_heap, Handle_kind::Heap);
    MTLTextureDescriptor *descriptor = texture_descriptor(raw_descriptor);
    id<MTLTexture> texture = nil;
    if (Is_block(raw_offset)) {
      const std::int64_t offset = Int64_val(Field(raw_offset, 0));
      if (offset < 0) {
        CAMLreturn(result_error_text("heap texture offset is negative"));
      }
      texture = [heap newTextureWithDescriptor:descriptor
                                        offset:static_cast<NSUInteger>(offset)];
    } else {
      texture = [heap newTextureWithDescriptor:descriptor];
    }
    if (texture == nil) {
      CAMLreturn(result_error_text("Metal failed to allocate the heap texture"));
    }
    const bool expected_sparse = heap.type == MTLHeapTypeSparse;
    if (texture.isSparse != expected_sparse) {
      CAMLreturn(result_error_text(
          "Metal changed the heap texture's sparse identity"));
    }
    if (Is_block(raw_label)) {
      NSString *label = string_from_ocaml(Field(raw_label, 0));
      if (label == nil) {
        CAMLreturn(result_error_text("heap texture label is not valid UTF-8"));
      }
      texture.label = label;
    }
    raw = allocate_handle(texture, Handle_kind::Texture);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_residency_set_create(
    value raw_device, value raw_capacity, value raw_label) {
  CAMLparam3(raw_device, raw_capacity, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
        const intnat capacity = Long_val(raw_capacity);
        if (capacity < 0) {
          CAMLreturn(result_error_text(
              "residency-set initial capacity must be nonnegative"));
        }
        MTLResidencySetDescriptor *descriptor =
            [[MTLResidencySetDescriptor alloc] init];
        descriptor.initialCapacity = static_cast<NSUInteger>(capacity);
        NSString *expected_label = nil;
        if (Is_block(raw_label)) {
          expected_label = string_from_ocaml(Field(raw_label, 0));
          if (expected_label == nil) {
            CAMLreturn(result_error_text(
                "residency-set label is not valid UTF-8"));
          }
          descriptor.label = expected_label;
        }
        if (descriptor.initialCapacity != static_cast<NSUInteger>(capacity) ||
            ((expected_label == nil) != (descriptor.label == nil)) ||
            (expected_label != nil &&
             ![descriptor.label isEqualToString:expected_label])) {
          CAMLreturn(result_error_text(
              "Metal changed checked residency-set descriptor properties"));
        }
        NSError *error = nil;
        id<MTLResidencySet> residency_set =
            [device newResidencySetWithDescriptor:descriptor error:&error];
        if (residency_set == nil) {
          CAMLreturn(result_error(error_description(
              error, @"Metal residency-set creation failed without NSError")));
        }
        if (residency_set.device.registryID != device.registryID ||
            (expected_label == nil && residency_set.label != nil) ||
            (expected_label != nil && residency_set.label != nil &&
             ![residency_set.label isEqualToString:expected_label])) {
          CAMLreturn(result_error([NSString
              stringWithFormat:
                  @"Metal changed checked residency-set creation properties "
                   "(expected device=%llu label=%@; actual device=%llu label=%@)",
                  static_cast<unsigned long long>(device.registryID),
                  expected_label ?: @"<nil>",
                  static_cast<unsigned long long>(
                      residency_set.device.registryID),
                  residency_set.label ?: @"<nil>"]));
        }
        raw = allocate_handle(residency_set, Handle_kind::Residency_set);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text("residency sets require macOS 15"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_residency_set_counts(value raw) {
  CAMLparam1(raw);
  CAMLlocal4(count, all_count, counts, result);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw, Handle_kind::Residency_set);
        const std::uint64_t allocation_count = residency_set.allocationCount;
        NSArray<id<MTLAllocation>> *all_allocations =
            residency_set.allAllocations;
        const std::uint64_t array_count = all_allocations.count;
        if (allocation_count > static_cast<std::uint64_t>(INT64_MAX) ||
            array_count > static_cast<std::uint64_t>(INT64_MAX)) {
          CAMLreturn(result_error_text(
              "residency allocation count exceeds OCaml int64"));
        }
        count = caml_copy_int64(static_cast<std::int64_t>(allocation_count));
        all_count = caml_copy_int64(static_cast<std::int64_t>(array_count));
        counts = caml_alloc_tuple(2);
        Store_field(counts, 0, count);
        Store_field(counts, 1, all_count);
        result = result_ok(counts);
        CAMLreturn(result);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_residency_set_add_allocation(
    value raw_set, value raw_allocation) {
  CAMLparam2(raw_set, raw_allocation);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw_set, Handle_kind::Residency_set);
        [residency_set addAllocation:allocation_of_handle(raw_allocation)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_residency_set_add_allocations(
    value raw_set, value raw_allocations) {
  CAMLparam2(raw_set, raw_allocations);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw_set, Handle_kind::Residency_set);
        auto allocations = allocations_of_array(raw_allocations);
        [residency_set addAllocations:allocations.data()
                                count:allocations.size()];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_residency_set_remove_allocation(
    value raw_set, value raw_allocation) {
  CAMLparam2(raw_set, raw_allocation);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw_set, Handle_kind::Residency_set);
        [residency_set removeAllocation:allocation_of_handle(raw_allocation)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_residency_set_remove_allocations(
    value raw_set, value raw_allocations) {
  CAMLparam2(raw_set, raw_allocations);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw_set, Handle_kind::Residency_set);
        auto allocations = allocations_of_array(raw_allocations);
        [residency_set removeAllocations:allocations.data()
                                   count:allocations.size()];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_texture_create(
    value raw_device, value raw_descriptor, value raw_label) {
  CAMLparam3(raw_device, raw_descriptor, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    MTLTextureDescriptor *descriptor = texture_descriptor(raw_descriptor);
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    if (texture == nil) {
      CAMLreturn(result_error_text("Metal rejected the texture descriptor"));
    }
    if (Is_block(raw_label)) {
      NSString *label = string_from_ocaml(Field(raw_label, 0));
      if (label == nil) {
        CAMLreturn(result_error_text("texture label is not valid UTF-8"));
      }
      texture.label = label;
    }
    raw = allocate_handle(texture, Handle_kind::Texture);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_texture_info(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  id<MTLTexture> texture = object_of_handle(raw, Handle_kind::Texture);
  const MTLTextureSwizzleChannels swizzle = texture.swizzle;
  result = caml_alloc(18, 0);
  Store_field(result, 0, Val_long(texture.textureType));
  Store_field(result, 1, Val_long(texture.pixelFormat));
  Store_field(result, 2, Val_long(texture.width));
  Store_field(result, 3, Val_long(texture.height));
  Store_field(result, 4, Val_long(texture.depth));
  Store_field(result, 5, Val_long(texture.mipmapLevelCount));
  Store_field(result, 6, Val_long(texture.sampleCount));
  Store_field(result, 7, Val_long(texture.arrayLength));
  Store_field(result, 8, Val_long(texture.usage));
  Store_field(result, 9, Val_long(texture.storageMode));
  Store_field(result, 10, Val_long(texture.cpuCacheMode));
  Store_field(result, 11, Val_long(texture.hazardTrackingMode));
  Store_field(result, 12, Val_bool(texture.allowGPUOptimizedContents));
  Store_field(result, 13, Val_long(texture.compressionType));
  Store_field(result, 14, Val_long(swizzle.red));
  Store_field(result, 15, Val_long(swizzle.green));
  Store_field(result, 16, Val_long(swizzle.blue));
  Store_field(result, 17, Val_long(swizzle.alpha));
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_texture_is_sparse(value raw) {
  CAMLparam1(raw);
  id<MTLTexture> texture = object_of_handle(raw, Handle_kind::Texture);
  CAMLreturn(Val_bool(texture_is_sparse_resource(texture)));
}

extern "C" CAMLprim value caml_prismel_metal_texture_sparse_info(
    value raw_device, value raw_texture, value raw_page_size) {
  CAMLparam3(raw_device, raw_texture, raw_page_size);
  CAMLlocal3(result, info, item);
  @autoreleasepool {
    @try {
      id<MTLDevice> device =
          object_of_handle(raw_device, Handle_kind::Device);
      id<MTLTexture> texture =
          object_of_handle(raw_texture, Handle_kind::Texture);
      const int page_size = Int_val(raw_page_size);
      if (!texture_is_sparse_resource(texture)) {
        CAMLreturn(result_error_text("texture is not sparse"));
      }
      if (!valid_sparse_page_size(page_size)) {
        CAMLreturn(result_error_text("invalid sparse page size"));
      }
      if (texture.device.registryID != device.registryID) {
        CAMLreturn(result_error_text(
            "sparse texture belongs to a different device"));
      }
      const auto sparse_page_size =
          static_cast<MTLSparsePageSize>(page_size);
      const MTLSize tile = [device
          sparseTileSizeWithTextureType:texture.textureType
                              pixelFormat:texture.pixelFormat
                              sampleCount:texture.sampleCount
                           sparsePageSize:sparse_page_size];
      const NSUInteger tile_bytes = [device
          sparseTileSizeInBytesForSparsePageSize:sparse_page_size];
      const NSUInteger first_tail = texture.firstMipmapInTail;
      const NSUInteger tail_bytes = texture.tailSizeInBytes;
      if (tile.width == 0 || tile.height == 0 || tile.depth == 0 ||
          tile_bytes == 0 ||
          tile.width > static_cast<NSUInteger>(INT64_MAX) ||
          tile.height > static_cast<NSUInteger>(INT64_MAX) ||
          tile.depth > static_cast<NSUInteger>(INT64_MAX) ||
          tile_bytes > static_cast<NSUInteger>(INT64_MAX) ||
          tail_bytes > static_cast<NSUInteger>(INT64_MAX)) {
        CAMLreturn(result_error_text(
            "Metal returned malformed sparse texture properties"));
      }
      info = caml_alloc(6, 0);
      item = caml_copy_int64(static_cast<std::int64_t>(tile.width));
      Store_field(info, 0, item);
      item = caml_copy_int64(static_cast<std::int64_t>(tile.height));
      Store_field(info, 1, item);
      item = caml_copy_int64(static_cast<std::int64_t>(tile.depth));
      Store_field(info, 2, item);
      item = caml_copy_int64(static_cast<std::int64_t>(tile_bytes));
      Store_field(info, 3, item);
      item = caml_copy_int64(
          first_tail > static_cast<NSUInteger>(INT64_MAX)
              ? -1
              : static_cast<std::int64_t>(first_tail));
      Store_field(info, 4, item);
      item = caml_copy_int64(static_cast<std::int64_t>(tail_bytes));
      Store_field(info, 5, item);
      result = result_ok(info);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_texture_is_shareable(value raw) {
  CAMLparam1(raw);
  id<MTLTexture> texture = object_of_handle(raw, Handle_kind::Texture);
  CAMLreturn(Val_bool(texture.shareable));
}

extern "C" CAMLprim value caml_prismel_metal_texture_write(
    value raw, value raw_transfer, value source) {
  CAMLparam3(raw, raw_transfer, source);
  id<MTLTexture> texture = object_of_handle(raw, Handle_kind::Texture);
  MTLRegion region{};
  NSUInteger level = 0;
  NSUInteger slice = 0;
  intnat source_offset = 0;
  intnat bytes_per_row = 0;
  intnat bytes_per_image = 0;
  intnat total_bytes = 0;
  if (!texture_transfer_range(texture, raw_transfer, &region, &level, &slice,
                              &source_offset, &bytes_per_row, &bytes_per_image,
                              &total_bytes) ||
      source_offset > static_cast<intnat>(caml_string_length(source)) ||
      total_bytes >
          static_cast<intnat>(caml_string_length(source)) - source_offset ||
      texture.storageMode == MTLStorageModePrivate ||
      texture.textureType == MTLTextureType2DMultisample ||
      texture.textureType == MTLTextureType2DMultisampleArray) {
    CAMLreturn(result_error_text("texture write arguments are invalid"));
  }
  [texture replaceRegion:region
             mipmapLevel:level
                    slice:slice
                withBytes:reinterpret_cast<const std::uint8_t *>(
                              Bytes_val(source)) +
                          source_offset
              bytesPerRow:static_cast<NSUInteger>(bytes_per_row)
            bytesPerImage:static_cast<NSUInteger>(bytes_per_image)];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_texture_read(
    value raw, value raw_transfer) {
  CAMLparam2(raw, raw_transfer);
  CAMLlocal2(bytes, result);
  id<MTLTexture> texture = object_of_handle(raw, Handle_kind::Texture);
  MTLRegion region{};
  NSUInteger level = 0;
  NSUInteger slice = 0;
  intnat ignored_offset = 0;
  intnat bytes_per_row = 0;
  intnat bytes_per_image = 0;
  intnat total_bytes = 0;
  if (!texture_transfer_range(texture, raw_transfer, &region, &level, &slice,
                              &ignored_offset, &bytes_per_row, &bytes_per_image,
                              &total_bytes) ||
      texture.storageMode == MTLStorageModePrivate ||
      texture.textureType == MTLTextureType2DMultisample ||
      texture.textureType == MTLTextureType2DMultisampleArray) {
    CAMLreturn(result_error_text("texture read arguments are invalid"));
  }
  bytes = caml_alloc_string(static_cast<mlsize_t>(total_bytes));
  std::memset(Bytes_val(bytes), 0, static_cast<std::size_t>(total_bytes));
  [texture getBytes:Bytes_val(bytes)
             bytesPerRow:static_cast<NSUInteger>(bytes_per_row)
           bytesPerImage:static_cast<NSUInteger>(bytes_per_image)
             fromRegion:region
            mipmapLevel:level
                   slice:slice];
  result = result_ok(bytes);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_texture_read_into(
    value raw, value raw_transfer, value destination) {
  CAMLparam3(raw, raw_transfer, destination);
  id<MTLTexture> texture = object_of_handle(raw, Handle_kind::Texture);
  MTLRegion region{};
  NSUInteger level = 0;
  NSUInteger slice = 0;
  intnat ignored_offset = 0;
  intnat bytes_per_row = 0;
  intnat bytes_per_image = 0;
  intnat total_bytes = 0;
  if (!texture_transfer_range(texture, raw_transfer, &region, &level, &slice,
                              &ignored_offset, &bytes_per_row, &bytes_per_image,
                              &total_bytes) ||
      total_bytes != static_cast<intnat>(caml_string_length(destination)) ||
      texture.storageMode == MTLStorageModePrivate ||
      texture.textureType == MTLTextureType2DMultisample ||
      texture.textureType == MTLTextureType2DMultisampleArray) {
    CAMLreturn(result_error_text("texture read-into arguments are invalid"));
  }
  [texture getBytes:Bytes_val(destination)
             bytesPerRow:static_cast<NSUInteger>(bytes_per_row)
           bytesPerImage:static_cast<NSUInteger>(bytes_per_image)
             fromRegion:region
            mipmapLevel:level
                   slice:slice];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_texture_create_view(
    value raw_parent, value raw_descriptor, value raw_label) {
  CAMLparam3(raw_parent, raw_descriptor, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLTexture> parent =
          object_of_handle(raw_parent, Handle_kind::Texture);
      const intnat format = Long_val(Field(raw_descriptor, 0));
      const intnat kind = Long_val(Field(raw_descriptor, 1));
      const intnat base_level = Long_val(Field(raw_descriptor, 2));
      const intnat level_count = Long_val(Field(raw_descriptor, 3));
      const intnat base_slice = Long_val(Field(raw_descriptor, 4));
      const intnat slice_count = Long_val(Field(raw_descriptor, 5));
      const MTLTextureSwizzleChannels requested_swizzle =
          texture_swizzle_channels(raw_descriptor, 6);
      const MTLTextureSwizzleChannels effective_swizzle =
          texture_swizzle_channels(raw_descriptor, 10);
      const bool parent_writable =
          (parent.usage &
           (MTLTextureUsageShaderWrite | MTLTextureUsageShaderAtomic)) != 0;
      if (parent_writable &&
          (!texture_swizzles_equal(requested_swizzle,
                                   MTLTextureSwizzleChannelsDefault) ||
           !texture_swizzles_equal(effective_swizzle,
                                   MTLTextureSwizzleChannelsDefault))) {
        CAMLreturn(result_error_text(
            "writable textures cannot create swizzled views"));
      }
      const NSUInteger parent_slices = texture_slice_count(parent);
      if (base_level < 0 || level_count <= 0 || base_slice < 0 ||
          slice_count <= 0 ||
          static_cast<NSUInteger>(base_level) > parent.mipmapLevelCount ||
          static_cast<NSUInteger>(level_count) >
              parent.mipmapLevelCount - static_cast<NSUInteger>(base_level) ||
          static_cast<NSUInteger>(base_slice) > parent_slices ||
          static_cast<NSUInteger>(slice_count) >
              parent_slices - static_cast<NSUInteger>(base_slice)) {
        CAMLreturn(result_error_text("texture view range is invalid"));
      }
      NSString *label = nil;
      if (Is_block(raw_label)) {
        label = string_from_ocaml(Field(raw_label, 0));
        if (label == nil) {
          CAMLreturn(
              result_error_text("texture-view label is not valid UTF-8"));
        }
      }
      id<MTLTexture> view = nil;
      const NSRange levels =
          NSMakeRange(static_cast<NSUInteger>(base_level),
                      static_cast<NSUInteger>(level_count));
      const NSRange slices =
          NSMakeRange(static_cast<NSUInteger>(base_slice),
                      static_cast<NSUInteger>(slice_count));
      if (@available(macOS 26.0, *)) {
        // The descriptor path takes Prismel's already-composed effective
        // swizzle. The deployment-floor constructor receives the requested
        // view-local swizzle and performs its documented parent composition.
        MTLTextureViewDescriptor *descriptor =
            [[MTLTextureViewDescriptor alloc] init];
        descriptor.pixelFormat = static_cast<MTLPixelFormat>(format);
        descriptor.textureType = static_cast<MTLTextureType>(kind);
        descriptor.levelRange = levels;
        descriptor.sliceRange = slices;
        descriptor.swizzle = effective_swizzle;
        if (descriptor.pixelFormat != static_cast<MTLPixelFormat>(format) ||
            descriptor.textureType != static_cast<MTLTextureType>(kind) ||
            !NSEqualRanges(descriptor.levelRange, levels) ||
            !NSEqualRanges(descriptor.sliceRange, slices) ||
            !texture_swizzles_equal(descriptor.swizzle, effective_swizzle)) {
          CAMLreturn(result_error_text(
              "Metal changed the checked texture-view descriptor"));
        }
        view = [parent newTextureViewWithDescriptor:descriptor];
      } else {
        view = [parent
            newTextureViewWithPixelFormat:static_cast<MTLPixelFormat>(format)
                             textureType:static_cast<MTLTextureType>(kind)
                                  levels:levels
                                  slices:slices
                                 swizzle:requested_swizzle];
      }
      if (view == nil) {
        CAMLreturn(result_error_text("Metal rejected the texture view"));
      }
      if (view.parentTexture != parent ||
          view.parentRelativeLevel != static_cast<NSUInteger>(base_level) ||
          view.parentRelativeSlice != static_cast<NSUInteger>(base_slice)) {
        CAMLreturn(result_error_text(
            "Metal changed the checked texture-view parent metadata"));
      }
      if (label != nil) {
        view.label = label;
      }
      raw = allocate_handle(view, Handle_kind::Texture);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_sampler_create(
    value raw_device, value raw_descriptor, value raw_label) {
  CAMLparam3(raw_device, raw_descriptor, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    const intnat anisotropy = Long_val(Field(raw_descriptor, 3));
    const intnat reduction_mode = Long_val(Field(raw_descriptor, 8));
    const double lod_min = Double_val(Field(raw_descriptor, 10));
    const double lod_max = Double_val(Field(raw_descriptor, 11));
    const double lod_bias = Double_val(Field(raw_descriptor, 13));
    const bool sampler_reduction_supported =
        device_supports_sampler_reduction(device);
    if (anisotropy < 1 || anisotropy > 16 || !std::isfinite(lod_min) ||
        !std::isfinite(lod_max) || lod_min < 0.0 || lod_max < lod_min ||
        lod_max > std::numeric_limits<float>::max() ||
        reduction_mode < 0 || reduction_mode > 2 ||
        !std::isfinite(lod_bias) || lod_bias < -16.0 || lod_bias > 15.999) {
      CAMLreturn(result_error_text("sampler descriptor values are invalid"));
    }
    if ((reduction_mode != 0 || lod_bias != 0.0) &&
        !sampler_reduction_supported) {
      CAMLreturn(result_error_text(
          "sampler reduction modes and LOD bias require macOS 26 and Apple "
          "GPU family 10"));
    }
    MTLSamplerDescriptor *descriptor = [[MTLSamplerDescriptor alloc] init];
    descriptor.minFilter = static_cast<MTLSamplerMinMagFilter>(
        Long_val(Field(raw_descriptor, 0)));
    descriptor.magFilter = static_cast<MTLSamplerMinMagFilter>(
        Long_val(Field(raw_descriptor, 1)));
    descriptor.mipFilter =
        static_cast<MTLSamplerMipFilter>(Long_val(Field(raw_descriptor, 2)));
    descriptor.maxAnisotropy = static_cast<NSUInteger>(anisotropy);
    descriptor.sAddressMode =
        static_cast<MTLSamplerAddressMode>(Long_val(Field(raw_descriptor, 4)));
    descriptor.tAddressMode =
        static_cast<MTLSamplerAddressMode>(Long_val(Field(raw_descriptor, 5)));
    descriptor.rAddressMode =
        static_cast<MTLSamplerAddressMode>(Long_val(Field(raw_descriptor, 6)));
    descriptor.borderColor =
        static_cast<MTLSamplerBorderColor>(Long_val(Field(raw_descriptor, 7)));
    descriptor.normalizedCoordinates = Bool_val(Field(raw_descriptor, 9));
    descriptor.lodMinClamp = static_cast<float>(lod_min);
    descriptor.lodMaxClamp = static_cast<float>(lod_max);
    descriptor.lodAverage = Bool_val(Field(raw_descriptor, 12));
    descriptor.compareFunction =
        static_cast<MTLCompareFunction>(Long_val(Field(raw_descriptor, 14)));
    descriptor.supportArgumentBuffers = Bool_val(Field(raw_descriptor, 15));
    if (sampler_reduction_supported) {
      if (@available(macOS 26.0, *)) {
        descriptor.reductionMode =
            static_cast<MTLSamplerReductionMode>(reduction_mode);
        descriptor.lodBias = static_cast<float>(lod_bias);
      }
    }
    NSString *expected_label = nil;
    if (Is_block(raw_label)) {
      expected_label = string_from_ocaml(Field(raw_label, 0));
      if (expected_label == nil) {
        CAMLreturn(result_error_text("sampler label is not valid UTF-8"));
      }
      descriptor.label = expected_label;
    }
    const bool base_descriptor_matches =
        descriptor.minFilter ==
            static_cast<MTLSamplerMinMagFilter>(
                Long_val(Field(raw_descriptor, 0))) &&
        descriptor.magFilter ==
            static_cast<MTLSamplerMinMagFilter>(
                Long_val(Field(raw_descriptor, 1))) &&
        descriptor.mipFilter ==
            static_cast<MTLSamplerMipFilter>(
                Long_val(Field(raw_descriptor, 2))) &&
        descriptor.maxAnisotropy == static_cast<NSUInteger>(anisotropy) &&
        descriptor.sAddressMode ==
            static_cast<MTLSamplerAddressMode>(
                Long_val(Field(raw_descriptor, 4))) &&
        descriptor.tAddressMode ==
            static_cast<MTLSamplerAddressMode>(
                Long_val(Field(raw_descriptor, 5))) &&
        descriptor.rAddressMode ==
            static_cast<MTLSamplerAddressMode>(
                Long_val(Field(raw_descriptor, 6))) &&
        descriptor.borderColor ==
            static_cast<MTLSamplerBorderColor>(
                Long_val(Field(raw_descriptor, 7))) &&
        descriptor.normalizedCoordinates == Bool_val(Field(raw_descriptor, 9)) &&
        descriptor.lodMinClamp == static_cast<float>(lod_min) &&
        descriptor.lodMaxClamp == static_cast<float>(lod_max) &&
        descriptor.lodAverage == Bool_val(Field(raw_descriptor, 12)) &&
        descriptor.compareFunction ==
            static_cast<MTLCompareFunction>(
                Long_val(Field(raw_descriptor, 14))) &&
        descriptor.supportArgumentBuffers == Bool_val(Field(raw_descriptor, 15));
    bool extended_descriptor_matches = true;
    if (sampler_reduction_supported) {
      if (@available(macOS 26.0, *)) {
        extended_descriptor_matches =
            descriptor.reductionMode ==
                static_cast<MTLSamplerReductionMode>(reduction_mode) &&
            descriptor.lodBias == static_cast<float>(lod_bias);
      }
    }
    if (!base_descriptor_matches || !extended_descriptor_matches ||
        ((expected_label == nil) != (descriptor.label == nil)) ||
        (expected_label != nil &&
         ![descriptor.label isEqualToString:expected_label])) {
      CAMLreturn(result_error_text(
          "Metal changed checked sampler descriptor properties"));
    }
    id<MTLSamplerState> sampler =
        [device newSamplerStateWithDescriptor:descriptor];
    if (sampler == nil) {
      CAMLreturn(result_error_text("Metal rejected the sampler descriptor"));
    }
    if (sampler.device.registryID != device.registryID ||
        ((expected_label == nil) != (sampler.label == nil)) ||
        (expected_label != nil &&
         ![sampler.label isEqualToString:expected_label])) {
      CAMLreturn(result_error_text(
          "Metal changed checked sampler creation properties"));
    }
    raw = allocate_handle(sampler, Handle_kind::Sampler);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_depth_stencil_create(
    value raw_device, value raw_descriptor) {
  CAMLparam2(raw_device, raw_descriptor);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      value raw_compare = Field(raw_descriptor, 0);
      value raw_write = Field(raw_descriptor, 1);
      value raw_front = Field(raw_descriptor, 2);
      value raw_back = Field(raw_descriptor, 3);
      value raw_label = Field(raw_descriptor, 4);
      const intnat compare = Long_val(raw_compare);
      if (compare < 0 || compare > 7) {
        CAMLreturn(result_error_text(
            "depth/stencil compare function is invalid"));
      }
      auto stencil_matches = [](value raw_face,
                                MTLStencilDescriptor *face) -> bool {
        if (face == nil) {
          return false;
        }
        const intnat face_compare = Long_val(Field(raw_face, 0));
        const intnat stencil_fail = Long_val(Field(raw_face, 1));
        const intnat depth_fail = Long_val(Field(raw_face, 2));
        const intnat pass = Long_val(Field(raw_face, 3));
        const std::uint32_t read_mask =
            static_cast<std::uint32_t>(Int32_val(Field(raw_face, 4)));
        const std::uint32_t write_mask =
            static_cast<std::uint32_t>(Int32_val(Field(raw_face, 5)));
        return face_compare >= 0 && face_compare <= 7 &&
               stencil_fail >= 0 && stencil_fail <= 7 && depth_fail >= 0 &&
               depth_fail <= 7 && pass >= 0 && pass <= 7 &&
               face.stencilCompareFunction ==
                   static_cast<MTLCompareFunction>(face_compare) &&
               face.stencilFailureOperation ==
                   static_cast<MTLStencilOperation>(stencil_fail) &&
               face.depthFailureOperation ==
                   static_cast<MTLStencilOperation>(depth_fail) &&
               face.depthStencilPassOperation ==
                   static_cast<MTLStencilOperation>(pass) &&
               face.readMask == read_mask && face.writeMask == write_mask;
      };
      auto make_stencil = [&](value raw_face) -> MTLStencilDescriptor * {
        const intnat face_compare = Long_val(Field(raw_face, 0));
        const intnat stencil_fail = Long_val(Field(raw_face, 1));
        const intnat depth_fail = Long_val(Field(raw_face, 2));
        const intnat pass = Long_val(Field(raw_face, 3));
        if (face_compare < 0 || face_compare > 7 || stencil_fail < 0 ||
            stencil_fail > 7 || depth_fail < 0 || depth_fail > 7 || pass < 0 ||
            pass > 7) {
          return nil;
        }
        MTLStencilDescriptor *face = [[MTLStencilDescriptor alloc] init];
        face.stencilCompareFunction =
            static_cast<MTLCompareFunction>(face_compare);
        face.stencilFailureOperation =
            static_cast<MTLStencilOperation>(stencil_fail);
        face.depthFailureOperation =
            static_cast<MTLStencilOperation>(depth_fail);
        face.depthStencilPassOperation =
            static_cast<MTLStencilOperation>(pass);
        face.readMask =
            static_cast<std::uint32_t>(Int32_val(Field(raw_face, 4)));
        face.writeMask =
            static_cast<std::uint32_t>(Int32_val(Field(raw_face, 5)));
        return stencil_matches(raw_face, face) ? face : nil;
      };
      MTLStencilDescriptor *front = nil;
      if (Is_block(raw_front)) {
        front = make_stencil(Field(raw_front, 0));
        if (front == nil) {
          CAMLreturn(result_error_text(
              "front-face stencil descriptor is invalid"));
        }
      }
      MTLStencilDescriptor *back = nil;
      if (Is_block(raw_back)) {
        back = make_stencil(Field(raw_back, 0));
        if (back == nil) {
          CAMLreturn(result_error_text(
              "back-face stencil descriptor is invalid"));
        }
      }
      NSString *expected_label = nil;
      if (Is_block(raw_label)) {
        expected_label = string_from_ocaml(Field(raw_label, 0));
        if (expected_label == nil) {
          CAMLreturn(result_error_text(
              "depth/stencil label is not valid UTF-8"));
        }
      }
      MTLDepthStencilDescriptor *descriptor =
          [[MTLDepthStencilDescriptor alloc] init];
      descriptor.depthCompareFunction =
          static_cast<MTLCompareFunction>(compare);
      descriptor.depthWriteEnabled = Bool_val(raw_write);
      if (front != nil) {
        descriptor.frontFaceStencil = front;
      }
      if (back != nil) {
        descriptor.backFaceStencil = back;
      }
      if (expected_label != nil) {
        descriptor.label = expected_label;
      }
      if (descriptor.depthCompareFunction !=
              static_cast<MTLCompareFunction>(compare) ||
          descriptor.isDepthWriteEnabled != Bool_val(raw_write) ||
          (front != nil &&
           !stencil_matches(Field(raw_front, 0),
                            descriptor.frontFaceStencil)) ||
          (back != nil &&
           !stencil_matches(Field(raw_back, 0), descriptor.backFaceStencil)) ||
          ((expected_label == nil) != (descriptor.label == nil)) ||
          (expected_label != nil &&
           ![descriptor.label isEqualToString:expected_label])) {
        CAMLreturn(result_error_text(
            "Metal changed checked depth/stencil descriptor properties"));
      }
      id<MTLDepthStencilState> state =
          [device newDepthStencilStateWithDescriptor:descriptor];
      if (state == nil || state.device.registryID != device.registryID ||
          ((expected_label == nil) != (state.label == nil)) ||
          (expected_label != nil &&
           ![state.label isEqualToString:expected_label])) {
        CAMLreturn(result_error_text(
            "Metal rejected or changed checked depth/stencil state"));
      }
      raw = allocate_handle(state, Handle_kind::Depth_stencil);
      CAMLreturn(result_ok(raw));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_indirect_command_buffer_create(
    value raw_device, value raw_descriptor, value raw_count,
    value raw_options) {
  CAMLparam4(raw_device, raw_descriptor, raw_count, raw_options);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      NSUInteger count = 0;
      NSUInteger options = 0;
      if (!nsuinteger_from_ocaml_int64(raw_count, &count) || count == 0 ||
          !nsuinteger_from_ocaml_int64(raw_options, &options)) {
        CAMLreturn(result_error_text("invalid indirect command buffer size or options"));
      }
      MTLIndirectCommandBufferDescriptor *descriptor =
          [[MTLIndirectCommandBufferDescriptor alloc] init];
      descriptor.commandTypes = static_cast<MTLIndirectCommandType>(
          Int64_val(Field(raw_descriptor, 0)));
      descriptor.inheritBuffers = Bool_val(Field(raw_descriptor, 1));
      descriptor.inheritPipelineState = Bool_val(Field(raw_descriptor, 2));
      NSUInteger counts[7] = {};
      const int count_fields[7] = {3, 4, 5, 8, 9, 10, 11};
      for (int index = 0; index < 7; ++index) {
        if (!nsuinteger_from_ocaml_int64(Field(raw_descriptor, count_fields[index]),
                                         &counts[index])) {
          CAMLreturn(result_error_text("invalid indirect descriptor binding count"));
        }
      }
      descriptor.maxVertexBufferBindCount = counts[0];
      descriptor.maxFragmentBufferBindCount = counts[1];
      if (@available(macOS 11.0, *)) {
        descriptor.maxKernelBufferBindCount = counts[2];
      } else if (counts[2] != 0) {
        CAMLreturn(result_error_text("indirect compute commands require macOS 11 or newer"));
      }
      if (@available(macOS 13.0, *)) {
        descriptor.supportRayTracing = Bool_val(Field(raw_descriptor, 6));
      } else if (Bool_val(Field(raw_descriptor, 6))) {
        CAMLreturn(result_error_text("indirect ray tracing requires macOS 13 or newer"));
      }
      if (@available(macOS 14.0, *)) {
        descriptor.supportDynamicAttributeStride = Bool_val(Field(raw_descriptor, 7));
        descriptor.maxKernelThreadgroupMemoryBindCount = counts[3];
        descriptor.maxObjectBufferBindCount = counts[4];
        descriptor.maxMeshBufferBindCount = counts[5];
        descriptor.maxObjectThreadgroupMemoryBindCount = counts[6];
      } else if (Bool_val(Field(raw_descriptor, 7)) || counts[3] != 0 ||
                 counts[4] != 0 || counts[5] != 0 || counts[6] != 0) {
        CAMLreturn(result_error_text("advanced indirect commands require macOS 14 or newer"));
      }
      if (@available(macOS 26.0, *)) {
        descriptor.inheritDepthStencilState = Bool_val(Field(raw_descriptor, 12));
        descriptor.inheritDepthBias = Bool_val(Field(raw_descriptor, 13));
        descriptor.inheritDepthClipMode = Bool_val(Field(raw_descriptor, 14));
        descriptor.inheritCullMode = Bool_val(Field(raw_descriptor, 15));
        descriptor.inheritFrontFacingWinding = Bool_val(Field(raw_descriptor, 16));
        descriptor.inheritTriangleFillMode = Bool_val(Field(raw_descriptor, 17));
        descriptor.supportColorAttachmentMapping = Bool_val(Field(raw_descriptor, 18));
      } else if (Bool_val(Field(raw_descriptor, 12)) ||
                 Bool_val(Field(raw_descriptor, 13)) ||
                 Bool_val(Field(raw_descriptor, 14)) ||
                 Bool_val(Field(raw_descriptor, 15)) ||
                 Bool_val(Field(raw_descriptor, 16)) ||
                 Bool_val(Field(raw_descriptor, 17)) ||
                 Bool_val(Field(raw_descriptor, 18))) {
        CAMLreturn(result_error_text("Metal 4 indirect inheritance requires macOS 26 or newer"));
      }
      id<MTLIndirectCommandBuffer> buffer =
          [device newIndirectCommandBufferWithDescriptor:descriptor
                                         maxCommandCount:count
                                                  options:static_cast<MTLResourceOptions>(options)];
      if (buffer == nil || buffer.device.registryID != device.registryID ||
          buffer.size == 0) {
        CAMLreturn(result_error_text("Metal rejected the indirect command buffer descriptor"));
      }
      raw = allocate_handle(buffer, Handle_kind::Indirect_command_buffer);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_indirect_command_buffer_reset(
    value raw, value raw_location, value raw_length) {
  CAMLparam3(raw, raw_location, raw_length);
  @try {
    id<MTLIndirectCommandBuffer> buffer =
        object_of_handle(raw, Handle_kind::Indirect_command_buffer);
    NSUInteger location = 0, length = 0;
    if (!nsuinteger_from_ocaml_int64(raw_location, &location) ||
        !nsuinteger_from_ocaml_int64(raw_length, &length)) {
      CAMLreturn(result_error_text("invalid indirect command reset range"));
    }
    [buffer resetWithRange:NSMakeRange(location, length)];
  } @catch (NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_indirect_render_command(
    value raw, value raw_index) {
  CAMLparam2(raw, raw_index);
  CAMLlocal1(command_raw);
  @try {
    NSUInteger index = 0;
    if (!nsuinteger_from_ocaml_int64(raw_index, &index))
      CAMLreturn(result_error_text("invalid indirect render command index"));
    id<MTLIndirectCommandBuffer> buffer =
        object_of_handle(raw, Handle_kind::Indirect_command_buffer);
    id<MTLIndirectRenderCommand> command = [buffer indirectRenderCommandAtIndex:index];
    if (command == nil) CAMLreturn(result_error_text("Metal returned no indirect render command"));
    command_raw = allocate_handle(command, Handle_kind::Indirect_render_command);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  CAMLreturn(result_ok(command_raw));
}

#define PRISMEL_ICB_COMMAND0(name, kind, selector) \
extern "C" CAMLprim value name(value raw) { CAMLparam1(raw); @try { \
  id command = object_of_handle(raw, kind); [command selector]; \
} @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
CAMLreturn(result_unit()); }

extern "C" CAMLprim value caml_prismel_metal_indirect_render_command_set_pipeline(value raw, value raw_pipeline) {
  CAMLparam2(raw, raw_pipeline); @try {
    id<MTLIndirectRenderCommand> command = object_of_handle(raw, Handle_kind::Indirect_render_command);
    id<MTLRenderPipelineState> pipeline = object_of_handle(raw_pipeline, Handle_kind::Render_pipeline);
    [command setRenderPipelineState:pipeline];
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  CAMLreturn(result_unit());
}

static value indirect_set_buffer(value raw, value raw_buffer, value raw_offset,
                                 value raw_index, bool fragment, bool compute) {
  CAMLparam4(raw, raw_buffer, raw_offset, raw_index);
  @try {
    NSUInteger offset = 0; const intnat index = Long_val(raw_index);
    if (!nsuinteger_from_ocaml_int64(raw_offset, &offset) || index < 0)
      CAMLreturn(result_error_text("invalid indirect buffer binding"));
    id<MTLBuffer> buffer = object_of_handle(raw_buffer, Handle_kind::Buffer);
    if (compute) {
      id<MTLIndirectComputeCommand> command = object_of_handle(raw, Handle_kind::Indirect_compute_command);
      [command setKernelBuffer:buffer offset:offset atIndex:static_cast<NSUInteger>(index)];
    } else {
      id<MTLIndirectRenderCommand> command = object_of_handle(raw, Handle_kind::Indirect_render_command);
      if (fragment) [command setFragmentBuffer:buffer offset:offset atIndex:static_cast<NSUInteger>(index)];
      else [command setVertexBuffer:buffer offset:offset atIndex:static_cast<NSUInteger>(index)];
    }
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_indirect_render_command_set_vertex_buffer(value a,value b,value c,value d) { return indirect_set_buffer(a,b,c,d,false,false); }
extern "C" CAMLprim value caml_prismel_metal_indirect_render_command_set_fragment_buffer(value a,value b,value c,value d) { return indirect_set_buffer(a,b,c,d,true,false); }

extern "C" CAMLprim value caml_prismel_metal_indirect_render_command_draw_primitives(
    value raw, value raw_primitive, value raw_start, value raw_count,
    value raw_instances, value raw_base_instance) {
  CAMLparam5(raw, raw_primitive, raw_start, raw_count, raw_instances);
  CAMLxparam1(raw_base_instance);
  @try {
    NSUInteger start=0,count=0,instances=0,base=0;
    if (!nsuinteger_from_ocaml_int64(raw_start,&start) || !nsuinteger_from_ocaml_int64(raw_count,&count) ||
        !nsuinteger_from_ocaml_int64(raw_instances,&instances) || !nsuinteger_from_ocaml_int64(raw_base_instance,&base))
      CAMLreturn(result_error_text("invalid indirect draw range"));
    id<MTLIndirectRenderCommand> command=object_of_handle(raw,Handle_kind::Indirect_render_command);
    [command drawPrimitives:static_cast<MTLPrimitiveType>(Long_val(raw_primitive)) vertexStart:start vertexCount:count instanceCount:instances baseInstance:base];
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  CAMLreturn(result_unit());
}
extern "C" CAMLprim value caml_prismel_metal_indirect_render_command_draw_primitives_bytecode(value *argv,int argn) {
  (void)argn; return caml_prismel_metal_indirect_render_command_draw_primitives(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5]);
}

extern "C" CAMLprim value caml_prismel_metal_library_compile(
    value raw_device, value raw_source, value raw_label) {
  CAMLparam3(raw_device, raw_source, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      NSString *source = string_from_ocaml(raw_source);
      if (source == nil) {
        CAMLreturn(result_error_text("Metal source is not valid UTF-8"));
      }
      NSString *expected_label = nil;
      if (Is_block(raw_label)) {
        expected_label = string_from_ocaml(Field(raw_label, 0));
        if (expected_label == nil) {
          CAMLreturn(result_error_text("Metal library label is not valid UTF-8"));
        }
      }
      MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
      options.fastMathEnabled = NO;
      NSError *error = nil;
      id<MTLLibrary> library = [device newLibraryWithSource:source
                                                    options:options
                                                      error:&error];
      if (library == nil) {
        CAMLreturn(result_error(labeled_error_description(
            expected_label, error,
            @"Metal source compilation failed without NSError")));
      }
      library.label = expected_label;
      if (library.device.registryID != device.registryID ||
          ((expected_label == nil) != (library.label == nil)) ||
          (expected_label != nil &&
           ![library.label isEqualToString:expected_label])) {
        CAMLreturn(result_error_text(
            "Metal changed checked library creation properties"));
      }
      raw = allocate_handle(library, Handle_kind::Library);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_library_compile_descriptor(
    value raw_device, value raw_source, value raw_descriptor) {
  CAMLparam3(raw_device, raw_source, raw_descriptor);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      NSString *source = string_from_ocaml(raw_source);
      if (source == nil) {
        CAMLreturn(result_error_text("Metal source is not valid UTF-8"));
      }
      NSString *expected_label = nil;
      value raw_label = Field(raw_descriptor, 0);
      if (Is_block(raw_label)) {
        expected_label = string_from_ocaml(Field(raw_label, 0));
        if (expected_label == nil) {
          CAMLreturn(result_error_text("Metal library label is not valid UTF-8"));
        }
      }
      const intnat library_type_code = Long_val(Field(raw_descriptor, 1));
      if (library_type_code != 0 && library_type_code != 1) {
        CAMLreturn(result_error_text("Metal library type is invalid"));
      }
      const MTLLibraryType library_type =
          static_cast<MTLLibraryType>(library_type_code);
      NSString *expected_install_name = nil;
      value raw_install_name = Field(raw_descriptor, 2);
      if (Is_block(raw_install_name)) {
        expected_install_name =
            string_from_ocaml(Field(raw_install_name, 0));
        if (expected_install_name == nil) {
          CAMLreturn(result_error_text(
              "Metal library install name is not valid UTF-8"));
        }
      }
      if ((library_type == MTLLibraryTypeDynamic) !=
          (expected_install_name != nil)) {
        CAMLreturn(result_error_text(
            "Metal dynamic library type and install name disagree"));
      }
      std::vector<id<MTLDynamicLibrary>> linked_libraries =
          dynamic_libraries_of_array(Field(raw_descriptor, 3));
      NSMutableArray<id<MTLDynamicLibrary>> *linked_array =
          [NSMutableArray arrayWithCapacity:linked_libraries.size()];
      NSMutableSet<NSString *> *install_names = [NSMutableSet set];
      for (id<MTLDynamicLibrary> linked : linked_libraries) {
        if (linked.device.registryID != device.registryID ||
            linked.installName == nil ||
            [install_names containsObject:linked.installName]) {
          CAMLreturn(result_error_text(
              "Metal linked dynamic library is incompatible or duplicated"));
        }
        [install_names addObject:linked.installName];
        [linked_array addObject:linked];
      }
      MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
      options.fastMathEnabled = NO;
      options.libraryType = library_type;
      options.installName = expected_install_name;
      options.libraries = linked_array.count == 0 ? nil : linked_array;
      if (options.libraryType != library_type ||
          ((expected_install_name == nil) != (options.installName == nil)) ||
          (expected_install_name != nil &&
           ![options.installName isEqualToString:expected_install_name]) ||
          options.libraries.count != linked_array.count) {
        CAMLreturn(result_error_text(
            "Metal changed checked library compile options"));
      }
      NSError *error = nil;
      id<MTLLibrary> library = [device newLibraryWithSource:source
                                                    options:options
                                                      error:&error];
      if (library == nil) {
        CAMLreturn(result_error(labeled_error_description(
            expected_label, error,
            @"Metal source compilation failed without NSError")));
      }
      library.label = expected_label;
      if (library.device.registryID != device.registryID ||
          library.type != library_type ||
          (library_type == MTLLibraryTypeDynamic &&
           (((expected_install_name == nil) != (library.installName == nil)) ||
            (expected_install_name != nil &&
             ![library.installName isEqualToString:expected_install_name]))) ||
          ((expected_label == nil) != (library.label == nil)) ||
          (expected_label != nil &&
           ![library.label isEqualToString:expected_label])) {
        CAMLreturn(result_error_text(
            "Metal changed checked library compilation properties"));
      }
      raw = allocate_handle(library, Handle_kind::Library);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_library_kind(value raw) {
  CAMLparam1(raw);
  id<MTLLibrary> library = object_of_handle(raw, Handle_kind::Library);
  CAMLreturn(Val_long(static_cast<intnat>(library.type)));
}

extern "C" CAMLprim value caml_prismel_metal_library_function_names(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal2(array, name);
  @autoreleasepool {
    id<MTLLibrary> library = object_of_handle(raw, Handle_kind::Library);
    NSArray<NSString *> *names = library.functionNames;
    if (names.count > static_cast<NSUInteger>(Max_wosize)) {
      caml_failwith("Metal library function-name list exceeds OCaml limits");
    }
    array = caml_alloc(static_cast<mlsize_t>(names.count), 0);
    for (NSUInteger index = 0; index < names.count; ++index) {
      name = caml_copy_string(names[index].UTF8String ?: "");
      Store_field(array, static_cast<mlsize_t>(index), name);
    }
  }
  CAMLreturn(array);
}

extern "C" CAMLprim value caml_prismel_metal_function_find(
    value raw_library, value raw_name) {
  CAMLparam2(raw_library, raw_name);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLLibrary> library = object_of_handle(raw_library, Handle_kind::Library);
    NSString *name = string_from_ocaml(raw_name);
    if (name == nil) {
      CAMLreturn(result_error_text("Metal function name is not valid UTF-8"));
    }
    id<MTLFunction> function = [library newFunctionWithName:name];
    if (function == nil) {
      CAMLreturn(result_error(
          [NSString stringWithFormat:@"Metal library has no function named %@", name]));
    }
    if (function.device.registryID != library.device.registryID ||
        ![function.name isEqualToString:name]) {
      CAMLreturn(result_error_text(
          "Metal changed checked function lookup properties"));
    }
    raw = allocate_handle(function, Handle_kind::Function);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_function_name(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLFunction> function = object_of_handle(raw, Handle_kind::Function);
    result = caml_copy_string(function.name.UTF8String ?: "");
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_function_kind(value raw) {
  CAMLparam1(raw);
  id<MTLFunction> function = object_of_handle(raw, Handle_kind::Function);
  CAMLreturn(Val_long(static_cast<intnat>(function.functionType)));
}

extern "C" CAMLprim value caml_prismel_metal_function_specialize(
    value raw_library, value raw_name, value raw_constants, value raw_label) {
  CAMLparam4(raw_library, raw_name, raw_constants, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLLibrary> library =
          object_of_handle(raw_library, Handle_kind::Library);
      NSString *name = string_from_ocaml(raw_name);
      if (name == nil) {
        CAMLreturn(result_error_text("Metal function name is not valid UTF-8"));
      }
      NSString *expected_label = nil;
      if (Is_block(raw_label)) {
        expected_label = string_from_ocaml(Field(raw_label, 0));
        if (expected_label == nil) {
          CAMLreturn(result_error_text(
              "Metal function label is not valid UTF-8"));
        }
      }
      MTLFunctionConstantValues *constant_values =
          [[MTLFunctionConstantValues alloc] init];
      NSMutableSet<NSString *> *names = [NSMutableSet set];
      const mlsize_t count = Wosize_val(raw_constants);
      for (mlsize_t index = 0; index < count; ++index) {
        value raw_constant = Field(raw_constants, index);
        NSString *constant_name = string_from_ocaml(Field(raw_constant, 0));
        if (constant_name == nil) {
          CAMLreturn(result_error_text(
              "Metal function-constant name is not valid UTF-8"));
        }
        if ([names containsObject:constant_name]) {
          CAMLreturn(result_error_text(
              "Metal function-constant list contains a duplicate name"));
        }
        [names addObject:constant_name];
        const intnat tag = Long_val(Field(raw_constant, 1));
        const std::int64_t integral = Int64_val(Field(raw_constant, 2));
        const double floating = Double_val(Field(raw_constant, 3));
        switch (tag) {
        case 0: {
          const bool constant = integral != 0;
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeBool
                                   withName:constant_name];
          break;
        }
        case 1: {
          const std::int8_t constant = static_cast<std::int8_t>(integral);
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeChar
                                   withName:constant_name];
          break;
        }
        case 2: {
          const std::uint8_t constant = static_cast<std::uint8_t>(integral);
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeUChar
                                   withName:constant_name];
          break;
        }
        case 3: {
          const std::int16_t constant = static_cast<std::int16_t>(integral);
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeShort
                                   withName:constant_name];
          break;
        }
        case 4: {
          const std::uint16_t constant = static_cast<std::uint16_t>(integral);
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeUShort
                                   withName:constant_name];
          break;
        }
        case 5: {
          const std::int32_t constant = static_cast<std::int32_t>(integral);
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeInt
                                   withName:constant_name];
          break;
        }
        case 6: {
          const std::uint32_t constant = static_cast<std::uint32_t>(integral);
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeUInt
                                   withName:constant_name];
          break;
        }
        case 7: {
          const std::int64_t constant = integral;
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeLong
                                   withName:constant_name];
          break;
        }
        case 8: {
          const std::uint64_t constant =
              static_cast<std::uint64_t>(integral);
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeULong
                                   withName:constant_name];
          break;
        }
        case 9: {
          const _Float16 constant = static_cast<_Float16>(floating);
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeHalf
                                   withName:constant_name];
          break;
        }
        case 10: {
          const float constant = static_cast<float>(floating);
          [constant_values setConstantValue:&constant
                                       type:MTLDataTypeFloat
                                   withName:constant_name];
          break;
        }
        default:
          CAMLreturn(result_error_text(
              "Metal function-constant type tag is invalid"));
        }
      }
      NSError *error = nil;
      id<MTLFunction> function =
          [library newFunctionWithName:name
                        constantValues:constant_values
                                 error:&error];
      if (function == nil) {
        CAMLreturn(result_error(labeled_error_description(
            expected_label ?: name, error,
            @"Metal function specialization failed without NSError")));
      }
      function.label = expected_label;
      if (function.device.registryID != library.device.registryID ||
          ![function.name isEqualToString:name] ||
          ((expected_label == nil) != (function.label == nil)) ||
          (expected_label != nil &&
           ![function.label isEqualToString:expected_label])) {
        CAMLreturn(result_error_text(
            "Metal changed checked function specialization properties"));
      }
      raw = allocate_handle(function, Handle_kind::Function);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_dynamic_library_create(
    value raw_device, value raw_library, value raw_label) {
  CAMLparam3(raw_device, raw_library, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      id<MTLLibrary> library =
          object_of_handle(raw_library, Handle_kind::Library);
      if (!device.supportsDynamicLibraries ||
          library.device.registryID != device.registryID ||
          library.type != MTLLibraryTypeDynamic || library.installName == nil) {
        CAMLreturn(result_error_text(
            "Metal dynamic-library source is incompatible with the device"));
      }
      NSString *expected_label = nil;
      if (Is_block(raw_label)) {
        expected_label = string_from_ocaml(Field(raw_label, 0));
        if (expected_label == nil) {
          CAMLreturn(result_error_text(
              "Metal dynamic-library label is not valid UTF-8"));
        }
      }
      NSError *error = nil;
      id<MTLDynamicLibrary> dynamic_library =
          [device newDynamicLibrary:library error:&error];
      if (dynamic_library == nil) {
        CAMLreturn(result_error(labeled_error_description(
            expected_label ?: library.installName, error,
            @"Metal dynamic-library creation failed without NSError")));
      }
      dynamic_library.label = expected_label;
      if (dynamic_library.device.registryID != device.registryID ||
          dynamic_library.installName == nil ||
          ![dynamic_library.installName isEqualToString:library.installName] ||
          ((expected_label == nil) != (dynamic_library.label == nil)) ||
          (expected_label != nil &&
           ![dynamic_library.label isEqualToString:expected_label])) {
        CAMLreturn(result_error_text(
            "Metal changed checked dynamic-library creation properties"));
      }
      raw = allocate_handle(dynamic_library, Handle_kind::Dynamic_library);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_dynamic_library_load_file(
    value raw_device, value raw_path, value raw_label) {
  CAMLparam3(raw_device, raw_path, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      if (!device.supportsDynamicLibraries) {
        CAMLreturn(result_error_text(
            "Metal device does not support dynamic libraries"));
      }
      NSString *path = string_from_ocaml(raw_path);
      if (!valid_absolute_path(path)) {
        CAMLreturn(result_error_text(
            "Metal dynamic-library path must be a nonempty absolute UTF-8 path"));
      }
      NSString *expected_label = nil;
      if (Is_block(raw_label)) {
        expected_label = string_from_ocaml(Field(raw_label, 0));
        if (expected_label == nil) {
          CAMLreturn(result_error_text(
              "Metal dynamic-library label is not valid UTF-8"));
        }
      }
      NSError *error = nil;
      id<MTLDynamicLibrary> dynamic_library =
          [device newDynamicLibraryWithURL:[NSURL fileURLWithPath:path]
                                     error:&error];
      if (dynamic_library == nil) {
        CAMLreturn(result_error(labeled_error_description(
            expected_label ?: path.lastPathComponent, error,
            @"Metal dynamic-library loading failed without NSError")));
      }
      dynamic_library.label = expected_label;
      if (dynamic_library.device.registryID != device.registryID ||
          dynamic_library.installName == nil ||
          ((expected_label == nil) != (dynamic_library.label == nil)) ||
          (expected_label != nil &&
           ![dynamic_library.label isEqualToString:expected_label])) {
        CAMLreturn(result_error_text(
            "Metal changed checked loaded dynamic-library properties"));
      }
      raw = allocate_handle(dynamic_library, Handle_kind::Dynamic_library);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_dynamic_library_install_name(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLDynamicLibrary> library =
        object_of_handle(raw, Handle_kind::Dynamic_library);
    result = caml_copy_string(library.installName.UTF8String ?: "");
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_dynamic_library_serialize(
    value raw, value raw_path) {
  CAMLparam2(raw, raw_path);
  @autoreleasepool {
    @try {
      id<MTLDynamicLibrary> library =
          object_of_handle(raw, Handle_kind::Dynamic_library);
      NSString *path = string_from_ocaml(raw_path);
      if (!valid_absolute_path(path)) {
        CAMLreturn(result_error_text(
            "Metal dynamic-library path must be a nonempty absolute UTF-8 path"));
      }
      NSError *error = nil;
      if (![library serializeToURL:[NSURL fileURLWithPath:path] error:&error]) {
        CAMLreturn(result_error(labeled_error_description(
            library.label ?: library.installName, error,
            @"Metal dynamic-library serialization failed without NSError")));
      }
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(Val_unit));
}

extern "C" CAMLprim value caml_prismel_metal_binary_archive_create(
    value raw_device, value raw_path, value raw_label) {
  CAMLparam3(raw_device, raw_path, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      NSString *path = nil;
      if (Is_block(raw_path)) {
        path = string_from_ocaml(Field(raw_path, 0));
        if (!valid_absolute_path(path)) {
          CAMLreturn(result_error_text(
              "Metal binary-archive path must be a nonempty absolute UTF-8 path"));
        }
      }
      NSString *expected_label = nil;
      if (Is_block(raw_label)) {
        expected_label = string_from_ocaml(Field(raw_label, 0));
        if (expected_label == nil) {
          CAMLreturn(result_error_text(
              "Metal binary-archive label is not valid UTF-8"));
        }
      }
      MTLBinaryArchiveDescriptor *descriptor =
          [[MTLBinaryArchiveDescriptor alloc] init];
      descriptor.url = path == nil ? nil : [NSURL fileURLWithPath:path];
      if ((path == nil) != (descriptor.url == nil)) {
        CAMLreturn(result_error_text(
            "Metal changed checked binary-archive descriptor properties"));
      }
      NSError *error = nil;
      id<MTLBinaryArchive> archive =
          [device newBinaryArchiveWithDescriptor:descriptor error:&error];
      if (archive == nil) {
        CAMLreturn(result_error(labeled_error_description(
            expected_label ?: path.lastPathComponent, error,
            @"Metal binary-archive creation failed without NSError")));
      }
      archive.label = expected_label;
      if (archive.device.registryID != device.registryID ||
          ((expected_label == nil) != (archive.label == nil)) ||
          (expected_label != nil &&
           ![archive.label isEqualToString:expected_label])) {
        CAMLreturn(result_error_text(
            "Metal changed checked binary-archive creation properties"));
      }
      raw = allocate_handle(archive, Handle_kind::Binary_archive);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_binary_archive_add_compute(
    value raw_archive, value raw_function, value raw_linked_functions,
    value raw_preloaded_libraries) {
  CAMLparam4(raw_archive, raw_function, raw_linked_functions,
             raw_preloaded_libraries);
  @autoreleasepool {
    @try {
      id<MTLBinaryArchive> archive =
          object_of_handle(raw_archive, Handle_kind::Binary_archive);
      id<MTLFunction> function =
          object_of_handle(raw_function, Handle_kind::Function);
      if (function.device.registryID != archive.device.registryID ||
          function.functionType != MTLFunctionTypeKernel) {
        CAMLreturn(result_error_text(
            "Metal archive compute function is incompatible"));
      }
      std::vector<id<MTLFunction>> linked_functions =
          functions_of_array(raw_linked_functions);
      if (!linked_functions.empty() &&
          !archive.device.supportsFunctionPointers) {
        CAMLreturn(result_error_text(
            "Metal archive linked functions are unsupported by the device"));
      }
      NSMutableArray<id<MTLFunction>> *linked_array =
          [NSMutableArray arrayWithCapacity:linked_functions.size()];
      NSMutableSet<NSString *> *linked_names = [NSMutableSet set];
      for (id<MTLFunction> linked : linked_functions) {
        if (linked.device.registryID != archive.device.registryID ||
            linked.functionType != MTLFunctionTypeVisible ||
            [linked_names containsObject:linked.name]) {
          CAMLreturn(result_error_text(
              "Metal archive linked function is incompatible or duplicated"));
        }
        [linked_names addObject:linked.name];
        [linked_array addObject:linked];
      }
      MTLComputePipelineDescriptor *descriptor =
          [[MTLComputePipelineDescriptor alloc] init];
      descriptor.computeFunction = function;
      if (linked_array.count != 0) {
        MTLLinkedFunctions *linked = [MTLLinkedFunctions linkedFunctions];
        linked.functions = linked_array;
        descriptor.linkedFunctions = linked;
      }
      std::vector<id<MTLDynamicLibrary>> preloaded_libraries =
          dynamic_libraries_of_array(raw_preloaded_libraries);
      if (!preloaded_libraries.empty() &&
          !archive.device.supportsDynamicLibraries) {
        CAMLreturn(result_error_text(
            "Metal archive dynamic libraries are unsupported by the device"));
      }
      NSMutableArray<id<MTLDynamicLibrary>> *preloaded_array =
          [NSMutableArray arrayWithCapacity:preloaded_libraries.size()];
      NSMutableSet<NSString *> *install_names = [NSMutableSet set];
      for (id<MTLDynamicLibrary> library : preloaded_libraries) {
        if (library.device.registryID != archive.device.registryID ||
            library.installName == nil ||
            [install_names containsObject:library.installName]) {
          CAMLreturn(result_error_text(
              "Metal archive dynamic library is incompatible or duplicated"));
        }
        [install_names addObject:library.installName];
        [preloaded_array addObject:library];
      }
      descriptor.preloadedLibraries = preloaded_array;
      NSError *error = nil;
      if (![archive addComputePipelineFunctionsWithDescriptor:descriptor
                                                        error:&error]) {
        CAMLreturn(result_error(labeled_error_description(
            archive.label, error,
            @"Metal binary-archive insertion failed without NSError")));
      }
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(Val_unit));
}

extern "C" CAMLprim value caml_prismel_metal_binary_archive_serialize(
    value raw, value raw_path) {
  CAMLparam2(raw, raw_path);
  @autoreleasepool {
    @try {
      id<MTLBinaryArchive> archive =
          object_of_handle(raw, Handle_kind::Binary_archive);
      NSString *path = string_from_ocaml(raw_path);
      if (!valid_absolute_path(path)) {
        CAMLreturn(result_error_text(
            "Metal binary-archive path must be a nonempty absolute UTF-8 path"));
      }
      NSError *error = nil;
      if (![archive serializeToURL:[NSURL fileURLWithPath:path] error:&error]) {
        CAMLreturn(result_error(labeled_error_description(
            archive.label ?: path.lastPathComponent, error,
            @"Metal binary-archive serialization failed without NSError")));
      }
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(Val_unit));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_create(
    value raw_device, value raw_dataset, value raw_label) {
  CAMLparam3(raw_device, raw_dataset, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTLDevice> device =
            object_of_handle(raw_device, Handle_kind::Device);
        if (!device_supports_metal4_compiler(device)) {
          CAMLreturn(result_error_text(
              "Metal 4 compilers are unsupported by the device"));
        }
        id<MTL4PipelineDataSetSerializer> expected_dataset = nil;
        if (Is_block(raw_dataset)) {
          expected_dataset = object_of_handle(Field(raw_dataset, 0),
                                              Handle_kind::Pipeline_dataset);
        }
        NSString *expected_label = nil;
        if (Is_block(raw_label)) {
          expected_label = string_from_ocaml(Field(raw_label, 0));
          if (expected_label == nil) {
            CAMLreturn(result_error_text(
                "Metal compiler label is not valid UTF-8"));
          }
        }
        MTL4CompilerDescriptor *descriptor =
            [[MTL4CompilerDescriptor alloc] init];
        if (expected_label != nil) {
          descriptor.label = expected_label;
        }
        descriptor.pipelineDataSetSerializer = expected_dataset;
        if (((expected_label == nil) != (descriptor.label == nil)) ||
            (expected_label != nil &&
             ![descriptor.label isEqualToString:expected_label]) ||
            descriptor.pipelineDataSetSerializer != expected_dataset) {
          CAMLreturn(result_error_text(
              "Metal changed checked compiler descriptor properties"));
        }
        NSError *error = nil;
        id<MTL4Compiler> compiler =
            [device newCompilerWithDescriptor:descriptor error:&error];
        if (compiler == nil) {
          CAMLreturn(result_error(labeled_error_description(
              expected_label, error,
              @"Metal compiler creation failed without NSError")));
        }
        if (compiler.device.registryID != device.registryID) {
          CAMLreturn(result_error_text(
              "Metal changed the checked compiler device"));
        }
        if ((expected_label == nil && compiler.label != nil) ||
            (expected_label != nil && compiler.label != nil &&
             ![compiler.label isEqualToString:expected_label])) {
          CAMLreturn(result_error_text(
              "Metal changed the checked compiler label"));
        }
        if (compiler.pipelineDataSetSerializer != expected_dataset) {
          CAMLreturn(result_error_text(
              "Metal changed the checked compiler pipeline dataset"));
        }
        raw = allocate_handle(compiler, Handle_kind::Compiler);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 compilers require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

API_AVAILABLE(macos(26.0))
PrismelMetalCheckedComputeRequest *checked_compute_request(
    value raw_descriptor, id<MTL4Compiler> compiler,
    NSString *__autoreleasing *failure) {
  id<MTLLibrary> library =
      object_of_handle(Field(raw_descriptor, 1), Handle_kind::Library);
  if (library.device.registryID != compiler.device.registryID) {
    *failure = @"Metal 4 compute library is incompatible with the compiler";
    return nil;
  }
  NSString *expected_label = nil;
  value raw_label = Field(raw_descriptor, 0);
  if (Is_block(raw_label)) {
    expected_label = string_from_ocaml(Field(raw_label, 0));
    if (expected_label == nil) {
      *failure = @"Metal 4 compute-pipeline label is not valid UTF-8";
      return nil;
    }
  }
  NSString *function_name = string_from_ocaml(Field(raw_descriptor, 2));
  if (function_name == nil || function_name.length == 0) {
    *failure = @"Metal 4 compute function name is not valid nonempty UTF-8";
    return nil;
  }
  if (![library.functionNames containsObject:function_name]) {
    *failure = @"Metal 4 compute function is absent from the source library";
    return nil;
  }
  NSUInteger max_total_threads = 0;
  NSUInteger required_width = 0;
  NSUInteger required_height = 0;
  NSUInteger required_depth = 0;
  NSUInteger max_call_stack_depth = 0;
  if (!nsuinteger_from_ocaml_int64(Field(raw_descriptor, 5),
                                   &max_total_threads) ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 6),
                                   &required_width) ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 7),
                                   &required_height) ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 8),
                                   &required_depth) ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 12),
                                   &max_call_stack_depth)) {
    *failure = @"Metal 4 compute descriptor contains an invalid cardinality";
    return nil;
  }
  const bool no_required_threads = required_width == 0 &&
                                   required_height == 0 &&
                                   required_depth == 0;
  if (!no_required_threads &&
      (required_width == 0 || required_height == 0 || required_depth == 0 ||
       required_width > NSUIntegerMax / required_height ||
       required_width * required_height > NSUIntegerMax / required_depth ||
       (max_total_threads != 0 &&
        required_width * required_height * required_depth !=
            max_total_threads))) {
    *failure = @"Metal 4 required threadgroup dimensions are invalid";
    return nil;
  }
  std::vector<id<MTLDynamicLibrary>> preloaded_libraries =
      dynamic_libraries_of_array(Field(raw_descriptor, 11));
  NSMutableArray<id<MTLDynamicLibrary>> *preloaded_array =
      [NSMutableArray arrayWithCapacity:preloaded_libraries.size()];
  NSMutableSet<NSString *> *install_names = [NSMutableSet set];
  for (id<MTLDynamicLibrary> dynamic_library : preloaded_libraries) {
    if (!compiler.device.supportsDynamicLibraries ||
        dynamic_library.device.registryID != compiler.device.registryID ||
        dynamic_library.installName == nil ||
        [install_names containsObject:dynamic_library.installName]) {
      *failure =
          @"Metal 4 preloaded dynamic library is incompatible or duplicated";
      return nil;
    }
    [install_names addObject:dynamic_library.installName];
    [preloaded_array addObject:dynamic_library];
  }
  std::vector<id<MTL4BinaryFunction>> binary_functions =
      binary_functions_of_array(Field(raw_descriptor, 14));
  NSMutableArray<id<MTL4BinaryFunction>> *binary_function_array =
      [NSMutableArray arrayWithCapacity:binary_functions.size()];
  NSMutableSet<id<MTL4BinaryFunction>> *binary_function_set =
      [NSMutableSet set];
  for (id<MTL4BinaryFunction> function : binary_functions) {
    if (!compiler.device.supportsFunctionPointers ||
        [binary_function_set containsObject:function]) {
      *failure =
          @"Metal 4 binary linked function is incompatible or duplicated";
      return nil;
    }
    [binary_function_set addObject:function];
    [binary_function_array addObject:function];
  }
  if ((preloaded_array.count != 0 || binary_function_array.count != 0) &&
      max_call_stack_depth == 0) {
    *failure = @"Metal 4 dynamic linking requires a positive call-stack depth";
    return nil;
  }
  MTL4LibraryFunctionDescriptor *function_descriptor =
      [[MTL4LibraryFunctionDescriptor alloc] init];
  function_descriptor.name = function_name;
  function_descriptor.library = library;
  MTL4ComputePipelineDescriptor *descriptor =
      [[MTL4ComputePipelineDescriptor alloc] init];
  value raw_static_linking = Field(raw_descriptor, 15);
  NSString *static_linking_failure = nil;
  MTL4StaticLinkingDescriptor *static_linking =
      checked_static_linking_descriptor(
          raw_static_linking, compiler.device,
          compiler.device.supportsFunctionPointers, &static_linking_failure);
  if (Is_block(raw_static_linking) && static_linking == nil) {
    *failure = static_linking_failure;
    return nil;
  }
  if (expected_label != nil) {
    descriptor.label = expected_label;
  }
  descriptor.computeFunctionDescriptor = function_descriptor;
  descriptor.staticLinkingDescriptor = static_linking;
  const bool threadgroup_size_multiple = Bool_val(Field(raw_descriptor, 4));
  const bool support_binary_linking = Bool_val(Field(raw_descriptor, 9));
  const auto indirect_command_support =
      Bool_val(Field(raw_descriptor, 10))
          ? MTL4IndirectCommandBufferSupportStateEnabled
          : MTL4IndirectCommandBufferSupportStateDisabled;
  descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth =
      threadgroup_size_multiple;
  descriptor.maxTotalThreadsPerThreadgroup = max_total_threads;
  descriptor.requiredThreadsPerThreadgroup =
      MTLSizeMake(required_width, required_height, required_depth);
  descriptor.supportBinaryLinking = support_binary_linking;
  descriptor.supportIndirectCommandBuffers = indirect_command_support;
  const bool reflection_requested = Bool_val(Field(raw_descriptor, 3));
  const MTL4ShaderReflection expected_reflection =
      MTL4ShaderReflectionBindingInfo | MTL4ShaderReflectionBufferTypeInfo;
  if (reflection_requested) {
    MTL4PipelineOptions *options = [[MTL4PipelineOptions alloc] init];
    options.shaderReflection = expected_reflection;
    descriptor.options = options;
  }
  MTL4PipelineStageDynamicLinkingDescriptor *dynamic_linking = nil;
  if (preloaded_array.count != 0 || binary_function_array.count != 0 ||
      max_call_stack_depth != 0) {
    dynamic_linking =
        [[MTL4PipelineStageDynamicLinkingDescriptor alloc] init];
    dynamic_linking.maxCallStackDepth = max_call_stack_depth;
    dynamic_linking.binaryLinkedFunctions = binary_function_array;
    dynamic_linking.preloadedLibraries = preloaded_array;
  }
  NSString *task_options_failure = nil;
  MTL4CompilerTaskOptions *task_options =
      checked_pipeline_task_options(Field(raw_descriptor, 13), @"compute",
                                    &task_options_failure);
  if (task_options_failure != nil) {
    *failure = task_options_failure;
    return nil;
  }
  MTL4FunctionDescriptor *stored_function = descriptor.computeFunctionDescriptor;
  if (![stored_function isKindOfClass:[MTL4LibraryFunctionDescriptor class]]) {
    *failure = @"Metal changed the Metal 4 compute function descriptor type";
    return nil;
  }
  MTL4LibraryFunctionDescriptor *stored_library_function =
      static_cast<MTL4LibraryFunctionDescriptor *>(stored_function);
  if (stored_library_function.library != library ||
      ![stored_library_function.name isEqualToString:function_name] ||
      ((expected_label == nil) != (descriptor.label == nil)) ||
      (expected_label != nil &&
       ![descriptor.label isEqualToString:expected_label]) ||
      descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth !=
          threadgroup_size_multiple ||
      descriptor.maxTotalThreadsPerThreadgroup != max_total_threads ||
      descriptor.requiredThreadsPerThreadgroup.width != required_width ||
      descriptor.requiredThreadsPerThreadgroup.height != required_height ||
      descriptor.requiredThreadsPerThreadgroup.depth != required_depth ||
      descriptor.supportBinaryLinking != support_binary_linking ||
      descriptor.supportIndirectCommandBuffers != indirect_command_support ||
      (static_linking == nil && descriptor.staticLinkingDescriptor != nil &&
       (descriptor.staticLinkingDescriptor.functionDescriptors.count != 0 ||
        descriptor.staticLinkingDescriptor.privateFunctionDescriptors.count !=
            0 ||
        descriptor.staticLinkingDescriptor.groups.count != 0)) ||
      (static_linking != nil &&
       (descriptor.staticLinkingDescriptor == nil ||
        descriptor.staticLinkingDescriptor.functionDescriptors.count !=
            static_linking.functionDescriptors.count ||
        descriptor.staticLinkingDescriptor.privateFunctionDescriptors.count !=
            static_linking.privateFunctionDescriptors.count ||
        descriptor.staticLinkingDescriptor.groups.count !=
            static_linking.groups.count)) ||
      (reflection_requested &&
       (descriptor.options == nil ||
        descriptor.options.shaderReflection != expected_reflection)) ||
      (!reflection_requested && descriptor.options != nil) ||
      (dynamic_linking != nil &&
       (dynamic_linking.maxCallStackDepth != max_call_stack_depth ||
        dynamic_linking.binaryLinkedFunctions.count !=
            binary_function_array.count ||
        dynamic_linking.preloadedLibraries.count != preloaded_array.count))) {
    *failure = @"Metal changed checked Metal 4 compute descriptor properties";
    return nil;
  }
  PrismelMetalCheckedComputeRequest *request =
      [[PrismelMetalCheckedComputeRequest alloc] init];
  request.descriptor = descriptor;
  request.dynamicLinking = dynamic_linking;
  request.taskOptions = task_options;
  request.label = expected_label;
  request.reflectionRequested = reflection_requested;
  return request;
}

API_AVAILABLE(macos(26.0))
MTL4LibraryFunctionDescriptor *checked_pipeline_function_descriptor(
    id<MTLLibrary> library, NSString *name,
    std::initializer_list<MTLFunctionType> expected_types, NSString *stage,
    NSString *__autoreleasing *failure) {
  if (name == nil || name.length == 0 ||
      ![library.functionNames containsObject:name]) {
    *failure = [NSString
        stringWithFormat:@"Metal 4 %@ function is absent from the source library",
                         stage];
    return nil;
  }
  id<MTLFunction> function = [library newFunctionWithName:name];
  bool function_type_matches = false;
  if (function != nil) {
    for (MTLFunctionType expected_type : expected_types) {
      function_type_matches =
          function_type_matches || function.functionType == expected_type;
    }
  }
  if (!function_type_matches) {
    *failure =
        [NSString stringWithFormat:@"Metal 4 %@ function has the wrong stage",
                                   stage];
    return nil;
  }
  MTL4LibraryFunctionDescriptor *descriptor =
      [[MTL4LibraryFunctionDescriptor alloc] init];
  descriptor.library = library;
  descriptor.name = name;
  if (descriptor.library != library ||
      ![descriptor.name isEqualToString:name]) {
    *failure = [NSString
        stringWithFormat:@"Metal changed the checked %@ function descriptor",
                         stage];
    return nil;
  }
  return descriptor;
}

API_AVAILABLE(macos(26.0))
bool checked_stored_render_function(
    MTL4FunctionDescriptor *stored,
    MTL4LibraryFunctionDescriptor *expected, id<MTLLibrary> library,
    NSString *name, NSString *stage,
    NSString *__autoreleasing *failure) {
  if (expected == nil) {
    if (stored != nil) {
      *failure = [NSString
          stringWithFormat:@"Metal changed the absent %@ function descriptor",
                           stage];
      return false;
    }
    return true;
  }
  if (![stored isKindOfClass:[MTL4LibraryFunctionDescriptor class]]) {
    *failure = [NSString
        stringWithFormat:@"Metal changed the checked %@ function descriptor",
                         stage];
    return false;
  }
  MTL4LibraryFunctionDescriptor *stored_library =
      static_cast<MTL4LibraryFunctionDescriptor *>(stored);
  if (stored_library.library != library ||
      ![stored_library.name isEqualToString:name]) {
    *failure = [NSString
        stringWithFormat:@"Metal changed checked Metal 4 %@ function properties",
                         stage];
    return false;
  }
  return true;
}

API_AVAILABLE(macos(26.0))
NSUInteger checked_vertex_format_size(intnat format) {
  switch (format) {
  case MTLVertexFormatUChar:
  case MTLVertexFormatChar:
  case MTLVertexFormatUCharNormalized:
  case MTLVertexFormatCharNormalized:
    return 1;
  case MTLVertexFormatUChar2:
  case MTLVertexFormatChar2:
  case MTLVertexFormatUChar2Normalized:
  case MTLVertexFormatChar2Normalized:
  case MTLVertexFormatUShort:
  case MTLVertexFormatShort:
  case MTLVertexFormatUShortNormalized:
  case MTLVertexFormatShortNormalized:
  case MTLVertexFormatHalf:
    return 2;
  case MTLVertexFormatUChar3:
  case MTLVertexFormatChar3:
  case MTLVertexFormatUChar3Normalized:
  case MTLVertexFormatChar3Normalized:
    return 3;
  case MTLVertexFormatUChar4:
  case MTLVertexFormatChar4:
  case MTLVertexFormatUChar4Normalized:
  case MTLVertexFormatChar4Normalized:
  case MTLVertexFormatUShort2:
  case MTLVertexFormatShort2:
  case MTLVertexFormatUShort2Normalized:
  case MTLVertexFormatShort2Normalized:
  case MTLVertexFormatHalf2:
  case MTLVertexFormatFloat:
  case MTLVertexFormatInt:
  case MTLVertexFormatUInt:
  case MTLVertexFormatInt1010102Normalized:
  case MTLVertexFormatUInt1010102Normalized:
  case MTLVertexFormatUChar4Normalized_BGRA:
  case MTLVertexFormatFloatRG11B10:
  case MTLVertexFormatFloatRGB9E5:
    return 4;
  case MTLVertexFormatUShort3:
  case MTLVertexFormatShort3:
  case MTLVertexFormatUShort3Normalized:
  case MTLVertexFormatShort3Normalized:
  case MTLVertexFormatHalf3:
    return 6;
  case MTLVertexFormatUShort4:
  case MTLVertexFormatShort4:
  case MTLVertexFormatUShort4Normalized:
  case MTLVertexFormatShort4Normalized:
  case MTLVertexFormatHalf4:
  case MTLVertexFormatFloat2:
  case MTLVertexFormatInt2:
  case MTLVertexFormatUInt2:
    return 8;
  case MTLVertexFormatFloat3:
  case MTLVertexFormatInt3:
  case MTLVertexFormatUInt3:
    return 12;
  case MTLVertexFormatFloat4:
  case MTLVertexFormatInt4:
  case MTLVertexFormatUInt4:
    return 16;
  default:
    return 0;
  }
}

API_AVAILABLE(macos(26.0))
bool configure_render_vertex_descriptor(
    MTL4RenderPipelineDescriptor *pipeline, value raw_vertex_descriptor,
    NSString *__autoreleasing *failure) {
  if (!Is_block(raw_vertex_descriptor)) {
    return true;
  }
  value raw_descriptor = Field(raw_vertex_descriptor, 0);
  value raw_attributes = Field(raw_descriptor, 0);
  value raw_layouts = Field(raw_descriptor, 1);
  const mlsize_t attribute_count = Wosize_val(raw_attributes);
  const mlsize_t layout_count = Wosize_val(raw_layouts);
  if (attribute_count == 0 || attribute_count > 31 || layout_count == 0 ||
      layout_count > 31) {
    *failure = @"Metal 4 vertex descriptor cardinality is invalid";
    return false;
  }
  std::array<bool, 31> attribute_present{};
  std::array<bool, 31> layout_present{};
  std::array<bool, 31> layout_used{};
  std::array<bool, 31> layout_dynamic{};
  std::array<NSUInteger, 31> layout_strides{};
  MTLVertexDescriptor *descriptor = [MTLVertexDescriptor vertexDescriptor];
  [descriptor reset];
  for (mlsize_t index = 0; index < layout_count; ++index) {
    value raw_layout = Field(raw_layouts, index);
    const intnat buffer_index = Long_val(Field(raw_layout, 0));
    value raw_stride = Field(raw_layout, 1);
    const intnat step_function = Long_val(Field(raw_layout, 2));
    NSUInteger step_rate = 0;
    if (buffer_index < 0 || buffer_index >= 31 ||
        layout_present[static_cast<std::size_t>(buffer_index)] ||
        step_function < 0 || step_function > 4 ||
        !nsuinteger_from_ocaml_int64(Field(raw_layout, 3), &step_rate) ||
        step_rate == 0) {
      *failure = @"Metal 4 vertex buffer layout is invalid";
      return false;
    }
    NSUInteger stride = MTLBufferLayoutStrideDynamic;
    const bool dynamic = !Is_block(raw_stride);
    if (!dynamic &&
        (!nsuinteger_from_ocaml_int64(Field(raw_stride, 0), &stride) ||
         (stride == 0 &&
          step_function !=
              static_cast<intnat>(MTLVertexStepFunctionConstant)))) {
      *failure = @"Metal 4 vertex buffer stride is invalid";
      return false;
    }
    MTLVertexBufferLayoutDescriptor *layout =
        [[MTLVertexBufferLayoutDescriptor alloc] init];
    layout.stride = stride;
    layout.stepFunction = static_cast<MTLVertexStepFunction>(step_function);
    layout.stepRate = step_rate;
    [descriptor.layouts setObject:layout
                 atIndexedSubscript:static_cast<NSUInteger>(buffer_index)];
    const std::size_t slot = static_cast<std::size_t>(buffer_index);
    layout_present[slot] = true;
    layout_dynamic[slot] = dynamic;
    layout_strides[slot] = stride;
  }
  for (mlsize_t index = 0; index < attribute_count; ++index) {
    value raw_attribute = Field(raw_attributes, index);
    const intnat attribute_index = Long_val(Field(raw_attribute, 0));
    const intnat format = Long_val(Field(raw_attribute, 1));
    NSUInteger offset = 0;
    const intnat buffer_index = Long_val(Field(raw_attribute, 3));
    const NSUInteger format_size = checked_vertex_format_size(format);
    if (attribute_index < 0 || attribute_index >= 31 ||
        attribute_present[static_cast<std::size_t>(attribute_index)] ||
        buffer_index < 0 || buffer_index >= 31 ||
        !layout_present[static_cast<std::size_t>(buffer_index)] ||
        format_size == 0 ||
        !nsuinteger_from_ocaml_int64(Field(raw_attribute, 2), &offset) ||
        offset > std::numeric_limits<NSUInteger>::max() - format_size) {
      *failure = @"Metal 4 vertex attribute is invalid";
      return false;
    }
    const std::size_t layout_slot = static_cast<std::size_t>(buffer_index);
    if (!layout_dynamic[layout_slot] && layout_strides[layout_slot] != 0 &&
        offset + format_size > layout_strides[layout_slot]) {
      *failure = @"Metal 4 vertex attribute exceeds its static stride";
      return false;
    }
    MTLVertexAttributeDescriptor *attribute =
        [[MTLVertexAttributeDescriptor alloc] init];
    attribute.format = static_cast<MTLVertexFormat>(format);
    attribute.offset = offset;
    attribute.bufferIndex = static_cast<NSUInteger>(buffer_index);
    [descriptor.attributes setObject:attribute
                    atIndexedSubscript:static_cast<NSUInteger>(attribute_index)];
    attribute_present[static_cast<std::size_t>(attribute_index)] = true;
    layout_used[layout_slot] = true;
  }
  for (std::size_t index = 0; index < layout_present.size(); ++index) {
    if (layout_present[index] && !layout_used[index]) {
      *failure = @"Metal 4 vertex buffer layout has no attribute";
      return false;
    }
  }
  pipeline.vertexDescriptor = descriptor;
  const MTLVertexDescriptor *stored = pipeline.vertexDescriptor;
  if (stored == nil) {
    *failure = @"Metal discarded the checked render vertex descriptor";
    return false;
  }
  for (mlsize_t index = 0; index < layout_count; ++index) {
    value raw_layout = Field(raw_layouts, index);
    const NSUInteger buffer_index =
        static_cast<NSUInteger>(Long_val(Field(raw_layout, 0)));
    value raw_stride = Field(raw_layout, 1);
    const NSUInteger expected_stride = Is_block(raw_stride)
        ? static_cast<NSUInteger>(Int64_val(Field(raw_stride, 0)))
        : MTLBufferLayoutStrideDynamic;
    const MTLVertexBufferLayoutDescriptor *layout =
        [stored.layouts objectAtIndexedSubscript:buffer_index];
    if (layout.stride != expected_stride ||
        layout.stepFunction != static_cast<MTLVertexStepFunction>(
                                   Long_val(Field(raw_layout, 2))) ||
        layout.stepRate !=
            static_cast<NSUInteger>(Int64_val(Field(raw_layout, 3)))) {
      *failure = @"Metal changed checked render vertex buffer properties";
      return false;
    }
  }
  for (mlsize_t index = 0; index < attribute_count; ++index) {
    value raw_attribute = Field(raw_attributes, index);
    const NSUInteger attribute_index =
        static_cast<NSUInteger>(Long_val(Field(raw_attribute, 0)));
    const MTLVertexAttributeDescriptor *attribute =
        [stored.attributes objectAtIndexedSubscript:attribute_index];
    if (attribute.format != static_cast<MTLVertexFormat>(
                                Long_val(Field(raw_attribute, 1))) ||
        attribute.offset !=
            static_cast<NSUInteger>(Int64_val(Field(raw_attribute, 2))) ||
        attribute.bufferIndex !=
            static_cast<NSUInteger>(Long_val(Field(raw_attribute, 3)))) {
      *failure = @"Metal changed checked render vertex attribute properties";
      return false;
    }
  }
  return true;
}

API_AVAILABLE(macos(26.0))
bool configure_render_color_attachments(
    MTL4RenderPipelineColorAttachmentDescriptorArray *attachments,
    value raw_attachments, bool rasterization_enabled,
    NSString *__autoreleasing *failure) {
  const mlsize_t attachment_count = Wosize_val(raw_attachments);
  if ((rasterization_enabled && attachment_count == 0) ||
      (!rasterization_enabled && attachment_count != 0) ||
      attachment_count > 8) {
    *failure = @"Metal 4 render color-attachment count is invalid";
    return false;
  }
  for (mlsize_t index = 0; index < attachment_count; ++index) {
    value raw_attachment = Field(raw_attachments, index);
    const intnat pixel_format = Long_val(Field(raw_attachment, 0));
    const intnat blending_state = Long_val(Field(raw_attachment, 1));
    const intnat source_rgb = Long_val(Field(raw_attachment, 2));
    const intnat destination_rgb = Long_val(Field(raw_attachment, 3));
    const intnat rgb_operation = Long_val(Field(raw_attachment, 4));
    const intnat source_alpha = Long_val(Field(raw_attachment, 5));
    const intnat destination_alpha = Long_val(Field(raw_attachment, 6));
    const intnat alpha_operation = Long_val(Field(raw_attachment, 7));
    const intnat write_mask = Long_val(Field(raw_attachment, 8));
    if (pixel_format <= static_cast<intnat>(MTLPixelFormatInvalid) ||
        blending_state < 0 || blending_state > 1 || source_rgb < 0 ||
        source_rgb > 18 || destination_rgb < 0 || destination_rgb > 18 ||
        rgb_operation < 0 || rgb_operation > 4 || source_alpha < 0 ||
        source_alpha > 18 || destination_alpha < 0 ||
        destination_alpha > 18 || alpha_operation < 0 ||
        alpha_operation > 4 || write_mask < 0 || (write_mask & ~15) != 0) {
      *failure = @"Metal 4 render color-attachment state is invalid";
      return false;
    }
    MTL4RenderPipelineColorAttachmentDescriptor *attachment =
        [[MTL4RenderPipelineColorAttachmentDescriptor alloc] init];
    attachment.pixelFormat = static_cast<MTLPixelFormat>(pixel_format);
    attachment.blendingState = static_cast<MTL4BlendState>(blending_state);
    attachment.sourceRGBBlendFactor =
        static_cast<MTLBlendFactor>(source_rgb);
    attachment.destinationRGBBlendFactor =
        static_cast<MTLBlendFactor>(destination_rgb);
    attachment.rgbBlendOperation =
        static_cast<MTLBlendOperation>(rgb_operation);
    attachment.sourceAlphaBlendFactor =
        static_cast<MTLBlendFactor>(source_alpha);
    attachment.destinationAlphaBlendFactor =
        static_cast<MTLBlendFactor>(destination_alpha);
    attachment.alphaBlendOperation =
        static_cast<MTLBlendOperation>(alpha_operation);
    attachment.writeMask = static_cast<MTLColorWriteMask>(write_mask);
    [attachments setObject:attachment atIndexedSubscript:index];
  }
  for (mlsize_t index = 0; index < attachment_count; ++index) {
    value raw_attachment = Field(raw_attachments, index);
    const MTL4RenderPipelineColorAttachmentDescriptor *attachment =
        [attachments objectAtIndexedSubscript:index];
    if (attachment.pixelFormat !=
            static_cast<MTLPixelFormat>(
                Long_val(Field(raw_attachment, 0))) ||
        attachment.blendingState !=
            static_cast<MTL4BlendState>(
                Long_val(Field(raw_attachment, 1))) ||
        attachment.sourceRGBBlendFactor !=
            static_cast<MTLBlendFactor>(
                Long_val(Field(raw_attachment, 2))) ||
        attachment.destinationRGBBlendFactor !=
            static_cast<MTLBlendFactor>(
                Long_val(Field(raw_attachment, 3))) ||
        attachment.rgbBlendOperation !=
            static_cast<MTLBlendOperation>(
                Long_val(Field(raw_attachment, 4))) ||
        attachment.sourceAlphaBlendFactor !=
            static_cast<MTLBlendFactor>(
                Long_val(Field(raw_attachment, 5))) ||
        attachment.destinationAlphaBlendFactor !=
            static_cast<MTLBlendFactor>(
                Long_val(Field(raw_attachment, 6))) ||
        attachment.alphaBlendOperation !=
            static_cast<MTLBlendOperation>(
                Long_val(Field(raw_attachment, 7))) ||
        attachment.writeMask !=
            static_cast<MTLColorWriteMask>(
                Long_val(Field(raw_attachment, 8)))) {
      *failure = @"Metal changed checked render color-attachment properties";
      return false;
    }
  }
  return true;
}

API_AVAILABLE(macos(26.0))
bool configure_tile_color_attachments(
    MTLTileRenderPipelineColorAttachmentDescriptorArray *attachments,
    value raw_formats, NSString *__autoreleasing *failure) {
  const mlsize_t format_count = Wosize_val(raw_formats);
  if (format_count > 8) {
    *failure = @"Metal 4 tile color-attachment count is invalid";
    return false;
  }
  for (mlsize_t index = 0; index < format_count; ++index) {
    const intnat code = Long_val(Field(raw_formats, index));
    if (code <= static_cast<intnat>(MTLPixelFormatInvalid)) {
      *failure = @"Metal 4 tile color format is invalid";
      return false;
    }
    MTLTileRenderPipelineColorAttachmentDescriptor *attachment =
        [[MTLTileRenderPipelineColorAttachmentDescriptor alloc] init];
    attachment.pixelFormat = static_cast<MTLPixelFormat>(code);
    [attachments setObject:attachment atIndexedSubscript:index];
  }
  for (mlsize_t index = 0; index < format_count; ++index) {
    const MTLTileRenderPipelineColorAttachmentDescriptor *attachment =
        [attachments objectAtIndexedSubscript:index];
    if (attachment.pixelFormat !=
        static_cast<MTLPixelFormat>(Long_val(Field(raw_formats, index)))) {
      *failure = @"Metal changed checked tile color-attachment properties";
      return false;
    }
  }
  return true;
}

bool checked_threadgroup_size(value raw_width, value raw_height,
                              value raw_depth, NSUInteger maximum,
                              NSString *stage, MTLSize *result,
                              NSString *__autoreleasing *failure) {
  NSUInteger width = 0;
  NSUInteger height = 0;
  NSUInteger depth = 0;
  if (!nsuinteger_from_ocaml_int64(raw_width, &width) ||
      !nsuinteger_from_ocaml_int64(raw_height, &height) ||
      !nsuinteger_from_ocaml_int64(raw_depth, &depth)) {
    *failure = [NSString
        stringWithFormat:@"Metal 4 %@ threadgroup size is out of range", stage];
    return false;
  }
  const bool disabled = width == 0 && height == 0 && depth == 0;
  if (!disabled && (width == 0 || height == 0 || depth == 0)) {
    *failure = [NSString
        stringWithFormat:@"Metal 4 %@ threadgroup size is incomplete", stage];
    return false;
  }
  if (!disabled) {
    if (width > std::numeric_limits<NSUInteger>::max() / height ||
        width * height > std::numeric_limits<NSUInteger>::max() / depth) {
      *failure = [NSString
          stringWithFormat:@"Metal 4 %@ threadgroup size overflows", stage];
      return false;
    }
    const NSUInteger cardinality = width * height * depth;
    if (maximum != 0 && cardinality != maximum) {
      *failure = [NSString
          stringWithFormat:@"Metal 4 %@ threadgroup size disagrees with its maximum",
                           stage];
      return false;
    }
  }
  *result = MTLSizeMake(width, height, depth);
  return true;
}

API_AVAILABLE(macos(26.0))
bool configure_render_stage_dynamic_linking(
    MTL4PipelineStageDynamicLinkingDescriptor *descriptor,
    value raw_linking, id<MTLDevice> device, bool support_binary_linking,
    NSString *stage, NSString *__autoreleasing *failure) {
  if (!Is_block(raw_linking)) {
    return true;
  }
  value raw_descriptor = Field(raw_linking, 0);
  NSUInteger max_call_stack_depth = 0;
  if (!nsuinteger_from_ocaml_int64(Field(raw_descriptor, 0),
                                   &max_call_stack_depth) ||
      max_call_stack_depth == 0) {
    *failure = [NSString
        stringWithFormat:@"Metal 4 %@ dynamic-link depth is invalid", stage];
    return false;
  }
  std::vector<id<MTL4BinaryFunction>> binary_functions =
      binary_functions_of_array(Field(raw_descriptor, 1));
  if (!binary_functions.empty() && !support_binary_linking) {
    *failure = [NSString
        stringWithFormat:@"Metal 4 %@ binary linking is disabled", stage];
    return false;
  }
  NSMutableArray<id<MTL4BinaryFunction>> *binary_array =
      [NSMutableArray arrayWithCapacity:binary_functions.size()];
  NSMutableSet<id<MTL4BinaryFunction>> *binary_set = [NSMutableSet set];
  for (id<MTL4BinaryFunction> function : binary_functions) {
    if (!device.supportsFunctionPointersFromRender ||
        [binary_set containsObject:function]) {
      *failure = [NSString
          stringWithFormat:@"Metal 4 %@ binary function is incompatible or duplicated",
                           stage];
      return false;
    }
    [binary_set addObject:function];
    [binary_array addObject:function];
  }
  std::vector<id<MTLDynamicLibrary>> preloaded_libraries =
      dynamic_libraries_of_array(Field(raw_descriptor, 2));
  NSMutableArray<id<MTLDynamicLibrary>> *preloaded_array =
      [NSMutableArray arrayWithCapacity:preloaded_libraries.size()];
  NSMutableSet<NSString *> *install_names = [NSMutableSet set];
  for (id<MTLDynamicLibrary> library : preloaded_libraries) {
    if (!device.supportsDynamicLibraries ||
        library.device.registryID != device.registryID ||
        library.installName == nil ||
        [install_names containsObject:library.installName]) {
      *failure = [NSString
          stringWithFormat:@"Metal 4 %@ preloaded library is incompatible or duplicated",
                           stage];
      return false;
    }
    [install_names addObject:library.installName];
    [preloaded_array addObject:library];
  }
  descriptor.maxCallStackDepth = max_call_stack_depth;
  descriptor.binaryLinkedFunctions = binary_array;
  descriptor.preloadedLibraries = preloaded_array;
  if (descriptor.maxCallStackDepth != max_call_stack_depth ||
      descriptor.binaryLinkedFunctions.count != binary_array.count ||
      descriptor.preloadedLibraries.count != preloaded_array.count) {
    *failure = [NSString
        stringWithFormat:@"Metal changed checked %@ dynamic-link properties",
                         stage];
    return false;
  }
  for (NSUInteger index = 0; index < binary_array.count; ++index) {
    if (descriptor.binaryLinkedFunctions[index] != binary_array[index]) {
      *failure = [NSString
          stringWithFormat:@"Metal changed checked %@ binary function identity",
                           stage];
      return false;
    }
  }
  for (NSUInteger index = 0; index < preloaded_array.count; ++index) {
    if (descriptor.preloadedLibraries[index] != preloaded_array[index]) {
      *failure = [NSString
          stringWithFormat:@"Metal changed checked %@ preloaded library identity",
                           stage];
      return false;
    }
  }
  return true;
}

API_AVAILABLE(macos(26.0))
MTL4RenderPipelineDynamicLinkingDescriptor *
new_checked_render_dynamic_linking_descriptor(
    NSString *__autoreleasing *failure) {
  MTL4RenderPipelineDynamicLinkingDescriptor *descriptor =
      [[MTL4RenderPipelineDynamicLinkingDescriptor alloc] init];
  if (descriptor.vertexLinkingDescriptor == nil ||
      descriptor.fragmentLinkingDescriptor == nil ||
      descriptor.tileLinkingDescriptor == nil ||
      descriptor.objectLinkingDescriptor == nil ||
      descriptor.meshLinkingDescriptor == nil) {
    *failure = @"Metal returned incomplete render dynamic-link descriptors";
    return nil;
  }
  return descriptor;
}

API_AVAILABLE(macos(26.0))
bool poison_checked_render_attachment_copy(
    MTL4RenderPipelineColorAttachmentDescriptorArray *attachments,
    NSString *__autoreleasing *failure) {
  MTL4RenderPipelineColorAttachmentDescriptor *source =
      [[MTL4RenderPipelineColorAttachmentDescriptor alloc] init];
  source.pixelFormat = MTLPixelFormatRGBA8Unorm;
  source.blendingState = MTL4BlendStateEnabled;
  source.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
  source.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  source.rgbBlendOperation = MTLBlendOperationReverseSubtract;
  source.sourceAlphaBlendFactor = MTLBlendFactorDestinationAlpha;
  source.destinationAlphaBlendFactor = MTLBlendFactorOneMinusDestinationAlpha;
  source.alphaBlendOperation = MTLBlendOperationMax;
  source.writeMask = MTLColorWriteMaskRed | MTLColorWriteMaskAlpha;
  [attachments setObject:source atIndexedSubscript:0];
  source.pixelFormat = MTLPixelFormatBGRA8Unorm;
  source.blendingState = MTL4BlendStateDisabled;
  MTL4RenderPipelineColorAttachmentDescriptor *stored =
      [attachments objectAtIndexedSubscript:0];
  if (stored == nil || stored.pixelFormat != MTLPixelFormatRGBA8Unorm ||
      stored.blendingState != MTL4BlendStateEnabled ||
      stored.sourceRGBBlendFactor != MTLBlendFactorSourceAlpha ||
      stored.destinationRGBBlendFactor != MTLBlendFactorOneMinusSourceAlpha ||
      stored.rgbBlendOperation != MTLBlendOperationReverseSubtract ||
      stored.sourceAlphaBlendFactor != MTLBlendFactorDestinationAlpha ||
      stored.destinationAlphaBlendFactor !=
          MTLBlendFactorOneMinusDestinationAlpha ||
      stored.alphaBlendOperation != MTLBlendOperationMax ||
      stored.writeMask != (MTLColorWriteMaskRed | MTLColorWriteMaskAlpha)) {
    *failure =
        @"Metal changed Metal 4 render color-attachment copy semantics";
    return false;
  }
  return true;
}

API_AVAILABLE(macos(26.0))
bool checked_reset_render_attachment_defaults(
    MTL4RenderPipelineColorAttachmentDescriptorArray *attachments,
    NSString *pipeline_kind, NSString *__autoreleasing *failure) {
  MTL4RenderPipelineColorAttachmentDescriptor *attachment =
      [attachments objectAtIndexedSubscript:0];
  if (attachment == nil || attachment.pixelFormat != MTLPixelFormatInvalid ||
      attachment.blendingState != MTL4BlendStateDisabled ||
      attachment.sourceRGBBlendFactor != MTLBlendFactorOne ||
      attachment.destinationRGBBlendFactor != MTLBlendFactorZero ||
      attachment.rgbBlendOperation != MTLBlendOperationAdd ||
      attachment.sourceAlphaBlendFactor != MTLBlendFactorOne ||
      attachment.destinationAlphaBlendFactor != MTLBlendFactorZero ||
      attachment.alphaBlendOperation != MTLBlendOperationAdd ||
      attachment.writeMask != MTLColorWriteMaskAll) {
    *failure = [NSString
        stringWithFormat:@"Metal changed Metal 4 %@ color-attachment reset defaults",
                         pipeline_kind];
    return false;
  }
  return true;
}

API_AVAILABLE(macos(26.0))
bool reset_checked_render_pipeline_descriptor(
    MTL4RenderPipelineDescriptor *descriptor,
    MTL4LibraryFunctionDescriptor *poison_function, id<MTLDevice> device,
    NSString *__autoreleasing *failure) {
  descriptor.label = @"prismel-render-reset-poison";
  descriptor.options = [[MTL4PipelineOptions alloc] init];
  descriptor.vertexFunctionDescriptor = poison_function;
  descriptor.fragmentFunctionDescriptor = poison_function;
  MTLVertexDescriptor *poison_vertex_descriptor =
      [MTLVertexDescriptor vertexDescriptor];
  poison_vertex_descriptor.attributes[0].format = MTLVertexFormatFloat;
  poison_vertex_descriptor.attributes[0].bufferIndex = 0;
  poison_vertex_descriptor.layouts[0].stride = sizeof(float);
  descriptor.vertexDescriptor = poison_vertex_descriptor;
  descriptor.rasterSampleCount =
      [device supportsTextureSampleCount:2] ? 2 : 1;
  descriptor.alphaToCoverageState = MTL4AlphaToCoverageStateEnabled;
  descriptor.alphaToOneState = MTL4AlphaToOneStateEnabled;
  descriptor.rasterizationEnabled = NO;
  descriptor.maxVertexAmplificationCount =
      [device supportsVertexAmplificationCount:2] ? 2 : 1;
  descriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
  descriptor.supportVertexBinaryLinking = YES;
  descriptor.supportFragmentBinaryLinking = YES;
  descriptor.colorAttachmentMappingState =
      MTL4LogicalToPhysicalColorAttachmentMappingStateInherited;
  if (!poison_checked_render_attachment_copy(descriptor.colorAttachments,
                                             failure)) {
    return false;
  }
  [descriptor reset];
  MTLVertexDescriptor *reset_vertex_descriptor = descriptor.vertexDescriptor;
  const bool vertex_descriptor_reset = reset_vertex_descriptor == nil ||
      (reset_vertex_descriptor.attributes[0].format == MTLVertexFormatInvalid &&
       reset_vertex_descriptor.layouts[0].stride == 0);
  if (descriptor.label != nil || descriptor.options != nil ||
      descriptor.vertexFunctionDescriptor != nil ||
      descriptor.fragmentFunctionDescriptor != nil ||
      !vertex_descriptor_reset || descriptor.rasterSampleCount != 1 ||
      descriptor.alphaToCoverageState != MTL4AlphaToCoverageStateDisabled ||
      descriptor.alphaToOneState != MTL4AlphaToOneStateDisabled ||
      !descriptor.isRasterizationEnabled ||
      descriptor.maxVertexAmplificationCount != 1 ||
      descriptor.inputPrimitiveTopology !=
          MTLPrimitiveTopologyClassUnspecified ||
      descriptor.supportVertexBinaryLinking ||
      descriptor.supportFragmentBinaryLinking ||
      descriptor.colorAttachmentMappingState !=
          MTL4LogicalToPhysicalColorAttachmentMappingStateIdentity ||
      !checked_reset_render_attachment_defaults(
          descriptor.colorAttachments, @"render", failure)) {
    if (*failure == nil) {
      *failure = [NSString
          stringWithFormat:
              @"Metal changed Metal 4 render-pipeline reset defaults "
               "(label=%d options=%d vertex=%d fragment=%d layout=%d "
               "samples=%lu coverage=%ld one=%ld raster=%d amplification=%lu "
               "topology=%lu vertex-link=%d fragment-link=%d mapping=%ld "
               "indirect=%ld)",
              descriptor.label != nil, descriptor.options != nil,
              descriptor.vertexFunctionDescriptor != nil,
              descriptor.fragmentFunctionDescriptor != nil,
              !vertex_descriptor_reset,
              static_cast<unsigned long>(descriptor.rasterSampleCount),
              static_cast<long>(descriptor.alphaToCoverageState),
              static_cast<long>(descriptor.alphaToOneState),
              descriptor.isRasterizationEnabled,
              static_cast<unsigned long>(
                  descriptor.maxVertexAmplificationCount),
              static_cast<unsigned long>(descriptor.inputPrimitiveTopology),
              descriptor.supportVertexBinaryLinking,
              descriptor.supportFragmentBinaryLinking,
              static_cast<long>(descriptor.colorAttachmentMappingState),
              static_cast<long>(descriptor.supportIndirectCommandBuffers)];
    }
    return false;
  }
  return true;
}

API_AVAILABLE(macos(26.0))
bool reset_checked_mesh_pipeline_descriptor(
    MTL4MeshRenderPipelineDescriptor *descriptor,
    MTL4LibraryFunctionDescriptor *poison_function, id<MTLDevice> device,
    NSString *__autoreleasing *failure) {
  descriptor.label = @"prismel-mesh-reset-poison";
  descriptor.options = [[MTL4PipelineOptions alloc] init];
  descriptor.objectFunctionDescriptor = poison_function;
  descriptor.meshFunctionDescriptor = poison_function;
  descriptor.fragmentFunctionDescriptor = poison_function;
  descriptor.maxTotalThreadsPerObjectThreadgroup = 1;
  descriptor.maxTotalThreadsPerMeshThreadgroup = 1;
  descriptor.requiredThreadsPerObjectThreadgroup = MTLSizeMake(1, 1, 1);
  descriptor.requiredThreadsPerMeshThreadgroup = MTLSizeMake(1, 1, 1);
  descriptor.objectThreadgroupSizeIsMultipleOfThreadExecutionWidth = YES;
  descriptor.meshThreadgroupSizeIsMultipleOfThreadExecutionWidth = YES;
  descriptor.payloadMemoryLength = 1;
  descriptor.maxTotalThreadgroupsPerMeshGrid = 1;
  descriptor.rasterSampleCount =
      [device supportsTextureSampleCount:2] ? 2 : 1;
  descriptor.alphaToCoverageState = MTL4AlphaToCoverageStateEnabled;
  descriptor.alphaToOneState = MTL4AlphaToOneStateEnabled;
  descriptor.rasterizationEnabled = NO;
  descriptor.maxVertexAmplificationCount =
      [device supportsVertexAmplificationCount:2] ? 2 : 1;
  descriptor.supportObjectBinaryLinking = YES;
  descriptor.supportMeshBinaryLinking = YES;
  descriptor.supportFragmentBinaryLinking = YES;
  descriptor.colorAttachmentMappingState =
      MTL4LogicalToPhysicalColorAttachmentMappingStateInherited;
  if (!poison_checked_render_attachment_copy(descriptor.colorAttachments,
                                             failure)) {
    return false;
  }
  [descriptor reset];
  const MTLSize reset_object_threads =
      descriptor.requiredThreadsPerObjectThreadgroup;
  const MTLSize reset_mesh_threads =
      descriptor.requiredThreadsPerMeshThreadgroup;
  if (descriptor.label != nil || descriptor.options != nil ||
      descriptor.objectFunctionDescriptor != nil ||
      descriptor.meshFunctionDescriptor != nil ||
      descriptor.fragmentFunctionDescriptor != nil ||
      descriptor.maxTotalThreadsPerObjectThreadgroup != 0 ||
      descriptor.maxTotalThreadsPerMeshThreadgroup != 0 ||
      reset_object_threads.width != 0 || reset_object_threads.height != 0 ||
      reset_object_threads.depth != 0 || reset_mesh_threads.width != 0 ||
      reset_mesh_threads.height != 0 || reset_mesh_threads.depth != 0 ||
      descriptor.objectThreadgroupSizeIsMultipleOfThreadExecutionWidth ||
      descriptor.meshThreadgroupSizeIsMultipleOfThreadExecutionWidth ||
      descriptor.payloadMemoryLength != 0 ||
      descriptor.maxTotalThreadgroupsPerMeshGrid != 0 ||
      descriptor.rasterSampleCount != 1 ||
      descriptor.alphaToCoverageState != MTL4AlphaToCoverageStateDisabled ||
      descriptor.alphaToOneState != MTL4AlphaToOneStateDisabled ||
      !descriptor.isRasterizationEnabled ||
      descriptor.maxVertexAmplificationCount != 1 ||
      descriptor.supportObjectBinaryLinking ||
      descriptor.supportMeshBinaryLinking ||
      descriptor.supportFragmentBinaryLinking ||
      descriptor.colorAttachmentMappingState !=
          MTL4LogicalToPhysicalColorAttachmentMappingStateIdentity ||
      !checked_reset_render_attachment_defaults(
          descriptor.colorAttachments, @"mesh", failure)) {
    if (*failure == nil) {
      *failure = @"Metal changed Metal 4 mesh-pipeline reset defaults";
    }
    return false;
  }
  return true;
}

API_AVAILABLE(macos(26.0))
bool reset_checked_tile_pipeline_descriptor(
    MTL4TileRenderPipelineDescriptor *descriptor,
    MTL4LibraryFunctionDescriptor *poison_function, id<MTLDevice> device,
    NSString *__autoreleasing *failure) {
  descriptor.label = @"prismel-tile-reset-poison";
  descriptor.options = [[MTL4PipelineOptions alloc] init];
  descriptor.tileFunctionDescriptor = poison_function;
  descriptor.rasterSampleCount =
      [device supportsTextureSampleCount:2] ? 2 : 1;
  MTLTileRenderPipelineColorAttachmentDescriptor *source =
      [[MTLTileRenderPipelineColorAttachmentDescriptor alloc] init];
  source.pixelFormat = MTLPixelFormatRGBA8Unorm;
  [descriptor.colorAttachments setObject:source atIndexedSubscript:0];
  source.pixelFormat = MTLPixelFormatBGRA8Unorm;
  MTLTileRenderPipelineColorAttachmentDescriptor *stored =
      [descriptor.colorAttachments objectAtIndexedSubscript:0];
  if (stored == nil || stored.pixelFormat != MTLPixelFormatRGBA8Unorm) {
    *failure = @"Metal changed Metal 4 tile color-attachment copy semantics";
    return false;
  }
  descriptor.threadgroupSizeMatchesTileSize = YES;
  descriptor.maxTotalThreadsPerThreadgroup = 1;
  descriptor.requiredThreadsPerThreadgroup = MTLSizeMake(1, 1, 1);
  descriptor.supportBinaryLinking = YES;
  [descriptor reset];
  const MTLSize reset_threads = descriptor.requiredThreadsPerThreadgroup;
  MTLTileRenderPipelineColorAttachmentDescriptor *reset_attachment =
      [descriptor.colorAttachments objectAtIndexedSubscript:0];
  if (descriptor.label != nil || descriptor.options != nil ||
      descriptor.tileFunctionDescriptor != nil ||
      descriptor.rasterSampleCount != 1 || reset_attachment == nil ||
      reset_attachment.pixelFormat != MTLPixelFormatInvalid ||
      descriptor.threadgroupSizeMatchesTileSize ||
      descriptor.maxTotalThreadsPerThreadgroup != 0 ||
      reset_threads.width != 0 || reset_threads.height != 0 ||
      reset_threads.depth != 0 || descriptor.supportBinaryLinking) {
    *failure = @"Metal changed Metal 4 tile-pipeline reset defaults";
    return false;
  }
  return true;
}

API_AVAILABLE(macos(26.0))
PrismelMetalCheckedRenderRequest *checked_render_request(
    value raw_descriptor, id<MTL4Compiler> compiler,
    NSString *__autoreleasing *failure) {
  id<MTLLibrary> library =
      object_of_handle(Field(raw_descriptor, 1), Handle_kind::Library);
  if (library.device.registryID != compiler.device.registryID) {
    *failure = @"Metal 4 render library is incompatible with the compiler";
    return nil;
  }
  NSString *expected_label = nil;
  value raw_label = Field(raw_descriptor, 0);
  if (Is_block(raw_label)) {
    expected_label = string_from_ocaml(Field(raw_label, 0));
    if (expected_label == nil) {
      *failure = @"Metal 4 render-pipeline label is not valid UTF-8";
      return nil;
    }
  }
  NSString *vertex_name = string_from_ocaml(Field(raw_descriptor, 2));
  MTL4LibraryFunctionDescriptor *vertex =
      checked_pipeline_function_descriptor(
          library, vertex_name, {MTLFunctionTypeVertex}, @"vertex", failure);
  if (vertex == nil) {
    return nil;
  }
  MTL4LibraryFunctionDescriptor *fragment = nil;
  NSString *fragment_name = nil;
  value raw_fragment = Field(raw_descriptor, 3);
  if (Is_block(raw_fragment)) {
    fragment_name = string_from_ocaml(Field(raw_fragment, 0));
    fragment = checked_pipeline_function_descriptor(
        library, fragment_name, {MTLFunctionTypeFragment}, @"fragment",
        failure);
    if (fragment == nil) {
      return nil;
    }
  }
  const bool rasterization_enabled = Bool_val(Field(raw_descriptor, 7));
  if (rasterization_enabled != (fragment != nil)) {
    *failure =
        @"Metal 4 render rasterization and fragment-function configuration disagree";
    return nil;
  }
  NSUInteger sample_count = 0;
  if (!nsuinteger_from_ocaml_int64(Field(raw_descriptor, 5),
                                   &sample_count) ||
      sample_count == 0 ||
      ![compiler.device supportsTextureSampleCount:sample_count]) {
    *failure = @"Metal 4 render sample count is unsupported";
    return nil;
  }
  value raw_attachments = Field(raw_descriptor, 6);
  const intnat topology_code = Long_val(Field(raw_descriptor, 8));
  if (topology_code <
          static_cast<intnat>(MTLPrimitiveTopologyClassPoint) ||
      topology_code >
          static_cast<intnat>(MTLPrimitiveTopologyClassTriangle)) {
    *failure = @"Metal 4 render primitive topology is invalid";
    return nil;
  }
  const intnat alpha_to_coverage_code =
      Long_val(Field(raw_descriptor, 18));
  const intnat alpha_to_one_code = Long_val(Field(raw_descriptor, 19));
  const intnat color_attachment_mapping_code =
      Long_val(Field(raw_descriptor, 21));
  NSUInteger max_vertex_amplification_count = 0;
  if (alpha_to_coverage_code < 0 || alpha_to_coverage_code > 1 ||
      alpha_to_one_code < 0 || alpha_to_one_code > 1 ||
      color_attachment_mapping_code < 0 ||
      color_attachment_mapping_code > 1 ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 20),
                                   &max_vertex_amplification_count) ||
      max_vertex_amplification_count == 0 ||
      ![compiler.device supportsVertexAmplificationCount:
                            max_vertex_amplification_count]) {
    *failure = @"Metal 4 render raster state is invalid or unsupported";
    return nil;
  }
  const auto alpha_to_coverage =
      static_cast<MTL4AlphaToCoverageState>(alpha_to_coverage_code);
  const auto alpha_to_one =
      static_cast<MTL4AlphaToOneState>(alpha_to_one_code);
  const auto color_attachment_mapping =
      static_cast<MTL4LogicalToPhysicalColorAttachmentMappingState>(
          color_attachment_mapping_code);
  MTL4RenderPipelineDescriptor *descriptor =
      [[MTL4RenderPipelineDescriptor alloc] init];
  if (!reset_checked_render_pipeline_descriptor(
          descriptor, vertex, compiler.device, failure)) {
    return nil;
  }
  descriptor.label = expected_label;
  descriptor.vertexFunctionDescriptor = vertex;
  descriptor.fragmentFunctionDescriptor = fragment;
  descriptor.rasterSampleCount = sample_count;
  descriptor.alphaToCoverageState = alpha_to_coverage;
  descriptor.alphaToOneState = alpha_to_one;
  descriptor.rasterizationEnabled = rasterization_enabled;
  descriptor.maxVertexAmplificationCount = max_vertex_amplification_count;
  descriptor.inputPrimitiveTopology =
      static_cast<MTLPrimitiveTopologyClass>(topology_code);
  descriptor.colorAttachmentMappingState = color_attachment_mapping;
  const auto indirect_support = Bool_val(Field(raw_descriptor, 9))
      ? MTL4IndirectCommandBufferSupportStateEnabled
      : MTL4IndirectCommandBufferSupportStateDisabled;
  descriptor.supportIndirectCommandBuffers = indirect_support;
  const bool support_vertex_binary_linking =
      Bool_val(Field(raw_descriptor, 12));
  const bool support_fragment_binary_linking =
      Bool_val(Field(raw_descriptor, 13));
  value raw_vertex_static_linking = Field(raw_descriptor, 16);
  value raw_fragment_static_linking = Field(raw_descriptor, 17);
  if (fragment == nil &&
      (support_fragment_binary_linking ||
       Is_block(Field(raw_descriptor, 15)) ||
       Is_block(raw_fragment_static_linking))) {
    *failure = @"Metal 4 render linking targets an absent fragment stage";
    return nil;
  }
  if ((support_vertex_binary_linking || support_fragment_binary_linking) &&
      !compiler.device.supportsFunctionPointersFromRender) {
    *failure = @"Metal 4 render binary linking requires function pointers";
    return nil;
  }
  NSString *static_linking_failure = nil;
  MTL4StaticLinkingDescriptor *vertex_static_linking =
      checked_render_static_linking_descriptor(
          raw_vertex_static_linking, compiler.device, &static_linking_failure);
  if (Is_block(raw_vertex_static_linking) && vertex_static_linking == nil) {
    *failure = static_linking_failure;
    return nil;
  }
  MTL4StaticLinkingDescriptor *fragment_static_linking =
      checked_render_static_linking_descriptor(
          raw_fragment_static_linking, compiler.device,
          &static_linking_failure);
  if (Is_block(raw_fragment_static_linking) &&
      fragment_static_linking == nil) {
    *failure = static_linking_failure;
    return nil;
  }
  descriptor.supportVertexBinaryLinking = support_vertex_binary_linking;
  descriptor.supportFragmentBinaryLinking = support_fragment_binary_linking;
  descriptor.vertexStaticLinkingDescriptor = vertex_static_linking;
  descriptor.fragmentStaticLinkingDescriptor = fragment_static_linking;
  if (!checked_stored_static_linking_descriptor(
          descriptor.vertexStaticLinkingDescriptor, vertex_static_linking,
          @"vertex", failure) ||
      !checked_stored_static_linking_descriptor(
          descriptor.fragmentStaticLinkingDescriptor,
          fragment_static_linking, @"fragment", failure)) {
    return nil;
  }
  if (!configure_render_vertex_descriptor(
          descriptor, Field(raw_descriptor, 11), failure)) {
    return nil;
  }
  MTL4RenderPipelineDynamicLinkingDescriptor *dynamic_linking = nil;
  if (Is_block(Field(raw_descriptor, 14)) ||
      Is_block(Field(raw_descriptor, 15))) {
    dynamic_linking =
        new_checked_render_dynamic_linking_descriptor(failure);
    if (dynamic_linking == nil ||
        !configure_render_stage_dynamic_linking(
            dynamic_linking.vertexLinkingDescriptor,
            Field(raw_descriptor, 14), compiler.device,
            support_vertex_binary_linking, @"vertex", failure) ||
        !configure_render_stage_dynamic_linking(
            dynamic_linking.fragmentLinkingDescriptor,
            Field(raw_descriptor, 15), compiler.device,
            support_fragment_binary_linking, @"fragment", failure)) {
      return nil;
    }
  }
  if (!configure_render_color_attachments(descriptor.colorAttachments,
                                          raw_attachments,
                                          rasterization_enabled, failure)) {
    return nil;
  }
  const bool reflection_requested = Bool_val(Field(raw_descriptor, 4));
  const MTL4ShaderReflection expected_reflection =
      MTL4ShaderReflectionBindingInfo | MTL4ShaderReflectionBufferTypeInfo;
  if (reflection_requested) {
    MTL4PipelineOptions *options = [[MTL4PipelineOptions alloc] init];
    options.shaderReflection = expected_reflection;
    descriptor.options = options;
  }
  NSString *task_options_failure = nil;
  MTL4CompilerTaskOptions *task_options =
      checked_pipeline_task_options(Field(raw_descriptor, 10), @"render",
                                    &task_options_failure);
  if (task_options_failure != nil) {
    *failure = task_options_failure;
    return nil;
  }
  if (((expected_label == nil) != (descriptor.label == nil)) ||
      (expected_label != nil &&
       ![descriptor.label isEqualToString:expected_label]) ||
      descriptor.rasterSampleCount != sample_count ||
      descriptor.alphaToCoverageState != alpha_to_coverage ||
      descriptor.alphaToOneState != alpha_to_one ||
      descriptor.isRasterizationEnabled != rasterization_enabled ||
      descriptor.maxVertexAmplificationCount !=
          max_vertex_amplification_count ||
      descriptor.inputPrimitiveTopology !=
          static_cast<MTLPrimitiveTopologyClass>(topology_code) ||
      descriptor.colorAttachmentMappingState != color_attachment_mapping ||
      descriptor.supportIndirectCommandBuffers != indirect_support ||
      descriptor.supportVertexBinaryLinking !=
          support_vertex_binary_linking ||
      descriptor.supportFragmentBinaryLinking !=
          support_fragment_binary_linking ||
      (reflection_requested &&
       (descriptor.options == nil ||
        descriptor.options.shaderReflection != expected_reflection)) ||
      (!reflection_requested && descriptor.options != nil)) {
    *failure = @"Metal changed checked Metal 4 render descriptor properties";
    return nil;
  }
  if (!checked_stored_render_function(
          descriptor.vertexFunctionDescriptor, vertex, library, vertex_name,
          @"vertex", failure) ||
      !checked_stored_render_function(
          descriptor.fragmentFunctionDescriptor, fragment, library,
          fragment_name, @"fragment", failure)) {
    return nil;
  }
  PrismelMetalCheckedRenderRequest *request =
      [[PrismelMetalCheckedRenderRequest alloc] init];
  request.descriptor = descriptor;
  request.dynamicLinking = dynamic_linking;
  request.taskOptions = task_options;
  request.label = expected_label;
  request.reflectionRequested = reflection_requested;
  return request;
}

API_AVAILABLE(macos(26.0))
PrismelMetalCheckedRenderRequest *checked_mesh_request(
    value raw_descriptor, id<MTL4Compiler> compiler,
    NSString *__autoreleasing *failure) {
  id<MTLLibrary> library =
      object_of_handle(Field(raw_descriptor, 1), Handle_kind::Library);
  if (library.device.registryID != compiler.device.registryID) {
    *failure = @"Metal 4 mesh library is incompatible with the compiler";
    return nil;
  }
  NSString *expected_label = nil;
  value raw_label = Field(raw_descriptor, 0);
  if (Is_block(raw_label)) {
    expected_label = string_from_ocaml(Field(raw_label, 0));
    if (expected_label == nil) {
      *failure = @"Metal 4 mesh-pipeline label is not valid UTF-8";
      return nil;
    }
  }
  NSString *object_name = nil;
  MTL4LibraryFunctionDescriptor *object = nil;
  value raw_object = Field(raw_descriptor, 2);
  if (Is_block(raw_object)) {
    object_name = string_from_ocaml(Field(raw_object, 0));
    object = checked_pipeline_function_descriptor(
        library, object_name, {MTLFunctionTypeObject}, @"object", failure);
    if (object == nil) {
      return nil;
    }
  }
  NSString *mesh_name = string_from_ocaml(Field(raw_descriptor, 3));
  MTL4LibraryFunctionDescriptor *mesh = checked_pipeline_function_descriptor(
      library, mesh_name, {MTLFunctionTypeMesh}, @"mesh", failure);
  if (mesh == nil) {
    return nil;
  }
  NSString *fragment_name = nil;
  MTL4LibraryFunctionDescriptor *fragment = nil;
  value raw_fragment = Field(raw_descriptor, 4);
  if (Is_block(raw_fragment)) {
    fragment_name = string_from_ocaml(Field(raw_fragment, 0));
    fragment = checked_pipeline_function_descriptor(
        library, fragment_name, {MTLFunctionTypeFragment}, @"fragment",
        failure);
    if (fragment == nil) {
      return nil;
    }
  }
  const bool rasterization_enabled = Bool_val(Field(raw_descriptor, 20));
  if (rasterization_enabled != (fragment != nil)) {
    *failure =
        @"Metal 4 mesh rasterization and fragment-function configuration disagree";
    return nil;
  }
  NSUInteger max_object = 0;
  NSUInteger max_mesh = 0;
  NSUInteger payload_length = 0;
  NSUInteger max_mesh_grid = 0;
  NSUInteger sample_count = 0;
  if (!nsuinteger_from_ocaml_int64(Field(raw_descriptor, 6), &max_object) ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 7), &max_mesh) ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 16),
                                   &payload_length) ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 17),
                                   &max_mesh_grid) ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 18),
                                   &sample_count) ||
      payload_length > 16'384 || sample_count == 0 ||
      ![compiler.device supportsTextureSampleCount:sample_count]) {
    *failure = @"Metal 4 mesh numeric descriptor property is invalid";
    return nil;
  }
  const intnat alpha_to_coverage_code =
      Long_val(Field(raw_descriptor, 32));
  const intnat alpha_to_one_code = Long_val(Field(raw_descriptor, 33));
  const intnat color_attachment_mapping_code =
      Long_val(Field(raw_descriptor, 35));
  NSUInteger max_vertex_amplification_count = 0;
  if (alpha_to_coverage_code < 0 || alpha_to_coverage_code > 1 ||
      alpha_to_one_code < 0 || alpha_to_one_code > 1 ||
      color_attachment_mapping_code < 0 ||
      color_attachment_mapping_code > 1 ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 34),
                                   &max_vertex_amplification_count) ||
      max_vertex_amplification_count == 0 ||
      ![compiler.device supportsVertexAmplificationCount:
                            max_vertex_amplification_count]) {
    *failure = @"Metal 4 mesh raster state is invalid or unsupported";
    return nil;
  }
  const auto alpha_to_coverage =
      static_cast<MTL4AlphaToCoverageState>(alpha_to_coverage_code);
  const auto alpha_to_one =
      static_cast<MTL4AlphaToOneState>(alpha_to_one_code);
  const auto color_attachment_mapping =
      static_cast<MTL4LogicalToPhysicalColorAttachmentMappingState>(
          color_attachment_mapping_code);
  MTLSize required_object = {};
  MTLSize required_mesh = {};
  if (!checked_threadgroup_size(
          Field(raw_descriptor, 8), Field(raw_descriptor, 9),
          Field(raw_descriptor, 10), max_object, @"object", &required_object,
          failure) ||
      !checked_threadgroup_size(
          Field(raw_descriptor, 11), Field(raw_descriptor, 12),
          Field(raw_descriptor, 13), max_mesh, @"mesh", &required_mesh,
          failure)) {
    return nil;
  }
  const bool object_multiple = Bool_val(Field(raw_descriptor, 14));
  const bool mesh_multiple = Bool_val(Field(raw_descriptor, 15));
  if (object == nil &&
      (max_object != 0 || required_object.width != 0 || object_multiple ||
       payload_length != 0 || max_mesh_grid != 0)) {
    *failure = @"Metal 4 object configuration has no object function";
    return nil;
  }
  const bool indirect_requested = Bool_val(Field(raw_descriptor, 21));
  if (indirect_requested &&
      ![compiler.device supportsFamily:MTLGPUFamilyApple9]) {
    *failure = @"Metal 4 indirect mesh draws require Apple9 or newer";
    return nil;
  }
  const bool support_object_binary_linking =
      Bool_val(Field(raw_descriptor, 23));
  const bool support_mesh_binary_linking =
      Bool_val(Field(raw_descriptor, 24));
  const bool support_fragment_binary_linking =
      Bool_val(Field(raw_descriptor, 25));
  value raw_object_static_linking = Field(raw_descriptor, 29);
  value raw_mesh_static_linking = Field(raw_descriptor, 30);
  value raw_fragment_static_linking = Field(raw_descriptor, 31);
  if ((object == nil &&
       (support_object_binary_linking ||
        Is_block(Field(raw_descriptor, 26)) ||
        Is_block(raw_object_static_linking))) ||
      (fragment == nil &&
       (support_fragment_binary_linking ||
        Is_block(Field(raw_descriptor, 28)) ||
        Is_block(raw_fragment_static_linking)))) {
    *failure = @"Metal 4 mesh linking targets an absent pipeline stage";
    return nil;
  }
  if ((support_object_binary_linking || support_mesh_binary_linking) &&
      ![compiler.device supportsFamily:MTLGPUFamilyApple9]) {
    *failure =
        @"Metal 4 object/mesh binary linking requires Apple9 or newer";
    return nil;
  }
  if ((support_object_binary_linking || support_mesh_binary_linking ||
       support_fragment_binary_linking) &&
      !compiler.device.supportsFunctionPointersFromRender) {
    *failure = @"Metal 4 mesh binary linking requires function pointers";
    return nil;
  }
  NSString *static_linking_failure = nil;
  MTL4StaticLinkingDescriptor *object_static_linking =
      checked_render_static_linking_descriptor(
          raw_object_static_linking, compiler.device, &static_linking_failure);
  if (Is_block(raw_object_static_linking) && object_static_linking == nil) {
    *failure = static_linking_failure;
    return nil;
  }
  MTL4StaticLinkingDescriptor *mesh_static_linking =
      checked_render_static_linking_descriptor(
          raw_mesh_static_linking, compiler.device, &static_linking_failure);
  if (Is_block(raw_mesh_static_linking) && mesh_static_linking == nil) {
    *failure = static_linking_failure;
    return nil;
  }
  MTL4StaticLinkingDescriptor *fragment_static_linking =
      checked_render_static_linking_descriptor(
          raw_fragment_static_linking, compiler.device,
          &static_linking_failure);
  if (Is_block(raw_fragment_static_linking) &&
      fragment_static_linking == nil) {
    *failure = static_linking_failure;
    return nil;
  }
  MTL4MeshRenderPipelineDescriptor *descriptor =
      [[MTL4MeshRenderPipelineDescriptor alloc] init];
  if (!reset_checked_mesh_pipeline_descriptor(
          descriptor, mesh, compiler.device, failure)) {
    return nil;
  }
  descriptor.label = expected_label;
  descriptor.objectFunctionDescriptor = object;
  descriptor.meshFunctionDescriptor = mesh;
  descriptor.fragmentFunctionDescriptor = fragment;
  descriptor.maxTotalThreadsPerObjectThreadgroup = max_object;
  descriptor.maxTotalThreadsPerMeshThreadgroup = max_mesh;
  descriptor.requiredThreadsPerObjectThreadgroup = required_object;
  descriptor.requiredThreadsPerMeshThreadgroup = required_mesh;
  descriptor.objectThreadgroupSizeIsMultipleOfThreadExecutionWidth =
      object_multiple;
  descriptor.meshThreadgroupSizeIsMultipleOfThreadExecutionWidth =
      mesh_multiple;
  descriptor.payloadMemoryLength = payload_length;
  descriptor.maxTotalThreadgroupsPerMeshGrid = max_mesh_grid;
  descriptor.rasterSampleCount = sample_count;
  descriptor.alphaToCoverageState = alpha_to_coverage;
  descriptor.alphaToOneState = alpha_to_one;
  descriptor.rasterizationEnabled = rasterization_enabled;
  descriptor.maxVertexAmplificationCount = max_vertex_amplification_count;
  descriptor.colorAttachmentMappingState = color_attachment_mapping;
  const auto indirect_support = indirect_requested
      ? MTL4IndirectCommandBufferSupportStateEnabled
      : MTL4IndirectCommandBufferSupportStateDisabled;
  descriptor.supportIndirectCommandBuffers = indirect_support;
  descriptor.supportObjectBinaryLinking = support_object_binary_linking;
  descriptor.supportMeshBinaryLinking = support_mesh_binary_linking;
  descriptor.supportFragmentBinaryLinking = support_fragment_binary_linking;
  descriptor.objectStaticLinkingDescriptor = object_static_linking;
  descriptor.meshStaticLinkingDescriptor = mesh_static_linking;
  descriptor.fragmentStaticLinkingDescriptor = fragment_static_linking;
  if (!checked_stored_static_linking_descriptor(
          descriptor.objectStaticLinkingDescriptor, object_static_linking,
          @"object", failure) ||
      !checked_stored_static_linking_descriptor(
          descriptor.meshStaticLinkingDescriptor, mesh_static_linking, @"mesh",
          failure) ||
      !checked_stored_static_linking_descriptor(
          descriptor.fragmentStaticLinkingDescriptor,
          fragment_static_linking, @"fragment", failure)) {
    return nil;
  }
  MTL4RenderPipelineDynamicLinkingDescriptor *dynamic_linking = nil;
  if (Is_block(Field(raw_descriptor, 26)) ||
      Is_block(Field(raw_descriptor, 27)) ||
      Is_block(Field(raw_descriptor, 28))) {
    dynamic_linking =
        new_checked_render_dynamic_linking_descriptor(failure);
    if (dynamic_linking == nil ||
        !configure_render_stage_dynamic_linking(
            dynamic_linking.objectLinkingDescriptor,
            Field(raw_descriptor, 26), compiler.device,
            support_object_binary_linking, @"object", failure) ||
        !configure_render_stage_dynamic_linking(
            dynamic_linking.meshLinkingDescriptor, Field(raw_descriptor, 27),
            compiler.device, support_mesh_binary_linking, @"mesh", failure) ||
        !configure_render_stage_dynamic_linking(
            dynamic_linking.fragmentLinkingDescriptor,
            Field(raw_descriptor, 28), compiler.device,
            support_fragment_binary_linking, @"fragment", failure)) {
      return nil;
    }
  }
  value raw_attachments = Field(raw_descriptor, 19);
  if (!configure_render_color_attachments(descriptor.colorAttachments,
                                          raw_attachments,
                                          rasterization_enabled, failure)) {
    return nil;
  }
  const bool reflection_requested = Bool_val(Field(raw_descriptor, 5));
  const MTL4ShaderReflection expected_reflection =
      MTL4ShaderReflectionBindingInfo | MTL4ShaderReflectionBufferTypeInfo;
  if (reflection_requested) {
    MTL4PipelineOptions *options = [[MTL4PipelineOptions alloc] init];
    options.shaderReflection = expected_reflection;
    descriptor.options = options;
  }
  NSString *task_options_failure = nil;
  MTL4CompilerTaskOptions *task_options =
      checked_pipeline_task_options(Field(raw_descriptor, 22), @"mesh",
                                    &task_options_failure);
  if (task_options_failure != nil) {
    *failure = task_options_failure;
    return nil;
  }
  if (((expected_label == nil) != (descriptor.label == nil)) ||
      (expected_label != nil &&
       ![descriptor.label isEqualToString:expected_label]) ||
      descriptor.maxTotalThreadsPerObjectThreadgroup != max_object ||
      descriptor.maxTotalThreadsPerMeshThreadgroup != max_mesh ||
      descriptor.requiredThreadsPerObjectThreadgroup.width !=
          required_object.width ||
      descriptor.requiredThreadsPerObjectThreadgroup.height !=
          required_object.height ||
      descriptor.requiredThreadsPerObjectThreadgroup.depth !=
          required_object.depth ||
      descriptor.requiredThreadsPerMeshThreadgroup.width !=
          required_mesh.width ||
      descriptor.requiredThreadsPerMeshThreadgroup.height !=
          required_mesh.height ||
      descriptor.requiredThreadsPerMeshThreadgroup.depth !=
          required_mesh.depth ||
      descriptor.objectThreadgroupSizeIsMultipleOfThreadExecutionWidth !=
          object_multiple ||
      descriptor.meshThreadgroupSizeIsMultipleOfThreadExecutionWidth !=
          mesh_multiple ||
      descriptor.payloadMemoryLength != payload_length ||
      descriptor.maxTotalThreadgroupsPerMeshGrid != max_mesh_grid ||
      descriptor.rasterSampleCount != sample_count ||
      descriptor.alphaToCoverageState != alpha_to_coverage ||
      descriptor.alphaToOneState != alpha_to_one ||
      descriptor.isRasterizationEnabled != rasterization_enabled ||
      descriptor.maxVertexAmplificationCount !=
          max_vertex_amplification_count ||
      descriptor.colorAttachmentMappingState != color_attachment_mapping ||
      descriptor.supportIndirectCommandBuffers != indirect_support ||
      descriptor.supportObjectBinaryLinking !=
          support_object_binary_linking ||
      descriptor.supportMeshBinaryLinking != support_mesh_binary_linking ||
      descriptor.supportFragmentBinaryLinking !=
          support_fragment_binary_linking ||
      (reflection_requested &&
       (descriptor.options == nil ||
        descriptor.options.shaderReflection != expected_reflection)) ||
      (!reflection_requested && descriptor.options != nil)) {
    *failure = @"Metal changed checked Metal 4 mesh descriptor properties";
    return nil;
  }
  if (!checked_stored_render_function(
          descriptor.objectFunctionDescriptor, object, library, object_name,
          @"object", failure) ||
      !checked_stored_render_function(
          descriptor.meshFunctionDescriptor, mesh, library, mesh_name, @"mesh",
          failure) ||
      !checked_stored_render_function(
          descriptor.fragmentFunctionDescriptor, fragment, library,
          fragment_name, @"fragment", failure)) {
    return nil;
  }
  PrismelMetalCheckedRenderRequest *request =
      [[PrismelMetalCheckedRenderRequest alloc] init];
  request.descriptor = descriptor;
  request.dynamicLinking = dynamic_linking;
  request.taskOptions = task_options;
  request.label = expected_label;
  request.reflectionRequested = reflection_requested;
  return request;
}

API_AVAILABLE(macos(26.0))
PrismelMetalCheckedRenderRequest *checked_tile_request(
    value raw_descriptor, id<MTL4Compiler> compiler,
    NSString *__autoreleasing *failure) {
  id<MTLLibrary> library =
      object_of_handle(Field(raw_descriptor, 1), Handle_kind::Library);
  if (library.device.registryID != compiler.device.registryID) {
    *failure = @"Metal 4 tile library is incompatible with the compiler";
    return nil;
  }
  if (![compiler.device supportsFamily:MTLGPUFamilyApple4]) {
    *failure = @"Metal 4 tile shaders require Apple4 or newer";
    return nil;
  }
  NSString *expected_label = nil;
  value raw_label = Field(raw_descriptor, 0);
  if (Is_block(raw_label)) {
    expected_label = string_from_ocaml(Field(raw_label, 0));
    if (expected_label == nil) {
      *failure = @"Metal 4 tile-pipeline label is not valid UTF-8";
      return nil;
    }
  }
  NSString *tile_name = string_from_ocaml(Field(raw_descriptor, 2));
  MTL4LibraryFunctionDescriptor *tile =
      checked_pipeline_function_descriptor(
          library, tile_name,
          {MTLFunctionTypeKernel, MTLFunctionTypeFragment}, @"tile", failure);
  if (tile == nil) {
    return nil;
  }
  NSUInteger sample_count = 0;
  NSUInteger max_total_threads = 0;
  if (!nsuinteger_from_ocaml_int64(Field(raw_descriptor, 4), &sample_count) ||
      !nsuinteger_from_ocaml_int64(Field(raw_descriptor, 7),
                                   &max_total_threads) ||
      sample_count == 0 ||
      ![compiler.device supportsTextureSampleCount:sample_count]) {
    *failure = @"Metal 4 tile numeric descriptor property is invalid";
    return nil;
  }
  MTLSize required_threads = {};
  if (!checked_threadgroup_size(
          Field(raw_descriptor, 8), Field(raw_descriptor, 9),
          Field(raw_descriptor, 10), max_total_threads, @"tile",
          &required_threads, failure)) {
    return nil;
  }
  const bool support_binary_linking = Bool_val(Field(raw_descriptor, 11));
  if (support_binary_linking &&
      !compiler.device.supportsFunctionPointersFromRender) {
    *failure = @"Metal 4 tile binary linking requires function pointers";
    return nil;
  }
  value raw_static_linking = Field(raw_descriptor, 12);
  NSString *static_linking_failure = nil;
  MTL4StaticLinkingDescriptor *static_linking =
      checked_render_static_linking_descriptor(
          raw_static_linking, compiler.device, &static_linking_failure);
  if (Is_block(raw_static_linking) && static_linking == nil) {
    *failure = static_linking_failure;
    return nil;
  }
  MTL4TileRenderPipelineDescriptor *descriptor =
      [[MTL4TileRenderPipelineDescriptor alloc] init];
  if (!reset_checked_tile_pipeline_descriptor(
          descriptor, tile, compiler.device, failure)) {
    return nil;
  }
  descriptor.label = expected_label;
  descriptor.tileFunctionDescriptor = tile;
  descriptor.rasterSampleCount = sample_count;
  const bool matches_tile_size = Bool_val(Field(raw_descriptor, 6));
  descriptor.threadgroupSizeMatchesTileSize = matches_tile_size;
  descriptor.maxTotalThreadsPerThreadgroup = max_total_threads;
  descriptor.requiredThreadsPerThreadgroup = required_threads;
  descriptor.supportBinaryLinking = support_binary_linking;
  descriptor.staticLinkingDescriptor = static_linking;
  if (!checked_stored_static_linking_descriptor(
          descriptor.staticLinkingDescriptor, static_linking, @"tile",
          failure)) {
    return nil;
  }
  MTL4RenderPipelineDynamicLinkingDescriptor *dynamic_linking = nil;
  if (Is_block(Field(raw_descriptor, 14))) {
    dynamic_linking =
        new_checked_render_dynamic_linking_descriptor(failure);
    if (dynamic_linking == nil ||
        !configure_render_stage_dynamic_linking(
            dynamic_linking.tileLinkingDescriptor, Field(raw_descriptor, 14),
            compiler.device, support_binary_linking, @"tile", failure)) {
      return nil;
    }
  }
  if (!configure_tile_color_attachments(
          descriptor.colorAttachments, Field(raw_descriptor, 5), failure)) {
    return nil;
  }
  const bool reflection_requested = Bool_val(Field(raw_descriptor, 3));
  const MTL4ShaderReflection expected_reflection =
      MTL4ShaderReflectionBindingInfo | MTL4ShaderReflectionBufferTypeInfo;
  if (reflection_requested) {
    MTL4PipelineOptions *options = [[MTL4PipelineOptions alloc] init];
    options.shaderReflection = expected_reflection;
    descriptor.options = options;
  }
  NSString *task_options_failure = nil;
  MTL4CompilerTaskOptions *task_options =
      checked_pipeline_task_options(Field(raw_descriptor, 13), @"tile",
                                    &task_options_failure);
  if (task_options_failure != nil) {
    *failure = task_options_failure;
    return nil;
  }
  if (((expected_label == nil) != (descriptor.label == nil)) ||
      (expected_label != nil &&
       ![descriptor.label isEqualToString:expected_label]) ||
      descriptor.rasterSampleCount != sample_count ||
      descriptor.threadgroupSizeMatchesTileSize != matches_tile_size ||
      descriptor.maxTotalThreadsPerThreadgroup != max_total_threads ||
      descriptor.requiredThreadsPerThreadgroup.width != required_threads.width ||
      descriptor.requiredThreadsPerThreadgroup.height !=
          required_threads.height ||
      descriptor.requiredThreadsPerThreadgroup.depth != required_threads.depth ||
      descriptor.supportBinaryLinking != support_binary_linking ||
      (reflection_requested &&
       (descriptor.options == nil ||
        descriptor.options.shaderReflection != expected_reflection)) ||
      (!reflection_requested && descriptor.options != nil)) {
    *failure = @"Metal changed checked Metal 4 tile descriptor properties";
    return nil;
  }
  if (!checked_stored_render_function(
          descriptor.tileFunctionDescriptor, tile, library, tile_name, @"tile",
          failure)) {
    return nil;
  }
  PrismelMetalCheckedRenderRequest *request =
      [[PrismelMetalCheckedRenderRequest alloc] init];
  request.descriptor = descriptor;
  request.dynamicLinking = dynamic_linking;
  request.taskOptions = task_options;
  request.label = expected_label;
  request.reflectionRequested = reflection_requested;
  return request;
}

API_AVAILABLE(macos(26.0))
bool checked_render_pipeline_result(
    id<MTLRenderPipelineState> pipeline, id<MTL4Compiler> compiler,
    NSString *expected_label, bool reflection_requested,
    NSString *__autoreleasing *failure) {
  if (pipeline == nil) {
    *failure = @"Metal returned no render pipeline";
    return false;
  }
  if (reflection_requested && pipeline.reflection == nil) {
    *failure = @"Metal omitted requested render-pipeline reflection";
    return false;
  }
  if (pipeline.device.registryID != compiler.device.registryID ||
      ((expected_label == nil) != (pipeline.label == nil)) ||
      (expected_label != nil &&
       ![pipeline.label isEqualToString:expected_label])) {
    *failure = @"Metal changed checked render-pipeline properties";
    return false;
  }
  return true;
}

API_AVAILABLE(macos(26.0))
id<MTLRenderPipelineState> compile_checked_render_pipeline(
    id<MTL4Compiler> compiler, PrismelMetalCheckedRenderRequest *request,
    NSString *__autoreleasing *failure) {
  NSError *error = nil;
  id<MTLRenderPipelineState> pipeline = request.dynamicLinking == nil
      ? [compiler newRenderPipelineStateWithDescriptor:request.descriptor
                                   compilerTaskOptions:request.taskOptions
                                                 error:&error]
      : [compiler newRenderPipelineStateWithDescriptor:request.descriptor
                              dynamicLinkingDescriptor:request.dynamicLinking
                                   compilerTaskOptions:request.taskOptions
                                                 error:&error];
  if (pipeline == nil) {
    *failure = labeled_error_description(
        request.label, error,
        @"Metal 4 render-pipeline compilation failed without NSError");
    return nil;
  }
  if (!checked_render_pipeline_result(
          pipeline, compiler, request.label, request.reflectionRequested,
          failure)) {
    return nil;
  }
  return pipeline;
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_create_render_pipeline(
    value raw_compiler, value raw_descriptor) {
  CAMLparam2(raw_compiler, raw_descriptor);
  CAMLlocal3(raw, reflection, pair);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *validation_failure = nil;
        PrismelMetalCheckedRenderRequest *request =
            checked_render_request(raw_descriptor, compiler,
                                   &validation_failure);
        if (request == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        id<MTLRenderPipelineState> pipeline =
            compile_checked_render_pipeline(compiler, request,
                                            &validation_failure);
        if (pipeline == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        raw = allocate_handle(pipeline, Handle_kind::Render_pipeline);
        reflection = copy_render_reflection(pipeline.reflection);
        pair = caml_alloc_tuple(2);
        Store_field(pair, 0, raw);
        Store_field(pair, 1, reflection);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 render pipelines require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(pair));
}

extern "C" CAMLprim value caml_prismel_metal_compute_pipeline_create(
    value raw_device, value raw_function) {
  CAMLparam2(raw_device, raw_function);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    id<MTLFunction> function =
        object_of_handle(raw_function, Handle_kind::Function);
    NSError *error = nil;
    id<MTLComputePipelineState> pipeline =
        [device newComputePipelineStateWithFunction:function error:&error];
    if (pipeline == nil) {
      CAMLreturn(result_error(error_description(
          error, @"Metal compute pipeline creation failed without NSError")));
    }
    raw = allocate_handle(pipeline, Handle_kind::Compute_pipeline);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compute_pipeline_create_descriptor(
    value raw_device, value raw_function, value raw_descriptor) {
  CAMLparam3(raw_device, raw_function, raw_descriptor);
  CAMLlocal3(raw, bindings, pair);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      id<MTLFunction> function =
          object_of_handle(raw_function, Handle_kind::Function);
      if (function.device.registryID != device.registryID ||
          function.functionType != MTLFunctionTypeKernel) {
        CAMLreturn(result_error_text(
            "Metal compute entry point is incompatible with the device"));
      }
      NSString *expected_label = nil;
      value raw_label = Field(raw_descriptor, 0);
      if (Is_block(raw_label)) {
        expected_label = string_from_ocaml(Field(raw_label, 0));
        if (expected_label == nil) {
          CAMLreturn(result_error_text(
              "Metal compute-pipeline label is not valid UTF-8"));
        }
      }
      std::vector<id<MTLFunction>> linked_functions =
          functions_of_array(Field(raw_descriptor, 2));
      NSMutableSet<NSString *> *linked_names = [NSMutableSet set];
      NSMutableArray<id<MTLFunction>> *linked_array =
          [NSMutableArray arrayWithCapacity:linked_functions.size()];
      for (id<MTLFunction> linked : linked_functions) {
        if (linked.device.registryID != device.registryID ||
            (linked.functionType != MTLFunctionTypeVisible &&
             linked.functionType != MTLFunctionTypeIntersection) ||
            [linked_names containsObject:linked.name]) {
          CAMLreturn(result_error_text(
              "Metal linked function is incompatible or duplicated"));
        }
        [linked_names addObject:linked.name];
        [linked_array addObject:linked];
      }
      std::vector<id<MTLDynamicLibrary>> preloaded_libraries =
          dynamic_libraries_of_array(Field(raw_descriptor, 3));
      NSMutableArray<id<MTLDynamicLibrary>> *preloaded_array =
          [NSMutableArray arrayWithCapacity:preloaded_libraries.size()];
      NSMutableSet<NSString *> *install_names = [NSMutableSet set];
      for (id<MTLDynamicLibrary> library : preloaded_libraries) {
        if (!device.supportsDynamicLibraries ||
            library.device.registryID != device.registryID ||
            library.installName == nil ||
            [install_names containsObject:library.installName]) {
          CAMLreturn(result_error_text(
              "Metal preloaded dynamic library is incompatible or duplicated"));
        }
        [install_names addObject:library.installName];
        [preloaded_array addObject:library];
      }
      std::vector<id<MTLBinaryArchive>> binary_archives =
          binary_archives_of_array(Field(raw_descriptor, 4));
      NSMutableArray<id<MTLBinaryArchive>> *archive_array =
          [NSMutableArray arrayWithCapacity:binary_archives.size()];
      NSMutableSet<id<MTLBinaryArchive>> *archive_set = [NSMutableSet set];
      for (id<MTLBinaryArchive> archive : binary_archives) {
        if (archive.device.registryID != device.registryID ||
            [archive_set containsObject:archive]) {
          CAMLreturn(result_error_text(
              "Metal binary archive is incompatible or duplicated"));
        }
        [archive_set addObject:archive];
        [archive_array addObject:archive];
      }
      const bool fail_on_archive_miss = Bool_val(Field(raw_descriptor, 5));
      if (fail_on_archive_miss && archive_array.count == 0) {
        CAMLreturn(result_error_text(
            "Metal fail-on-archive-miss has no binary archive"));
      }
      MTLComputePipelineDescriptor *descriptor =
          [[MTLComputePipelineDescriptor alloc] init];
      descriptor.computeFunction = function;
      if (expected_label != nil) {
        descriptor.label = expected_label;
      }
      if (linked_array.count != 0) {
        MTLLinkedFunctions *linked = [MTLLinkedFunctions linkedFunctions];
        linked.functions = linked_array;
        descriptor.linkedFunctions = linked;
      }
      descriptor.preloadedLibraries = preloaded_array;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      descriptor.insertLibraries = preloaded_array;
      MTLPipelineBufferDescriptorArray *checked_buffers = descriptor.buffers;
      const bool checked_insert_libraries =
          descriptor.insertLibraries.count == preloaded_array.count;
#pragma clang diagnostic pop
      descriptor.binaryArchives = archive_array;
      descriptor.supportIndirectCommandBuffers = Bool_val(Field(raw_descriptor, 6));
      value raw_buffer_mutabilities = Field(raw_descriptor, 7);
      if (Wosize_val(raw_buffer_mutabilities) != static_cast<mlsize_t>(31)) {
        CAMLreturn(result_error_text(
            "Metal compute pipeline buffer mutability snapshot must have 31 slots"));
      }
      for (NSUInteger index = 0; index < 31; ++index) {
        const intnat code = Long_val(Field(raw_buffer_mutabilities, index));
        if (code < static_cast<intnat>(MTLMutabilityDefault) ||
            code > static_cast<intnat>(MTLMutabilityImmutable)) {
          CAMLreturn(result_error_text(
              "Metal compute pipeline buffer mutability is invalid"));
        }
        descriptor.buffers[index].mutability = static_cast<MTLMutability>(code);
      }
      if (descriptor.computeFunction != function ||
          ((expected_label == nil) != (descriptor.label == nil)) ||
          (expected_label != nil &&
           ![descriptor.label isEqualToString:expected_label]) ||
          descriptor.preloadedLibraries.count != preloaded_array.count ||
          !checked_insert_libraries ||
          checked_buffers == nil ||
          descriptor.binaryArchives.count != archive_array.count ||
          descriptor.supportIndirectCommandBuffers != Bool_val(Field(raw_descriptor, 6))) {
        CAMLreturn(result_error_text(
            "Metal changed checked compute-pipeline descriptor properties"));
      }
      const bool reflection_requested = Bool_val(Field(raw_descriptor, 1));
      NSUInteger option_bits = reflection_requested
          ? MTLPipelineOptionBindingInfo | MTLPipelineOptionBufferTypeInfo
          : MTLPipelineOptionNone;
      if (fail_on_archive_miss) {
        option_bits |= MTLPipelineOptionFailOnBinaryArchiveMiss;
      }
      const MTLPipelineOption options =
          static_cast<MTLPipelineOption>(option_bits);
      MTLAutoreleasedComputePipelineReflection reflection = nil;
      NSError *error = nil;
      id<MTLComputePipelineState> pipeline =
          [device newComputePipelineStateWithDescriptor:descriptor
                                                options:options
                                             reflection:&reflection
                                                  error:&error];
      if (pipeline == nil) {
        CAMLreturn(result_error(labeled_error_description(
            expected_label, error,
            @"Metal compute pipeline creation failed without NSError")));
      }
      if (reflection_requested && reflection == nil) {
        CAMLreturn(result_error_text(
            "Metal omitted requested compute-pipeline reflection"));
      }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      const bool has_legacy_arguments =
          !reflection_requested || reflection.arguments != nil;
#pragma clang diagnostic pop
      if (!has_legacy_arguments) {
        CAMLreturn(result_error_text(
            "Metal omitted requested legacy compute-pipeline arguments"));
      }
      if (pipeline.device.registryID != device.registryID ||
          ((expected_label == nil) != (pipeline.label == nil)) ||
          (expected_label != nil &&
           ![pipeline.label isEqualToString:expected_label])) {
        CAMLreturn(result_error_text(
            "Metal changed checked compute-pipeline creation properties"));
      }
      raw = allocate_handle(pipeline, Handle_kind::Compute_pipeline);
      bindings = reflection_requested ? copy_bindings(reflection.bindings)
                                      : caml_alloc(0, 0);
      pair = caml_alloc_tuple(2);
      Store_field(pair, 0, raw);
      Store_field(pair, 1, bindings);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(pair));
}

extern "C" CAMLprim value
caml_prismel_metal_compute_pipeline_max_total_threads(value raw) {
  CAMLparam1(raw);
  id<MTLComputePipelineState> pipeline =
      object_of_handle(raw, Handle_kind::Compute_pipeline);
  CAMLreturn(Val_long(pipeline.maxTotalThreadsPerThreadgroup));
}

bool checked_metal4_store_action(value raw_action,
                                 MTLStoreAction *store_action) {
  if (!Is_long(raw_action)) {
    return false;
  }
  const intnat code = Long_val(raw_action);
  if (code != MTLStoreActionDontCare && code != MTLStoreActionStore &&
      code != MTLStoreActionMultisampleResolve &&
      code != MTLStoreActionStoreAndMultisampleResolve) {
    return false;
  }
  *store_action = static_cast<MTLStoreAction>(code);
  return true;
}

bool checked_ocaml_float32(value raw, float *result) {
  const double number = Double_val(raw);
  if (!std::isfinite(number) ||
      std::abs(number) > std::numeric_limits<float>::max()) {
    return false;
  }
  *result = static_cast<float>(number);
  return true;
}

bool checked_metal4_scissor_rect(value raw, MTLScissorRect *result) {
  NSUInteger x = 0;
  NSUInteger y = 0;
  NSUInteger width = 0;
  NSUInteger height = 0;
  if (!nsuinteger_from_ocaml_int64(Field(raw, 0), &x) ||
      !nsuinteger_from_ocaml_int64(Field(raw, 1), &y) ||
      !nsuinteger_from_ocaml_int64(Field(raw, 2), &width) ||
      !nsuinteger_from_ocaml_int64(Field(raw, 3), &height) || width == 0 ||
      height == 0) {
    return false;
  }
  result->x = x;
  result->y = y;
  result->width = width;
  result->height = height;
  return true;
}

bool checked_metal4_viewport(value raw, MTLViewport *result) {
  const double origin_x = Double_val(Field(raw, 0));
  const double origin_y = Double_val(Field(raw, 1));
  const double width = Double_val(Field(raw, 2));
  const double height = Double_val(Field(raw, 3));
  const double z_near = Double_val(Field(raw, 4));
  const double z_far = Double_val(Field(raw, 5));
  if (!std::isfinite(origin_x) || !std::isfinite(origin_y) ||
      !std::isfinite(width) || !std::isfinite(height) ||
      !std::isfinite(z_near) || !std::isfinite(z_far) || origin_x < 0.0 ||
      origin_y < 0.0 || width <= 0.0 || height <= 0.0 || z_near < 0.0 ||
      z_near > 1.0 || z_far < 0.0 || z_far > 1.0 || z_near > z_far) {
    return false;
  }
  result->originX = origin_x;
  result->originY = origin_y;
  result->width = width;
  result->height = height;
  result->znear = z_near;
  result->zfar = z_far;
  return true;
}

API_AVAILABLE(macos(26.0))
MTLLogicalToPhysicalColorAttachmentMap *
new_checked_color_attachment_map(
    const std::array<NSUInteger, 8> &expected_mapping,
    NSString *__autoreleasing *failure) {
  MTLLogicalToPhysicalColorAttachmentMap *mapping =
      [[MTLLogicalToPhysicalColorAttachmentMap alloc] init];
  if (mapping == nil) {
    *failure = @"Metal failed to allocate a color-attachment map";
    return nil;
  }
  for (NSUInteger logical_index = 0; logical_index < 8; ++logical_index) {
    [mapping setPhysicalIndex:7 - logical_index
              forLogicalIndex:logical_index];
    if ([mapping getPhysicalIndexForLogicalIndex:logical_index] !=
        7 - logical_index) {
      *failure = @"Metal changed checked color-attachment map properties";
      return nil;
    }
  }
  [mapping reset];
  for (NSUInteger logical_index = 0; logical_index < 8; ++logical_index) {
    if ([mapping getPhysicalIndexForLogicalIndex:logical_index] !=
        logical_index) {
      *failure = @"Metal changed color-attachment map reset semantics";
      return nil;
    }
    [mapping setPhysicalIndex:expected_mapping[logical_index]
              forLogicalIndex:logical_index];
  }
  for (NSUInteger logical_index = 0; logical_index < 8; ++logical_index) {
    if ([mapping getPhysicalIndexForLogicalIndex:logical_index] !=
        expected_mapping[logical_index]) {
      *failure = @"Metal changed the requested color-attachment mapping";
      return nil;
    }
  }
  MTLLogicalToPhysicalColorAttachmentMap *copied_mapping = [mapping copy];
  if (copied_mapping == nil) {
    *failure = @"Metal failed to copy a checked color-attachment map";
    return nil;
  }
  for (NSUInteger logical_index = 0; logical_index < 8; ++logical_index) {
    if ([copied_mapping getPhysicalIndexForLogicalIndex:logical_index] !=
        expected_mapping[logical_index]) {
      *failure = @"Metal changed copied color-attachment map properties";
      return nil;
    }
  }
  return mapping;
}

API_AVAILABLE(macos(26.0))
bool retain_metal4_render_argument_tables(
    value raw_tables, PrismelMetal4CommandBufferState *command_buffer,
    NSString *__autoreleasing *failure) {
  const mlsize_t table_count = Wosize_val(raw_tables);
  if (table_count > 5) {
    *failure = @"Metal 4 render command has too many argument tables";
    return false;
  }
  for (mlsize_t index = 0; index < table_count; ++index) {
    PrismelMetal4ArgumentTableState *table =
        argument_table4_state_of_handle(Field(raw_tables, index));
    if (table.argumentTable.device.registryID !=
        command_buffer.commandBuffer.device.registryID) {
      *failure = @"Metal 4 render argument table belongs to another device";
      return false;
    }
    [command_buffer retainEncodedObject:table];
    [table retainBoundObjectsInCommandBuffer:command_buffer];
  }
  return true;
}

struct PrismelMetal4IndexedDraw {
  MTLPrimitiveType primitive;
  NSUInteger index_count;
  MTLIndexType index_type;
  MTLGPUAddress index_address;
  NSUInteger index_length;
};

API_AVAILABLE(macos(26.0))
bool prismel_metal4_indexed_draw(
    value raw_draw, id<MTLBuffer> index_buffer,
    PrismelMetal4CommandBufferState *command_buffer,
    PrismelMetal4IndexedDraw *draw, NSString *__autoreleasing *failure) {
  const intnat primitive = Long_val(Field(raw_draw, 0));
  const intnat index_count = Long_val(Field(raw_draw, 1));
  const intnat index_type = Long_val(Field(raw_draw, 2));
  const std::int64_t signed_offset = Int64_val(Field(raw_draw, 3));
  if (index_buffer.device.registryID !=
          command_buffer.commandBuffer.device.registryID ||
      primitive < 0 || primitive > 4 || index_count <= 0 || index_type < 0 ||
      index_type > 1 || signed_offset < 0) {
    *failure = @"Metal 4 indexed-draw arguments are invalid";
    return false;
  }
  const NSUInteger stride = index_type == 0 ? 2 : 4;
  const std::uint64_t unsigned_offset =
      static_cast<std::uint64_t>(signed_offset);
  if (unsigned_offset > index_buffer.length || unsigned_offset % stride != 0 ||
      static_cast<NSUInteger>(index_count) >
          std::numeric_limits<NSUInteger>::max() / stride) {
    *failure = @"Metal 4 indexed-draw arguments are invalid";
    return false;
  }
  const NSUInteger offset = static_cast<NSUInteger>(unsigned_offset);
  const NSUInteger required_length =
      static_cast<NSUInteger>(index_count) * stride;
  const MTLGPUAddress base_address = index_buffer.gpuAddress;
  const NSUInteger available_length = index_buffer.length - offset;
  if (required_length > available_length || base_address == 0 ||
      static_cast<MTLGPUAddress>(offset) >
          std::numeric_limits<MTLGPUAddress>::max() - base_address) {
    *failure = @"Metal 4 indexed draw exceeds its checked buffer range";
    return false;
  }
  draw->primitive = static_cast<MTLPrimitiveType>(primitive);
  draw->index_count = static_cast<NSUInteger>(index_count);
  draw->index_type = static_cast<MTLIndexType>(index_type);
  draw->index_address =
      base_address + static_cast<MTLGPUAddress>(offset);
  draw->index_length = available_length - (available_length % stride);
  return true;
}

struct PrismelMetal4BufferRange {
  MTLGPUAddress address;
  NSUInteger length;
};

static_assert(sizeof(MTLDrawPrimitivesIndirectArguments) == 16);
static_assert(offsetof(MTLDrawPrimitivesIndirectArguments, vertexCount) == 0);
static_assert(offsetof(MTLDrawPrimitivesIndirectArguments, instanceCount) == 4);
static_assert(offsetof(MTLDrawPrimitivesIndirectArguments, vertexStart) == 8);
static_assert(offsetof(MTLDrawPrimitivesIndirectArguments, baseInstance) == 12);
static_assert(sizeof(MTLDrawIndexedPrimitivesIndirectArguments) == 20);
static_assert(
    offsetof(MTLDrawIndexedPrimitivesIndirectArguments, indexCount) == 0);
static_assert(
    offsetof(MTLDrawIndexedPrimitivesIndirectArguments, instanceCount) == 4);
static_assert(
    offsetof(MTLDrawIndexedPrimitivesIndirectArguments, indexStart) == 8);
static_assert(
    offsetof(MTLDrawIndexedPrimitivesIndirectArguments, baseVertex) == 12);
static_assert(
    offsetof(MTLDrawIndexedPrimitivesIndirectArguments, baseInstance) == 16);

API_AVAILABLE(macos(26.0))
bool prismel_metal4_explicit_buffer_range(
    id<MTLBuffer> buffer, PrismelMetal4CommandBufferState *command_buffer,
    std::int64_t signed_offset, std::int64_t signed_length,
    NSUInteger alignment, PrismelMetal4BufferRange *range,
    NSString *__autoreleasing *failure) {
  if (buffer.device.registryID !=
          command_buffer.commandBuffer.device.registryID ||
      signed_offset < 0 || signed_length <= 0) {
    *failure = @"Metal 4 GPU-address buffer range is invalid";
    return false;
  }
  const std::uint64_t unsigned_offset =
      static_cast<std::uint64_t>(signed_offset);
  const std::uint64_t unsigned_length =
      static_cast<std::uint64_t>(signed_length);
  if (alignment == 0 || unsigned_offset % alignment != 0 ||
      unsigned_length % alignment != 0 || unsigned_offset > buffer.length ||
      unsigned_length > buffer.length - unsigned_offset) {
    *failure = @"Metal 4 GPU-address buffer range is misaligned or out of bounds";
    return false;
  }
  const MTLGPUAddress base_address = buffer.gpuAddress;
  if (base_address == 0 ||
      static_cast<MTLGPUAddress>(unsigned_offset) >
          std::numeric_limits<MTLGPUAddress>::max() - base_address) {
    *failure = @"Metal 4 GPU-address buffer range overflows";
    return false;
  }
  range->address =
      base_address + static_cast<MTLGPUAddress>(unsigned_offset);
  range->length = static_cast<NSUInteger>(unsigned_length);
  return true;
}

extern "C" CAMLprim value
caml_prismel_metal_command_queue_add_residency_sets(
    value raw_queue, value raw_sets) {
  CAMLparam2(raw_queue, raw_sets);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLCommandQueue> queue =
            object_of_handle(raw_queue, Handle_kind::Command_queue);
        auto residency_sets = residency_sets_of_array(raw_sets);
        [queue addResidencySets:residency_sets.data()
                            count:residency_sets.size()];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command_queue_remove_residency_sets(
    value raw_queue, value raw_sets) {
  CAMLparam2(raw_queue, raw_sets);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLCommandQueue> queue =
            object_of_handle(raw_queue, Handle_kind::Command_queue);
        auto residency_sets = residency_sets_of_array(raw_sets);
        [queue removeResidencySets:residency_sets.data()
                               count:residency_sets.size()];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command_buffer_use_residency_sets(
    value raw_buffer, value raw_sets) {
  CAMLparam2(raw_buffer, raw_sets);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLCommandBuffer> buffer =
            object_of_handle(raw_buffer, Handle_kind::Command_buffer);
        auto residency_sets = residency_sets_of_array(raw_sets);
        [buffer useResidencySets:residency_sets.data()
                             count:residency_sets.size()];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

static_assert(sizeof(MTLAccelerationStructureInstanceDescriptor) == 64);
static_assert(offsetof(MTLAccelerationStructureInstanceDescriptor, options) == 48);
static_assert(offsetof(MTLAccelerationStructureInstanceDescriptor, mask) == 52);
static_assert(offsetof(MTLAccelerationStructureInstanceDescriptor, accelerationStructureIndex) == 60);

extern "C" CAMLprim value caml_prismel_metal_acceleration_structure_create(
    value raw_device, value raw_size) {
  CAMLparam2(raw_device, raw_size);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      id<MTLAccelerationStructure> acceleration =
          [device newAccelerationStructureWithSize:Int64_val(raw_size)];
      if (acceleration == nil)
        CAMLreturn(result_error_text("Metal failed to allocate acceleration structure"));
      raw = allocate_handle(acceleration, Handle_kind::Acceleration_structure);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_acceleration_encoder_copy(
    value raw_encoder, value raw_source, value raw_destination) {
  CAMLparam3(raw_encoder, raw_source, raw_destination);
  @autoreleasepool {
    @try {
      id<MTLAccelerationStructureCommandEncoder> encoder =
          object_of_handle(raw_encoder, Handle_kind::Acceleration_encoder);
      [encoder copyAccelerationStructure:
                   object_of_handle(raw_source, Handle_kind::Acceleration_structure)
                toAccelerationStructure:
                   object_of_handle(raw_destination, Handle_kind::Acceleration_structure)];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value
caml_prismel_metal_acceleration_encoder_copy_and_compact(
    value raw_encoder, value raw_source, value raw_destination) {
  CAMLparam3(raw_encoder, raw_source, raw_destination);
  @autoreleasepool {
    @try {
      id<MTLAccelerationStructureCommandEncoder> encoder =
          object_of_handle(raw_encoder, Handle_kind::Acceleration_encoder);
      [encoder copyAndCompactAccelerationStructure:
                   object_of_handle(raw_source, Handle_kind::Acceleration_structure)
                          toAccelerationStructure:
                   object_of_handle(raw_destination, Handle_kind::Acceleration_structure)];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_compute_pipeline_function_handle(
    value raw_pipeline, value raw_function) {
  CAMLparam2(raw_pipeline, raw_function);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLComputePipelineState> pipeline =
        object_of_handle(raw_pipeline, Handle_kind::Compute_pipeline);
    id<MTLFunction> function = object_of_handle(raw_function, Handle_kind::Function);
    id<MTLFunctionHandle> handle = [pipeline functionHandleWithFunction:function];
    if (handle == nil)
      CAMLreturn(result_error_text("Metal pipeline rejected the function handle"));
    raw = allocate_handle(handle, Handle_kind::Function_handle);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compute_pipeline_visible_function_table(
    value raw_pipeline, value raw_count) {
  CAMLparam2(raw_pipeline, raw_count);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLComputePipelineState> pipeline =
        object_of_handle(raw_pipeline, Handle_kind::Compute_pipeline);
    MTLVisibleFunctionTableDescriptor *descriptor =
        [MTLVisibleFunctionTableDescriptor visibleFunctionTableDescriptor];
    descriptor.functionCount = Int64_val(raw_count);
    id<MTLVisibleFunctionTable> table =
        [pipeline newVisibleFunctionTableWithDescriptor:descriptor];
    if (table == nil)
      CAMLreturn(result_error_text("Metal failed to allocate visible function table"));
    raw = allocate_handle(table, Handle_kind::Visible_function_table);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compute_pipeline_intersection_function_table(
    value raw_pipeline, value raw_count) {
  CAMLparam2(raw_pipeline, raw_count);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLComputePipelineState> pipeline =
        object_of_handle(raw_pipeline, Handle_kind::Compute_pipeline);
    MTLIntersectionFunctionTableDescriptor *descriptor =
        [MTLIntersectionFunctionTableDescriptor intersectionFunctionTableDescriptor];
    descriptor.functionCount = Int64_val(raw_count);
    id<MTLIntersectionFunctionTable> table =
        [pipeline newIntersectionFunctionTableWithDescriptor:descriptor];
    if (table == nil)
      CAMLreturn(result_error_text("Metal failed to allocate intersection function table"));
    raw = allocate_handle(table, Handle_kind::Intersection_function_table);
  }
  CAMLreturn(result_ok(raw));
}

static id optional_object(value raw, Handle_kind kind) {
  return Is_block(raw) ? object_of_handle(Field(raw, 0), kind) : nil;
}

extern "C" CAMLprim value caml_prismel_metal_visible_function_table_set_function(
    value raw_table, value raw_function, value raw_index) {
  CAMLparam3(raw_table, raw_function, raw_index);
  @autoreleasepool {
    id<MTLVisibleFunctionTable> table =
        object_of_handle(raw_table, Handle_kind::Visible_function_table);
    [table setFunction:optional_object(raw_function, Handle_kind::Function_handle)
                atIndex:Int_val(raw_index)];
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value
caml_prismel_metal_intersection_function_table_set_function(
    value raw_table, value raw_function, value raw_index) {
  CAMLparam3(raw_table, raw_function, raw_index);
  @autoreleasepool {
    id<MTLIntersectionFunctionTable> table =
        object_of_handle(raw_table, Handle_kind::Intersection_function_table);
    [table setFunction:optional_object(raw_function, Handle_kind::Function_handle)
                atIndex:Int_val(raw_index)];
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value
caml_prismel_metal_intersection_function_table_set_buffer(
    value raw_table, value raw_buffer, value raw_offset, value raw_index) {
  CAMLparam4(raw_table, raw_buffer, raw_offset, raw_index);
  @autoreleasepool {
    id<MTLIntersectionFunctionTable> table =
        object_of_handle(raw_table, Handle_kind::Intersection_function_table);
    [table setBuffer:optional_object(raw_buffer, Handle_kind::Buffer)
               offset:Int64_val(raw_offset) atIndex:Int_val(raw_index)];
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_layer_create(value raw_device) {
  CAMLparam1(raw_device); CAMLlocal1(raw); @autoreleasepool { @try {
    CAMetalLayer *layer=[CAMetalLayer layer]; layer.device=object_of_handle(raw_device,Handle_kind::Device);
    raw=allocate_handle(layer,Handle_kind::Metal_layer);
  } @catch(NSException*x){CAMLreturn(result_error(x.reason));} } CAMLreturn(result_ok(raw));
}
extern "C" CAMLprim value caml_prismel_metal_layer_adopt_borrowed(value raw_device,value token,value owner,value generation){CAMLparam4(raw_device,token,owner,generation);CAMLlocal1(raw);@autoreleasepool{@try{void*pointer=prismel_native_layer_token_borrow(token,Int64_val(owner),Int64_val(generation));if(pointer==nullptr)CAMLreturn(result_error_text("native layer token is stale or belongs to another owner"));id object=(__bridge id)pointer;if(![object isKindOfClass:[CAMetalLayer class]])CAMLreturn(result_error_text("native layer token does not contain CAMetalLayer"));CAMetalLayer*layer=(CAMetalLayer*)object;id<MTLDevice>device=object_of_handle(raw_device,Handle_kind::Device);if(layer.device!=nil&&layer.device.registryID!=device.registryID)CAMLreturn(result_error_text("CAMetalLayer belongs to another Metal device"));layer.device=device;raw=allocate_handle(layer,Handle_kind::Metal_layer);CAMLreturn(result_ok(raw));}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}}
extern "C" CAMLprim value caml_prismel_metal_layer_configure(value rl,value rw,value rh,value rf,value rflags){
  CAMLparam5(rl,rw,rh,rf,rflags); @try { CAMetalLayer*l=object_of_handle(rl,Handle_kind::Metal_layer);
    intnat w=Long_val(rw),h=Long_val(rh),format=Long_val(rf),maximum=Long_val(Field(rflags,1)); if(w<=0||h<=0||maximum<2||maximum>3||(format!=80&&format!=81&&format!=115))CAMLreturn(result_error_text("invalid Metal layer configuration"));
    l.drawableSize=CGSizeMake(w,h);l.pixelFormat=(MTLPixelFormat)format;l.framebufferOnly=Bool_val(Field(rflags,0));l.maximumDrawableCount=Long_val(Field(rflags,1));l.allowsNextDrawableTimeout=Bool_val(Field(rflags,2));l.displaySyncEnabled=Bool_val(Field(rflags,3));l.presentsWithTransaction=Bool_val(Field(rflags,4));
    CAMLreturn(result_unit()); } @catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_layer_next_drawable(value rl){CAMLparam1(rl);CAMLlocal3(raw,option,result);@autoreleasepool{@try{id<CAMetalDrawable>d=[object_of_handle(rl,Handle_kind::Metal_layer) nextDrawable];if(!d)CAMLreturn(result_ok(Val_none));raw=allocate_handle(d,Handle_kind::Metal_drawable);option=caml_alloc(1,0);Store_field(option,0,raw);result=result_ok(option);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}}

/* M3: former metal_layer10_residual_bridge.inc */

/* M3: former metal_presentation_layer_snapshot.inc */

extern "C" CAMLprim value caml_prismel_metal_drawable_texture(value rd){CAMLparam1(rd);CAMLlocal3(raw,metadata,result);@autoreleasepool{@try{id<CAMetalDrawable>d=object_of_handle(rd,Handle_kind::Metal_drawable);id<MTLTexture>texture=d.texture;if(!texture)CAMLreturn(result_error_text("drawable has no texture"));raw=allocate_handle(texture,Handle_kind::Texture);metadata=caml_alloc_tuple(4);Store_field(metadata,0,raw);Store_field(metadata,1,Val_long(texture.width));Store_field(metadata,2,Val_long(texture.height));Store_field(metadata,3,Val_long(texture.pixelFormat));result=result_ok(metadata);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}}
extern "C" CAMLprim value caml_prismel_metal_command_buffer_present_drawable(value rc,value rd,value rmode,value rt){CAMLparam4(rc,rd,rmode,rt);@try{id<MTLCommandBuffer>c=object_of_handle(rc,Handle_kind::Command_buffer);id<CAMetalDrawable>d=object_of_handle(rd,Handle_kind::Metal_drawable);switch(Long_val(rmode)){case 0:[c presentDrawable:d];break;case 1:[c presentDrawable:d atTime:Double_val(rt)];break;case 2:[c presentDrawable:d afterMinimumDuration:Double_val(rt)];break;default:CAMLreturn(result_error_text("invalid presentation mode"));}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

/* M3: former metal_presentation_command_snapshot.inc */
extern "C" CAMLprim value caml_prismel_metal_presentation_command_snapshot(value raw){CAMLparam1(raw);CAMLlocal2(tuple,result);@try{id<MTLCommandBuffer>c=object_of_handle(raw,Handle_kind::Command_buffer);tuple=caml_alloc_tuple(8);Store_field(tuple,0,caml_copy_int64(c.commandQueue.device.registryID));Store_field(tuple,1,caml_copy_int64(c.device.registryID));Store_field(tuple,2,caml_copy_int64(c.errorOptions));Store_field(tuple,3,caml_copy_double(c.GPUStartTime));Store_field(tuple,4,caml_copy_double(c.GPUEndTime));Store_field(tuple,5,caml_copy_double(c.kernelStartTime));Store_field(tuple,6,caml_copy_double(c.kernelEndTime));Store_field(tuple,7,Val_bool(c.retainedReferences));result=result_ok(tuple);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

struct PresentationCallbackState { std::atomic<int> state{0}; value *root=nullptr; };
struct PresentationCallbackToken { std::shared_ptr<PresentationCallbackState> state; };

extern "C" CAMLprim value caml_prismel_metal_command_buffer_cancel_handler(value raw_token){CAMLparam1(raw_token);auto *token=(PresentationCallbackToken*)Nativeint_val(raw_token);if(token){int expected=0;if(token->state->state.compare_exchange_strong(expected,2)){caml_remove_generational_global_root(token->state->root);free(token->state->root);token->state->root=nullptr;}delete token;}CAMLreturn(Val_unit);}
extern "C" CAMLprim value caml_prismel_metal_render_pass_descriptor_create(value unit){CAMLparam1(unit);CAMLlocal1(raw);@autoreleasepool{raw=allocate_handle([MTLRenderPassDescriptor renderPassDescriptor],Handle_kind::Render_pass_descriptor);}CAMLreturn(result_ok(raw));}
extern "C" CAMLprim value caml_prismel_metal_render_pass_descriptor_set_sizes(value rp,value rw,value rh,value ra,value rs){CAMLparam5(rp,rw,rh,ra,rs);MTLRenderPassDescriptor*p=object_of_handle(rp,Handle_kind::Render_pass_descriptor);intnat w=Long_val(rw),h=Long_val(rh),a=Long_val(ra),s=Long_val(rs);if(w<=0||h<=0||a<=0||s<=0)CAMLreturn(result_error_text("invalid render pass sizes"));p.renderTargetWidth=w;p.renderTargetHeight=h;p.renderTargetArrayLength=a;p.defaultRasterSampleCount=s;CAMLreturn(result_unit());}

/* M3: former metal_presentation_render_pass_advanced.inc */

extern "C" CAMLprim value caml_prismel_metal_render_pass_sample_set(
    value raw,value raw_index,value raw_buffer,value raw_sv,value raw_ev,
    value raw_sf,value raw_ef){
  CAMLparam5(raw,raw_index,raw_buffer,raw_sv,raw_ev);CAMLxparam2(raw_sf,raw_ef);
  int64_t index=Int64_val(raw_index);
  if(index<0||index>=4)CAMLreturn(result_error_text("render sample attachment index is outside [0,4)"));
  @try{
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);
    MTLRenderPassSampleBufferAttachmentDescriptor*source=nil;
    if(!Is_none(raw_buffer)){
      source=[MTLRenderPassSampleBufferAttachmentDescriptor new];
      source.sampleBuffer=object_of_handle(Field(raw_buffer,0),Handle_kind::Counter_sample_buffer);
      source.startOfVertexSampleIndex=(NSUInteger)Int64_val(raw_sv);
      source.endOfVertexSampleIndex=(NSUInteger)Int64_val(raw_ev);
      source.startOfFragmentSampleIndex=(NSUInteger)Int64_val(raw_sf);
      source.endOfFragmentSampleIndex=(NSUInteger)Int64_val(raw_ef);
    }
    [p.sampleBufferAttachments setObject:source atIndexedSubscript:(NSUInteger)index];
    MTLRenderPassSampleBufferAttachmentDescriptor*stored=
      [p.sampleBufferAttachments objectAtIndexedSubscript:(NSUInteger)index];
    if(stored==nil||stored==source)CAMLreturn(result_error_text("Metal changed render sample attachment copy/reset semantics"));
    if(source!=nil&&(stored.sampleBuffer!=source.sampleBuffer||
       stored.startOfVertexSampleIndex!=source.startOfVertexSampleIndex||
       stored.endOfVertexSampleIndex!=source.endOfVertexSampleIndex||
       stored.startOfFragmentSampleIndex!=source.startOfFragmentSampleIndex||
       stored.endOfFragmentSampleIndex!=source.endOfFragmentSampleIndex))
      CAMLreturn(result_error_text("Metal changed render sample attachment values"));
    if(source==nil&&stored.sampleBuffer!=nil)
      CAMLreturn(result_error_text("Metal failed to reset render sample attachment"));
    CAMLreturn(result_unit());
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_render_pass_sample_set_bytecode(value*argv,int argc){(void)argc;return caml_prismel_metal_render_pass_sample_set(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5],argv[6]);}

extern "C" CAMLprim value caml_prismel_metal_render_pass_resolve_texture(
    value raw,value replacement,value set_raw){
  CAMLparam3(raw,replacement,set_raw);CAMLlocal3(handle,option,result);
  @try{
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);
    MTLRenderPassColorAttachmentDescriptor*color=p.colorAttachments[0];
    if(Bool_val(set_raw))color.resolveTexture=Is_none(replacement)?nil:object_of_handle(Field(replacement,0),Handle_kind::Texture);
    id<MTLTexture>texture=color.resolveTexture;
    if(texture==nil)option=Val_none;else{handle=allocate_handle(texture,Handle_kind::Texture);option=caml_alloc(1,0);Store_field(option,0,handle);}
    result=result_ok(option);CAMLreturn(result);
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_render_pass_color_store_action(value raw,value action){
  CAMLparam2(raw,action);
  @try{
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);
    p.colorAttachments[0].storeAction=(MTLStoreAction)Int_val(action);
    CAMLreturn(result_unit());
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_render_pass_color_load_action(value raw,value action){
  CAMLparam2(raw,action);
  @try{
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);
    p.colorAttachments[0].loadAction=(MTLLoadAction)Int_val(action);
    CAMLreturn(result_unit());
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}
}

extern "C" CAMLprim value caml_prismel_metal_render_pass_descriptor_set_attachments(
    value rp,value rc,value rd,value rs,value rv,value rclear) {
  CAMLparam5(rp,rc,rd,rs,rv); CAMLxparam1(rclear);
  MTLRenderPassDescriptor *p=nil;
  id<MTLTexture> old_color=nil,old_depth=nil,old_stencil=nil;
  id<MTLBuffer> old_visibility=nil;
  MTLLoadAction old_color_load=MTLLoadActionDontCare;
  MTLStoreAction old_color_store=MTLStoreActionDontCare;
  MTLClearColor old_clear=MTLClearColorMake(0,0,0,0);
  MTLLoadAction old_depth_load=MTLLoadActionDontCare;
  MTLStoreAction old_depth_store=MTLStoreActionDontCare;
  double old_clear_depth=1.0;
  MTLLoadAction old_stencil_load=MTLLoadActionDontCare;
  MTLStoreAction old_stencil_store=MTLStoreActionDontCare;
  uint32_t old_clear_stencil=0;
  auto restore = [&]() {
    if(!p)return;
    p.colorAttachments[0].texture=old_color;
    p.colorAttachments[0].loadAction=old_color_load;
    p.colorAttachments[0].storeAction=old_color_store;
    p.colorAttachments[0].clearColor=old_clear;
    p.depthAttachment.texture=old_depth;
    p.depthAttachment.loadAction=old_depth_load;
    p.depthAttachment.storeAction=old_depth_store;
    p.depthAttachment.clearDepth=old_clear_depth;
    p.stencilAttachment.texture=old_stencil;
    p.stencilAttachment.loadAction=old_stencil_load;
    p.stencilAttachment.storeAction=old_stencil_store;
    p.stencilAttachment.clearStencil=old_clear_stencil;
    p.visibilityResultBuffer=old_visibility;
  };
  @try {
    p=object_of_handle(rp,Handle_kind::Render_pass_descriptor);
    old_color=p.colorAttachments[0].texture;
    old_color_load=p.colorAttachments[0].loadAction;
    old_color_store=p.colorAttachments[0].storeAction;
    old_clear=p.colorAttachments[0].clearColor;
    old_depth=p.depthAttachment.texture;
    old_depth_load=p.depthAttachment.loadAction;
    old_depth_store=p.depthAttachment.storeAction;
    old_clear_depth=p.depthAttachment.clearDepth;
    old_stencil=p.stencilAttachment.texture;
    old_stencil_load=p.stencilAttachment.loadAction;
    old_stencil_store=p.stencilAttachment.storeAction;
    old_clear_stencil=p.stencilAttachment.clearStencil;
    old_visibility=p.visibilityResultBuffer;
    id<MTLTexture> color=object_of_handle(rc,Handle_kind::Texture);
    id<MTLTexture> depth=optional_object(rd,Handle_kind::Texture);
    id<MTLTexture> stencil=optional_object(rs,Handle_kind::Texture);
    id<MTLBuffer> visibility=optional_object(rv,Handle_kind::Buffer);
    MTLRenderPassColorAttachmentDescriptor *source=
        [MTLRenderPassColorAttachmentDescriptor new];
    source.texture=color;
    source.loadAction=MTLLoadActionClear;
    source.storeAction=MTLStoreActionStore;
    source.clearColor=MTLClearColorMake(Double_val(Field(rclear,0)),Double_val(Field(rclear,1)),Double_val(Field(rclear,2)),Double_val(Field(rclear,3)));
    [p.colorAttachments setObject:source atIndexedSubscript:0];
    MTLRenderPassColorAttachmentDescriptor *stored=
        [p.colorAttachments objectAtIndexedSubscript:0];
    if(stored==nil||stored==source){restore();CAMLreturn(result_error_text("Metal changed render color attachment copy semantics"));}
    p.depthAttachment.texture=depth;
    if(depth){p.depthAttachment.loadAction=MTLLoadActionClear;p.depthAttachment.storeAction=MTLStoreActionStore;p.depthAttachment.clearDepth=1.0;}
    p.stencilAttachment.texture=stencil;
    if(stencil){p.stencilAttachment.loadAction=MTLLoadActionClear;p.stencilAttachment.storeAction=MTLStoreActionStore;p.stencilAttachment.clearStencil=0;}
    p.visibilityResultBuffer=visibility;
    if(stored.texture!=color || p.depthAttachment.texture!=depth ||
       p.stencilAttachment.texture!=stencil || p.visibilityResultBuffer!=visibility){
      restore();
      CAMLreturn(result_error_text("render pass attachment round-trip mismatch"));
    }
    CAMLreturn(result_unit());
  } @catch(NSException*x){restore();CAMLreturn(result_error(x.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_render_pass_descriptor_set_attachments_bytecode(value *argv,int argc){(void)argc;return caml_prismel_metal_render_pass_descriptor_set_attachments(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5]);}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_render_encoder_attachments(
    value raw_buffer,value raw_color,value raw_depth,value raw_stencil,value raw_clear) {
  CAMLparam5(raw_buffer,raw_color,raw_depth,raw_stencil,raw_clear); CAMLlocal1(raw);
  @autoreleasepool { @try {
    id<MTLCommandBuffer> buffer=object_of_handle(raw_buffer,Handle_kind::Command_buffer);
    id<MTLTexture> color=object_of_handle(raw_color,Handle_kind::Texture);
    id<MTLTexture> depth=optional_object(raw_depth,Handle_kind::Texture);
    id<MTLTexture> stencil=optional_object(raw_stencil,Handle_kind::Texture);
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=color; pass.colorAttachments[0].loadAction=MTLLoadActionClear; pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    pass.colorAttachments[0].clearColor=MTLClearColorMake(Double_val(Field(raw_clear,0)),Double_val(Field(raw_clear,1)),Double_val(Field(raw_clear,2)),Double_val(Field(raw_clear,3)));
    if(depth){pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.storeAction=MTLStoreActionStore;pass.depthAttachment.clearDepth=1.0;}
    if(stencil){pass.stencilAttachment.texture=stencil;pass.stencilAttachment.loadAction=MTLLoadActionClear;pass.stencilAttachment.storeAction=MTLStoreActionStore;pass.stencilAttachment.clearStencil=0;}
    id<MTLRenderCommandEncoder> encoder=[buffer renderCommandEncoderWithDescriptor:pass];
    if(!encoder) CAMLreturn(result_error_text("Metal failed to create render encoder with attachments"));
    raw=allocate_handle(encoder,Handle_kind::Render_encoder);
  } @catch(NSException*x){CAMLreturn(result_error(x.reason));} }
  CAMLreturn(result_ok(raw));
}
extern "C" CAMLprim value caml_prismel_metal_command_buffer_render_encoder_attachments_bytecode(value *argv,int argc){(void)argc;return caml_prismel_metal_command_buffer_render_encoder_attachments(argv[0],argv[1],argv[2],argv[3],argv[4]);}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_update_fence(value re,value rf,value rs){
  CAMLparam3(re,rf,rs); @try { [object_of_handle(re,Handle_kind::Render_encoder) updateFence:object_of_handle(rf,Handle_kind::Fence) afterStages:(MTLRenderStages)Long_val(rs)]; CAMLreturn(result_unit()); } @catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_encoder_wait_fence(value re,value rf,value rs){
  CAMLparam3(re,rf,rs); @try { [object_of_handle(re,Handle_kind::Render_encoder) waitForFence:object_of_handle(rf,Handle_kind::Fence) beforeStages:(MTLRenderStages)Long_val(rs)]; CAMLreturn(result_unit()); } @catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_use_heaps(value re,value rh,value rs){CAMLparam3(re,rh,rs);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);mlsize_t n=Wosize_val(rh);std::vector<id<MTLHeap>>v;v.reserve(n);for(mlsize_t i=0;i<n;i++)v.push_back(object_of_handle(Field(rh,i),Handle_kind::Heap));[e useHeaps:v.data() count:n stages:(MTLRenderStages)Long_val(rs)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
static std::atomic<int> test_render_encoder_resource_failure_countdown{-1};

extern "C" CAMLprim value
caml_prismel_metal_render_encoder_use_resources(value re, value rr, value ru,
                                                  value rs) {
  CAMLparam4(re, rr, ru, rs);
  int remaining = test_render_encoder_resource_failure_countdown.load();
  if (remaining >= 0) {
    remaining = test_render_encoder_resource_failure_countdown.fetch_sub(1);
    if (remaining == 0) {
      test_render_encoder_resource_failure_countdown.store(-1);
      CAMLreturn(result_error(@"injected render resource-use failure"));
    }
  }
  @try {
    id<MTLRenderCommandEncoder> e =
        object_of_handle(re, Handle_kind::Render_encoder);
    mlsize_t n = Wosize_val(rr);
    std::vector<id<MTLResource>> v;
    v.reserve(n);
    for (mlsize_t i = 0; i < n; i++)
      v.push_back(resource_of_handle(Field(rr, i)));
    [e useResources:v.data()
              count:n
              usage:(MTLResourceUsage)Long_val(ru)
             stages:(MTLRenderStages)Long_val(rs)];
    CAMLreturn(result_unit());
  } @catch (NSException *x) {
    CAMLreturn(result_error(x.reason));
  }
}
extern "C" CAMLprim value caml_prismel_metal_render_encoder_execute_icb_range(value re,value ri,value rl,value rn){CAMLparam4(re,ri,rl,rn);@try{[object_of_handle(re,Handle_kind::Render_encoder) executeCommandsInBuffer:object_of_handle(ri,Handle_kind::Indirect_command_buffer) withRange:NSMakeRange(Long_val(rl),Long_val(rn))];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_pipeline(
    value raw_encoder, value raw_pipeline) {
  CAMLparam2(raw_encoder, raw_pipeline);
  id<MTLRenderCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  id<MTLRenderPipelineState> pipeline =
      object_of_handle(raw_pipeline, Handle_kind::Render_pipeline);
  [encoder setRenderPipelineState:pipeline];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_vertex_buffer(
    value raw_encoder, value raw_buffer, value raw_offset, value raw_index) {
  CAMLparam4(raw_encoder, raw_buffer, raw_offset, raw_index);
  id<MTLRenderCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  id<MTLBuffer> buffer = object_of_handle(raw_buffer, Handle_kind::Buffer);
  const std::int64_t offset = Int64_val(raw_offset);
  const intnat index = Long_val(raw_index);
  if (offset < 0 || static_cast<std::uint64_t>(offset) > buffer.length ||
      index < 0 || index >= 31) {
    CAMLreturn(result_error_text("render vertex-buffer binding is out of range"));
  }
  [encoder setVertexBuffer:buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_fragment_buffer(
    value raw_encoder, value raw_buffer, value raw_offset, value raw_index) {
  CAMLparam4(raw_encoder, raw_buffer, raw_offset, raw_index);
  id<MTLRenderCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  id<MTLBuffer> buffer = object_of_handle(raw_buffer, Handle_kind::Buffer);
  const std::int64_t offset = Int64_val(raw_offset);
  const intnat index = Long_val(raw_index);
  if (offset < 0 || static_cast<std::uint64_t>(offset) > buffer.length ||
      index < 0 || index >= 31) {
    CAMLreturn(result_error_text("render fragment-buffer binding is out of range"));
  }
  [encoder setFragmentBuffer:buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index];
  CAMLreturn(result_unit());
}

static const char *validate_indexed_draw_batch(
    value raw_pipelines, value raw_buffers, value raw_stages,
    value raw_offsets, value raw_slots, value raw_primitives, value raw_counts,
    value raw_index_types, value raw_index_buffers, value raw_index_offsets,
    id<MTLDevice> expected_device) {
  const mlsize_t draw_count = Wosize_val(raw_pipelines);
  if (draw_count == 0 || Wosize_val(raw_buffers) != draw_count ||
      Wosize_val(raw_stages) != draw_count ||
      Wosize_val(raw_offsets) != draw_count ||
      Wosize_val(raw_slots) != draw_count ||
      Wosize_val(raw_primitives) != draw_count ||
      Wosize_val(raw_counts) != draw_count ||
      Wosize_val(raw_index_types) != draw_count ||
      Wosize_val(raw_index_buffers) != draw_count ||
      Wosize_val(raw_index_offsets) != draw_count)
    return "indexed draw batch cardinality differs";
  for (mlsize_t draw = 0; draw < draw_count; ++draw) {
    value buffers = Field(raw_buffers, draw);
    value stages = Field(raw_stages, draw);
    value offsets = Field(raw_offsets, draw);
    value slots = Field(raw_slots, draw);
    const mlsize_t binding_count = Wosize_val(buffers);
    if (Wosize_val(stages) != binding_count ||
        Wosize_val(offsets) != binding_count ||
        Wosize_val(slots) != binding_count)
      return "indexed draw binding cardinality differs";
    id<MTLRenderPipelineState> pipeline = object_of_handle(
        Field(raw_pipelines, draw), Handle_kind::Render_pipeline);
    const intnat primitive = Long_val(Field(raw_primitives, draw));
    const std::int64_t count = Int64_val(Field(raw_counts, draw));
    const intnat index_type = Long_val(Field(raw_index_types, draw));
    id<MTLBuffer> index_buffer = object_of_handle(
        Field(raw_index_buffers, draw), Handle_kind::Buffer);
    const std::int64_t index_offset = Int64_val(Field(raw_index_offsets, draw));
    const std::uint64_t index_width = index_type == 0 ? 2 : 4;
    if ((expected_device != nil &&
         (pipeline.device.registryID != expected_device.registryID ||
          index_buffer.device.registryID != expected_device.registryID)) ||
        primitive < 0 || primitive > 4 || count <= 0 ||
        (index_type != 0 && index_type != 1) || index_offset < 0 ||
        static_cast<std::uint64_t>(index_offset) % index_width != 0 ||
        static_cast<std::uint64_t>(count) >
            std::numeric_limits<std::uint64_t>::max() / index_width ||
        static_cast<std::uint64_t>(index_offset) > index_buffer.length ||
        static_cast<std::uint64_t>(count) * index_width >
            index_buffer.length - static_cast<std::uint64_t>(index_offset))
      return "indexed draw range or device is invalid";
    for (mlsize_t binding = 0; binding < binding_count; ++binding) {
      id<MTLBuffer> buffer =
          object_of_handle(Field(buffers, binding), Handle_kind::Buffer);
      const std::int64_t offset = Int64_val(Field(offsets, binding));
      const intnat slot = Long_val(Field(slots, binding));
      const intnat stage = Long_val(Field(stages, binding));
      if ((expected_device != nil &&
           buffer.device.registryID != expected_device.registryID) ||
          (stage != 0 && stage != 1) || slot < 0 || slot >= 31 || offset < 0 ||
          static_cast<std::uint64_t>(offset) > buffer.length)
        return "indexed draw binding is invalid";
    }
  }
  return nullptr;
}

static void encode_indexed_draw_batch(
    id<MTLRenderCommandEncoder> encoder, value raw_pipelines,
    value raw_buffers, value raw_stages, value raw_offsets, value raw_slots,
    value raw_primitives, value raw_counts, value raw_index_types,
    value raw_index_buffers, value raw_index_offsets) {
  const mlsize_t draw_count = Wosize_val(raw_pipelines);
  for (mlsize_t draw = 0; draw < draw_count; ++draw) {
    value buffers = Field(raw_buffers, draw);
    value stages = Field(raw_stages, draw);
    value offsets = Field(raw_offsets, draw);
    value slots = Field(raw_slots, draw);
    const mlsize_t binding_count = Wosize_val(buffers);
    [encoder setRenderPipelineState:
        object_of_handle(Field(raw_pipelines, draw),
                         Handle_kind::Render_pipeline)];
    for (mlsize_t binding = 0; binding < binding_count; ++binding) {
      id<MTLBuffer> buffer =
          object_of_handle(Field(buffers, binding), Handle_kind::Buffer);
      const NSUInteger offset = (NSUInteger)Int64_val(Field(offsets, binding));
      const NSUInteger slot = (NSUInteger)Long_val(Field(slots, binding));
      if (Long_val(Field(stages, binding)) == 0)
        [encoder setVertexBuffer:buffer offset:offset atIndex:slot];
      else
        [encoder setFragmentBuffer:buffer offset:offset atIndex:slot];
    }
    [encoder drawIndexedPrimitives:
        (MTLPrimitiveType)Long_val(Field(raw_primitives, draw))
                            indexCount:(NSUInteger)Int64_val(Field(raw_counts, draw))
                             indexType:(MTLIndexType)Long_val(Field(raw_index_types, draw))
                           indexBuffer:object_of_handle(
                               Field(raw_index_buffers, draw), Handle_kind::Buffer)
                     indexBufferOffset:(NSUInteger)Int64_val(
                               Field(raw_index_offsets, draw))];
  }
}

extern "C" CAMLprim value
caml_prismel_metal_render_encoder_execute_indexed_draws(
    value raw_encoder, value raw_pipelines, value raw_buffers,
    value raw_stages, value raw_offsets, value raw_slots,
    value raw_primitives, value raw_counts, value raw_index_types,
    value raw_index_buffers, value raw_index_offsets) {
  CAMLparam5(raw_encoder, raw_pipelines, raw_buffers, raw_stages, raw_offsets);
  CAMLxparam5(raw_slots, raw_primitives, raw_counts, raw_index_types,
              raw_index_buffers);
  CAMLxparam1(raw_index_offsets);
  @try {
    const char *error = validate_indexed_draw_batch(
        raw_pipelines, raw_buffers, raw_stages, raw_offsets, raw_slots,
        raw_primitives, raw_counts, raw_index_types, raw_index_buffers,
        raw_index_offsets, nil);
    if (error != nullptr) CAMLreturn(result_error_text(error));
    id<MTLRenderCommandEncoder> encoder =
        object_of_handle(raw_encoder, Handle_kind::Render_encoder);
    encode_indexed_draw_batch(
        encoder, raw_pipelines, raw_buffers, raw_stages, raw_offsets, raw_slots,
        raw_primitives, raw_counts, raw_index_types, raw_index_buffers,
        raw_index_offsets);
    CAMLreturn(result_unit());
  } @catch (NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_render_encoder_execute_indexed_draws_bytecode(
    value *arguments, int count) {
  (void)count;
  return caml_prismel_metal_render_encoder_execute_indexed_draws(
      arguments[0], arguments[1], arguments[2], arguments[3], arguments[4],
      arguments[5], arguments[6], arguments[7], arguments[8], arguments[9],
      arguments[10]);
}

struct Prepared_render_pass_state {
  id<MTLCommandBuffer> command;
  MTLRenderPassDescriptor *pass;
  id<MTLTexture> target;
  id<MTLDepthStencilState> depth;
  MTLCullMode cull;
  bool has_stencil_references;
  uint32_t front_stencil_reference;
  uint32_t back_stencil_reference;
  MTLViewport viewport;
  MTLScissorRect scissor;
};

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_vertex_texture(
    value raw_encoder, value raw_texture, value raw_index) {
  CAMLparam3(raw_encoder, raw_texture, raw_index);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  id<MTLTexture> texture = object_of_handle(raw_texture, Handle_kind::Texture);
  const intnat index = Long_val(raw_index);
  if (index < 0 || index >= 31) CAMLreturn(result_error_text("render vertex-texture index is out of range"));
  [encoder setVertexTexture:texture atIndex:(NSUInteger)index];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_fragment_texture(
    value raw_encoder, value raw_texture, value raw_index) {
  CAMLparam3(raw_encoder, raw_texture, raw_index);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  id<MTLTexture> texture = object_of_handle(raw_texture, Handle_kind::Texture);
  const intnat index = Long_val(raw_index);
  if (index < 0 || index >= 31) CAMLreturn(result_error_text("render fragment-texture index is out of range"));
  [encoder setFragmentTexture:texture atIndex:(NSUInteger)index];
  CAMLreturn(result_unit());
}

static value render_encoder_set_bytes(value raw_encoder, value raw_bytes,
                                      value raw_index, bool vertex) {
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  NSUInteger length = caml_string_length(raw_bytes), index = Long_val(raw_index);
  if (length == 0 || length > 4096 || index >= 31)
    return result_error_text("render inline bytes are empty, too large, or out of range");
  if (vertex) [encoder setVertexBytes:Bytes_val(raw_bytes) length:length atIndex:index];
  else [encoder setFragmentBytes:Bytes_val(raw_bytes) length:length atIndex:index];
  return result_unit();
}
extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_vertex_bytes(value e,value b,value i){ CAMLparam3(e,b,i); CAMLreturn(render_encoder_set_bytes(e,b,i,true)); }
extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_fragment_bytes(value e,value b,value i){ CAMLparam3(e,b,i); CAMLreturn(render_encoder_set_bytes(e,b,i,false)); }

static value render_encoder_set_sampler(value raw_encoder, value raw_sampler,
                                        value raw_lod, value raw_index, bool vertex) {
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  id<MTLSamplerState> sampler = object_of_handle(raw_sampler, Handle_kind::Sampler);
  NSUInteger index = Long_val(raw_index);
  if (index >= 31) return result_error_text("render sampler index is out of range");
  if (Is_long(raw_lod)) {
    if (vertex) [encoder setVertexSamplerState:sampler atIndex:index];
    else [encoder setFragmentSamplerState:sampler atIndex:index];
  } else {
    value pair = Field(raw_lod,0); float lo=Double_val(Field(pair,0)), hi=Double_val(Field(pair,1));
    if (vertex) [encoder setVertexSamplerState:sampler lodMinClamp:lo lodMaxClamp:hi atIndex:index];
    else [encoder setFragmentSamplerState:sampler lodMinClamp:lo lodMaxClamp:hi atIndex:index];
  }
  return result_unit();
}
extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_vertex_sampler(value e,value s,value i){ CAMLparam3(e,s,i); CAMLreturn(render_encoder_set_sampler(e,s,Val_int(0),i,true)); }
extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_fragment_sampler(value e,value s,value i){ CAMLparam3(e,s,i); CAMLreturn(render_encoder_set_sampler(e,s,Val_int(0),i,false)); }
extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_vertex_sampler_lod(value e,value s,value l,value i){ CAMLparam4(e,s,l,i); CAMLlocal1(o); o=caml_alloc_small(1,0); Field(o,0)=l; CAMLreturn(render_encoder_set_sampler(e,s,o,i,true)); }
extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_fragment_sampler_lod(value e,value s,value l,value i){ CAMLparam4(e,s,l,i); CAMLlocal1(o); o=caml_alloc_small(1,0); Field(o,0)=l; CAMLreturn(render_encoder_set_sampler(e,s,o,i,false)); }

extern "C" CAMLprim value caml_prismel_metal_render_encoder_draw(
    value raw_encoder, value raw_first, value raw_count, value raw_instances) {
  CAMLparam4(raw_encoder, raw_first, raw_count, raw_instances);
  id<MTLRenderCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  const intnat first = Long_val(raw_first);
  const intnat count = Long_val(raw_count);
  const intnat instances = Long_val(raw_instances);
  if (first < 0 || count <= 0 || instances <= 0) {
    CAMLreturn(result_error_text("render draw range is invalid"));
  }
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle
              vertexStart:(NSUInteger)first
              vertexCount:(NSUInteger)count
            instanceCount:(NSUInteger)instances];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_draw_primitives(
    value raw_encoder, value raw_primitive, value raw_first, value raw_count,
    value raw_instances) {
  CAMLparam5(raw_encoder, raw_primitive, raw_first, raw_count, raw_instances);
  id<MTLRenderCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  const intnat primitive = Long_val(raw_primitive);
  const intnat first = Long_val(raw_first);
  const intnat count = Long_val(raw_count);
  const intnat instances = Long_val(raw_instances);
  if (primitive < 0 || primitive > 4 || first < 0 || count <= 0 || instances <= 0) {
    CAMLreturn(result_error_text("render draw primitive or range is invalid"));
  }
  [encoder drawPrimitives:static_cast<MTLPrimitiveType>(primitive)
              vertexStart:(NSUInteger)first
              vertexCount:(NSUInteger)count
            instanceCount:(NSUInteger)instances];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_pass_depth_stencil_actions(
    value rp, value rdepth_load, value rdepth_store, value rclear_depth,
    value rstencil_load, value rstencil_store, value rclear_stencil) {
  CAMLparam5(rp, rdepth_load, rdepth_store, rclear_depth, rstencil_load);
  CAMLxparam2(rstencil_store, rclear_stencil);
  @try {
    MTLRenderPassDescriptor *p = object_of_handle(rp, Handle_kind::Render_pass_descriptor);
    const intnat depth_load = Long_val(rdepth_load), depth_store = Long_val(rdepth_store);
    const intnat stencil_load = Long_val(rstencil_load), stencil_store = Long_val(rstencil_store);
    const double clear_depth = Double_val(rclear_depth);
    const intnat clear_stencil = Long_val(rclear_stencil);
    if (depth_load < 0 || depth_load > 2 || stencil_load < 0 || stencil_load > 2 ||
        depth_store < 0 || depth_store > 1 || stencil_store < 0 || stencil_store > 1 ||
        !(clear_depth >= 0.0 && clear_depth <= 1.0) || clear_stencil < 0 || clear_stencil > 255) {
      CAMLreturn(result_error_text("render pass depth/stencil action is out of range"));
    }
    if (p.depthAttachment.texture != nil) {
      p.depthAttachment.loadAction = static_cast<MTLLoadAction>(depth_load);
      p.depthAttachment.storeAction = depth_store ? MTLStoreActionStore : MTLStoreActionDontCare;
      p.depthAttachment.clearDepth = clear_depth;
    }
    if (p.stencilAttachment.texture != nil) {
      p.stencilAttachment.loadAction = static_cast<MTLLoadAction>(stencil_load);
      p.stencilAttachment.storeAction = stencil_store ? MTLStoreActionStore : MTLStoreActionDontCare;
      p.stencilAttachment.clearStencil = (uint32_t)clear_stencil;
    }
    CAMLreturn(result_unit());
  } @catch (NSException *x) { CAMLreturn(result_error(x.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_render_pass_depth_stencil_actions_bytecode(value *argv, int argc) {
  (void)argc;
  return caml_prismel_metal_render_pass_depth_stencil_actions(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_viewport(
    value raw_encoder, value raw_viewport) {
  CAMLparam2(raw_encoder, raw_viewport);
  id<MTLRenderCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  MTLViewport viewport = {
      Double_val(Field(raw_viewport, 0)), Double_val(Field(raw_viewport, 1)),
      Double_val(Field(raw_viewport, 2)), Double_val(Field(raw_viewport, 3)),
      Double_val(Field(raw_viewport, 4)), Double_val(Field(raw_viewport, 5))};
  [encoder setViewport:viewport];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_scissor(
    value raw_encoder, value raw_scissor) {
  CAMLparam2(raw_encoder, raw_scissor);
  id<MTLRenderCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  MTLScissorRect scissor = {(NSUInteger)Long_val(Field(raw_scissor, 0)),
                            (NSUInteger)Long_val(Field(raw_scissor, 1)),
                            (NSUInteger)Long_val(Field(raw_scissor, 2)),
                            (NSUInteger)Long_val(Field(raw_scissor, 3))};
  [encoder setScissorRect:scissor];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_cull_mode(
    value raw_encoder, value raw_mode) {
  CAMLparam2(raw_encoder, raw_mode);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  static const MTLCullMode modes[] = {MTLCullModeNone, MTLCullModeFront, MTLCullModeBack};
  [encoder setCullMode:modes[Long_val(raw_mode)]];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_winding(
    value raw_encoder, value raw_winding) {
  CAMLparam2(raw_encoder, raw_winding);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  static const MTLWinding values[] = {MTLWindingClockwise, MTLWindingCounterClockwise};
  [encoder setFrontFacingWinding:values[Long_val(raw_winding)]];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_stencil_reference(
    value raw_encoder, value raw_front, value raw_back) {
  CAMLparam3(raw_encoder, raw_front, raw_back);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  [encoder setStencilFrontReferenceValue:(uint32_t)Int32_val(raw_front)
                      backReferenceValue:(uint32_t)Int32_val(raw_back)];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_tile_width(value raw) {
  CAMLparam1(raw);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw, Handle_kind::Render_encoder);
  CAMLreturn(Val_long((intnat)encoder.tileWidth));
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_tile_height(value raw) {
  CAMLparam1(raw);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw, Handle_kind::Render_encoder);
  CAMLreturn(Val_long((intnat)encoder.tileHeight));
}

extern "C" CAMLprim value caml_prismel_metal_compute_encoder_set_pipeline(
    value raw_encoder, value raw_pipeline) {
  CAMLparam2(raw_encoder, raw_pipeline);
  id<MTLComputeCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Compute_encoder);
  id<MTLComputePipelineState> pipeline =
      object_of_handle(raw_pipeline, Handle_kind::Compute_pipeline);
  [encoder setComputePipelineState:pipeline];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_compute_encoder_set_buffer(
    value raw_encoder, value raw_buffer, value raw_offset, value raw_index) {
  CAMLparam4(raw_encoder, raw_buffer, raw_offset, raw_index);
  id<MTLComputeCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Compute_encoder);
  id<MTLBuffer> buffer = object_of_handle(raw_buffer, Handle_kind::Buffer);
  const std::int64_t offset = Int64_val(raw_offset);
  const intnat index = Long_val(raw_index);
  if (offset < 0 || static_cast<std::uint64_t>(offset) > buffer.length ||
      index < 0) {
    CAMLreturn(result_error_text("compute buffer binding is out of range"));
  }
  [encoder setBuffer:buffer
              offset:static_cast<NSUInteger>(offset)
             atIndex:static_cast<NSUInteger>(index)];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_compute_encoder_set_texture(
    value raw_encoder, value raw_texture, value raw_index) {
  CAMLparam3(raw_encoder, raw_texture, raw_index);
  id<MTLComputeCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Compute_encoder);
  id<MTLTexture> texture =
      object_of_handle(raw_texture, Handle_kind::Texture);
  const intnat index = Long_val(raw_index);
  if (index < 0) {
    CAMLreturn(result_error_text("compute texture index is negative"));
  }
  [encoder setTexture:texture atIndex:static_cast<NSUInteger>(index)];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_compute_encoder_dispatch(
    value raw_encoder, value raw_threads, value raw_threadgroup) {
  CAMLparam3(raw_encoder, raw_threads, raw_threadgroup);
  id<MTLComputeCommandEncoder> encoder =
      object_of_handle(raw_encoder, Handle_kind::Compute_encoder);
  const MTLSize threads =
      MTLSizeMake(positive_dimension(raw_threads, 0),
                  positive_dimension(raw_threads, 1),
                  positive_dimension(raw_threads, 2));
  const MTLSize threadgroup =
      MTLSizeMake(positive_dimension(raw_threadgroup, 0),
                  positive_dimension(raw_threadgroup, 1),
                  positive_dimension(raw_threadgroup, 2));
  [encoder dispatchThreads:threads threadsPerThreadgroup:threadgroup];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value
caml_prismel_metal_resource_state_encoder_update_texture_mapping(
    value raw_encoder, value raw_texture, value raw_mode, value raw_region,
    value raw_level, value raw_slice) {
  CAMLparam5(raw_encoder, raw_texture, raw_mode, raw_region, raw_level);
  CAMLxparam1(raw_slice);
  @autoreleasepool {
    @try {
      id<MTLResourceStateCommandEncoder> encoder = object_of_handle(
          raw_encoder, Handle_kind::Resource_state_encoder);
      id<MTLTexture> texture =
          object_of_handle(raw_texture, Handle_kind::Texture);
      const intnat mode = Long_val(raw_mode);
      const intnat x = Long_val(Field(raw_region, 0));
      const intnat y = Long_val(Field(raw_region, 1));
      const intnat z = Long_val(Field(raw_region, 2));
      const intnat width = Long_val(Field(raw_region, 3));
      const intnat height = Long_val(Field(raw_region, 4));
      const intnat depth = Long_val(Field(raw_region, 5));
      const intnat level = Long_val(raw_level);
      const intnat slice = Long_val(raw_slice);
      if (!texture.isSparse ||
          (mode != MTLSparseTextureMappingModeMap &&
           mode != MTLSparseTextureMappingModeUnmap) ||
          x < 0 || y < 0 || z < 0 || width <= 0 || height <= 0 ||
          depth <= 0 || level < 0 || slice < 0 ||
          static_cast<NSUInteger>(level) >= texture.mipmapLevelCount ||
          static_cast<NSUInteger>(slice) >= texture_slice_count(texture)) {
        CAMLreturn(result_error_text(
            "sparse texture mapping arguments are invalid"));
      }
      const MTLRegion region = MTLRegionMake3D(
          static_cast<NSUInteger>(x), static_cast<NSUInteger>(y),
          static_cast<NSUInteger>(z), static_cast<NSUInteger>(width),
          static_cast<NSUInteger>(height), static_cast<NSUInteger>(depth));
      [encoder updateTextureMapping:texture
                               mode:static_cast<MTLSparseTextureMappingMode>(mode)
                             region:region
                           mipLevel:static_cast<NSUInteger>(level)
                              slice:static_cast<NSUInteger>(slice)];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value
caml_prismel_metal_resource_state_encoder_update_texture_mapping_bytecode(
    value *argv, int argn) {
  (void)argn;
  return caml_prismel_metal_resource_state_encoder_update_texture_mapping(
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

extern "C" CAMLprim value
caml_prismel_metal_blit_encoder_copy_buffer_to_texture(
    value raw_encoder, value raw_buffer, value raw_texture, value raw_copy) {
  CAMLparam4(raw_encoder, raw_buffer, raw_texture, raw_copy);
  @autoreleasepool {
    @try {
      id<MTLBlitCommandEncoder> encoder =
          object_of_handle(raw_encoder, Handle_kind::Blit_encoder);
      id<MTLBuffer> buffer =
          object_of_handle(raw_buffer, Handle_kind::Buffer);
      id<MTLTexture> texture =
          object_of_handle(raw_texture, Handle_kind::Texture);
      const std::int64_t source_offset = Int64_val(Field(raw_copy, 0));
      const intnat bytes_per_row = Long_val(Field(raw_copy, 1));
      const intnat bytes_per_image = Long_val(Field(raw_copy, 2));
      value raw_size = Field(raw_copy, 3);
      const intnat width = Long_val(Field(raw_size, 0));
      const intnat height = Long_val(Field(raw_size, 1));
      const intnat depth = Long_val(Field(raw_size, 2));
      const intnat slice = Long_val(Field(raw_copy, 4));
      const intnat level = Long_val(Field(raw_copy, 5));
      value raw_origin = Field(raw_copy, 6);
      const intnat x = Long_val(Field(raw_origin, 0));
      const intnat y = Long_val(Field(raw_origin, 1));
      const intnat z = Long_val(Field(raw_origin, 2));
      const Texture_format_layout layout =
          texture_format_layout(texture.pixelFormat);
      if (source_offset < 0 || bytes_per_row <= 0 || bytes_per_image <= 0 ||
          width <= 0 || height <= 0 || depth <= 0 || slice < 0 || level < 0 ||
          x < 0 || y < 0 || z < 0 || layout.block_width == 0 ||
          layout.block_height == 0 || layout.bytes_per_block == 0 ||
          static_cast<NSUInteger>(slice) >= texture_slice_count(texture) ||
          static_cast<NSUInteger>(level) >= texture.mipmapLevelCount ||
          texture.sampleCount != 1 ||
          buffer.device.registryID != texture.device.registryID) {
        CAMLreturn(result_error_text("buffer-to-texture blit is invalid"));
      }
      const auto copy_width = static_cast<NSUInteger>(width);
      const auto copy_height = static_cast<NSUInteger>(height);
      const auto copy_depth = static_cast<NSUInteger>(depth);
      const auto destination_x = static_cast<NSUInteger>(x);
      const auto destination_y = static_cast<NSUInteger>(y);
      const auto destination_z = static_cast<NSUInteger>(z);
      const NSUInteger mip_width =
          std::max<NSUInteger>(1, texture.width >> level);
      const NSUInteger mip_height =
          std::max<NSUInteger>(1, texture.height >> level);
      const NSUInteger mip_depth =
          std::max<NSUInteger>(1, texture.depth >> level);
      const NSUInteger row_blocks = copy_width / layout.block_width +
          (copy_width % layout.block_width == 0 ? 0 : 1);
      const NSUInteger image_block_rows = copy_height / layout.block_height +
          (copy_height % layout.block_height == 0 ? 0 : 1);
      if (destination_x % layout.block_width != 0 ||
          destination_y % layout.block_height != 0 ||
          (copy_width % layout.block_width != 0 &&
           destination_x + copy_width != mip_width) ||
          (copy_height % layout.block_height != 0 &&
           destination_y + copy_height != mip_height) ||
          row_blocks > std::numeric_limits<NSUInteger>::max() /
                           layout.bytes_per_block ||
          static_cast<NSUInteger>(bytes_per_row) <
              row_blocks * layout.bytes_per_block ||
          static_cast<NSUInteger>(bytes_per_row) % layout.bytes_per_block != 0 ||
          static_cast<NSUInteger>(bytes_per_row) >
              std::numeric_limits<NSUInteger>::max() / image_block_rows ||
          static_cast<NSUInteger>(bytes_per_image) <
              static_cast<NSUInteger>(bytes_per_row) * image_block_rows ||
          static_cast<NSUInteger>(bytes_per_image) >
              std::numeric_limits<NSUInteger>::max() / copy_depth ||
          destination_x > mip_width || copy_width > mip_width - destination_x ||
          destination_y > mip_height ||
          copy_height > mip_height - destination_y ||
          destination_z > mip_depth || copy_depth > mip_depth - destination_z) {
        CAMLreturn(result_error_text("buffer-to-texture blit range is invalid"));
      }
      const NSUInteger required =
          static_cast<NSUInteger>(bytes_per_image) * copy_depth;
      const auto unsigned_offset = static_cast<std::uint64_t>(source_offset);
      if (unsigned_offset > buffer.length || required > buffer.length - unsigned_offset) {
        CAMLreturn(result_error_text(
            "buffer-to-texture blit exceeds the source buffer"));
      }
      [encoder
          copyFromBuffer:buffer
             sourceOffset:static_cast<NSUInteger>(source_offset)
        sourceBytesPerRow:static_cast<NSUInteger>(bytes_per_row)
      sourceBytesPerImage:static_cast<NSUInteger>(bytes_per_image)
               sourceSize:MTLSizeMake(copy_width, copy_height, copy_depth)
                toTexture:texture
         destinationSlice:static_cast<NSUInteger>(slice)
         destinationLevel:static_cast<NSUInteger>(level)
        destinationOrigin:MTLOriginMake(destination_x, destination_y,
                                        destination_z)];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_wait(value raw) {
  CAMLparam1(raw);
  id<MTLCommandBuffer> buffer =
      object_of_handle(raw, Handle_kind::Command_buffer);
  caml_enter_blocking_section();
  @autoreleasepool {
    [buffer waitUntilCompleted];
  }
  caml_leave_blocking_section();
  CAMLreturn(Val_unit);
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_error(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLCommandBuffer> buffer =
        object_of_handle(raw, Handle_kind::Command_buffer);
    NSError *error = buffer.error;
    result = error == nil
                 ? Val_none
                 : copy_optional_string(error_description(error, @"Metal error"));
  }
  CAMLreturn(result);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#include "metal_gen_stubs.inc"
#pragma clang diagnostic pop

/* M3: former metal_resource_descriptor_owned_generated.inc */
/* Isolated resource100 descriptor-owned shard.  Transplant after adding the
   three explicit Handle_kind cases named below. */

#define PRISMEL_LAYOUT_GET(NAME,PROP) extern "C" CAMLprim value NAME(value raw){ CAMLparam1(raw); CAMLlocal2(v,result); @try { MTLBufferLayoutDescriptor *d=object_of_handle(raw,Handle_kind::Buffer_layout_descriptor); v=caml_copy_int64((int64_t)d.PROP); result=result_ok(v); CAMLreturn(result); } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
#define PRISMEL_LAYOUT_SET(NAME,PROP) extern "C" CAMLprim value NAME(value raw,value v){ CAMLparam2(raw,v); @try { MTLBufferLayoutDescriptor *d=object_of_handle(raw,Handle_kind::Buffer_layout_descriptor); d.PROP=(NSUInteger)Int64_val(v); CAMLreturn(result_unit()); } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }

#undef PRISMEL_LAYOUT_GET
#undef PRISMEL_LAYOUT_SET

#define PRISMEL_SAMPLE_GET(NAME,PROP) extern "C" CAMLprim value NAME(value raw){ CAMLparam1(raw); CAMLlocal2(v,result); @try { MTLResourceStatePassSampleBufferAttachmentDescriptor *d=object_of_handle(raw,Handle_kind::Resource_state_sample_attachment_descriptor); v=caml_copy_int64((int64_t)d.PROP); result=result_ok(v); CAMLreturn(result); } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
#define PRISMEL_SAMPLE_SET(NAME,PROP) extern "C" CAMLprim value NAME(value raw,value v){ CAMLparam2(raw,v); @try { MTLResourceStatePassSampleBufferAttachmentDescriptor *d=object_of_handle(raw,Handle_kind::Resource_state_sample_attachment_descriptor); d.PROP=(NSUInteger)Int64_val(v); CAMLreturn(result_unit()); } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
#undef PRISMEL_SAMPLE_GET
#undef PRISMEL_SAMPLE_SET

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/* M3: former metal_resource_ownership_generated.inc */
/* resource100 ownership shard: 44 direct typed selectors / 56 inventory IDs.
   The safe OCaml adapter validates liveness, same-device, ranges, alignment,
   capabilities and completion retention before entering these wrappers. */

#define PRISMEL_RESOURCE_HANDLE_GET(NAME,TYPE,KIND,EXPR,RKIND) extern "C" CAMLprim value NAME(value raw){CAMLparam1(raw);CAMLlocal2(option,result);@try{TYPE object=object_of_handle(raw,KIND);option=prismel_resource_optional_handle((EXPR),RKIND);result=result_ok(option);CAMLreturn(result);}@catch(NSException*e){CAMLreturn(result_error(e.reason));}}

#define PRISMEL_HEAP_ACCEL(NAME,CALL) extern "C" CAMLprim value NAME(value rh,value rv){CAMLparam2(rh,rv);CAMLlocal2(raw,result);@try{id<MTLHeap>h=object_of_handle(rh,Handle_kind::Heap);id<MTLAccelerationStructure>a=(CALL);if(!a)CAMLreturn(result_error_text("heap acceleration constructor returned nil"));raw=allocate_handle(a,Handle_kind::Acceleration_structure);result=result_ok(raw);CAMLreturn(result);}@catch(NSException*e){CAMLreturn(result_error(e.reason));}}
#undef PRISMEL_HEAP_ACCEL

#define PRISMEL_TEXTURE_DESC_RESULT(EXPR) do{MTLTextureDescriptor*d=(EXPR);if(!d)CAMLreturn(result_error_text("texture descriptor constructor returned nil"));raw=allocate_handle(d,Handle_kind::Texture_descriptor);result=result_ok(raw);CAMLreturn(result);}while(0)

#undef PRISMEL_TEXTURE_DESC_RESULT
#undef PRISMEL_RESOURCE_HANDLE_GET

/* Native-entry companions for OCaml externals whose bytecode entry receives an
   argv vector.  The bytecode vector remains rooted by the OCaml caller. */

#pragma clang diagnostic pop

/* M3: former metal_resource_scalar_generated.inc */

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/* M3: former metal_render_command_mechanical_generated.inc */
#define PRISMEL_RENDER_WRAP1(NAME,CALL) extern "C" CAMLprim value NAME(value re,value a){CAMLparam2(re,a);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);CALL;CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_RENDER_WRAP2(NAME,CALL) extern "C" CAMLprim value NAME(value re,value a,value b){CAMLparam3(re,a,b);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);CALL;CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_RENDER_WRAP3(NAME,CALL) extern "C" CAMLprim value NAME(value re,value a,value b,value c){CAMLparam4(re,a,b,c);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);CALL;CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_RENDER_WRAP4(NAME,CALL) extern "C" CAMLprim value NAME(value re,value a,value b,value c,value d){CAMLparam5(re,a,b,c,d);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);CALL;CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

#undef PRISMEL_RENDER_WRAP1
#undef PRISMEL_RENDER_WRAP2
#undef PRISMEL_RENDER_WRAP3
#undef PRISMEL_RENDER_WRAP4

/* M3: former metal_render_command_sample_descriptor.inc */

#define PRISMEL_RENDER_SAMPLE_GET(NAME,PROP) extern "C" CAMLprim value NAME(value raw){CAMLparam1(raw);CAMLlocal2(v,result);@try{MTLRenderPassSampleBufferAttachmentDescriptor*d=object_of_handle(raw,Handle_kind::Render_sample_attachment_descriptor);v=caml_copy_int64(d.PROP);result=result_ok(v);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_RENDER_SAMPLE_SET(NAME,PROP) extern "C" CAMLprim value NAME(value raw,value v){CAMLparam2(raw,v);@try{MTLRenderPassSampleBufferAttachmentDescriptor*d=object_of_handle(raw,Handle_kind::Render_sample_attachment_descriptor);d.PROP=Int64_val(v);CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#undef PRISMEL_RENDER_SAMPLE_GET
#undef PRISMEL_RENDER_SAMPLE_SET

/* M3: former metal_render_command_stage_bindings.inc */
enum class PrismelRenderStage:intnat{Vertex=0,Fragment=1,Tile=2,Object=3,Mesh=4};
static PrismelRenderStage prismel_render_stage(value v){intnat n=Long_val(v);if(n<0||n>4)@throw[NSException exceptionWithName:NSInvalidArgumentException reason:@"invalid render stage" userInfo:nil];return(PrismelRenderStage)n;}
template<class T>static std::vector<T> prismel_render_handles(value a,Handle_kind kind){mlsize_t n=Wosize_val(a);std::vector<T>v;v.reserve(n);for(mlsize_t i=0;i<n;i++)v.push_back(Is_none(Field(a,i))?nil:object_of_handle(Field(Field(a,i),0),kind));return v;}
#define PRISMEL_RENDER_ENTRY(NAME) extern "C" CAMLprim value NAME

PRISMEL_RENDER_ENTRY(caml_prismel_metal_render_stage_buffer)(value re,value rs,value rb,value ro,value stride,value ri){CAMLparam5(re,rs,rb,ro,stride);CAMLxparam1(ri);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);id<MTLBuffer>b=Is_none(rb)?nil:object_of_handle(Field(rb,0),Handle_kind::Buffer);switch(prismel_render_stage(rs)){case PrismelRenderStage::Vertex:[e setVertexBuffer:b offset:Int64_val(ro) attributeStride:Int64_val(stride) atIndex:Int64_val(ri)];break;case PrismelRenderStage::Tile:[e setTileBuffer:b offset:Int64_val(ro) atIndex:Int64_val(ri)];break;case PrismelRenderStage::Object:[e setObjectBuffer:b offset:Int64_val(ro) atIndex:Int64_val(ri)];break;case PrismelRenderStage::Mesh:[e setMeshBuffer:b offset:Int64_val(ro) atIndex:Int64_val(ri)];break;default:CAMLreturn(result_error_text("stage has no single-buffer selector"));}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_stage_buffer_bytecode(value*argv,int argc){(void)argc;return caml_prismel_metal_render_stage_buffer(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5]);}

PRISMEL_RENDER_ENTRY(caml_prismel_metal_render_stage_bytes_bytecode)(value*argv,int argc){(void)argc;CAMLparam0();@try{id<MTLRenderCommandEncoder>e=object_of_handle(argv[0],Handle_kind::Render_encoder);void*p=Bytes_val(argv[2]);NSUInteger n=caml_string_length(argv[2]),stride=Int64_val(argv[3]),index=Int64_val(argv[4]);switch(prismel_render_stage(argv[1])){case PrismelRenderStage::Vertex:[e setVertexBytes:p length:n attributeStride:stride atIndex:index];break;case PrismelRenderStage::Tile:[e setTileBytes:p length:n atIndex:index];break;case PrismelRenderStage::Object:[e setObjectBytes:p length:n atIndex:index];break;case PrismelRenderStage::Mesh:[e setMeshBytes:p length:n atIndex:index];break;default:CAMLreturn(result_error_text("stage has no byte selector"));}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

PRISMEL_RENDER_ENTRY(caml_prismel_metal_render_stage_sampler_bytecode)(value*argv,int argc){(void)argc;CAMLparam0();@try{id<MTLRenderCommandEncoder>e=object_of_handle(argv[0],Handle_kind::Render_encoder);id<MTLSamplerState>s=Is_none(argv[2])?nil:object_of_handle(Field(argv[2],0),Handle_kind::Sampler);NSUInteger index=Int64_val(argv[5]);BOOL lod=Bool_val(argv[3]);float lo=Double_val(Field(argv[4],0)),hi=Double_val(Field(argv[4],1));switch(prismel_render_stage(argv[1])){case PrismelRenderStage::Tile:if(lod)[e setTileSamplerState:s lodMinClamp:lo lodMaxClamp:hi atIndex:index];else[e setTileSamplerState:s atIndex:index];break;case PrismelRenderStage::Object:if(lod)[e setObjectSamplerState:s lodMinClamp:lo lodMaxClamp:hi atIndex:index];else[e setObjectSamplerState:s atIndex:index];break;case PrismelRenderStage::Mesh:if(lod)[e setMeshSamplerState:s lodMinClamp:lo lodMaxClamp:hi atIndex:index];else[e setMeshSamplerState:s atIndex:index];break;default:CAMLreturn(result_error_text("stage has no single-sampler selector"));}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

PRISMEL_RENDER_ENTRY(caml_prismel_metal_render_stage_texture)(value re,value rs,value rt,value ri){CAMLparam4(re,rs,rt,ri);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);id<MTLTexture>t=Is_none(rt)?nil:object_of_handle(Field(rt,0),Handle_kind::Texture);NSUInteger i=Int64_val(ri);switch(prismel_render_stage(rs)){case PrismelRenderStage::Tile:[e setTileTexture:t atIndex:i];break;case PrismelRenderStage::Object:[e setObjectTexture:t atIndex:i];break;case PrismelRenderStage::Mesh:[e setMeshTexture:t atIndex:i];break;default:CAMLreturn(result_error_text("stage has no single-texture selector"));}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

#define PRISMEL_RENDER_STAGE_OBJECT(NAME,TYPE,KIND,VERTEX,FRAGMENT,TILE) PRISMEL_RENDER_ENTRY(NAME)(value re,value rs,value ro,value ri){CAMLparam4(re,rs,ro,ri);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);TYPE o=Is_none(ro)?nil:object_of_handle(Field(ro,0),KIND);NSUInteger i=Int64_val(ri);switch(prismel_render_stage(rs)){case PrismelRenderStage::Vertex:[e VERTEX:o atBufferIndex:i];break;case PrismelRenderStage::Fragment:[e FRAGMENT:o atBufferIndex:i];break;case PrismelRenderStage::Tile:[e TILE:o atBufferIndex:i];break;default:CAMLreturn(result_error_text("object unsupported for stage"));}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#undef PRISMEL_RENDER_STAGE_OBJECT

#define PRISMEL_RENDER_STAGE_TABLES(NAME,TYPE,KIND,VERTEX,FRAGMENT,TILE) PRISMEL_RENDER_ENTRY(NAME)(value re,value rs,value ra,value start){CAMLparam4(re,rs,ra,start);@try{id<MTLRenderCommandEncoder>e=object_of_handle(re,Handle_kind::Render_encoder);auto a=prismel_render_handles<TYPE>(ra,KIND);NSRange r=NSMakeRange(Int64_val(start),a.size());switch(prismel_render_stage(rs)){case PrismelRenderStage::Vertex:[e VERTEX:a.data() withBufferRange:r];break;case PrismelRenderStage::Fragment:[e FRAGMENT:a.data() withBufferRange:r];break;case PrismelRenderStage::Tile:[e TILE:a.data() withBufferRange:r];break;default:CAMLreturn(result_error_text("table array unsupported for stage"));}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#undef PRISMEL_RENDER_STAGE_TABLES
#undef PRISMEL_RENDER_ENTRY

extern "C" CAMLprim value caml_prismel_metal_render_stage_bytes(value a,value b,value c,value d,value e){value argv[]={a,b,c,d,e};return caml_prismel_metal_render_stage_bytes_bytecode(argv,5);}
extern "C" CAMLprim value caml_prismel_metal_render_stage_sampler(value a,value b,value c,value d,value e,value f){value argv[]={a,b,c,d,e,f};return caml_prismel_metal_render_stage_sampler_bytecode(argv,6);}

/* M3: former metal_render_command_draw_state.inc */
#define PRISMEL_RENDER_ENCODER(ARG) id<MTLRenderCommandEncoder>e=object_of_handle(ARG,Handle_kind::Render_encoder)

extern "C" CAMLprim value caml_prismel_metal_render_draw_indexed_instances_bytecode(value*a,int n){(void)n;CAMLparam0();@try{PRISMEL_RENDER_ENCODER(a[0]);[e drawIndexedPrimitives:(MTLPrimitiveType)Long_val(a[1]) indexCount:Int64_val(a[2]) indexType:(MTLIndexType)Long_val(a[3]) indexBuffer:object_of_handle(a[4],Handle_kind::Buffer) indexBufferOffset:Int64_val(a[5]) instanceCount:Int64_val(a[6])];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_draw_indexed_instances(value a,value b,value c,value d,value e,value f,value g){value v[]={a,b,c,d,e,f,g};return caml_prismel_metal_render_draw_indexed_instances_bytecode(v,7);}
extern "C" CAMLprim value caml_prismel_metal_render_draw_indexed_basic(value re,value p,value count,value ty,value rb,value off){CAMLparam5(re,p,count,ty,rb);CAMLxparam1(off);@try{PRISMEL_RENDER_ENCODER(re);[e drawIndexedPrimitives:(MTLPrimitiveType)Long_val(p) indexCount:Int64_val(count) indexType:(MTLIndexType)Long_val(ty) indexBuffer:object_of_handle(rb,Handle_kind::Buffer) indexBufferOffset:Int64_val(off)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_draw_indexed_basic_bytecode(value*a,int n){(void)n;return caml_prismel_metal_render_draw_indexed_basic(a[0],a[1],a[2],a[3],a[4],a[5]);}

extern "C" CAMLprim value caml_prismel_metal_render_depth_stencil(value re,value rs){CAMLparam2(re,rs);@try{PRISMEL_RENDER_ENCODER(re);[e setDepthStencilState:Is_none(rs)?nil:object_of_handle(Field(rs,0),Handle_kind::Depth_stencil)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

#undef PRISMEL_RENDER_ENCODER

#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/* M3: former metal_pipeline_header_mechanical_generated.mm */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
/* exact conventional render/compute pipeline mechanical shard */
/*method:-[MTLComputePipelineState gpuResourceID]*/
/*method:-[MTLComputePipelineState imageblockMemoryLengthForDimensions:]*/
/*method:-[MTLComputePipelineState requiredThreadsPerThreadgroup]*/
/*method:-[MTLComputePipelineState shaderValidation]*/
/*method:-[MTLComputePipelineState supportIndirectCommandBuffers]*/
/*method:-[MTLRenderPipelineState gpuResourceID]*/
/*method:-[MTLRenderPipelineState imageblockMemoryLengthForDimensions:]*/
/*method:-[MTLRenderPipelineState imageblockSampleLength]*/
/*method:-[MTLRenderPipelineState requiredThreadsPerMeshThreadgroup]*/
/*method:-[MTLRenderPipelineState requiredThreadsPerObjectThreadgroup]*/
/*method:-[MTLRenderPipelineState requiredThreadsPerTileThreadgroup]*/
/*method:-[MTLRenderPipelineState shaderValidation]*/
static BOOL prismel_pipeline_mtlrenderpipelinestate_supportindirectcommandbuffers(id<MTLRenderPipelineState> receiver){return [receiver supportIndirectCommandBuffers];}/*method:-[MTLRenderPipelineState supportIndirectCommandBuffers]*/

#pragma clang diagnostic pop

#define PRISMEL_PIPELINE_STATE_INT(NAME,KIND,TYPE,CALL) extern "C" CAMLprim value NAME(value raw){CAMLparam1(raw);CAMLlocal2(v,result);@try{TYPE object=object_of_handle(raw,KIND);v=caml_copy_int64((int64_t)(CALL));result=result_ok(v);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_PIPELINE_STATE_BOOL(NAME,KIND,TYPE,CALL) extern "C" CAMLprim value NAME(value raw){CAMLparam1(raw);@try{TYPE object=object_of_handle(raw,KIND);CAMLreturn(result_ok(Val_bool((CALL))));}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_PIPELINE_STATE_SIZE(NAME,KIND,TYPE,CALL) extern "C" CAMLprim value NAME(value raw){CAMLparam1(raw);CAMLlocal2(v,result);@try{TYPE object=object_of_handle(raw,KIND);v=prismel_pipeline_size_value((CALL));result=result_ok(v);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
PRISMEL_PIPELINE_STATE_BOOL(caml_prismel_metal_pipeline_render_indirect,Handle_kind::Render_pipeline,id<MTLRenderPipelineState>,prismel_pipeline_mtlrenderpipelinestate_supportindirectcommandbuffers(object))

#undef PRISMEL_PIPELINE_STATE_INT
#undef PRISMEL_PIPELINE_STATE_BOOL
#undef PRISMEL_PIPELINE_STATE_SIZE

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/* M3: former metal_shader_callable_bridge.inc */
/* Shader157 callable native subset.
   Exact OCaml descriptor schemas do not yet exist for stitching graphs,
   stitched-library descriptors, reflection objects, preprocessor dictionaries,
   or callback compilation. Those ownership IDs intentionally have no bridge
   symbol here. */

#define PRISMEL_SHADER_INT(NAME, KIND, TYPE, EXPR)                         \
  extern "C" CAMLprim value NAME(value raw) {                            \
    CAMLparam1(raw); CAMLlocal2(v, result); @try {                        \
      TYPE object = object_of_handle(raw, KIND);                          \
      v = caml_copy_int64(static_cast<int64_t>(EXPR));                    \
      result = result_ok(v); CAMLreturn(result);                          \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }
#define PRISMEL_SHADER_BOOL(NAME, KIND, TYPE, EXPR)                        \
  extern "C" CAMLprim value NAME(value raw) {                            \
    CAMLparam1(raw); @try { TYPE object = object_of_handle(raw, KIND);     \
      CAMLreturn(result_ok(Val_bool(EXPR)));                              \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }
#define PRISMEL_SHADER_SET_INT(NAME, KIND, TYPE, STMT)                     \
  extern "C" CAMLprim value NAME(value raw, value raw_value) {           \
    CAMLparam2(raw, raw_value); @try { TYPE object = object_of_handle(raw, KIND); \
      int64_t input = Int64_val(raw_value); if (input < 0)                 \
        CAMLreturn(result_error_text("shader property must be non-negative")); \
      STMT; CAMLreturn(result_unit());                                    \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }

extern "C" CAMLprim value caml_prismel_metal_shader_function_argument_encoder(
    value raw, value raw_index) {
  CAMLparam2(raw, raw_index); CAMLlocal2(handle, result);
  @try {
    int64_t index = Int64_val(raw_index);
    if (index < 0) CAMLreturn(result_error_text("argument buffer index must be non-negative"));
    id<MTLFunction> object = object_of_handle(raw, Handle_kind::Function);
    id<MTLArgumentEncoder> encoder =
        [object newArgumentEncoderWithBufferIndex:static_cast<NSUInteger>(index)];
    if (encoder == nil) CAMLreturn(result_error_text("Metal returned no argument encoder"));
    handle = allocate_handle(encoder, Handle_kind::Shader_argument_encoder);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

#define PRISMEL_SHADER_ATTRIBUTE_INT(NAME, FIELD)                          \
  extern "C" CAMLprim value NAME(value raw, value raw_vertex) {          \
    CAMLparam2(raw, raw_vertex); CAMLlocal2(v, result); @try {             \
      int64_t output = Bool_val(raw_vertex)                               \
        ? static_cast<int64_t>(static_cast<MTLVertexAttribute *>(object_of_handle(raw, Handle_kind::Shader_vertex_attribute)).FIELD) \
        : static_cast<int64_t>(static_cast<MTLAttribute *>(object_of_handle(raw, Handle_kind::Shader_attribute)).FIELD); \
      v = caml_copy_int64(output); result = result_ok(v); CAMLreturn(result); \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }
#define PRISMEL_SHADER_ATTRIBUTE_BOOL(NAME, FIELD)                         \
  extern "C" CAMLprim value NAME(value raw, value raw_vertex) {          \
    CAMLparam2(raw, raw_vertex); @try {                                   \
      bool output = Bool_val(raw_vertex)                                  \
        ? static_cast<MTLVertexAttribute *>(object_of_handle(raw, Handle_kind::Shader_vertex_attribute)).FIELD \
        : static_cast<MTLAttribute *>(object_of_handle(raw, Handle_kind::Shader_attribute)).FIELD; \
      CAMLreturn(result_ok(Val_bool(output)));                            \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }

#undef PRISMEL_SHADER_INT
#undef PRISMEL_SHADER_BOOL
#undef PRISMEL_SHADER_SET_INT
#undef PRISMEL_SHADER_ATTRIBUTE_INT
#undef PRISMEL_SHADER_ATTRIBUTE_BOOL

#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/* M3: former metal_mesh_tile_ownership_materializers.inc */
/* Isolated typed ownership shard for the 57 non-mechanical mesh/tile IDs.
   The includer supplies retain_handle/release_handle and converts NSError. */
enum class PrismelMeshTileKind { Function, BinaryArchive, DynamicLibrary,
  LinkedFunctions, BufferDescriptor, ColorAttachment, MeshDescriptor,
  TileDescriptor };

struct PrismelMeshTileObjects {
  id<MTLFunction> objectFunction;
  id<MTLFunction> meshFunction;
  id<MTLFunction> fragmentFunction;
  id<MTLFunction> tileFunction;
  NSArray<id<MTLBinaryArchive>> *binaryArchives;
  NSArray<id<MTLDynamicLibrary>> *preloadedLibraries;
  MTLLinkedFunctions *objectLinkedFunctions;
  MTLLinkedFunctions *meshLinkedFunctions;
  MTLLinkedFunctions *fragmentLinkedFunctions;
  MTLLinkedFunctions *tileLinkedFunctions;
};

static NSString *prismel_mesh_tile_validate_objects(PrismelMeshTileObjects v,
                                                     bool tile) {
  if (tile && v.tileFunction == nil) return @"tile function is required";
  if (!tile && v.meshFunction == nil) return @"mesh function is required";
  for (id x in v.binaryArchives) if (x == nil) return @"nil binary archive";
  for (id x in v.preloadedLibraries) if (x == nil) return @"nil dynamic library";
  return nil;
}

static MTLMeshRenderPipelineDescriptor *
prismel_materialize_mesh_descriptor(PrismelMeshTileObjects v,
                                    NSString **failure) {
  NSString *bad=prismel_mesh_tile_validate_objects(v,false); if(bad){*failure=bad;return nil;}
  MTLMeshRenderPipelineDescriptor *d=[MTLMeshRenderPipelineDescriptor new];
  @try { d.objectFunction=v.objectFunction; d.meshFunction=v.meshFunction;
    d.fragmentFunction=v.fragmentFunction; d.binaryArchives=v.binaryArchives;
    d.objectLinkedFunctions=v.objectLinkedFunctions;
    d.meshLinkedFunctions=v.meshLinkedFunctions;
    d.fragmentLinkedFunctions=v.fragmentLinkedFunctions; return d;
  } @catch(NSException *x) { *failure=x.reason; return nil; }
}

static MTLTileRenderPipelineDescriptor *
prismel_materialize_tile_descriptor(PrismelMeshTileObjects v,
                                    NSString **failure) {
  NSString *bad=prismel_mesh_tile_validate_objects(v,true); if(bad){*failure=bad;return nil;}
  MTLTileRenderPipelineDescriptor *d=[MTLTileRenderPipelineDescriptor new];
  @try { d.tileFunction=v.tileFunction; d.binaryArchives=v.binaryArchives;
    d.preloadedLibraries=v.preloadedLibraries; d.linkedFunctions=v.tileLinkedFunctions;
    return d;
  } @catch(NSException *x) { *failure=x.reason; return nil; }
}

/* Shared bridge hookup. Keeping this conditional makes the isolated native
   fixture compile without depending on Prismel's handle runtime. */
#ifdef PRISMEL_MESH_TILE_CAML_BRIDGE
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
extern bool prismel_mesh_tile_objects_from_value(value, bool,
                                                 PrismelMeshTileObjects *,
                                                 NSString **);
extern value prismel_mesh_tile_owned_handle(id, PrismelMeshTileKind);
extern value prismel_mesh_tile_error(NSString *);

extern "C" CAMLprim value caml_prismel_mesh_pipeline_descriptor(value raw) {
  CAMLparam1(raw); CAMLlocal1(result); @autoreleasepool {
    PrismelMeshTileObjects objects={}; NSString *failure=nil;
    if(!prismel_mesh_tile_objects_from_value(raw,false,&objects,&failure))
      CAMLreturn(prismel_mesh_tile_error(failure));
    MTLMeshRenderPipelineDescriptor *descriptor=
      prismel_materialize_mesh_descriptor(objects,&failure);
    if(!descriptor) CAMLreturn(prismel_mesh_tile_error(failure));
    result=prismel_mesh_tile_owned_handle(descriptor,
      PrismelMeshTileKind::MeshDescriptor); CAMLreturn(result);
  }
}
extern "C" CAMLprim value caml_prismel_tile_pipeline_descriptor(value raw) {
  CAMLparam1(raw); CAMLlocal1(result); @autoreleasepool {
    PrismelMeshTileObjects objects={}; NSString *failure=nil;
    if(!prismel_mesh_tile_objects_from_value(raw,true,&objects,&failure))
      CAMLreturn(prismel_mesh_tile_error(failure));
    MTLTileRenderPipelineDescriptor *descriptor=
      prismel_materialize_tile_descriptor(objects,&failure);
    if(!descriptor) CAMLreturn(prismel_mesh_tile_error(failure));
    result=prismel_mesh_tile_owned_handle(descriptor,
      PrismelMeshTileKind::TileDescriptor); CAMLreturn(result);
  }
}
#endif

/* M3: former metal_mesh_tile_counter_callable_bridge.inc */
/* Exact CAML hookup for the prepared mesh/tile materializers. */

static id prismel_optional_typed_handle(value option, Handle_kind kind) {
  return Is_block(option) ? object_of_handle(Field(option, 0), kind) : nil;
}

static NSArray<id<MTLBinaryArchive>> *prismel_mesh_archives(value raw) {
  std::vector<id<MTLBinaryArchive>> values = binary_archives_of_array(raw);
  return [NSArray arrayWithObjects:values.data() count:values.size()];
}

static NSArray<id<MTLDynamicLibrary>> *prismel_mesh_libraries(value raw) {
  std::vector<id<MTLDynamicLibrary>> values = dynamic_libraries_of_array(raw);
  return [NSArray arrayWithObjects:values.data() count:values.size()];
}

static bool prismel_mesh_objects_from_value(value raw, bool tile,
                                            PrismelMeshTileObjects *objects,
                                            NSString **failure) {
  @try {
    if (tile) {
      objects->tileFunction = object_of_handle(Field(raw, 0), Handle_kind::Function);
      objects->binaryArchives = prismel_mesh_archives(Field(raw, 1));
      objects->preloadedLibraries = prismel_mesh_libraries(Field(raw, 2));
      objects->tileLinkedFunctions = static_cast<MTLLinkedFunctions *>(
          prismel_optional_typed_handle(Field(raw, 3), Handle_kind::Linked_functions));
    } else {
      objects->objectFunction = prismel_optional_typed_handle(Field(raw, 0), Handle_kind::Function);
      objects->meshFunction = object_of_handle(Field(raw, 1), Handle_kind::Function);
      objects->fragmentFunction = prismel_optional_typed_handle(Field(raw, 2), Handle_kind::Function);
      objects->binaryArchives = prismel_mesh_archives(Field(raw, 3));
      objects->objectLinkedFunctions = static_cast<MTLLinkedFunctions *>(
          prismel_optional_typed_handle(Field(raw, 4), Handle_kind::Linked_functions));
      objects->meshLinkedFunctions = static_cast<MTLLinkedFunctions *>(
          prismel_optional_typed_handle(Field(raw, 5), Handle_kind::Linked_functions));
      objects->fragmentLinkedFunctions = static_cast<MTLLinkedFunctions *>(
          prismel_optional_typed_handle(Field(raw, 6), Handle_kind::Linked_functions));
    }
    return true;
  } @catch (NSException *exception) {
    *failure = exception.reason;
    return false;
  }
}

extern "C" CAMLprim value caml_prismel_mesh_pipeline_descriptor(value raw) {
  CAMLparam1(raw); CAMLlocal2(handle, result); @autoreleasepool {
    PrismelMeshTileObjects objects = {}; NSString *failure = nil;
    if (!prismel_mesh_objects_from_value(raw, false, &objects, &failure))
      CAMLreturn(result_error(failure));
    MTLMeshRenderPipelineDescriptor *descriptor =
        prismel_materialize_mesh_descriptor(objects, &failure);
    if (descriptor == nil) CAMLreturn(result_error(failure));
    handle = allocate_handle(descriptor, Handle_kind::Mesh_pipeline_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  }
}

extern "C" CAMLprim value caml_prismel_tile_pipeline_descriptor(value raw) {
  CAMLparam1(raw); CAMLlocal2(handle, result); @autoreleasepool {
    PrismelMeshTileObjects objects = {}; NSString *failure = nil;
    if (!prismel_mesh_objects_from_value(raw, true, &objects, &failure))
      CAMLreturn(result_error(failure));
    MTLTileRenderPipelineDescriptor *descriptor =
        prismel_materialize_tile_descriptor(objects, &failure);
    if (descriptor == nil) CAMLreturn(result_error(failure));
    handle = allocate_handle(descriptor, Handle_kind::Tile_pipeline_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  }
}

#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/* M3: former metal_command_support_mechanical.inc */
extern "C" CAMLprim value caml_prismel_metal_shared_event_value(value re){CAMLparam1(re);CAMLlocal2(v,result);@try{id<MTLSharedEvent>e=object_of_handle(re,Handle_kind::Shared_event);v=caml_copy_int64(e.signaledValue);result=result_ok(v);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_shared_event_set_value(value re,value rv){CAMLparam2(re,rv);@try{id<MTLSharedEvent>e=object_of_handle(re,Handle_kind::Shared_event);e.signaledValue=Int64_val(rv);CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

/* M3: former metal_command_support_callable_bridge.inc */
/* Corrected Command-support121 handwritten callable shard (18/103 split).
   Callback capture/event notification, function-log enumeration and complex
   blit copies remain blocked until their roots and full range schemas exist. */

#define PRISMEL_INDIRECT0(NAME, KIND, TYPE, CALL) \
extern "C" CAMLprim value NAME(value raw){CAMLparam1(raw);@try{TYPE command=object_of_handle(raw,KIND);[command CALL];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_INDIRECT_ENUM(NAME, KIND, TYPE, CALL, ENUM) \
extern "C" CAMLprim value NAME(value raw,value input){CAMLparam2(raw,input);@try{TYPE command=object_of_handle(raw,KIND);[command CALL:(ENUM)Long_val(input)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

#undef PRISMEL_INDIRECT0
#undef PRISMEL_INDIRECT_ENUM

#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/* M3: former metal_mesh_tile_mechanical_generated.mm */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

extern "C" void prismel_mtl_pipeline_buffer_set_mutability(
    MTLPipelineBufferDescriptor *value, MTLMutability mutability) { value.mutability=mutability; }
extern "C" void prismel_mtl_color_attachment_set_mechanical(
    MTLRenderPipelineColorAttachmentDescriptor *v, MTLPixelFormat pixel,
    MTLBlendFactor src_rgb, MTLBlendFactor dst_rgb, MTLBlendOperation rgb,
    MTLBlendFactor src_alpha, MTLBlendFactor dst_alpha, MTLBlendOperation alpha,
    MTLColorWriteMask mask) {
  v.pixelFormat=pixel; v.sourceRGBBlendFactor=src_rgb; v.destinationRGBBlendFactor=dst_rgb;
  v.rgbBlendOperation=rgb; v.sourceAlphaBlendFactor=src_alpha;
  v.destinationAlphaBlendFactor=dst_alpha; v.alphaBlendOperation=alpha; v.writeMask=mask;
}
extern "C" void prismel_mtl_mesh_descriptor_set_mechanical(
    MTLMeshRenderPipelineDescriptor *v, NSString *label, MTLPixelFormat depth,
    MTLPixelFormat stencil, MTLSize mesh_threads, MTLSize object_threads) {
  if(label!=nil)v.label=label; v.depthAttachmentPixelFormat=depth; v.stencilAttachmentPixelFormat=stencil;
  if (@available(macOS 26.0,*)) { v.requiredThreadsPerMeshThreadgroup=mesh_threads;
    v.requiredThreadsPerObjectThreadgroup=object_threads; }
}
extern "C" void prismel_mtl_tile_descriptor_set_mechanical(
    MTLTileRenderPipelineDescriptor *v, NSString *label, MTLSize threads) {
  if(label!=nil)v.label=label; if (@available(macOS 26.0,*)) v.requiredThreadsPerThreadgroup=threads;
}
extern "C" NSUInteger prismel_mtl_mesh_tile_mechanical_id_count(void) { return 48; }

/* M3: former metal_mesh_tile_mechanical_callable_bridge.inc */
/* Callable adapters for all 16 contained-value properties in the prepared
   Mesh/tile105 mechanical shard. Object graph properties remain handwritten. */

static bool prismel_mesh_size(value raw, MTLSize *size) {
  int64_t width = Int64_val(Field(raw, 0));
  int64_t height = Int64_val(Field(raw, 1));
  int64_t depth = Int64_val(Field(raw, 2));
  if (width <= 0 || height <= 0 || depth <= 0) return false;
  *size = MTLSizeMake(static_cast<NSUInteger>(width),
                      static_cast<NSUInteger>(height),
                      static_cast<NSUInteger>(depth));
  return true;
}

static bool prismel_mesh_object_size(value raw, MTLSize *size) {
  int64_t width = Int64_val(Field(raw, 0));
  int64_t height = Int64_val(Field(raw, 1));
  int64_t depth = Int64_val(Field(raw, 2));
  const bool all_zero = width == 0 && height == 0 && depth == 0;
  const bool all_positive = width > 0 && height > 0 && depth > 0;
  if (!all_zero && !all_positive) return false;
  *size = MTLSizeMake(static_cast<NSUInteger>(width),
                      static_cast<NSUInteger>(height),
                      static_cast<NSUInteger>(depth));
  return true;
}

extern "C" CAMLprim value caml_prismel_metal_mesh_descriptor_set_mechanical(
    value raw, value raw_label, value raw_depth, value raw_stencil,
    value raw_mesh_threads, value raw_object_threads) {
  CAMLparam5(raw, raw_label, raw_depth, raw_stencil, raw_mesh_threads);
  CAMLxparam1(raw_object_threads);
  @try {
    MTLMeshRenderPipelineDescriptor *descriptor = object_of_handle(
        raw, Handle_kind::Mesh_pipeline_descriptor);
    NSString *label = Is_block(raw_label)
        ? string_from_ocaml(Field(raw_label, 0)) : nil;
    if (Is_block(raw_label) && label == nil)
      CAMLreturn(result_error_text("mesh descriptor label is not valid UTF-8"));
    MTLSize mesh_threads, object_threads;
    if (!prismel_mesh_size(raw_mesh_threads, &mesh_threads) ||
        !prismel_mesh_object_size(raw_object_threads, &object_threads))
      CAMLreturn(result_error_text(
          "mesh threads must be positive; object threads must be positive or all zero"));
    prismel_mtl_mesh_descriptor_set_mechanical(
        descriptor, label, static_cast<MTLPixelFormat>(Int64_val(raw_depth)),
        static_cast<MTLPixelFormat>(Int64_val(raw_stencil)), mesh_threads,
        object_threads);
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_mesh_descriptor_set_mechanical_bytecode(
    value *argv, int argn) {
  (void)argn;
  return caml_prismel_metal_mesh_descriptor_set_mechanical(
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

extern "C" CAMLprim value caml_prismel_metal_tile_descriptor_set_mechanical(
    value raw, value raw_label, value raw_threads) {
  CAMLparam3(raw, raw_label, raw_threads); @try {
    MTLTileRenderPipelineDescriptor *descriptor = object_of_handle(
        raw, Handle_kind::Tile_pipeline_descriptor);
    NSString *label = Is_block(raw_label)
        ? string_from_ocaml(Field(raw_label, 0)) : nil;
    if (Is_block(raw_label) && label == nil)
      CAMLreturn(result_error_text("tile descriptor label is not valid UTF-8"));
    MTLSize threads;
    if (!prismel_mesh_size(raw_threads, &threads))
      CAMLreturn(result_error_text("tile threadgroup size must be positive"));
    prismel_mtl_tile_descriptor_set_mechanical(descriptor, label, threads);
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/* M3: former metal_command_event_constructors.inc */
/* Constructible Command-support event handles. The source registry ID is
   returned with the handle because some valid shared events report nil from
   MTLEvent.device on older Metal runtimes. */

static value prismel_command_event_result(id<MTLEvent> event,
                                          Handle_kind kind,
                                          id<MTLDevice> source) {
  CAMLparam0(); CAMLlocal4(handle, registry, pair, result);
  if (event == nil) CAMLreturn(result_error_text("Metal returned no event"));
  if (event.device != nil && event.device.registryID != source.registryID)
    CAMLreturn(result_error_text("Metal returned an event for another device"));
  handle = allocate_handle(event, kind);
  registry = caml_copy_int64(source.registryID);
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, handle);
  Store_field(pair, 1, registry);
  result = result_ok(pair);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_command_shared_event_create(value raw_device) {
  CAMLparam1(raw_device); @autoreleasepool { @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    id<MTLSharedEvent> event = [device newSharedEvent];
    CAMLreturn(prismel_command_event_result(event, Handle_kind::Shared_event, device));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
}

#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/* M3: former metal_io_counter_callable_tail.inc */
extern "C" CAMLprim value caml_prismel_metal_counter_sets(value rd){CAMLparam1(rd);CAMLlocal4(a,p,h,r);@try{id<MTLDevice>d=object_of_handle(rd,Handle_kind::Device);NSArray<id<MTLCounterSet>>*xs=d.counterSets;a=caml_alloc(xs.count,0);for(NSUInteger i=0;i<xs.count;i++){h=allocate_handle(xs[i],Handle_kind::Counter_set);p=caml_alloc_tuple(2);Store_field(p,0,h);Store_field(p,1,caml_copy_string(xs[i].name.UTF8String));Store_field(a,i,p);}r=result_ok(a);CAMLreturn(r);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_counter_descriptor_create(value unit){CAMLparam1(unit);CAMLlocal2(h,r);@try{MTLCounterSampleBufferDescriptor*d=[MTLCounterSampleBufferDescriptor new];h=allocate_handle(d,Handle_kind::Counter_descriptor);r=result_ok(h);CAMLreturn(r);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_counter_set_counters(value raw){CAMLparam1(raw);CAMLlocal4(a,p,h,r);@try{id<MTLCounterSet>s=object_of_handle(raw,Handle_kind::Counter_set);NSArray<id<MTLCounter>>*xs=s.counters;a=caml_alloc(xs.count,0);for(NSUInteger i=0;i<xs.count;i++){h=allocate_handle(xs[i],Handle_kind::Counter);p=caml_alloc_tuple(2);Store_field(p,0,h);Store_field(p,1,caml_copy_string(xs[i].name.UTF8String));Store_field(a,i,p);}r=result_ok(a);CAMLreturn(r);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_counter_descriptor_set(value raw,value rs,value rl,value rc,value rm){CAMLparam5(raw,rs,rl,rc,rm);@try{int64_t n=Int64_val(rc);if(n<=0)CAMLreturn(result_error_text("sample count must be positive"));MTLCounterSampleBufferDescriptor*d=object_of_handle(raw,Handle_kind::Counter_descriptor);d.counterSet=object_of_handle(rs,Handle_kind::Counter_set);d.label=Is_none(rl)?nil:string_from_ocaml(Field(rl,0));d.sampleCount=n;d.storageMode=(MTLStorageMode)Int64_val(rm);CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_counter_sample_buffer_create(value rd,value rx){CAMLparam2(rd,rx);CAMLlocal2(h,r);@try{NSError*e=nil;id<MTLCounterSampleBuffer>b=[object_of_handle(rd,Handle_kind::Device) newCounterSampleBufferWithDescriptor:object_of_handle(rx,Handle_kind::Counter_descriptor) error:&e];if(!b)CAMLreturn(result_error(e.localizedDescription?:@"counter creation failed"));h=allocate_handle(b,Handle_kind::Counter_sample_buffer);r=result_ok(h);CAMLreturn(r);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_counter_sample_resolve(value raw,value rs,value rn){CAMLparam3(raw,rs,rn);CAMLlocal2(bytes,r);@try{id<MTLCounterSampleBuffer>b=object_of_handle(raw,Handle_kind::Counter_sample_buffer);int64_t s=Int64_val(rs),n=Int64_val(rn);if(s<0||n<0||s>(int64_t)b.sampleCount-n)CAMLreturn(result_error_text("counter range invalid"));NSData*d=[b resolveCounterRange:NSMakeRange(s,n)];if(!d)CAMLreturn(result_error_text("counter resolve returned nil"));bytes=caml_alloc_string(d.length);memcpy(Bytes_val(bytes),d.bytes,d.length);r=result_ok(bytes);CAMLreturn(r);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_counter_supports_sampling(value rd,value rp){CAMLparam2(rd,rp);CAMLlocal2(v,r);@try{MTLCounterSamplingPoint p;switch(Long_val(rp)){case 0:p=MTLCounterSamplingPointAtStageBoundary;break;case 1:p=MTLCounterSamplingPointAtDrawBoundary;break;case 2:p=MTLCounterSamplingPointAtDispatchBoundary;break;case 3:p=MTLCounterSamplingPointAtBlitBoundary;break;default:CAMLreturn(result_error_text("unknown counter sampling point"));}v=Val_bool([object_of_handle(rd,Handle_kind::Device) supportsCounterSampling:p]);r=result_ok(v);CAMLreturn(r);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_blit_pass_create(value u){CAMLparam1(u);CAMLlocal2(h,r);h=allocate_handle([MTLBlitPassDescriptor blitPassDescriptor],Handle_kind::Blit_pass_descriptor);r=result_ok(h);CAMLreturn(r);}
extern "C" CAMLprim value caml_prismel_metal_blit_pass_attachments(value raw){CAMLparam1(raw);CAMLlocal2(h,r);MTLBlitPassDescriptor*d=object_of_handle(raw,Handle_kind::Blit_pass_descriptor);h=allocate_handle(d.sampleBufferAttachments,Handle_kind::Blit_sample_attachment_array);r=result_ok(h);CAMLreturn(r);}
extern "C" CAMLprim value caml_prismel_metal_blit_attachment(value ra,value ri,value rb,value rs,value re){CAMLparam5(ra,ri,rb,rs,re);CAMLlocal2(h,r);@try{MTLBlitPassSampleBufferAttachmentDescriptorArray*a=object_of_handle(ra,Handle_kind::Blit_sample_attachment_array);MTLBlitPassSampleBufferAttachmentDescriptor*d=a[Int64_val(ri)];d.sampleBuffer=Is_none(rb)?nil:object_of_handle(Field(rb,0),Handle_kind::Counter_sample_buffer);d.startOfEncoderSampleIndex=Int64_val(rs);d.endOfEncoderSampleIndex=Int64_val(re);h=allocate_handle(d,Handle_kind::Blit_sample_attachment);r=result_ok(h);CAMLreturn(r);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
/* M3: former metal_mesh_tile_pipeline_compile.inc */
/* Exact synchronous Mesh/tile105 descriptor compilation selectors:
   method:-[MTLDevice newRenderPipelineStateWithMeshDescriptor:options:reflection:error:]
   method:-[MTLDevice newRenderPipelineStateWithTileDescriptor:options:reflection:error:]
   The two asynchronous callback selectors remain blocked. */

static bool prismel_mesh_tile_same_device(id<MTLDevice> device, id object) {
  return object == nil ||
         ![object respondsToSelector:@selector(device)] ||
         ((id<MTLDevice>)[object device]).registryID == device.registryID;
}

static value prismel_mesh_tile_pipeline_result(
    id<MTLRenderPipelineState> pipeline,
    MTLRenderPipelineReflection *reflection) {
  CAMLparam0(); CAMLlocal4(handle, reflected, pair, result);
  handle = allocate_handle(pipeline, Handle_kind::Render_pipeline);
  reflected = copy_render_reflection(reflection);
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, handle);
  Store_field(pair, 1, reflected);
  result = result_ok(pair);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_mesh_pipeline_compile(
    value raw_device, value raw_descriptor, value raw_options) {
  CAMLparam3(raw_device, raw_descriptor, raw_options);
  @autoreleasepool {
    if (@available(macOS 13.0, *)) { @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      MTLMeshRenderPipelineDescriptor *descriptor = object_of_handle(
          raw_descriptor, Handle_kind::Mesh_pipeline_descriptor);
      int64_t options = Int64_val(raw_options);
      if (options < 0) CAMLreturn(result_error_text("mesh pipeline options are invalid"));
      if (descriptor.meshFunction == nil ||
          !prismel_mesh_tile_same_device(device, descriptor.objectFunction) ||
          !prismel_mesh_tile_same_device(device, descriptor.meshFunction) ||
          !prismel_mesh_tile_same_device(device, descriptor.fragmentFunction))
        CAMLreturn(result_error_text("mesh descriptor has missing or cross-device functions"));
      for (id archive in descriptor.binaryArchives)
        if (!prismel_mesh_tile_same_device(device, archive))
          CAMLreturn(result_error_text("mesh descriptor has a cross-device archive"));
      MTLRenderPipelineReflection *reflection = nil;
      NSError *error = nil;
      id<MTLRenderPipelineState> pipeline = [device
          newRenderPipelineStateWithMeshDescriptor:descriptor
                                           options:static_cast<MTLPipelineOption>(options)
                                        reflection:&reflection error:&error];
      if (pipeline == nil)
        CAMLreturn(result_error(error_description(error,
            @"Metal mesh pipeline compilation failed")));
      if (pipeline.device.registryID != device.registryID)
        CAMLreturn(result_error_text("Metal returned a mesh pipeline for another device"));
      CAMLreturn(prismel_mesh_tile_pipeline_result(pipeline, reflection));
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
    CAMLreturn(result_error_text("Metal mesh pipelines require macOS 13"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_tile_pipeline_compile(
    value raw_device, value raw_descriptor, value raw_options) {
  CAMLparam3(raw_device, raw_descriptor, raw_options);
  @autoreleasepool {
    if (@available(macOS 11.0, *)) { @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      MTLTileRenderPipelineDescriptor *descriptor = object_of_handle(
          raw_descriptor, Handle_kind::Tile_pipeline_descriptor);
      int64_t options = Int64_val(raw_options);
      if (options < 0) CAMLreturn(result_error_text("tile pipeline options are invalid"));
      if (descriptor.tileFunction == nil ||
          !prismel_mesh_tile_same_device(device, descriptor.tileFunction))
        CAMLreturn(result_error_text("tile descriptor has a missing or cross-device function"));
      for (id archive in descriptor.binaryArchives)
        if (!prismel_mesh_tile_same_device(device, archive))
          CAMLreturn(result_error_text("tile descriptor has a cross-device archive"));
      for (id library in descriptor.preloadedLibraries)
        if (!prismel_mesh_tile_same_device(device, library))
          CAMLreturn(result_error_text("tile descriptor has a cross-device library"));
      MTLRenderPipelineReflection *reflection = nil;
      NSError *error = nil;
      id<MTLRenderPipelineState> pipeline = [device
          newRenderPipelineStateWithTileDescriptor:descriptor
                                           options:static_cast<MTLPipelineOption>(options)
                                        reflection:&reflection error:&error];
      if (pipeline == nil)
        CAMLreturn(result_error(error_description(error,
            @"Metal tile pipeline compilation failed")));
      if (pipeline.device.registryID != device.registryID)
        CAMLreturn(result_error_text("Metal returned a tile pipeline for another device"));
      CAMLreturn(prismel_mesh_tile_pipeline_result(pipeline, reflection));
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
    CAMLreturn(result_error_text("Metal tile pipelines require macOS 11"));
  }
}

#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/* M3: former metal4_remaining_callable_bridge.inc */
/* Next coherent authoritative Metal4 ownership closure: binary-function
   descriptor graph (20 IDs), command-buffer resource views (7), and render
   encoder commands (9). */

/* M3: former metal4_acceleration_structure11_callable_bridge.inc */
/* MTL4AccelerationStructure11 is an exact class-metadata tail. These nine
   constructors are support machinery for concrete descriptor ownership; the
   abstract Descriptor and GeometryDescriptor classes are never instantiated. */

/* M3: former metal4_argument_table_resource_bridge.inc */
/* Exact MTL4ArgumentTable setResource:atBufferIndex: path.  The table stores a
   resource ID, not an owning object reference; the handwritten safe graph must
   retain the Buffer/AccelerationStructure until replacement or completion. */

/* M3: former metal4_command_encoder_wait_fence_bridge.inc */
/* Remaining MTL4CommandEncoder fence wait.  The command-buffer state is the
   retention owner; validation completes before the native command mutation. */

/* M3: former metal_device_residual_library5_bridge.inc */
/* Exact synchronous MTLLibrary constructors from the MTLDevice.h residual.
   Every returned library is owned by its OCaml handle.  Input bytes are copied
   into dispatch-owned storage before the synchronous Metal call. */

static value prismel_device_library_result(id<MTLLibrary> _Nullable library,
                                           NSError * _Nullable error,
                                           NSString * _Nonnull fallback) {
  if (library == nil) return result_error(error_description(error, fallback));
  return result_ok(allocate_handle(library, Handle_kind::Library));
}

extern "C" CAMLprim value caml_prismel_metal_device_library_data(
    value raw_device, value raw_bytes) {
  CAMLparam2(raw_device, raw_bytes);
  @try {
    mlsize_t length = caml_string_length(raw_bytes);
    void *copy = malloc(length == 0 ? 1 : length);
    if (copy == nullptr) CAMLreturn(result_error_text("unable to copy library data"));
    if (length != 0) memcpy(copy, String_val(raw_bytes), length);
    dispatch_data_t data = dispatch_data_create(
        copy, length, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
        ^{ free(copy); });
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithData:data error:&error];
    CAMLreturn(prismel_device_library_result(
        library, error, @"Metal rejected library data"));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

/* M3: former metal_device_residual_queues3_bridge.inc */
/* Exact MTLDevice queue constructors. Returned queue handles own the native
   object; descriptor log-state identity is validated before construction. */

#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

/* M3: former metal_tensor_mechanical_callable_bridge.inc */
/* Tensor descriptors still serve buffer-backed Resource100 tensors. */
static_assert(std::is_same_v<decltype(((MTLTensorDescriptor *)nil).dimensions), MTLTensorExtents *>);
static_assert(std::is_same_v<decltype(((MTLTensorDescriptor *)nil).strides), MTLTensorExtents *>);
static_assert(std::is_same_v<decltype(((MTLTensorDescriptor *)nil).dataType), MTLTensorDataType>);
#define PRISMEL_TENSOR_SET(NAME, EXPR)                                         \
  extern "C" CAMLprim value NAME(value raw, value input) {                     \
    CAMLparam2(raw, input);                                                     \
    @try { MTLTensorDescriptor *object = object_of_handle(raw, Handle_kind::Tensor_descriptor); \
      EXPR; CAMLreturn(result_unit());                                          \
    } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
  }

#undef PRISMEL_TENSOR_SET

/* MTLSize helpers retained for compile-option snapshots. */

/* M3: former metal_library42_callable_bridge.inc */
/* Remaining synchronous MTLLibrary42 calls use the ordinary Metal bridge
   handle/result helpers. The deprecated encoder reflection stays isolated. */

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#pragma clang diagnostic pop

/* M3: former metal_argument_encoder34_callable_bridge.inc */
/* ArgumentEncoder34 isolated callable shard. Array inputs are completely
   decoded, kind-checked, range-checked, and same-device checked before the
   first Objective-C mutation, preserving atomic rejection. */
static bool prismel_argument_same_device(id<MTLArgumentEncoder>e,id object){return [object respondsToSelector:@selector(device)]&&[[object device] registryID]==e.device.registryID;}
extern "C" CAMLprim value caml_prismel_metal_argument_encoder_snapshot(value raw){CAMLparam1(raw);CAMLlocal5(tuple,label,length,alignment,device);@try{id<MTLArgumentEncoder>e=object_of_handle(raw,Handle_kind::Shader_argument_encoder);label=copy_optional_string(e.label);length=caml_copy_int64(e.encodedLength);alignment=caml_copy_int64(e.alignment);device=caml_copy_int64(e.device.registryID);tuple=caml_alloc_tuple(4);Store_field(tuple,0,label);Store_field(tuple,1,length);Store_field(tuple,2,alignment);Store_field(tuple,3,device);CAMLreturn(result_ok(tuple));}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_argument_encoder_set_buffer(value raw,value buffer,value offset,value start,value element){CAMLparam5(raw,buffer,offset,start,element);@try{id<MTLArgumentEncoder>e=object_of_handle(raw,Handle_kind::Shader_argument_encoder);id<MTLBuffer>b=object_of_handle(buffer,Handle_kind::Buffer);int64_t o=Int64_val(offset),s=Int64_val(start),a=Int64_val(element);if(o<0||s<0||a<0||(uint64_t)o>b.length||!prismel_argument_same_device(e,b))CAMLreturn(result_error_text("argument buffer range or device mismatch"));if(a==0)[e setArgumentBuffer:b offset:o];else[e setArgumentBuffer:b startOffset:s arrayElement:a];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_argument_encoder_single(value raw,value tag,value object,value offset,value index){CAMLparam5(raw,tag,object,offset,index);int64_t o=Int64_val(offset),i=Int64_val(index);if(o<0||i<0)CAMLreturn(result_error_text("negative argument offset or index"));@try{id<MTLArgumentEncoder>e=object_of_handle(raw,Handle_kind::Shader_argument_encoder);id x=nil;switch(Long_val(tag)){case 0:x=object_of_handle(object,Handle_kind::Buffer);break;case 1:x=object_of_handle(object,Handle_kind::Texture);break;case 2:x=object_of_handle(object,Handle_kind::Sampler);break;case 3:x=object_of_handle(object,Handle_kind::Acceleration_structure);break;case 4:x=object_of_handle(object,Handle_kind::Indirect_command_buffer);break;case 5:x=object_of_handle(object,Handle_kind::Visible_function_table);break;case 6:x=object_of_handle(object,Handle_kind::Intersection_function_table);break;case 7:x=object_of_handle(object,Handle_kind::Render_pipeline);break;case 8:x=object_of_handle(object,Handle_kind::Compute_pipeline);break;case 9:x=object_of_handle(object,Handle_kind::Depth_stencil);break;default:CAMLreturn(result_error_text("unknown argument binding kind"));}if(!prismel_argument_same_device(e,x))CAMLreturn(result_error_text("argument binding device mismatch"));switch(Long_val(tag)){case 0:[e setBuffer:x offset:o atIndex:i];break;case 1:[e setTexture:x atIndex:i];break;case 2:[e setSamplerState:x atIndex:i];break;case 3:[e setAccelerationStructure:x atIndex:i];break;case 4:[e setIndirectCommandBuffer:x atIndex:i];break;case 5:[e setVisibleFunctionTable:x atIndex:i];break;case 6:[e setIntersectionFunctionTable:x atIndex:i];break;case 7:[e setRenderPipelineState:x atIndex:i];break;case 8:[e setComputePipelineState:x atIndex:i];break;case 9:[e setDepthStencilState:x atIndex:i];break;}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

/* M3: former metal_acceleration_command32_callable_bridge.inc */
/* Missing18 callable IDs complement the existing build/refit/copy/compact
   encoder methods. Every array is fully kind/device validated before mutation. */

extern "C" CAMLprim value caml_prismel_metal_acceleration_encoder_write_type(value raw,value structure,value buffer,value offset,value type){CAMLparam5(raw,structure,buffer,offset,type);int64_t o=Int64_val(offset);if(o<0)CAMLreturn(result_error_text("negative compacted-size offset"));@try{id<MTLBuffer>b=object_of_handle(buffer,Handle_kind::Buffer);NSUInteger bytes=Long_val(type)==0?sizeof(uint32_t):sizeof(uint64_t);if((uint64_t)o>b.length||bytes>b.length-o)CAMLreturn(result_error_text("compacted-size destination range out of bounds"));[object_of_handle(raw,Handle_kind::Acceleration_encoder) writeCompactedAccelerationStructureSize:object_of_handle(structure,Handle_kind::Acceleration_structure) toBuffer:b offset:o sizeDataType:(MTLDataType)Long_val(type)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

/* M3: former metal_blit_command25_callable_bridge.inc */
/* BlitCommand25 isolated callable shard. Positional copy specs are decoded and
   checked completely before the selected command is emitted. */
static bool prismel_blit_range(NSUInteger total,int64_t offset,int64_t length){return offset>=0&&length>=0&&(uint64_t)offset<=total&&(uint64_t)length<=total-(uint64_t)offset;}
extern "C" CAMLprim value caml_prismel_metal_blit_copy(value raw,value tag,value source,value destination,value spec){CAMLparam5(raw,tag,source,destination,spec);@try{id<MTLBlitCommandEncoder>e=object_of_handle(raw,Handle_kind::Blit_encoder);switch(Long_val(tag)){case 0:{id<MTLBuffer>s=object_of_handle(source,Handle_kind::Buffer);id<MTLTexture>d=object_of_handle(destination,Handle_kind::Texture);int64_t offset=Int64_val(Field(spec,0)),row=Int64_val(Field(spec,1)),image=Int64_val(Field(spec,2));MTLSize size=MTLSizeMake(Int64_val(Field(spec,3)),Int64_val(Field(spec,4)),Int64_val(Field(spec,5)));if(offset<0||row<=0||image<=0||!size.width||!size.height||!size.depth||s.device.registryID!=d.device.registryID)CAMLreturn(result_error_text("invalid buffer-to-texture copy"));[e copyFromBuffer:s sourceOffset:offset sourceBytesPerRow:row sourceBytesPerImage:image sourceSize:size toTexture:d destinationSlice:Int64_val(Field(spec,6)) destinationLevel:Int64_val(Field(spec,7)) destinationOrigin:MTLOriginMake(Int64_val(Field(spec,8)),Int64_val(Field(spec,9)),Int64_val(Field(spec,10))) options:(MTLBlitOption)Int64_val(Field(spec,11))];break;}case 1:{id<MTLBuffer>s=object_of_handle(source,Handle_kind::Buffer),d=object_of_handle(destination,Handle_kind::Buffer);int64_t so=Int64_val(Field(spec,0)),doff=Int64_val(Field(spec,1)),n=Int64_val(Field(spec,2));if(!prismel_blit_range(s.length,so,n)||!prismel_blit_range(d.length,doff,n)||s.device.registryID!=d.device.registryID)CAMLreturn(result_error_text("invalid buffer copy range"));[e copyFromBuffer:s sourceOffset:so toBuffer:d destinationOffset:doff size:n];break;}case 2:{if(@available(macOS 26.0,*)){id<MTLTensor>s=object_of_handle(source,Handle_kind::Tensor),d=object_of_handle(destination,Handle_kind::Tensor);MTLTensorExtents*so=object_of_handle(Field(spec,0),Handle_kind::Tensor_extents),*sd=object_of_handle(Field(spec,1),Handle_kind::Tensor_extents),*origin=object_of_handle(Field(spec,2),Handle_kind::Tensor_extents),*dimensions=object_of_handle(Field(spec,3),Handle_kind::Tensor_extents);if(s.device.registryID!=d.device.registryID||so.rank!=sd.rank||origin.rank!=dimensions.rank)CAMLreturn(result_error_text("invalid tensor copy rank/device"));[e copyFromTensor:s sourceOrigin:so sourceDimensions:sd toTensor:d destinationOrigin:origin destinationDimensions:dimensions];}else CAMLreturn(result_error_text("tensor blits require macOS 26"));break;}case 3:{id<MTLTexture>s=object_of_handle(source,Handle_kind::Texture);id<MTLBuffer>d=object_of_handle(destination,Handle_kind::Buffer);MTLOrigin origin=MTLOriginMake(Int64_val(Field(spec,2)),Int64_val(Field(spec,3)),Int64_val(Field(spec,4)));MTLSize size=MTLSizeMake(Int64_val(Field(spec,5)),Int64_val(Field(spec,6)),Int64_val(Field(spec,7)));if(s.device.registryID!=d.device.registryID||!size.width||!size.height||!size.depth)CAMLreturn(result_error_text("invalid texture-to-buffer copy"));[e copyFromTexture:s sourceSlice:Int64_val(Field(spec,0)) sourceLevel:Int64_val(Field(spec,1)) sourceOrigin:origin sourceSize:size toBuffer:d destinationOffset:Int64_val(Field(spec,8)) destinationBytesPerRow:Int64_val(Field(spec,9)) destinationBytesPerImage:Int64_val(Field(spec,10)) options:(MTLBlitOption)Int64_val(Field(spec,11))];break;}case 4:{id<MTLTexture>s=object_of_handle(source,Handle_kind::Texture),d=object_of_handle(destination,Handle_kind::Texture);MTLOrigin origin=MTLOriginMake(Int64_val(Field(spec,2)),Int64_val(Field(spec,3)),Int64_val(Field(spec,4)));MTLSize size=MTLSizeMake(Int64_val(Field(spec,5)),Int64_val(Field(spec,6)),Int64_val(Field(spec,7)));if(s.device.registryID!=d.device.registryID)CAMLreturn(result_error_text("texture copy device mismatch"));[e copyFromTexture:s sourceSlice:Int64_val(Field(spec,0)) sourceLevel:Int64_val(Field(spec,1)) sourceOrigin:origin sourceSize:size toTexture:d destinationSlice:Int64_val(Field(spec,8)) destinationLevel:Int64_val(Field(spec,9)) destinationOrigin:MTLOriginMake(Int64_val(Field(spec,10)),Int64_val(Field(spec,11)),Int64_val(Field(spec,12)))];break;}case 5:{id<MTLTexture>s=object_of_handle(source,Handle_kind::Texture),d=object_of_handle(destination,Handle_kind::Texture);if(s.device.registryID!=d.device.registryID)CAMLreturn(result_error_text("texture copy device mismatch"));[e copyFromTexture:s sourceSlice:Int64_val(Field(spec,0)) sourceLevel:Int64_val(Field(spec,1)) toTexture:d destinationSlice:Int64_val(Field(spec,2)) destinationLevel:Int64_val(Field(spec,3)) sliceCount:Int64_val(Field(spec,4)) levelCount:Int64_val(Field(spec,5))];break;}case 6:{id<MTLTexture>s=object_of_handle(source,Handle_kind::Texture),d=object_of_handle(destination,Handle_kind::Texture);if(s.device.registryID!=d.device.registryID)CAMLreturn(result_error_text("texture copy device mismatch"));[e copyFromTexture:s toTexture:d];break;}case 7:{id<MTLIndirectCommandBuffer>s=object_of_handle(source,Handle_kind::Indirect_command_buffer),d=object_of_handle(destination,Handle_kind::Indirect_command_buffer);NSRange range=NSMakeRange(Int64_val(Field(spec,0)),Int64_val(Field(spec,1)));if(s.device.registryID!=d.device.registryID||NSMaxRange(range)>s.size)CAMLreturn(result_error_text("invalid indirect command copy range"));[e copyIndirectCommandBuffer:s sourceRange:range destination:d destinationIndex:Int64_val(Field(spec,2))];break;}default:CAMLreturn(result_error_text("unknown blit copy kind"));}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_blit_fill_mipmap(value raw,value resource,value mode,value range_or_value){CAMLparam4(raw,resource,mode,range_or_value);@try{id<MTLBlitCommandEncoder>e=object_of_handle(raw,Handle_kind::Blit_encoder);if(Bool_val(mode)){id<MTLTexture>t=object_of_handle(resource,Handle_kind::Texture);if(t.mipmapLevelCount<2)CAMLreturn(result_error_text("texture has no mipmaps"));[e generateMipmapsForTexture:t];}else{id<MTLBuffer>b=object_of_handle(resource,Handle_kind::Buffer);int64_t o=Int64_val(Field(range_or_value,0)),n=Int64_val(Field(range_or_value,1)),v=Int64_val(Field(range_or_value,2));if(!prismel_blit_range(b.length,o,n)||v<0||v>255)CAMLreturn(result_error_text("invalid fill range/value"));[e fillBuffer:b range:NSMakeRange(o,n) value:(uint8_t)v];}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_blit_fence(value raw,value fence,value update){CAMLparam3(raw,fence,update);@try{id<MTLBlitCommandEncoder>e=object_of_handle(raw,Handle_kind::Blit_encoder);id<MTLFence>f=object_of_handle(fence,Handle_kind::Fence);if(Bool_val(update))[e updateFence:f];else[e waitForFence:f];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_blit_counter(value raw,value sample,value first,value count,value destination,value offset,value sample_now){CAMLparam5(raw,sample,first,count,destination);CAMLxparam2(offset,sample_now);@try{id<MTLBlitCommandEncoder>e=object_of_handle(raw,Handle_kind::Blit_encoder);id<MTLCounterSampleBuffer>s=object_of_handle(sample,Handle_kind::Counter_sample_buffer);int64_t i=Int64_val(first),n=Int64_val(count);if(i<0||n<0||(uint64_t)i>s.sampleCount||(uint64_t)n>s.sampleCount-i)CAMLreturn(result_error_text("counter sample range out of bounds"));if(Bool_val(sample_now))[e sampleCountersInBuffer:s atSampleIndex:i withBarrier:YES];else{ id<MTLBuffer>d=object_of_handle(destination,Handle_kind::Buffer);int64_t o=Int64_val(offset);if(o<0||(uint64_t)o>d.length)CAMLreturn(result_error_text("counter resolve offset out of bounds"));[e resolveCounters:s inRange:NSMakeRange(i,n) destinationBuffer:d destinationOffset:o];}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_blit_counter_bytecode(value*argv,int argc){(void)argc;return caml_prismel_metal_blit_counter(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5],argv[6]);}

/* M3: former metal_compute_pass20_callable_bridge.inc */
/* ComputePass20 complete descriptor graph. Returned objects use the three
   dedicated handle kinds added by integration. */
extern "C" CAMLprim value caml_prismel_metal_compute_pass_create(value dispatch){CAMLparam1(dispatch);CAMLlocal2(handle,result);int type=Long_val(dispatch);if(type<0||type>1)CAMLreturn(result_error_text("invalid compute dispatch type"));@try{MTLComputePassDescriptor*d=[MTLComputePassDescriptor computePassDescriptor];d.dispatchType=(MTLDispatchType)type;handle=allocate_handle(d,Handle_kind::Compute_pass_descriptor);result=result_ok(handle);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_compute_pass_snapshot(value raw){CAMLparam1(raw);CAMLlocal3(tuple,attachments,result);@try{MTLComputePassDescriptor*d=object_of_handle(raw,Handle_kind::Compute_pass_descriptor);attachments=allocate_handle(d.sampleBufferAttachments,Handle_kind::Compute_sample_attachment_array);tuple=caml_alloc_tuple(2);Store_field(tuple,0,Val_long(d.dispatchType));Store_field(tuple,1,attachments);result=result_ok(tuple);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_compute_pass_attachment(value raw,value index,value sample,value start,value finish){CAMLparam5(raw,index,sample,start,finish);CAMLlocal2(handle,result);int64_t i=Int64_val(index),s=Int64_val(start),e=Int64_val(finish);if(i<0||(Is_none(sample)?(s!=-1||e!=-1):(s<0||e<0||s>e)))CAMLreturn(result_error_text("invalid compute sample attachment indices"));@try{MTLComputePassSampleBufferAttachmentDescriptorArray*a=object_of_handle(raw,Handle_kind::Compute_sample_attachment_array);id<MTLCounterSampleBuffer>b=Is_none(sample)?nil:object_of_handle(Field(sample,0),Handle_kind::Counter_sample_buffer);if(b&&(NSUInteger)e>=b.sampleCount)CAMLreturn(result_error_text("compute sample index out of range"));MTLComputePassSampleBufferAttachmentDescriptor*d=a[i];d.sampleBuffer=b;d.startOfEncoderSampleIndex=s;d.endOfEncoderSampleIndex=e;handle=allocate_handle(d,Handle_kind::Compute_sample_attachment);result=result_ok(handle);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_compute_pass_attachment_snapshot(value raw){CAMLparam1(raw);CAMLlocal5(tuple,sample,handle,start,finish);@try{MTLComputePassSampleBufferAttachmentDescriptor*d=object_of_handle(raw,Handle_kind::Compute_sample_attachment);if(!d.sampleBuffer)sample=Val_none;else{handle=allocate_handle(d.sampleBuffer,Handle_kind::Counter_sample_buffer);sample=caml_alloc(1,0);Store_field(sample,0,handle);}start=caml_copy_int64(d.startOfEncoderSampleIndex);finish=caml_copy_int64(d.endOfEncoderSampleIndex);tuple=caml_alloc_tuple(3);Store_field(tuple,0,sample);Store_field(tuple,1,start);Store_field(tuple,2,finish);CAMLreturn(result_ok(tuple));}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

/* M3: former metal_function_log18_callable_bridge.inc */
/* FunctionLog18 ownership shard.  The scalar type/line/column selectors live
   in the mechanical command-support shard.  These wrappers preserve nullable
   protocol edges with exact handle kinds and copy NSString/NSURL text before
   the command-completion callback which supplied the log is allowed to end. */

/* M3: former metal_command_queue15_callable_bridge.inc */
/* CommandQueue15 isolated shard. Integration adds Command_queue_descriptor and
   Log_state handle kinds. Handles allocated for unretained-reference command
   buffers retain the returned Objective-C object, making that SDK fast path
   safe across OCaml ownership and queue-parent lifetime. */

/* mode 0 is commandBufferWithUnretainedReferences; mode 1 materializes the
   exact command-buffer descriptor tuple (retainedReferences,errorOptions,log). */

/* M3: former metal_compute_pipeline11_callable_bridge.inc */

/* M3: former metal_command_buffer19_encoder_info.inc */

/* M3: former metal_indirect_command14_callable_bridge.inc */
/* IndirectCommand14 residual shard. expected_device is the authoritative ICB
   owner registry ID retained by the safe parent; all resource edges are fully
   checked before a command mutation. Safe integration retains bound resources
   by command slot and releases that slot atomically after reset. */
static bool prismel_indirect_buffer_range(id<MTLBuffer> buffer, int64_t offset,
                                          int64_t bytes, int64_t device) {
  return offset >= 0 && bytes >= 0 && (uint64_t)offset <= buffer.length &&
    (uint64_t)bytes <= buffer.length - (uint64_t)offset &&
    (int64_t)buffer.device.registryID == device;
}

extern "C" CAMLprim value caml_prismel_metal_indirect_render_draw_indexed(
    value command_raw,value primitive_raw,value count_raw,value type_raw,
    value buffer_raw,value offset_raw,value instances_raw,value base_vertex_raw,
    value base_instance_raw,value device_raw){CAMLparam5(command_raw,primitive_raw,count_raw,type_raw,buffer_raw);CAMLxparam5(offset_raw,instances_raw,base_vertex_raw,base_instance_raw,device_raw);
  int64_t count=Int64_val(count_raw),offset=Int64_val(offset_raw),instances=Int64_val(instances_raw),base=Int64_val(base_instance_raw);int type=Long_val(type_raw);if(count<=0||instances<=0||base<0||(type!=0&&type!=1))CAMLreturn(result_error_text("invalid indexed indirect cardinality/type"));
  @try{id<MTLBuffer>b=object_of_handle(buffer_raw,Handle_kind::Buffer);int64_t element_bytes=type==0?2:4;if(count>INT64_MAX/element_bytes)CAMLreturn(result_error_text("indirect index byte count overflows"));int64_t bytes=count*element_bytes;if(!prismel_indirect_buffer_range(b,offset,bytes,Int64_val(device_raw)))CAMLreturn(result_error_text("indirect index range/device mismatch"));id<MTLIndirectRenderCommand>c=object_of_handle(command_raw,Handle_kind::Indirect_render_command);[c drawIndexedPrimitives:(MTLPrimitiveType)Long_val(primitive_raw) indexCount:count indexType:(MTLIndexType)type indexBuffer:b indexBufferOffset:offset instanceCount:instances baseVertex:Int64_val(base_vertex_raw) baseInstance:base];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_indirect_render_draw_indexed_bytecode(value*argv,int argc){(void)argc;return caml_prismel_metal_indirect_render_draw_indexed(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5],argv[6],argv[7],argv[8],argv[9]);}

/* Patch calls retain three buffers in the safe command slot. The positional
   tuple is (controlPoints,patchStart,patchCount,patchOffset,controlOffset,
   instances,baseInstance,tessOffset,tessStride), all int64. */

/* M3: former metal_acceleration_structure28_callable_bridge.inc */
/* AccelerationStructure28 constructor-only ownership shard. Integration adds
   ten exact descriptor handle kinds; property graphs remain handwritten and
   validate all buffers before mutating these retained descriptors. */

/* M3: former metal_log_state9_callable_bridge.inc */
#include <condition_variable>
#include <cstddef>
#include <mutex>

/* MTLLogState has no removeLogHandler: selector.  The native block therefore
   retains this state for as long as Metal retains the handler, while cancel()
   only closes the client callback gate.  A delivery admitted before cancel
   may finish; later deliveries are rejected. */
class PrismelLogHandlerGate {
 public:
  bool enter() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!active_) return false;
    ++in_flight_;
    return true;
  }

  void leave() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (in_flight_ == 0) return;
    --in_flight_;
    if (in_flight_ == 0) idle_.notify_all();
  }

  void cancel_and_wait() {
    std::unique_lock<std::mutex> lock(mutex_);
    active_ = false;
    idle_.wait(lock, [this] { return in_flight_ == 0; });
  }

  bool active() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return active_;
  }

 private:
  mutable std::mutex mutex_;
  std::condition_variable idle_;
  bool active_ = true;
  std::size_t in_flight_ = 0;
};

/* Metal retains the handler block and offers no unregister selector.  Keep a
   small shared gate in that block, admit every delivery until cancellation,
   and release the OCaml root only after all admitted callbacks have drained. */
struct PrismelLogHandlerState{std::shared_ptr<PrismelLogHandlerGate>gate=std::make_shared<PrismelLogHandlerGate>();value*root=nullptr;};
struct PrismelLogHandlerToken{std::shared_ptr<PrismelLogHandlerState>state;};

/* M3: former metal_function_handle8_callable_bridge.inc */
/* FunctionHandle8 isolated snapshot. A single exact-kind read materializes all
   four SDK properties; method/property companion IDs share these direct typed
   selectors without exposing Device handles or native strings. */

/* M3: former metal_linked_functions9_callable_bridge.inc */
/* LinkedFunctions9 isolated shard. The safe owner supplies its authoritative
   pipeline device ID. Every nullable array/dictionary edge is decoded,
   kind/device checked, and copied before the first descriptor mutation. */

/* M3: former metal_linked_functions9_constructor_bridge.inc */
/* Handwritten enabling constructor for the LinkedFunctions9 safe graph.
   MTLLinkedFunctions is a descriptor-like retained object with no device
   property.  The safe OCaml owner therefore records the authoritative device
   separately and passes its registry ID to every function-bearing setter. */

/* M3: former metal4_command_queue8_callable_bridge.inc */
/* MTL4CommandQueue8 isolated tail. Every call is compile/runtime gated and
   receives a live-state witness from the safe queue owner. */

/* operation: 0 add residency, 1 signal drawable, 2 wait drawable, 3 wait event. */

/* M3: former metal_render_pipeline93_descriptor_bridge.inc */
/* RenderPipeline93 mechanical descriptor foundation. The OCaml safe layer
   owns graph semantics; these direct calls only construct/reset descriptors,
   copy labels, and access the checked color-attachment array. */

/* operation 0 binary archives, 1 object function, 2 mesh function,
   3 fragment function. [expected] is also the replacement when [set_raw]. */

/* operation 0 binary archives, 1 preloaded libraries, 2 tile function. */

/* Descriptor-array immutable snapshots: descriptor kind 0 render, 1 mesh,
   2 tile; array kind 0 colors, then stage buffer arrays in header order. */
extern "C" CAMLprim value caml_prismel_metal_render93_array_snapshot(value descriptor_raw,value descriptor_kind_raw,value array_kind_raw) {
  CAMLparam3(descriptor_raw,descriptor_kind_raw,array_kind_raw); CAMLlocal2(values,result);
  @try {
    int descriptor_kind=Long_val(descriptor_kind_raw),array_kind=Long_val(array_kind_raw);
    if(array_kind==0){
      values=caml_alloc(8,0);
      if(descriptor_kind==0){MTLRenderPipelineDescriptor*d=object_of_handle(descriptor_raw,Handle_kind::Render_pipeline_descriptor);for(NSUInteger i=0;i<8;i++)Store_field(values,i,caml_copy_int64((int64_t)d.colorAttachments[i].pixelFormat));}
      else if(descriptor_kind==1){MTLMeshRenderPipelineDescriptor*d=object_of_handle(descriptor_raw,Handle_kind::Mesh_pipeline_descriptor);for(NSUInteger i=0;i<8;i++)Store_field(values,i,caml_copy_int64((int64_t)d.colorAttachments[i].pixelFormat));}
      else if(descriptor_kind==2){MTLTileRenderPipelineDescriptor*d=object_of_handle(descriptor_raw,Handle_kind::Tile_pipeline_descriptor);for(NSUInteger i=0;i<8;i++)Store_field(values,i,caml_copy_int64((int64_t)d.colorAttachments[i].pixelFormat));}
      else CAMLreturn(result_error_text("unknown render pipeline descriptor kind"));
    }else{
      MTLPipelineBufferDescriptorArray*array=nil;
      if(descriptor_kind==0){MTLRenderPipelineDescriptor*d=object_of_handle(descriptor_raw,Handle_kind::Render_pipeline_descriptor);if(array_kind==1)array=d.fragmentBuffers;else if(array_kind==2)array=d.vertexBuffers;}
      else if(descriptor_kind==1){MTLMeshRenderPipelineDescriptor*d=object_of_handle(descriptor_raw,Handle_kind::Mesh_pipeline_descriptor);if(array_kind==1)array=d.fragmentBuffers;else if(array_kind==2)array=d.meshBuffers;else if(array_kind==3)array=d.objectBuffers;}
      else if(descriptor_kind==2){MTLTileRenderPipelineDescriptor*d=object_of_handle(descriptor_raw,Handle_kind::Tile_pipeline_descriptor);if(array_kind==1)array=d.tileBuffers;}
      if(array==nil)CAMLreturn(result_error_text("buffer array does not belong to this render pipeline descriptor"));
      values=caml_alloc(31,0);for(NSUInteger i=0;i<31;i++)Store_field(values,i,caml_copy_int64((int64_t)array[i].mutability));
    }
    result=result_ok(values);CAMLreturn(result);
  } @catch(NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

/* M3: former metal_render_pipeline93_linked_graph_bridge.inc */
/* RenderPipeline93 linked-function graph closure (exact 12 SDK IDs).

   MTLLinkedFunctions properties are copied by the descriptor.  Setters accept
   an exact-kind handle, while getters return a fresh owned snapshot handle.
   The handwritten safe layer must retain its source graph until replacement
   and must validate every referenced function against the pipeline device.

   Mesh lanes: 0 object, 1 mesh, 2 fragment.  Tile has one linked-functions
   lane.  A missing OCaml option maps to nil and remains a valid graph reset. */

/* M3: former metal_render_pipeline93_function_handle_bridge.inc */
/* RenderPipeline93 pipeline-state function lookup closure (exact 3 IDs).
   Results are nullable and become independently owned Function_handle values.
   The safe layer validates liveness, same-device identity, one exact stage bit,
   UTF-8/NUL-free names, and retains the source function through this call. */

/* M3: former metal_render_pipeline93_function_tables_bridge.inc */
/* RenderPipeline93 function-table allocation closure (exact 2 IDs).
   The public safe API supplies a checked positive capacity and exact stage;
   this native layer constructs the SDK descriptor locally, avoiding exposure
   of a mutable descriptor handle, then returns one owned table handle. */

/* M3: former metal_render_pipeline93_functions_descriptor_bridge.inc */
/* RenderPipeline93 functions-descriptor closure (exact 10 IDs): class plus
   getter/setter/property triples for vertex, fragment and tile additional
   binary-linkable MTLFunction values.  Shared hookup must add the exact owned handle kind
   Render_pipeline_functions_descriptor.  Arrays are validated completely
   before any SDK setter executes; the safe layer retains logical children and
   validates one device identity when attaching this descriptor to a pipeline. */

/* M3: former metal_render_pipeline93_state_factories_bridge.inc */
/* Final RenderPipeline93 state factory closure (exact 3 IDs).
   Hookup adds Pipeline_descriptor4 and the functions-descriptor kind prepared
   in the exact10 shard.  Every returned object is independently owned. */

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/* M3: former metal_render_pipeline93_vertex_reflection_bridge.inc */
/* Final RenderPipeline93 descriptor/reflection closure (exact 9 IDs).
   Hookup adds exact owned Vertex_descriptor and Render_pipeline_reflection
   kinds. Vertex descriptors are copied; reflection arrays become immutable
   six-field value snapshots (name,index,type,access,active,array-length). */

#pragma clang diagnostic pop

/* M3: former metal_intersection_table8_callable_bridge.inc */
/* IntersectionFunctionTable8 isolated shard. Function-handle entries carry
   authoritative safe-owner registry IDs because MTLFunctionHandle exposes no
   device property. All arrays are decoded before the first table write. */

/* M3: former metal_stage_input_output10_callable_bridge.inc */
/* StageInputOutputDescriptor10 isolated ownership shard. Attribute replacement
   is decoded before mutation; returned child arrays/descriptors are retained
   exact-kind handles. The safe graph owns descriptor children until reset. */

/* M3: former metal_blit_pass10_callable_bridge.inc */
/* BlitPass10 residual ownership shard. Descriptor creation and attachment-array
   acquisition already use Blit_pass_descriptor/Blit_sample_attachment_array.
   These adapters complete nullable array and counter-buffer graph ownership. */
extern "C" CAMLprim value caml_prismel_metal_blit_pass10_attachment_at(
    value array_raw, value index_raw) {
  CAMLparam2(array_raw, index_raw); CAMLlocal3(option, handle, result);
  int64_t index = Int64_val(index_raw);
  if (index < 0) CAMLreturn(result_error_text("blit attachment index is negative"));
  @try { MTLBlitPassSampleBufferAttachmentDescriptorArray *array =
      object_of_handle(array_raw, Handle_kind::Blit_sample_attachment_array);
    MTLBlitPassSampleBufferAttachmentDescriptor *attachment = array[(NSUInteger)index];
    if (attachment == nil) option = Val_none;
    else { handle = allocate_handle(attachment, Handle_kind::Blit_sample_attachment);
      option = caml_alloc(1, 0); Store_field(option, 0, handle); }
    result = result_ok(option); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_blit_pass10_set_sample_buffer(
    value raw, value buffer_raw, value device_raw) {
  CAMLparam3(raw, buffer_raw, device_raw);
  @try { id<MTLCounterSampleBuffer> buffer = Is_none(buffer_raw) ? nil :
      object_of_handle(Field(buffer_raw, 0), Handle_kind::Counter_sample_buffer);
    if (buffer != nil && (int64_t)buffer.device.registryID != Int64_val(device_raw))
      CAMLreturn(result_error_text("blit sample buffer device mismatch"));
    MTLBlitPassSampleBufferAttachmentDescriptor *attachment =
      object_of_handle(raw, Handle_kind::Blit_sample_attachment);
    attachment.sampleBuffer = buffer; CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

/* M3: former metal_drawable10_callable_bridge.inc */
/* Drawable10 isolated shard. Safe owners retain the drawable from acquisition
   through schedule and completion. Handler roots are bounded, exactly-once,
   and explicitly cancellable if presentation never occurs. */
struct PrismelDrawableCallbackState {
  std::atomic<int> state{0}; value *root = nullptr;
};
struct PrismelDrawableCallbackToken {
  std::shared_ptr<PrismelDrawableCallbackState> state;
};

extern "C" CAMLprim value caml_prismel_metal_drawable10_snapshot(value raw) {
  CAMLparam1(raw); CAMLlocal4(tuple, identifier, presented, result);
  @try { id<MTLDrawable> drawable = object_of_handle(raw, Handle_kind::Metal_drawable);
    identifier = caml_copy_int64((int64_t)drawable.drawableID);
    presented = caml_copy_double(drawable.presentedTime);
    tuple = caml_alloc_tuple(2); Store_field(tuple, 0, identifier);
    Store_field(tuple, 1, presented); result = result_ok(tuple); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

/* M3: former metal_function_constant_values3_callable_bridge.inc */
/* FunctionConstantValues3 isolated shard. Values are passed as owned OCaml
   byte snapshots. The data type determines exact element width; the complete
   payload and range are validated before the single native mutation. */

/* M3: former metal_binary_archive5_callable_bridge.inc */
/* BinaryArchive5 isolated descriptor-addition shard. Descriptor/library device
   metadata is checked in full before invoking the selected archive mutation.
   Safe integration retains successful descriptor/library edges only after Ok. */

extern "C" CAMLprim value caml_prismel_metal_binary_archive5_configured_descriptor(
    value kind_raw, value first_raw, value second_raw, value format_raw) {
  CAMLparam4(kind_raw, first_raw, second_raw, format_raw); CAMLlocal2(handle, result);
  @try {
    int kind = Long_val(kind_raw); id descriptor = nil; Handle_kind handle_kind;
    id<MTLFunction> first = object_of_handle(first_raw, Handle_kind::Function);
    if (kind == 0) {
      MTLFunctionDescriptor *function = [MTLFunctionDescriptor functionDescriptor];
      function.name = first.name; descriptor = function;
      handle_kind = Handle_kind::Function_descriptor;
    } else if (kind == 2) {
      MTLMeshRenderPipelineDescriptor *mesh = [MTLMeshRenderPipelineDescriptor new];
      mesh.meshFunction = first;
      if (Is_block(second_raw)) mesh.fragmentFunction = object_of_handle(
        Field(second_raw, 0), Handle_kind::Function);
      mesh.colorAttachments[0].pixelFormat = (MTLPixelFormat)Int64_val(format_raw);
      descriptor = mesh; handle_kind = Handle_kind::Mesh_pipeline_descriptor;
    } else if (kind == 3) {
      if (Is_none(second_raw)) CAMLreturn(result_error_text("render archive descriptor requires a fragment function"));
      id<MTLFunction> second = object_of_handle(Field(second_raw, 0), Handle_kind::Function);
      MTLRenderPipelineDescriptor *render = [MTLRenderPipelineDescriptor new];
      render.vertexFunction = first; render.fragmentFunction = second;
      render.colorAttachments[0].pixelFormat = (MTLPixelFormat)Int64_val(format_raw);
      descriptor = render; handle_kind = Handle_kind::Render_pipeline_descriptor;
    } else if (kind == 4) {
      if (Is_block(second_raw)) CAMLreturn(result_error_text("tile archive descriptor has an unexpected second function"));
      MTLTileRenderPipelineDescriptor *tile = [MTLTileRenderPipelineDescriptor new];
      tile.tileFunction = first;
      tile.colorAttachments[0].pixelFormat = (MTLPixelFormat)Int64_val(format_raw);
      descriptor = tile; handle_kind = Handle_kind::Tile_pipeline_descriptor;
    } else CAMLreturn(result_error_text("binary archive descriptor kind is not configured by this safe path"));
    handle = allocate_handle(descriptor, handle_kind); result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_binary_archive5_add(
    value archive_raw, value kind_raw, value descriptor_raw, value library_raw,
    value archive_device_raw, value descriptor_device_raw, value library_device_raw) {
  CAMLparam5(archive_raw, kind_raw, descriptor_raw, library_raw,
    archive_device_raw); CAMLxparam2(descriptor_device_raw, library_device_raw);
  int kind = Long_val(kind_raw); int64_t archive_device = Int64_val(archive_device_raw);
  if (kind < 0 || kind > 4 || Int64_val(descriptor_device_raw) != archive_device)
    CAMLreturn(result_error_text("binary archive descriptor kind/device mismatch"));
  @try { id<MTLBinaryArchive> archive = object_of_handle(
      archive_raw, Handle_kind::Binary_archive);
    if ((int64_t)archive.device.registryID != archive_device)
      CAMLreturn(result_error_text("binary archive device identity changed"));
    NSError *error = nil; BOOL success = NO;
    if (kind == 0) {
      if (Is_none(library_raw) || Is_none(library_device_raw)
          || Int64_val(Field(library_device_raw, 0)) != archive_device)
        CAMLreturn(result_error_text("binary archive function library device mismatch"));
      id<MTLLibrary> library = object_of_handle(Field(library_raw, 0), Handle_kind::Library);
      if ((int64_t)library.device.registryID != archive_device)
        CAMLreturn(result_error_text("binary archive function library identity changed"));
      MTLFunctionDescriptor *descriptor = object_of_handle(
        descriptor_raw, Handle_kind::Function_descriptor);
      success = [archive addFunctionWithDescriptor:descriptor library:library error:&error];
    } else {
      if (!Is_none(library_raw) || !Is_none(library_device_raw))
        CAMLreturn(result_error_text("unexpected binary archive library edge"));
      if (kind == 2) success = [archive addMeshRenderPipelineFunctionsWithDescriptor:
          object_of_handle(descriptor_raw, Handle_kind::Mesh_pipeline_descriptor) error:&error];
      else if (kind == 3) success = [archive addRenderPipelineFunctionsWithDescriptor:
          object_of_handle(descriptor_raw, Handle_kind::Render_pipeline_descriptor) error:&error];
      else success = [archive addTileRenderPipelineFunctionsWithDescriptor:
          object_of_handle(descriptor_raw, Handle_kind::Tile_pipeline_descriptor) error:&error];
    }
    if (!success) CAMLreturn(result_error(error_description(error,
      @"binary archive descriptor addition failed")));
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_binary_archive5_add_bytecode(
    value *argv, int argc) { (void)argc;
  return caml_prismel_metal_binary_archive5_add(argv[0], argv[1], argv[2],
    argv[3], argv[4], argv[5], argv[6]);
}

/* M3: former metal_tensor_ownership_callable_bridge.inc */
/* Handwritten Tensor ownership15 bridge; returned objects receive exact kinds. */

/* M3: former metal_resource_remaining16_bridge.inc */
/* Typed enablers for the final Resource100 ownership graphs.  This include is
   intentionally standalone until the shared bridge owner yields integration. */

/* M3: former metal_compute_encoder35_bindings.inc */
template<class T> static std::vector<T> prismel_compute_handles(value a, Handle_kind kind) {
  mlsize_t n = Wosize_val(a); std::vector<T> values; values.reserve(n);
  for (mlsize_t i = 0; i < n; ++i)
    values.push_back(Is_none(Field(a,i)) ? nil : object_of_handle(Field(Field(a,i),0), kind));
  return values;
}
static std::vector<NSUInteger> prismel_compute_uints(value a) {
  mlsize_t n = Wosize_val(a); std::vector<NSUInteger> values(n);
  for (mlsize_t i = 0; i < n; ++i) values[i] = Int64_val(Field(a,i));
  return values;
}
static std::vector<float> prismel_compute_floats(value a) {
  mlsize_t n = Wosize_val(a); std::vector<float> values(n);
  for (mlsize_t i = 0; i < n; ++i) values[i] = Double_val(Field(a,i));
  return values;
}
#define COMPUTE_ENTRY(NAME) extern "C" CAMLprim value NAME
#define COMPUTE_ENCODER(V) id<MTLComputeCommandEncoder> e = object_of_handle((V), Handle_kind::Compute_encoder)

COMPUTE_ENTRY(caml_prismel_metal_compute35_buffer_stride)(value re,value rb,value ro,value rs,value ri){CAMLparam5(re,rb,ro,rs,ri);@try{COMPUTE_ENCODER(re);id<MTLBuffer>b=Is_none(rb)?nil:object_of_handle(Field(rb,0),Handle_kind::Buffer);[e setBuffer:b offset:Int64_val(ro) attributeStride:Int64_val(rs) atIndex:Int64_val(ri)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
COMPUTE_ENTRY(caml_prismel_metal_compute35_buffer_offset)(value re,value ro,value ri){CAMLparam3(re,ro,ri);@try{COMPUTE_ENCODER(re);[e setBufferOffset:Int64_val(ro) atIndex:Int64_val(ri)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
COMPUTE_ENTRY(caml_prismel_metal_compute35_buffer_offset_stride)(value re,value ro,value rs,value ri){CAMLparam4(re,ro,rs,ri);@try{COMPUTE_ENCODER(re);[e setBufferOffset:Int64_val(ro) attributeStride:Int64_val(rs) atIndex:Int64_val(ri)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
COMPUTE_ENTRY(caml_prismel_metal_compute35_buffers_bytecode)(value*argv,int argc){(void)argc;CAMLparam0();@try{COMPUTE_ENCODER(argv[0]);auto b=prismel_compute_handles<id<MTLBuffer>>(argv[1],Handle_kind::Buffer);auto o=prismel_compute_uints(argv[2]);auto s=prismel_compute_uints(argv[3]);if(b.size()!=o.size()||(!s.empty()&&s.size()!=b.size()))CAMLreturn(result_error_text("compute buffer binding cardinality mismatch"));NSRange r=NSMakeRange(Int64_val(argv[4]),b.size());if(s.empty())[e setBuffers:b.data() offsets:o.data() withRange:r];else[e setBuffers:b.data() offsets:o.data() attributeStrides:s.data() withRange:r];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
COMPUTE_ENTRY(caml_prismel_metal_compute35_buffers)(value a,value b,value c,value d,value e){value argv[]={a,b,c,d,e};return caml_prismel_metal_compute35_buffers_bytecode(argv,5);}
COMPUTE_ENTRY(caml_prismel_metal_compute35_bytes)(value re,value rb,value rs,value ri){CAMLparam4(re,rb,rs,ri);@try{COMPUTE_ENCODER(re);[e setBytes:Bytes_val(rb) length:caml_string_length(rb) attributeStride:Int64_val(rs) atIndex:Int64_val(ri)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
COMPUTE_ENTRY(caml_prismel_metal_compute35_textures)(value re,value ra,value rstart){CAMLparam3(re,ra,rstart);@try{COMPUTE_ENCODER(re);auto a=prismel_compute_handles<id<MTLTexture>>(ra,Handle_kind::Texture);[e setTextures:a.data() withRange:NSMakeRange(Int64_val(rstart),a.size())];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
COMPUTE_ENTRY(caml_prismel_metal_compute35_sampler)(value re,value rs,value rlod,value ri){CAMLparam4(re,rs,rlod,ri);@try{COMPUTE_ENCODER(re);id<MTLSamplerState>s=Is_none(rs)?nil:object_of_handle(Field(rs,0),Handle_kind::Sampler);NSUInteger i=Int64_val(ri);if(Is_none(rlod))[e setSamplerState:s atIndex:i];else{value p=Field(rlod,0);[e setSamplerState:s lodMinClamp:Double_val(Field(p,0)) lodMaxClamp:Double_val(Field(p,1)) atIndex:i];}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
COMPUTE_ENTRY(caml_prismel_metal_compute35_samplers)(value re,value ra,value rlo,value rhi,value rstart){CAMLparam5(re,ra,rlo,rhi,rstart);@try{COMPUTE_ENCODER(re);auto a=prismel_compute_handles<id<MTLSamplerState>>(ra,Handle_kind::Sampler);NSRange r=NSMakeRange(Int64_val(rstart),a.size());if(Is_none(rlo)&&Is_none(rhi))[e setSamplerStates:a.data() withRange:r];else if(!Is_none(rlo)&&!Is_none(rhi)){auto lo=prismel_compute_floats(Field(rlo,0));auto hi=prismel_compute_floats(Field(rhi,0));if(lo.size()!=a.size()||hi.size()!=a.size())CAMLreturn(result_error_text("compute sampler LOD cardinality mismatch"));[e setSamplerStates:a.data() lodMinClamps:lo.data() lodMaxClamps:hi.data() withRange:r];}else CAMLreturn(result_error_text("compute sampler LOD arrays must both be present"));CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
COMPUTE_ENTRY(caml_prismel_metal_compute35_acceleration)(value re,value ra,value ri){CAMLparam3(re,ra,ri);@try{COMPUTE_ENCODER(re);id<MTLAccelerationStructure>a=Is_none(ra)?nil:object_of_handle(Field(ra,0),Handle_kind::Acceleration_structure);[e setAccelerationStructure:a atBufferIndex:Int64_val(ri)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define COMPUTE_TABLE_ONE(NAME,TYPE,KIND,SELECTOR) COMPUTE_ENTRY(NAME)(value re,value rx,value ri){CAMLparam3(re,rx,ri);@try{COMPUTE_ENCODER(re);TYPE x=Is_none(rx)?nil:object_of_handle(Field(rx,0),KIND);[e SELECTOR:x atBufferIndex:Int64_val(ri)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define COMPUTE_TABLE_MANY(NAME,TYPE,KIND,SELECTOR) COMPUTE_ENTRY(NAME)(value re,value ra,value ri){CAMLparam3(re,ra,ri);@try{COMPUTE_ENCODER(re);auto a=prismel_compute_handles<TYPE>(ra,KIND);[e SELECTOR:a.data() withBufferRange:NSMakeRange(Int64_val(ri),a.size())];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
COMPUTE_TABLE_ONE(caml_prismel_metal_compute35_visible,id<MTLVisibleFunctionTable>,Handle_kind::Visible_function_table,setVisibleFunctionTable)
COMPUTE_TABLE_MANY(caml_prismel_metal_compute35_visibles,id<MTLVisibleFunctionTable>,Handle_kind::Visible_function_table,setVisibleFunctionTables)
COMPUTE_TABLE_ONE(caml_prismel_metal_compute35_intersection,id<MTLIntersectionFunctionTable>,Handle_kind::Intersection_function_table,setIntersectionFunctionTable)
COMPUTE_TABLE_MANY(caml_prismel_metal_compute35_intersections,id<MTLIntersectionFunctionTable>,Handle_kind::Intersection_function_table,setIntersectionFunctionTables)
#undef COMPUTE_TABLE_ONE
#undef COMPUTE_TABLE_MANY
#undef COMPUTE_ENTRY
#undef COMPUTE_ENCODER

/* M3: former metal_compute_encoder35_commands.inc */
static MTLSize prismel_compute35_size(value v){return MTLSizeMake(Long_val(Field(v,0)),Long_val(Field(v,1)),Long_val(Field(v,2)));}
static MTLRegion prismel_compute35_region(value v){return MTLRegionMake3D(Int64_val(Field(v,0)),Int64_val(Field(v,1)),Int64_val(Field(v,2)),Int64_val(Field(v,3)),Int64_val(Field(v,4)),Int64_val(Field(v,5)));}
static std::vector<id<MTLResource>> prismel_compute35_resources(value handles,value kinds){mlsize_t n=Wosize_val(handles);if(Wosize_val(kinds)!=n)@throw[NSException exceptionWithName:NSInvalidArgumentException reason:@"resource kind cardinality mismatch" userInfo:nil];std::vector<id<MTLResource>>r;r.reserve(n);for(mlsize_t i=0;i<n;i++){Handle_kind k=Bool_val(Field(kinds,i))?Handle_kind::Texture:Handle_kind::Buffer;r.push_back(object_of_handle(Field(handles,i),k));}return r;}
#define C35_ENTRY(NAME) extern "C" CAMLprim value NAME
#define C35_ENCODER(V) id<MTLComputeCommandEncoder> e=object_of_handle((V),Handle_kind::Compute_encoder)
C35_ENTRY(caml_prismel_metal_compute35_dispatch_groups)(value re,value rg,value rt){CAMLparam3(re,rg,rt);@try{C35_ENCODER(re);[e dispatchThreadgroups:prismel_compute35_size(rg) threadsPerThreadgroup:prismel_compute35_size(rt)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_dispatch_indirect)(value re,value rb,value ro,value rt){CAMLparam4(re,rb,ro,rt);@try{C35_ENCODER(re);id<MTLBuffer>b=object_of_handle(rb,Handle_kind::Buffer);[e dispatchThreadgroupsWithIndirectBuffer:b indirectBufferOffset:Int64_val(ro) threadsPerThreadgroup:prismel_compute35_size(rt)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_dispatch_type)(value re){CAMLparam1(re);CAMLlocal2(v,r);@try{C35_ENCODER(re);v=Val_long(e.dispatchType);r=result_ok(v);CAMLreturn(r);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_execute_indirect)(value re,value ri,value rb,value ro){CAMLparam4(re,ri,rb,ro);@try{C35_ENCODER(re);[e executeCommandsInBuffer:object_of_handle(ri,Handle_kind::Indirect_command_buffer) indirectBuffer:object_of_handle(rb,Handle_kind::Buffer) indirectBufferOffset:Int64_val(ro)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_barrier_resources)(value re,value rh,value rk){CAMLparam3(re,rh,rk);@try{C35_ENCODER(re);auto r=prismel_compute35_resources(rh,rk);[e memoryBarrierWithResources:r.data() count:r.size()];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_barrier_scope)(value re,value rs){CAMLparam2(re,rs);@try{C35_ENCODER(re);[e memoryBarrierWithScope:(MTLBarrierScope)Int64_val(rs)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_sample_counters)(value re,value rb,value ri,value barrier){CAMLparam4(re,rb,ri,barrier);@try{C35_ENCODER(re);[e sampleCountersInBuffer:object_of_handle(rb,Handle_kind::Counter_sample_buffer) atSampleIndex:Int64_val(ri) withBarrier:Bool_val(barrier)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_supports_stage_counters)(value rd){CAMLparam1(rd);CAMLlocal2(v,r);@try{id<MTLDevice>d=object_of_handle(rd,Handle_kind::Device);v=Val_bool([d supportsCounterSampling:MTLCounterSamplingPointAtDispatchBoundary]);r=result_ok(v);CAMLreturn(r);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_bytes_plain)(value re,value rb,value ri){CAMLparam3(re,rb,ri);@try{C35_ENCODER(re);[e setBytes:Bytes_val(rb) length:caml_string_length(rb) atIndex:Int64_val(ri)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_imageblock)(value re,value rw,value rh){CAMLparam3(re,rw,rh);@try{C35_ENCODER(re);[e setImageblockWidth:Int64_val(rw) height:Int64_val(rh)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_stage_region)(value re,value rr){CAMLparam2(re,rr);@try{C35_ENCODER(re);[e setStageInRegion:prismel_compute35_region(rr)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_stage_indirect)(value re,value rb,value ro){CAMLparam3(re,rb,ro);@try{C35_ENCODER(re);[e setStageInRegionWithIndirectBuffer:object_of_handle(rb,Handle_kind::Buffer) indirectBufferOffset:Int64_val(ro)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_threadgroup_memory)(value re,value rl,value ri){CAMLparam3(re,rl,ri);@try{C35_ENCODER(re);[e setThreadgroupMemoryLength:Int64_val(rl) atIndex:Int64_val(ri)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define C35_FENCE(NAME,SELECTOR) C35_ENTRY(NAME)(value re,value rf){CAMLparam2(re,rf);@try{C35_ENCODER(re);[e SELECTOR:object_of_handle(rf,Handle_kind::Fence)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_FENCE(caml_prismel_metal_compute35_update_fence,updateFence)
C35_FENCE(caml_prismel_metal_compute35_wait_fence,waitForFence)
#undef C35_FENCE
C35_ENTRY(caml_prismel_metal_compute35_heaps)(value re,value ra){CAMLparam2(re,ra);@try{C35_ENCODER(re);mlsize_t n=Wosize_val(ra);std::vector<id<MTLHeap>>h;h.reserve(n);for(mlsize_t i=0;i<n;i++)h.push_back(object_of_handle(Field(ra,i),Handle_kind::Heap));if(n==1)[e useHeap:h[0]];else[e useHeaps:h.data() count:n];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
C35_ENTRY(caml_prismel_metal_compute35_resources)(value re,value rh,value rk,value usage){CAMLparam4(re,rh,rk,usage);@try{C35_ENCODER(re);auto r=prismel_compute35_resources(rh,rk);if(r.size()==1)[e useResource:r[0] usage:(MTLResourceUsage)Int64_val(usage)];else[e useResources:r.data() count:r.size() usage:(MTLResourceUsage)Int64_val(usage)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#undef C35_ENTRY
#undef C35_ENCODER

/* M3: former metal_device_residual_final4_bridge.inc */
/* Final exact MTLDevice selector closure: two function handles, one immutable
   argument-descriptor array constructor, and the synchronous render pipeline
   constructor. */

/* M3: former metal_device_final_constructors3_bridge.inc */
/* Exact final three MTLDevice constructors. */

/* M3: former metal_device_capability13_bridge.inc */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#pragma clang diagnostic pop
#pragma clang diagnostic pop

/* M3: former metal_device_spatial_timestamp6_bridge.inc */

extern "C" CAMLprim value caml_prismel_metal_device_sample_timestamps(value rh) {
  CAMLparam1(rh); CAMLlocal2(pair, result);
  @try {
    id<MTLDevice> device = object_of_handle(rh, Handle_kind::Device);
    MTLTimestamp cpu = 0, gpu = 0;
    [device sampleTimestamps:&cpu gpuTimestamp:&gpu];
    pair = caml_alloc_tuple(2);
    Store_field(pair, 0, caml_copy_int64((int64_t)cpu));
    Store_field(pair, 1, caml_copy_int64((int64_t)gpu));
    result = result_ok(pair); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_device_timestamp_frequency(value rh) {
  CAMLparam1(rh);
  if (@available(macOS 26.0, *)) {
    @try { id<MTLDevice> d=object_of_handle(rh,Handle_kind::Device);
      CAMLreturn(result_ok(caml_copy_int64((int64_t)[d queryTimestampFrequency])));
    } @catch(NSException*x){CAMLreturn(result_error(x.reason));}
  }
  CAMLreturn(result_error_text("queryTimestampFrequency requires macOS 26"));
}

#pragma clang diagnostic pop

/* ---- Generic acceleration structure build descriptors (plan G5). One call
   builds a complete, retained MTLPrimitive/MTLInstanceAccelerationStructure
   descriptor from a validated OCaml record; sizes, build, and refit take that
   descriptor object. Field order mirrors metal_raw.accel_* records. ---- */
static NSArray<MTLMotionKeyframeData *> *accel_keyframes_of_ocaml(value raw) {
  NSMutableArray<MTLMotionKeyframeData *> *frames =
      [NSMutableArray arrayWithCapacity:Wosize_val(raw)];
  for (mlsize_t i = 0; i < Wosize_val(raw); i++) {
    value keyframe = Field(raw, i);
    MTLMotionKeyframeData *data = [MTLMotionKeyframeData data];
    data.buffer = object_of_handle(Field(keyframe, 0), Handle_kind::Buffer);
    data.offset = Int64_val(Field(keyframe, 1));
    [frames addObject:data];
  }
  return frames;
}

static void accel_geometry_common(MTLAccelerationStructureGeometryDescriptor *geometry,
                                  value opaque, value duplicate, value table_offset) {
  geometry.opaque = Bool_val(opaque);
  geometry.allowDuplicateIntersectionFunctionInvocation = Bool_val(duplicate);
  geometry.intersectionFunctionTableOffset = Int64_val(table_offset);
}

static MTLAccelerationStructureGeometryDescriptor *accel_geometry_of_ocaml(value g) {
  switch (Tag_val(g)) {
  case 0: {
    /* Raw_triangles: vertex, vertex_offset, vertex_stride, triangle_count,
       index option, index_offset, index_uint16, keyframes, opaque, allow_dup,
       table_offset */
    value keyframes = Field(g, 7);
    id<MTLBuffer> index =
        Is_block(Field(g, 4)) ? object_of_handle(Field(Field(g, 4), 0), Handle_kind::Buffer)
                              : nil;
    MTLIndexType index_type = Bool_val(Field(g, 6)) ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32;
    if (Wosize_val(keyframes) == 0) {
      MTLAccelerationStructureTriangleGeometryDescriptor *d =
          [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
      d.vertexBuffer = object_of_handle(Field(g, 0), Handle_kind::Buffer);
      d.vertexBufferOffset = Int64_val(Field(g, 1));
      d.vertexStride = Int64_val(Field(g, 2));
      d.triangleCount = Int64_val(Field(g, 3));
      if (index != nil) {
        d.indexBuffer = index;
        d.indexBufferOffset = Int64_val(Field(g, 5));
        d.indexType = index_type;
      }
      accel_geometry_common(d, Field(g, 8), Field(g, 9), Field(g, 10));
      return d;
    }
    MTLAccelerationStructureMotionTriangleGeometryDescriptor *d =
        [MTLAccelerationStructureMotionTriangleGeometryDescriptor descriptor];
    d.vertexBuffers = accel_keyframes_of_ocaml(keyframes);
    d.vertexStride = Int64_val(Field(g, 2));
    d.triangleCount = Int64_val(Field(g, 3));
    if (index != nil) {
      d.indexBuffer = index;
      d.indexBufferOffset = Int64_val(Field(g, 5));
      d.indexType = index_type;
    }
    accel_geometry_common(d, Field(g, 8), Field(g, 9), Field(g, 10));
    return d;
  }
  case 1: {
    /* Raw_boxes: boxes, box_offset, box_stride, box_count, keyframes, opaque,
       allow_dup, table_offset */
    value keyframes = Field(g, 4);
    if (Wosize_val(keyframes) == 0) {
      MTLAccelerationStructureBoundingBoxGeometryDescriptor *d =
          [MTLAccelerationStructureBoundingBoxGeometryDescriptor descriptor];
      d.boundingBoxBuffer = object_of_handle(Field(g, 0), Handle_kind::Buffer);
      d.boundingBoxBufferOffset = Int64_val(Field(g, 1));
      d.boundingBoxStride = Int64_val(Field(g, 2));
      d.boundingBoxCount = Int64_val(Field(g, 3));
      accel_geometry_common(d, Field(g, 5), Field(g, 6), Field(g, 7));
      return d;
    }
    MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor *d =
        [MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor descriptor];
    d.boundingBoxBuffers = accel_keyframes_of_ocaml(keyframes);
    d.boundingBoxStride = Int64_val(Field(g, 2));
    d.boundingBoxCount = Int64_val(Field(g, 3));
    accel_geometry_common(d, Field(g, 5), Field(g, 6), Field(g, 7));
    return d;
  }
  default: {
    /* Raw_curves: control, control_offset, control_stride, control_count,
       radius, radius_offset, radius_stride, index, index_offset, index_uint16,
       segment_count, segment_control_points, curve_type, basis, end_caps,
       control_keyframes, radius_keyframes, opaque, allow_dup, table_offset */
    value control_keyframes = Field(g, 15);
    MTLCurveType type = Long_val(Field(g, 12)) == 0 ? MTLCurveTypeRound : MTLCurveTypeFlat;
    MTLCurveBasis basis = MTLCurveBasisBSpline;
    switch (Long_val(Field(g, 13))) {
    case 1: basis = MTLCurveBasisCatmullRom; break;
    case 2: basis = MTLCurveBasisLinear; break;
    case 3: basis = MTLCurveBasisBezier; break;
    default: break;
    }
    MTLCurveEndCaps caps = MTLCurveEndCapsNone;
    switch (Long_val(Field(g, 14))) {
    case 1: caps = MTLCurveEndCapsDisk; break;
    case 2: caps = MTLCurveEndCapsSphere; break;
    default: break;
    }
    MTLIndexType index_type = Bool_val(Field(g, 9)) ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32;
    if (Wosize_val(control_keyframes) == 0) {
      MTLAccelerationStructureCurveGeometryDescriptor *d =
          [MTLAccelerationStructureCurveGeometryDescriptor descriptor];
      d.controlPointBuffer = object_of_handle(Field(g, 0), Handle_kind::Buffer);
      d.controlPointBufferOffset = Int64_val(Field(g, 1));
      d.controlPointStride = Int64_val(Field(g, 2));
      d.controlPointCount = Int64_val(Field(g, 3));
      d.controlPointFormat = MTLAttributeFormatFloat3;
      d.radiusBuffer = object_of_handle(Field(g, 4), Handle_kind::Buffer);
      d.radiusBufferOffset = Int64_val(Field(g, 5));
      d.radiusStride = Int64_val(Field(g, 6));
      d.radiusFormat = MTLAttributeFormatFloat;
      d.indexBuffer = object_of_handle(Field(g, 7), Handle_kind::Buffer);
      d.indexBufferOffset = Int64_val(Field(g, 8));
      d.indexType = index_type;
      d.segmentCount = Int64_val(Field(g, 10));
      d.segmentControlPointCount = Int64_val(Field(g, 11));
      d.curveType = type;
      d.curveBasis = basis;
      d.curveEndCaps = caps;
      accel_geometry_common(d, Field(g, 17), Field(g, 18), Field(g, 19));
      return d;
    }
    MTLAccelerationStructureMotionCurveGeometryDescriptor *d =
        [MTLAccelerationStructureMotionCurveGeometryDescriptor descriptor];
    d.controlPointBuffers = accel_keyframes_of_ocaml(control_keyframes);
    d.controlPointStride = Int64_val(Field(g, 2));
    d.controlPointCount = Int64_val(Field(g, 3));
    d.controlPointFormat = MTLAttributeFormatFloat3;
    d.radiusBuffers = accel_keyframes_of_ocaml(Field(g, 16));
    d.radiusStride = Int64_val(Field(g, 6));
    d.radiusFormat = MTLAttributeFormatFloat;
    d.indexBuffer = object_of_handle(Field(g, 7), Handle_kind::Buffer);
    d.indexBufferOffset = Int64_val(Field(g, 8));
    d.indexType = index_type;
    d.segmentCount = Int64_val(Field(g, 10));
    d.segmentControlPointCount = Int64_val(Field(g, 11));
    d.curveType = type;
    d.curveBasis = basis;
    d.curveEndCaps = caps;
    accel_geometry_common(d, Field(g, 17), Field(g, 18), Field(g, 19));
    return d;
  }
  }
}

static MTLAccelerationStructureUsage accel_usage_of_ocaml(value refit, value fast_build) {
  MTLAccelerationStructureUsage usage = MTLAccelerationStructureUsageNone;
  if (Bool_val(refit)) usage |= MTLAccelerationStructureUsageRefit;
  if (Bool_val(fast_build)) usage |= MTLAccelerationStructureUsagePreferFastBuild;
  return usage;
}

/* accel_primitive_raw: geometries, motion option, refit, fast_build;
   accel_motion_raw: keyframe_count, start_time, end_time, start_border, end_border */
extern "C" CAMLprim value caml_prismel_metal_accel_descriptor_primitive(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(handle);
  @autoreleasepool {
    @try {
      MTLPrimitiveAccelerationStructureDescriptor *descriptor =
          [MTLPrimitiveAccelerationStructureDescriptor descriptor];
      value geometries = Field(raw, 0);
      NSMutableArray<MTLAccelerationStructureGeometryDescriptor *> *list =
          [NSMutableArray arrayWithCapacity:Wosize_val(geometries)];
      for (mlsize_t i = 0; i < Wosize_val(geometries); i++)
        [list addObject:accel_geometry_of_ocaml(Field(geometries, i))];
      descriptor.geometryDescriptors = list;
      value motion = Field(raw, 1);
      if (Is_block(motion)) {
        value m = Field(motion, 0);
        descriptor.motionKeyframeCount = Int64_val(Field(m, 0));
        descriptor.motionStartTime = (float)Double_val(Field(m, 1));
        descriptor.motionEndTime = (float)Double_val(Field(m, 2));
        descriptor.motionStartBorderMode =
            Long_val(Field(m, 3)) == 0 ? MTLMotionBorderModeClamp : MTLMotionBorderModeVanish;
        descriptor.motionEndBorderMode =
            Long_val(Field(m, 4)) == 0 ? MTLMotionBorderModeClamp : MTLMotionBorderModeVanish;
      }
      descriptor.usage = accel_usage_of_ocaml(Field(raw, 2), Field(raw, 3));
      handle = allocate_handle(descriptor, Handle_kind::Acceleration_primitive_descriptor);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(handle));
}

/* accel_instances_raw: instance_buffer, instance_offset, instance_stride,
   instance_count, instance_kind, primitives, motion_transforms option,
   motion_transform_offset, motion_transform_count, refit */
extern "C" CAMLprim value caml_prismel_metal_accel_descriptor_instances(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(handle);
  @autoreleasepool {
    @try {
      MTLInstanceAccelerationStructureDescriptor *descriptor =
          [MTLInstanceAccelerationStructureDescriptor descriptor];
      descriptor.instanceDescriptorBuffer = object_of_handle(Field(raw, 0), Handle_kind::Buffer);
      descriptor.instanceDescriptorBufferOffset = Int64_val(Field(raw, 1));
      descriptor.instanceDescriptorStride = Int64_val(Field(raw, 2));
      descriptor.instanceCount = Int64_val(Field(raw, 3));
      switch (Long_val(Field(raw, 4))) {
      case 1: descriptor.instanceDescriptorType = MTLAccelerationStructureInstanceDescriptorTypeUserID; break;
      case 2: descriptor.instanceDescriptorType = MTLAccelerationStructureInstanceDescriptorTypeMotion; break;
      default: descriptor.instanceDescriptorType = MTLAccelerationStructureInstanceDescriptorTypeDefault; break;
      }
      value primitives = Field(raw, 5);
      NSMutableArray<id<MTLAccelerationStructure>> *structures =
          [NSMutableArray arrayWithCapacity:Wosize_val(primitives)];
      for (mlsize_t i = 0; i < Wosize_val(primitives); i++)
        [structures addObject:object_of_handle(Field(primitives, i),
                                               Handle_kind::Acceleration_structure)];
      descriptor.instancedAccelerationStructures = structures;
      value transforms = Field(raw, 6);
      if (Is_block(transforms)) {
        descriptor.motionTransformBuffer =
            object_of_handle(Field(transforms, 0), Handle_kind::Buffer);
        descriptor.motionTransformBufferOffset = Int64_val(Field(raw, 7));
        descriptor.motionTransformCount = Int64_val(Field(raw, 8));
      }
      descriptor.usage = accel_usage_of_ocaml(Field(raw, 9), Val_false);
      handle = allocate_handle(descriptor, Handle_kind::Acceleration_instance_descriptor);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(handle));
}

static MTLAccelerationStructureDescriptor *accel_build_descriptor_of_handle(value raw) {
  auto *handle = handle_of_value(raw);
  std::lock_guard<std::mutex> lock(handle_mutex);
  if (handle->kind != Handle_kind::Acceleration_primitive_descriptor &&
      handle->kind != Handle_kind::Acceleration_instance_descriptor)
    caml_failwith("Metal custom handle is not an acceleration build descriptor");
  if (handle->object == nullptr) caml_failwith("Metal custom handle is destroyed");
  return (__bridge MTLAccelerationStructureDescriptor *)handle->object;
}

extern "C" CAMLprim value caml_prismel_metal_accel_descriptor_sizes(value raw_device,
                                                                     value raw_descriptor) {
  CAMLparam2(raw_device, raw_descriptor);
  CAMLlocal4(result, tuple, first, second);
  CAMLlocal1(third);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      MTLAccelerationStructureSizes sizes = [device
          accelerationStructureSizesWithDescriptor:accel_build_descriptor_of_handle(raw_descriptor)];
      tuple = caml_alloc_tuple(3);
      first = caml_copy_int64((int64_t)sizes.accelerationStructureSize);
      second = caml_copy_int64((int64_t)sizes.buildScratchBufferSize);
      third = caml_copy_int64((int64_t)sizes.refitScratchBufferSize);
      Store_field(tuple, 0, first);
      Store_field(tuple, 1, second);
      Store_field(tuple, 2, third);
      result = result_ok(tuple);
    } @catch (NSException *exception) {
      result = result_error(exception.reason);
    }
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_accel_encoder_build_descriptor(
    value raw_encoder, value raw_destination, value raw_descriptor, value raw_scratch,
    value raw_scratch_offset) {
  CAMLparam5(raw_encoder, raw_destination, raw_descriptor, raw_scratch, raw_scratch_offset);
  @autoreleasepool {
    @try {
      id<MTLAccelerationStructureCommandEncoder> encoder =
          object_of_handle(raw_encoder, Handle_kind::Acceleration_encoder);
      [encoder buildAccelerationStructure:object_of_handle(raw_destination,
                                                           Handle_kind::Acceleration_structure)
                               descriptor:accel_build_descriptor_of_handle(raw_descriptor)
                            scratchBuffer:object_of_handle(raw_scratch, Handle_kind::Buffer)
                      scratchBufferOffset:Int64_val(raw_scratch_offset)];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_accel_encoder_refit_descriptor(
    value raw_encoder, value raw_source, value raw_destination, value raw_descriptor,
    value raw_scratch, value raw_scratch_offset) {
  CAMLparam5(raw_encoder, raw_source, raw_destination, raw_descriptor, raw_scratch);
  CAMLxparam1(raw_scratch_offset);
  @autoreleasepool {
    @try {
      id<MTLAccelerationStructureCommandEncoder> encoder =
          object_of_handle(raw_encoder, Handle_kind::Acceleration_encoder);
      [encoder refitAccelerationStructure:object_of_handle(raw_source,
                                                           Handle_kind::Acceleration_structure)
                               descriptor:accel_build_descriptor_of_handle(raw_descriptor)
                              destination:object_of_handle(raw_destination,
                                                           Handle_kind::Acceleration_structure)
                            scratchBuffer:object_of_handle(raw_scratch, Handle_kind::Buffer)
                      scratchBufferOffset:Int64_val(raw_scratch_offset)];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_accel_encoder_refit_descriptor_bytecode(
    value *argv, int argn) {
  (void)argn;
  return caml_prismel_metal_accel_encoder_refit_descriptor(argv[0], argv[1], argv[2], argv[3],
                                                           argv[4], argv[5]);
}

static_assert(sizeof(MTLAccelerationStructureUserIDInstanceDescriptor) == 68);
static_assert(offsetof(MTLAccelerationStructureUserIDInstanceDescriptor, userID) == 64);
static_assert(sizeof(MTLPackedFloat4x3) == 48);

/* Byte layout of one instance descriptor record for the given kind:
   [size; transform; options; mask; table_offset; structure_index; user_id;
    transforms_start; transforms_count; start_border; end_border; start_time;
    end_time], -1 where the kind lacks the field. */
extern "C" CAMLprim value caml_prismel_metal_accel_instance_layout(value raw_kind) {
  CAMLparam1(raw_kind);
  CAMLlocal1(layout);
  long values[13];
  for (int i = 0; i < 13; i++) values[i] = -1;
  switch (Long_val(raw_kind)) {
  case 1:
    values[0] = sizeof(MTLAccelerationStructureUserIDInstanceDescriptor);
    values[1] = offsetof(MTLAccelerationStructureUserIDInstanceDescriptor, transformationMatrix);
    values[2] = offsetof(MTLAccelerationStructureUserIDInstanceDescriptor, options);
    values[3] = offsetof(MTLAccelerationStructureUserIDInstanceDescriptor, mask);
    values[4] = offsetof(MTLAccelerationStructureUserIDInstanceDescriptor, intersectionFunctionTableOffset);
    values[5] = offsetof(MTLAccelerationStructureUserIDInstanceDescriptor, accelerationStructureIndex);
    values[6] = offsetof(MTLAccelerationStructureUserIDInstanceDescriptor, userID);
    break;
  case 2:
    values[0] = sizeof(MTLAccelerationStructureMotionInstanceDescriptor);
    values[2] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, options);
    values[3] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, mask);
    values[4] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, intersectionFunctionTableOffset);
    values[5] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, accelerationStructureIndex);
    values[6] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, userID);
    values[7] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, motionTransformsStartIndex);
    values[8] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, motionTransformsCount);
    values[9] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, motionStartBorderMode);
    values[10] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, motionEndBorderMode);
    values[11] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, motionStartTime);
    values[12] = offsetof(MTLAccelerationStructureMotionInstanceDescriptor, motionEndTime);
    break;
  default:
    values[0] = sizeof(MTLAccelerationStructureInstanceDescriptor);
    values[1] = offsetof(MTLAccelerationStructureInstanceDescriptor, transformationMatrix);
    values[2] = offsetof(MTLAccelerationStructureInstanceDescriptor, options);
    values[3] = offsetof(MTLAccelerationStructureInstanceDescriptor, mask);
    values[4] = offsetof(MTLAccelerationStructureInstanceDescriptor, intersectionFunctionTableOffset);
    values[5] = offsetof(MTLAccelerationStructureInstanceDescriptor, accelerationStructureIndex);
    break;
  }
  layout = caml_alloc(13, 0);
  for (int i = 0; i < 13; i++) Store_field(layout, i, Val_long(values[i]));
  CAMLreturn(layout);
}

// Plan G6: shared events on classic command buffers, host waits, and
// compute/blit encoders created from pass descriptors (stage-boundary
// counter sampling).

extern "C" CAMLprim value caml_prismel_metal_shared_event_wait(value raw, value raw_number,
                                                              value raw_timeout) {
  CAMLparam3(raw, raw_number, raw_timeout);
  id<MTLSharedEvent> event = nil;
  @try {
    event = object_of_handle(raw, Handle_kind::Shared_event);
  } @catch (NSException *x) {
    CAMLreturn(result_error(x.reason));
  }
  uint64_t target = (uint64_t)Int64_val(raw_number);
  uint64_t timeout = (uint64_t)Int64_val(raw_timeout);
  BOOL reached = NO;
  NSString *failure = nil;
  caml_release_runtime_system();
  @try {
    reached = [event waitUntilSignaledValue:target timeoutMS:timeout];
  } @catch (NSException *x) {
    failure = [x.reason copy];
  }
  caml_acquire_runtime_system();
  if (failure != nil) CAMLreturn(result_error(failure));
  CAMLreturn(result_ok(Val_bool(reached)));
}

// Plan G7: classic mesh draws and tile dispatches, mesh/tile color formats,
// and the MetalFX spatial scaler (linked as its own framework). MetalFX is
// imported last so its selectors never shadow the untyped sends above.
#import <MetalFX/MetalFX.h>
extern "C" CAMLprim value caml_prismel_metal_render_encoder_draw_mesh_threadgroups(
    value raw, value raw_sizes) {
  CAMLparam2(raw, raw_sizes);
  @try {
    id<MTLRenderCommandEncoder> encoder = object_of_handle(raw, Handle_kind::Render_encoder);
    NSUInteger v[9];
    for (int i = 0; i < 9; i++) {
      intnat x = Long_val(Field(raw_sizes, i));
      if (x <= 0) CAMLreturn(result_error_text("mesh dispatch sizes must be positive"));
      v[i] = (NSUInteger)x;
    }
    [encoder drawMeshThreadgroups:MTLSizeMake(v[0], v[1], v[2])
        threadsPerObjectThreadgroup:MTLSizeMake(v[3], v[4], v[5])
          threadsPerMeshThreadgroup:MTLSizeMake(v[6], v[7], v[8])];
    CAMLreturn(result_unit());
  } @catch (NSException *x) {
    CAMLreturn(result_error(x.reason));
  }
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_dispatch_threads_per_tile(
    value raw, value raw_width, value raw_height, value raw_depth) {
  CAMLparam4(raw, raw_width, raw_height, raw_depth);
  @try {
    id<MTLRenderCommandEncoder> encoder = object_of_handle(raw, Handle_kind::Render_encoder);
    intnat width = Long_val(raw_width), height = Long_val(raw_height), depth = Long_val(raw_depth);
    if (width <= 0 || height <= 0 || depth != 1)
      CAMLreturn(result_error_text("tile dispatch sizes must be positive with depth one"));
    [encoder dispatchThreadsPerTile:MTLSizeMake((NSUInteger)width, (NSUInteger)height, 1)];
    CAMLreturn(result_unit());
  } @catch (NSException *x) {
    CAMLreturn(result_error(x.reason));
  }
}

extern "C" CAMLprim value caml_prismel_metal_mesh_tile_descriptor_set_color_format(
    value raw, value raw_tile, value raw_index, value raw_format) {
  CAMLparam4(raw, raw_tile, raw_index, raw_format);
  @try {
    intnat index = Long_val(raw_index);
    if (index < 0 || index >= 8)
      CAMLreturn(result_error_text("color attachment index is outside [0,8)"));
    MTLPixelFormat format = static_cast<MTLPixelFormat>(Long_val(raw_format));
    if (Bool_val(raw_tile)) {
      MTLTileRenderPipelineDescriptor *descriptor =
          object_of_handle(raw, Handle_kind::Tile_pipeline_descriptor);
      descriptor.colorAttachments[(NSUInteger)index].pixelFormat = format;
    } else {
      MTLMeshRenderPipelineDescriptor *descriptor =
          object_of_handle(raw, Handle_kind::Mesh_pipeline_descriptor);
      descriptor.colorAttachments[(NSUInteger)index].pixelFormat = format;
    }
    CAMLreturn(result_unit());
  } @catch (NSException *x) {
    CAMLreturn(result_error(x.reason));
  }
}

extern "C" CAMLprim value caml_prismel_metal_fx_spatial_supported(value raw) {
  CAMLparam1(raw);
  @try {
    id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
    CAMLreturn(result_ok(Val_bool([MTLFXSpatialScalerDescriptor supportsDevice:device])));
  } @catch (NSException *x) {
    CAMLreturn(result_error(x.reason));
  }
}

// (input width, input height, output width, output height, color format, output format)
extern "C" CAMLprim value caml_prismel_metal_fx_spatial_create(value raw, value raw_sizes) {
  CAMLparam2(raw, raw_sizes);
  CAMLlocal2(handle, result);
  @try {
    id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
    if (![MTLFXSpatialScalerDescriptor supportsDevice:device])
      CAMLreturn(result_error_text("MetalFX spatial scaling is unsupported on this device"));
    MTLFXSpatialScalerDescriptor *descriptor = [MTLFXSpatialScalerDescriptor new];
    descriptor.inputWidth = (NSUInteger)Long_val(Field(raw_sizes, 0));
    descriptor.inputHeight = (NSUInteger)Long_val(Field(raw_sizes, 1));
    descriptor.outputWidth = (NSUInteger)Long_val(Field(raw_sizes, 2));
    descriptor.outputHeight = (NSUInteger)Long_val(Field(raw_sizes, 3));
    descriptor.colorTextureFormat = static_cast<MTLPixelFormat>(Long_val(Field(raw_sizes, 4)));
    descriptor.outputTextureFormat = static_cast<MTLPixelFormat>(Long_val(Field(raw_sizes, 5)));
    descriptor.colorProcessingMode = MTLFXSpatialScalerColorProcessingModePerceptual;
    id<MTLFXSpatialScaler> scaler = [descriptor newSpatialScalerWithDevice:device];
    if (scaler == nil) CAMLreturn(result_error_text("MetalFX rejected the spatial scaler descriptor"));
    handle = allocate_handle(scaler, Handle_kind::Fx_spatial_scaler);
    result = result_ok(handle);
    CAMLreturn(result);
  } @catch (NSException *x) {
    CAMLreturn(result_error(x.reason));
  }
}

extern "C" CAMLprim value caml_prismel_metal_fx_spatial_encode(value raw, value raw_command,
                                                             value raw_color, value raw_output) {
  CAMLparam4(raw, raw_command, raw_color, raw_output);
  @try {
    id<MTLFXSpatialScaler> scaler = object_of_handle(raw, Handle_kind::Fx_spatial_scaler);
    id<MTLCommandBuffer> command = object_of_handle(raw_command, Handle_kind::Command_buffer);
    id<MTLTexture> color = object_of_handle(raw_color, Handle_kind::Texture);
    id<MTLTexture> output = object_of_handle(raw_output, Handle_kind::Texture);
    if (color.width != scaler.inputWidth || color.height != scaler.inputHeight ||
        color.pixelFormat != scaler.colorTextureFormat)
      CAMLreturn(result_error_text("color texture does not match the scaler input"));
    if (output.width != scaler.outputWidth || output.height != scaler.outputHeight ||
        output.pixelFormat != scaler.outputTextureFormat)
      CAMLreturn(result_error_text("output texture does not match the scaler output"));
    if ((color.usage & scaler.colorTextureUsage) != scaler.colorTextureUsage)
      CAMLreturn(result_error([NSString stringWithFormat:@"color texture usage %lu lacks the scaler requirement %lu",
                                                         (unsigned long)color.usage, (unsigned long)scaler.colorTextureUsage]));
    if ((output.usage & scaler.outputTextureUsage) != scaler.outputTextureUsage)
      CAMLreturn(result_error([NSString stringWithFormat:@"output texture usage %lu lacks the scaler requirement %lu",
                                                         (unsigned long)output.usage, (unsigned long)scaler.outputTextureUsage]));
    scaler.colorTexture = color;
    scaler.outputTexture = output;
    scaler.inputContentWidth = scaler.inputWidth;
    scaler.inputContentHeight = scaler.inputHeight;
    [scaler encodeToCommandBuffer:command];
    scaler.colorTexture = nil;
    scaler.outputTexture = nil;
    CAMLreturn(result_unit());
  } @catch (NSException *x) {
    CAMLreturn(result_error(x.reason));
  }
}

#include "metal_gen_feature_checks.inc"
