#define CAML_NAME_SPACE

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <limits>
#include <mutex>
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

constexpr std::size_t kCompilerCompletionCapacity = 1024;
static std::array<std::uint64_t, kCompilerCompletionCapacity>
    compiler_completion_ids;
static std::mutex compiler_completion_mutex;
static std::size_t compiler_completion_head = 0;
static std::size_t compiler_completion_count = 0;
static std::atomic<std::uint64_t> compiler_completion_dropped{0};
static std::atomic<std::uint64_t> next_compiler_task_id{1};

static void enqueue_compiler_completion(std::uint64_t identifier) {
  std::lock_guard<std::mutex> lock(compiler_completion_mutex);
  if (compiler_completion_count == kCompilerCompletionCapacity) {
    compiler_completion_dropped.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  const std::size_t tail =
      (compiler_completion_head + compiler_completion_count) %
      kCompilerCompletionCapacity;
  compiler_completion_ids[tail] = identifier;
  ++compiler_completion_count;
}

typedef NS_ENUM(NSUInteger, PrismelMetalCompilerResultState) {
  PrismelMetalCompilerResultPending = 0,
  PrismelMetalCompilerResultSuccess = 1,
  PrismelMetalCompilerResultFailure = 2,
  PrismelMetalCompilerResultConsumed = 3,
};

typedef NS_ENUM(NSUInteger, PrismelMetalCompilerResultKind) {
  PrismelMetalCompilerResultLibrary = 0,
  PrismelMetalCompilerResultBinaryFunction = 1,
  PrismelMetalCompilerResultComputePipeline = 2,
  PrismelMetalCompilerResultDynamicLibrary = 3,
  PrismelMetalCompilerResultRenderPipeline = 4,
};

API_AVAILABLE(macos(26.0))
@interface PrismelMetalCompilerTaskState : NSObject
@property(nonatomic, readonly) std::uint64_t identifier;
@property(nonatomic, strong) id<MTL4CompilerTask> task;
@property(nonatomic, readonly) NSString *label;
@property(nonatomic, readonly) PrismelMetalCompilerResultKind resultKind;
@property(nonatomic, readonly) BOOL reflectionRequested;
@property(nonatomic, strong, nullable) id retainedInputs;
@property(nonatomic, copy, nullable) NSString *expectedInstallName;
@property(nonatomic, copy, nullable) NSString *diagnosticIdentity;
- (instancetype)initWithKind:(PrismelMetalCompilerResultKind)kind
                        label:(nullable NSString *)label
          reflectionRequested:(BOOL)reflectionRequested;
- (void)finishWithObject:(nullable id)object error:(nullable NSError *)error;
- (PrismelMetalCompilerResultState)takeObject:(id __autoreleasing *)object
                                        error:(NSError *__autoreleasing *)error;
@end

@implementation PrismelMetalCompilerTaskState {
  std::uint64_t _identifier;
  id<MTL4CompilerTask> _task;
  NSString *_label;
  PrismelMetalCompilerResultKind _resultKind;
  BOOL _reflectionRequested;
  id _retainedInputs;
  NSString *_expectedInstallName;
  NSString *_diagnosticIdentity;
  id _resultObject;
  NSError *_resultError;
  PrismelMetalCompilerResultState _resultState;
  std::mutex _resultMutex;
}

- (instancetype)initWithKind:(PrismelMetalCompilerResultKind)kind
                        label:(NSString *)label
          reflectionRequested:(BOOL)reflectionRequested {
  self = [super init];
  if (self != nil) {
    _identifier = next_compiler_task_id.fetch_add(1, std::memory_order_relaxed);
    _label = [label copy];
    _resultKind = kind;
    _reflectionRequested = reflectionRequested;
    _resultState = PrismelMetalCompilerResultPending;
  }
  return self;
}

- (std::uint64_t)identifier { return _identifier; }
- (id<MTL4CompilerTask>)task { return _task; }
- (void)setTask:(id<MTL4CompilerTask>)task { _task = task; }
- (NSString *)label { return _label; }
- (PrismelMetalCompilerResultKind)resultKind { return _resultKind; }
- (BOOL)reflectionRequested { return _reflectionRequested; }
- (id)retainedInputs { return _retainedInputs; }
- (void)setRetainedInputs:(id)retainedInputs {
  _retainedInputs = retainedInputs;
}
- (NSString *)expectedInstallName { return _expectedInstallName; }
- (void)setExpectedInstallName:(NSString *)expectedInstallName {
  _expectedInstallName = [expectedInstallName copy];
}
- (NSString *)diagnosticIdentity { return _diagnosticIdentity; }
- (void)setDiagnosticIdentity:(NSString *)diagnosticIdentity {
  _diagnosticIdentity = [diagnosticIdentity copy];
}

- (void)finishWithObject:(id)object error:(NSError *)error {
  {
    std::lock_guard<std::mutex> lock(_resultMutex);
    if (_resultState != PrismelMetalCompilerResultPending) {
      return;
    }
    _resultObject = object;
    _resultError = error;
    _retainedInputs = nil;
    _resultState = object == nil ? PrismelMetalCompilerResultFailure
                                 : PrismelMetalCompilerResultSuccess;
  }
  enqueue_compiler_completion(_identifier);
}

- (PrismelMetalCompilerResultState)takeObject:(id *)object
                                        error:(NSError **)error {
  std::lock_guard<std::mutex> lock(_resultMutex);
  const PrismelMetalCompilerResultState state = _resultState;
  if (state == PrismelMetalCompilerResultSuccess ||
      state == PrismelMetalCompilerResultFailure) {
    *object = _resultObject;
    *error = _resultError;
    _resultObject = nil;
    _resultError = nil;
    _resultState = PrismelMetalCompilerResultConsumed;
  }
  return state;
}

@end

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
- (nullable NSError *)waitUntilCompleted;
@end

@implementation PrismelMetal4SubmissionState {
  id<MTL4CommandQueue> _queue;
  NSArray<PrismelMetal4CommandBufferState *> *_buffers;
  NSCondition *_condition;
  NSError *_error;
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
    for (PrismelMetal4CommandBufferState *buffer in _buffers) {
      [buffer releaseEncodedObjects];
    }
    _buffers = nil;
    _completed = YES;
    [_condition broadcast];
  }
  [_condition unlock];
}

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

namespace {

enum class Handle_kind : std::uint32_t {
  Device = 1,
  Heap,
  Buffer,
  Texture,
  Sampler,
  Library,
  Function,
  Dynamic_library,
  Binary_archive,
  Compute_pipeline,
  Command_queue,
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
  Compiler_task,
  Render_pipeline,
  Command_allocator4,
  Command_queue4,
  Command_buffer4,
  Render_encoder4,
  Submission4,
  Argument_table4,
  Compute_encoder4,
  Depth_stencil,
  Indirect_command_buffer,
  Indirect_render_command,
  Indirect_compute_command,
  Acceleration_structure,
  Acceleration_encoder,
};

struct Handle {
  void *object;
  std::uint64_t generation;
  Handle_kind kind;
};

constexpr std::size_t release_capacity = 65'536;
std::array<void *, release_capacity> release_queue{};
std::size_t release_head = 0;
std::size_t release_count = 0;
std::mutex release_mutex;
std::mutex handle_mutex;
std::atomic<std::uint64_t> next_generation{1};
std::atomic<std::uint64_t> dropped_releases{0};
std::atomic<std::uint64_t> live_handle_count{0};
std::atomic<std::uint64_t> total_created_count{0};
std::atomic<std::uint64_t> total_released_count{0};
std::atomic<std::uint64_t> external_deallocation_count{0};
std::atomic<std::uint64_t> external_deallocation_mismatch_count{0};
std::atomic<std::uint64_t> placement_mapping_operation_count{0};

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
  if (release_count == release_capacity) {
    dropped_releases.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  const std::size_t tail = (release_head + release_count) % release_capacity;
  release_queue[tail] = pointer;
  ++release_count;
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
      handle->kind != Handle_kind::Texture) {
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

id<MTLCommandEncoder> command_encoder_of_handle(value raw) {
  auto *handle = handle_of_value(raw);
  std::lock_guard<std::mutex> lock(handle_mutex);
  if (handle->kind != Handle_kind::Compute_encoder &&
      handle->kind != Handle_kind::Resource_state_encoder &&
      handle->kind != Handle_kind::Blit_encoder &&
      handle->kind != Handle_kind::Acceleration_encoder) {
    caml_failwith("Metal custom handle is not a command encoder");
  }
  if (handle->object == nullptr) {
    caml_failwith("Metal custom handle is destroyed");
  }
  return (__bridge id<MTLCommandEncoder>)handle->object;
}

PrismelMetalExternalMemory *external_memory_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::External_memory);
}

IOSurface *io_surface_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Io_surface);
}

MTLSharedTextureHandle *shared_texture_handle_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Shared_texture_handle);
}

Handle_kind xpc_resource_handle_kind(PrismelMetalXpcResourceKind kind) {
  switch (kind) {
  case PrismelMetalXpcResourceKindSharedTexture:
    return Handle_kind::Shared_texture_handle;
  case PrismelMetalXpcResourceKindIoSurface:
    return Handle_kind::Io_surface;
  }
}

id xpc_resource_of_handle(value raw, PrismelMetalXpcResourceKind kind) {
  switch (kind) {
  case PrismelMetalXpcResourceKindSharedTexture:
    return shared_texture_handle_of_handle(raw);
  case PrismelMetalXpcResourceKindIoSurface:
    return io_surface_of_handle(raw);
  }
}

bool xpc_resource_kind_of_code(intnat code,
                               PrismelMetalXpcResourceKind *kind) {
  switch (code) {
  case PrismelMetalXpcResourceKindSharedTexture:
    *kind = PrismelMetalXpcResourceKindSharedTexture;
    return true;
  case PrismelMetalXpcResourceKindIoSurface:
    *kind = PrismelMetalXpcResourceKindIoSurface;
    return true;
  default:
    return false;
  }
}

PrismelMetalXpcConnection *xpc_connection_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Xpc_connection);
}

PrismelMetalXpcService *xpc_service_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Xpc_service);
}

PrismelMetalXpcRequest *xpc_request_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Xpc_request);
}

API_AVAILABLE(macos(26.0))
id<MTL4CommandQueue> placement_mapping_queue_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Placement_mapping_queue);
}

API_AVAILABLE(macos(26.0))
PrismelMetal4CommandBufferState *command_buffer4_state_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Command_buffer4);
}

API_AVAILABLE(macos(26.0))
PrismelMetal4SubmissionState *submission4_state_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Submission4);
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
std::vector<id<MTL4Archive>> pipeline_archives_of_array(value raw_array) {
  const mlsize_t count = Wosize_val(raw_array);
  std::vector<id<MTL4Archive>> archives;
  archives.reserve(count);
  for (mlsize_t index = 0; index < count; ++index) {
    archives.push_back(object_of_handle(Field(raw_array, index),
                                        Handle_kind::Pipeline_archive));
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

value copy_function_constants(id<MTLFunction> function) {
  CAMLparam0();
  CAMLlocal4(array, tuple, name, index_value);
  NSDictionary<NSString *, MTLFunctionConstant *> *dictionary =
      function.functionConstantsDictionary;
  NSArray<MTLFunctionConstant *> *constants = dictionary.allValues;
  if (constants.count > static_cast<NSUInteger>(Max_wosize)) {
    caml_failwith("Metal function-constant metadata exceeds OCaml limits");
  }
  array = caml_alloc(static_cast<mlsize_t>(constants.count), 0);
  for (NSUInteger index = 0; index < constants.count; ++index) {
    MTLFunctionConstant *constant = constants[index];
    if (constant.index >
        static_cast<NSUInteger>(std::numeric_limits<std::int64_t>::max())) {
      caml_failwith("Metal function-constant index exceeds int64");
    }
    tuple = caml_alloc_tuple(4);
    name = caml_copy_string(constant.name.UTF8String ?: "");
    Store_field(tuple, 0, name);
    Store_field(tuple, 1, Val_long(static_cast<intnat>(constant.type)));
    index_value =
        caml_copy_int64(static_cast<std::int64_t>(constant.index));
    Store_field(tuple, 2, index_value);
    Store_field(tuple, 3, Val_bool(constant.required));
    Store_field(array, static_cast<mlsize_t>(index), tuple);
  }
  CAMLreturn(array);
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

value copy_render_reflection(MTLRenderPipelineReflection *reflection) {
  CAMLparam0();
  CAMLlocal5(vertex, fragment, tile, object, mesh);
  CAMLlocal1(result);
  vertex = copy_bindings(reflection.vertexBindings);
  fragment = copy_bindings(reflection.fragmentBindings);
  tile = copy_bindings(reflection.tileBindings);
  object = copy_bindings(reflection.objectBindings);
  mesh = copy_bindings(reflection.meshBindings);
  result = caml_alloc_tuple(5);
  Store_field(result, 0, vertex);
  Store_field(result, 1, fragment);
  Store_field(result, 2, tile);
  Store_field(result, 3, object);
  Store_field(result, 4, mesh);
  CAMLreturn(result);
}

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

NSData *data_from_ocaml(value raw) {
  return [NSData dataWithBytes:Bytes_val(raw)
                       length:caml_string_length(raw)];
}

value copy_data(NSData *data) {
  CAMLparam0();
  CAMLlocal1(bytes);
  if (data == nil || data.length > static_cast<NSUInteger>(Max_long)) {
    caml_failwith("native data exceeds OCaml byte-buffer limits");
  }
  bytes = caml_alloc_string(static_cast<mlsize_t>(data.length));
  if (data.length != 0) {
    std::memcpy(Bytes_val(bytes), data.bytes, data.length);
  }
  CAMLreturn(bytes);
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

bool device_supports_metal4_commands(id<MTLDevice> device) {
  if (@available(macOS 26.0, *)) {
    return [device supportsFamily:MTLGPUFamilyMetal4] &&
           [device respondsToSelector:
               @selector(newCommandAllocatorWithDescriptor:error:)] &&
           [device respondsToSelector:@selector(newCommandBuffer)] &&
           [device respondsToSelector:
               @selector(newMTL4CommandQueueWithDescriptor:error:)] &&
           [device respondsToSelector:
               @selector(newArgumentTableWithDescriptor:error:)];
  }
  return false;
}

API_AVAILABLE(macos(26.0))
MTL4BinaryFunctionDescriptor *checked_binary_function_descriptor(
    value raw_descriptor, id<MTLDevice> device,
    NSArray<id<MTL4Archive>> *__autoreleasing *lookup_archives,
    NSString *__autoreleasing *failure) {
  id<MTLLibrary> library =
      object_of_handle(Field(raw_descriptor, 0), Handle_kind::Library);
  id<MTLFunction> source_function =
      object_of_handle(Field(raw_descriptor, 1), Handle_kind::Function);
  if (library.device.registryID != device.registryID ||
      source_function.device.registryID != device.registryID) {
    *failure = @"Metal 4 binary-function source is incompatible with the device";
    return nil;
  }
  if (source_function.functionType != MTLFunctionTypeVisible &&
      source_function.functionType != MTLFunctionTypeIntersection) {
    *failure = @"Metal 4 binary-function source is not visible or intersection";
    return nil;
  }
  NSString *binary_name = string_from_ocaml(Field(raw_descriptor, 2));
  if (binary_name == nil || binary_name.length == 0) {
    *failure = @"Metal 4 binary-function name is not valid nonempty UTF-8";
    return nil;
  }
  const bool pipeline_independent = Bool_val(Field(raw_descriptor, 3));
  if (pipeline_independent && !device.supportsFunctionPointers) {
    *failure = @"Metal 4 pipeline-independent binary functions require function pointers";
    return nil;
  }
  std::vector<id<MTL4Archive>> raw_archives =
      pipeline_archives_of_array(Field(raw_descriptor, 4));
  NSMutableArray<id<MTL4Archive>> *archive_array =
      [NSMutableArray arrayWithCapacity:raw_archives.size()];
  NSMutableSet<id<MTL4Archive>> *archive_set = [NSMutableSet set];
  for (id<MTL4Archive> archive : raw_archives) {
    if ([archive_set containsObject:archive]) {
      *failure = @"Metal 4 binary-function lookup archive is duplicated";
      return nil;
    }
    [archive_set addObject:archive];
    [archive_array addObject:archive];
  }
  MTL4LibraryFunctionDescriptor *function_descriptor =
      [[MTL4LibraryFunctionDescriptor alloc] init];
  function_descriptor.library = library;
  function_descriptor.name = source_function.name;
  MTL4BinaryFunctionDescriptor *descriptor =
      [[MTL4BinaryFunctionDescriptor alloc] init];
  descriptor.name = binary_name;
  descriptor.functionDescriptor = function_descriptor;
  const MTL4BinaryFunctionOptions options = pipeline_independent
      ? MTL4BinaryFunctionOptionPipelineIndependent
      : MTL4BinaryFunctionOptionNone;
  descriptor.options = options;
  MTL4FunctionDescriptor *stored_function = descriptor.functionDescriptor;
  if (![stored_function
          isKindOfClass:[MTL4LibraryFunctionDescriptor class]]) {
    *failure = @"Metal changed the Metal 4 binary function descriptor type";
    return nil;
  }
  MTL4LibraryFunctionDescriptor *stored_library_function =
      static_cast<MTL4LibraryFunctionDescriptor *>(stored_function);
  if (![descriptor.name isEqualToString:binary_name] ||
      descriptor.options != options ||
      stored_library_function.library != library ||
      ![stored_library_function.name isEqualToString:source_function.name]) {
    *failure = @"Metal changed checked binary-function descriptor properties";
    return nil;
  }
  *lookup_archives = [archive_array copy];
  return descriptor;
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

API_AVAILABLE(macos(26.0))
MTL4LibraryDescriptor *checked_compiler_library_descriptor(
    value raw_source, value raw_name,
    NSString *__autoreleasing *expected_name,
    NSString *__autoreleasing *failure) {
  NSString *source = string_from_ocaml(raw_source);
  if (source == nil || source.length == 0) {
    *failure = @"Metal compiler source is not valid nonempty UTF-8";
    return nil;
  }
  NSString *name = nil;
  if (Is_block(raw_name)) {
    name = string_from_ocaml(Field(raw_name, 0));
    if (name == nil || name.length == 0) {
      *failure = @"Metal compiler library name is not valid nonempty UTF-8";
      return nil;
    }
  }
  MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
  options.fastMathEnabled = NO;
  MTL4LibraryDescriptor *descriptor = [[MTL4LibraryDescriptor alloc] init];
  descriptor.source = source;
  descriptor.options = options;
  if (name != nil) {
    descriptor.name = name;
  }
  if (![descriptor.source isEqualToString:source] ||
      descriptor.options.fastMathEnabled ||
      ((name == nil) != (descriptor.name == nil)) ||
      (name != nil && ![descriptor.name isEqualToString:name])) {
    *failure =
        @"Metal changed checked compiler library descriptor properties";
    return nil;
  }
  *expected_name = name;
  return descriptor;
}

API_AVAILABLE(macos(26.0))
bool checked_compiler_library_result(id<MTLLibrary> library,
                                     id<MTL4Compiler> compiler,
                                     NSString *expected_name,
                                     NSString *__autoreleasing *failure) {
  if (library == nil) {
    *failure = @"Metal returned no compiled library";
    return false;
  }
  if (expected_name != nil) {
    library.label = expected_name;
  }
  if (library.device.registryID != compiler.device.registryID ||
      ((expected_name == nil) != (library.label == nil)) ||
      (expected_name != nil &&
       ![library.label isEqualToString:expected_name])) {
    *failure = @"Metal changed checked compiler library properties";
    return false;
  }
  return true;
}

API_AVAILABLE(macos(26.0))
id<MTLLibrary> checked_compiler_dynamic_library_source(
    value raw_library, id<MTL4Compiler> compiler,
    NSString *__autoreleasing *install_name,
    NSString *__autoreleasing *failure) {
  id<MTLLibrary> library =
      object_of_handle(raw_library, Handle_kind::Library);
  if (!compiler.device.supportsDynamicLibraries ||
      library.device.registryID != compiler.device.registryID ||
      library.type != MTLLibraryTypeDynamic || library.installName == nil ||
      library.installName.length == 0) {
    *failure =
        @"Metal 4 dynamic-library source is incompatible or lacks an install name";
    return nil;
  }
  *install_name = library.installName;
  return library;
}

API_AVAILABLE(macos(26.0))
bool checked_compiler_dynamic_library_result(
    id<MTLDynamicLibrary> library, id<MTL4Compiler> compiler,
    NSString *expected_label, NSString *expected_install_name,
    NSString *__autoreleasing *failure) {
  if (library == nil) {
    *failure = @"Metal returned no compiled dynamic library";
    return false;
  }
  library.label = expected_label;
  if (library.device.registryID != compiler.device.registryID ||
      library.installName == nil || library.installName.length == 0 ||
      (expected_install_name != nil &&
       ![library.installName isEqualToString:expected_install_name]) ||
      ((expected_label == nil) != (library.label == nil)) ||
      (expected_label != nil &&
       ![library.label isEqualToString:expected_label])) {
    *failure = @"Metal changed checked compiler dynamic-library properties";
    return false;
  }
  return true;
}

API_AVAILABLE(macos(26.0))
bool synchronize_placement_mapping(id<MTL4CommandQueue> queue,
                                   void (^update)(void),
                                   NSString **failure) {
  id<MTLDevice> device = queue.device;
  id<MTL4CommandAllocator> allocator = [device newCommandAllocator];
  id<MTL4CommandBuffer> command_buffer = [device newCommandBuffer];
  id<MTLSharedEvent> event = [device newSharedEvent];
  if (allocator == nil || command_buffer == nil || event == nil) {
    if (failure != nullptr) {
      *failure = @"Metal failed to allocate placement-mapping synchronization objects";
    }
    return false;
  }

  [command_buffer beginCommandBufferWithAllocator:allocator];
  id<MTL4ComputeCommandEncoder> encoder =
      [command_buffer computeCommandEncoder];
  if (encoder == nil) {
    [command_buffer endCommandBuffer];
    if (failure != nullptr) {
      *failure = @"Metal failed to create a placement-mapping barrier encoder";
    }
    return false;
  }
  [encoder barrierAfterQueueStages:MTLStageResourceState
                      beforeStages:MTLStageAll
                 visibilityOptions:MTL4VisibilityOptionResourceAlias];
  [encoder endEncoding];
  [command_buffer endCommandBuffer];
  update();
  const id<MTL4CommandBuffer> command_buffers[] = {command_buffer};
  [queue commit:command_buffers count:1];
  [queue signalEvent:event value:1];

  __block BOOL completed = NO;
  __block NSString *wait_failure = nil;
  caml_release_runtime_system();
  @try {
    completed =
        [event waitUntilSignaledValue:1
                           timeoutMS:std::numeric_limits<std::uint64_t>::max()];
  } @catch (NSException *exception) {
    wait_failure = [exception.reason copy];
  }
  caml_acquire_runtime_system();
  if (wait_failure != nil) {
    if (failure != nullptr) {
      *failure = wait_failure;
    }
    return false;
  }
  if (!completed) {
    if (failure != nullptr) {
      *failure = @"Metal placement-mapping synchronization timed out";
    }
    return false;
  }
  [allocator reset];
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

int buffer_sparse_tier_or_unavailable(id<MTLBuffer> buffer) {
  if (@available(macOS 26.0, *)) {
    @try {
      if ([buffer respondsToSelector:@selector(sparseBufferTier)]) {
        return static_cast<int>(buffer.sparseBufferTier);
      }
    } @catch (NSException *exception) {
      (void)exception;
    }
  }
  return -1;
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

MTLPurgeableState purgeable_state(int state) {
  switch (state) {
  case MTLPurgeableStateKeepCurrent:
  case MTLPurgeableStateNonVolatile:
  case MTLPurgeableStateVolatile:
  case MTLPurgeableStateEmpty:
    return static_cast<MTLPurgeableState>(state);
  default:
    caml_invalid_argument("invalid Metal purgeable state");
  }
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

NSUInteger texture_bytes_per_pixel(MTLPixelFormat format) {
  const Texture_format_layout layout = texture_format_layout(format);
  if (layout.block_width != 1 || layout.block_height != 1) {
    return 0;
  }
  return layout.bytes_per_block;
}

bool texture_supports_buffer_backing(MTLPixelFormat format) {
  switch (format) {
  case MTLPixelFormatGBGR422:
  case MTLPixelFormatBGRG422:
  case MTLPixelFormatDepth16Unorm:
  case MTLPixelFormatDepth32Float:
  case MTLPixelFormatStencil8:
  case MTLPixelFormatDepth24Unorm_Stencil8:
  case MTLPixelFormatDepth32Float_Stencil8:
  case MTLPixelFormatX32_Stencil8:
  case MTLPixelFormatX24_Stencil8:
    return false;
  default:
    const Texture_format_layout layout = texture_format_layout(format);
    return layout.block_width == 1 && layout.block_height == 1 &&
           layout.bytes_per_block != 0;
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

bool io_surface_plane_range(IOSurface *surface, intnat signed_plane,
                            std::int64_t signed_offset, intnat signed_length,
                            std::size_t *plane, std::size_t *offset,
                            std::size_t *length) {
  if (signed_plane < 0 || signed_offset < 0 || signed_length < 0) {
    return false;
  }
  IOSurfaceRef surface_ref = (__bridge IOSurfaceRef)surface;
  const std::size_t native_plane_count = IOSurfaceGetPlaneCount(surface_ref);
  const std::size_t usable_plane_count =
      native_plane_count == 0 ? 1 : native_plane_count;
  const auto selected_plane = static_cast<std::size_t>(signed_plane);
  if (selected_plane >= usable_plane_count) {
    return false;
  }
  const std::size_t bytes_per_row =
      IOSurfaceGetBytesPerRowOfPlane(surface_ref, selected_plane);
  const std::size_t height =
      IOSurfaceGetHeightOfPlane(surface_ref, selected_plane);
  if (bytes_per_row == 0 || height == 0 ||
      bytes_per_row > std::numeric_limits<std::size_t>::max() / height) {
    return false;
  }
  const std::size_t plane_size = bytes_per_row * height;
  const auto unsigned_offset = static_cast<std::uint64_t>(signed_offset);
  const auto unsigned_length = static_cast<std::uint64_t>(signed_length);
  if (unsigned_offset > std::numeric_limits<std::size_t>::max() ||
      unsigned_length > std::numeric_limits<std::size_t>::max()) {
    return false;
  }
  const auto checked_offset = static_cast<std::size_t>(unsigned_offset);
  const auto checked_length = static_cast<std::size_t>(unsigned_length);
  if (checked_offset > plane_size ||
      checked_length > plane_size - checked_offset) {
    return false;
  }
  *plane = selected_plane;
  *offset = checked_offset;
  *length = checked_length;
  return true;
}

} // namespace

static void invoke_ocaml_xpc_handler_with_runtime(
    value *callback_root, PrismelMetalXpcRequest *request) {
  CAMLparam0();
  CAMLlocal5(raw_request, operation, raw_handle, metadata, data);
  CAMLlocal1(callback_result);
  raw_request = allocate_handle(request, Handle_kind::Xpc_request);
  operation = caml_copy_string(request.operation.UTF8String);
  raw_handle = allocate_handle(request.resource,
                               xpc_resource_handle_kind(request.resourceKind));
  metadata = copy_data(request.metadata);
  data = copy_data(request.data);
  value arguments[5] = {raw_request, operation, raw_handle, metadata, data};
  callback_result = caml_callbackN_exn(*callback_root, 5, arguments);
  if (Is_exception_result(callback_result) && !request.finished) {
    (void)[request rejectWithMessage:[NSString
        stringWithFormat:@"%@ XPC OCaml handler raised an exception",
                         PrismelMetalXpcResourceName(request.resourceKind)]];
  }
  CAMLreturn0;
}

static void invoke_ocaml_xpc_handler(
    value *callback_root, PrismelMetalXpcRequest *request) {
  if (caml_c_thread_register() == 0) {
    (void)[request rejectWithMessage:[NSString
        stringWithFormat:@"%@ XPC could not register its callback thread",
                         PrismelMetalXpcResourceName(request.resourceKind)]];
    return;
  }
  caml_acquire_runtime_system();
  prismel_metal_xpc_main_executor = true;
  invoke_ocaml_xpc_handler_with_runtime(callback_root, request);
  prismel_metal_xpc_main_executor = false;
  caml_release_runtime_system();
  (void)caml_c_thread_unregister();
}

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

extern "C" CAMLprim value caml_prismel_metal_destroyed(value raw) {
  CAMLparam1(raw);
  bool destroyed = false;
  {
    std::lock_guard<std::mutex> lock(handle_mutex);
    destroyed = handle_of_value(raw)->object == nullptr;
  }
  CAMLreturn(Val_bool(destroyed));
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
      if (release_count == 0) {
        break;
      }
      pointer = release_queue[release_head];
      release_queue[release_head] = nullptr;
      release_head = (release_head + 1) % release_capacity;
      --release_count;
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
    pending = release_count;
  }
  CAMLreturn(Val_long(pending));
}

extern "C" CAMLprim value caml_prismel_metal_dropped_releases(value unit) {
  CAMLparam1(unit);
  CAMLreturn(Val_long(dropped_releases.load(std::memory_order_relaxed)));
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

extern "C" CAMLprim value
caml_prismel_metal_placement_mapping_operations(value unit) {
  CAMLparam1(unit);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(
      placement_mapping_operation_count.load(std::memory_order_relaxed))));
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

extern "C" CAMLprim value caml_prismel_metal_all_devices(value unit) {
  CAMLparam1(unit);
  CAMLlocal3(array, raw, result);
  @autoreleasepool {
    NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();
    if (devices == nil) {
      CAMLreturn(result_error_text("MTLCopyAllDevices returned nil"));
    }
    const NSUInteger count = devices.count;
    array = caml_alloc(static_cast<mlsize_t>(count), 0);
    for (NSUInteger index = 0; index < count; ++index) {
      raw = allocate_handle(devices[index], Handle_kind::Device);
      Store_field(array, static_cast<mlsize_t>(index), raw);
    }
    result = result_ok(array);
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_device_name(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
    result = caml_copy_string(device.name.UTF8String ?: "Unnamed Metal device");
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_device_registry_id(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(device.registryID)));
}

extern "C" CAMLprim value caml_prismel_metal_device_is_low_power(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.lowPower));
}

extern "C" CAMLprim value caml_prismel_metal_device_is_removable(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.removable));
}

extern "C" CAMLprim value caml_prismel_metal_device_is_headless(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.headless));
}

extern "C" CAMLprim value
caml_prismel_metal_device_has_unified_memory(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.hasUnifiedMemory));
}

extern "C" CAMLprim value
caml_prismel_metal_device_recommended_max_working_set_size(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(
      device.recommendedMaxWorkingSetSize)));
}

extern "C" CAMLprim value
caml_prismel_metal_device_current_allocated_size(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(caml_copy_int64(
      static_cast<std::int64_t>(device.currentAllocatedSize)));
}

extern "C" CAMLprim value
caml_prismel_metal_device_max_buffer_length(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(caml_copy_int64(
      static_cast<std::int64_t>(device.maxBufferLength)));
}

extern "C" CAMLprim value caml_prismel_metal_device_supports_family(
    value raw, value family) {
  CAMLparam2(raw, family);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  const auto family_value = static_cast<MTLGPUFamily>(Long_val(family));
  CAMLreturn(Val_bool([device supportsFamily:family_value]));
}

extern "C" CAMLprim value
caml_prismel_metal_device_minimum_texture_alignment(
    value raw, value raw_kind, value raw_format) {
  CAMLparam3(raw, raw_kind, raw_format);
  CAMLlocal2(result, copied_alignment);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
      const auto kind = static_cast<MTLTextureType>(Long_val(raw_kind));
      const auto format = static_cast<MTLPixelFormat>(Long_val(raw_format));
      if ((kind != MTLTextureType2D &&
           kind != MTLTextureTypeTextureBuffer) ||
          !texture_supports_buffer_backing(format)) {
        CAMLreturn(result_error_text(
            "texture alignment requires a 2D or texture-buffer ordinary color format"));
      }
      const NSUInteger alignment = kind == MTLTextureTypeTextureBuffer
          ? [device minimumTextureBufferAlignmentForPixelFormat:format]
          : [device minimumLinearTextureAlignmentForPixelFormat:format];
      if (alignment == 0 || alignment > static_cast<NSUInteger>(INT64_MAX)) {
        CAMLreturn(result_error_text(
            "Metal returned an invalid buffer-backed texture alignment"));
      }
      copied_alignment =
          caml_copy_int64(static_cast<std::int64_t>(alignment));
      result = result_ok(copied_alignment);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_raytracing(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.supportsRaytracing));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_raytracing_from_render(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  const bool supported =
      [device respondsToSelector:@selector(supportsRaytracingFromRender)] &&
      device.supportsRaytracingFromRender;
  CAMLreturn(Val_bool(supported));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_dynamic_libraries(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.supportsDynamicLibraries));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_function_pointers(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.supportsFunctionPointers));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_function_pointers_from_render(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  const bool supported =
      [device respondsToSelector:@selector(supportsFunctionPointersFromRender)] &&
      device.supportsFunctionPointersFromRender;
  CAMLreturn(Val_bool(supported));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_vertex_amplification_count(
    value raw, value raw_count) {
  CAMLparam2(raw, raw_count);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  const intnat count = Long_val(raw_count);
  if (count <= 0) {
    CAMLreturn(Val_false);
  }
  CAMLreturn(Val_bool([device supportsVertexAmplificationCount:
                                 static_cast<NSUInteger>(count)]));
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

extern "C" CAMLprim value caml_prismel_metal_buffer_placement_sparse_create(
    value raw_device, value raw_length, value raw_options,
    value raw_page_size) {
  CAMLparam4(raw_device, raw_length, raw_options, raw_page_size);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device =
          object_of_handle(raw_device, Handle_kind::Device);
      const std::int64_t signed_length = Int64_val(raw_length);
      const int page_size = Int_val(raw_page_size);
      if (signed_length <= 0) {
        CAMLreturn(result_error_text(
            "placement sparse buffer length must be positive"));
      }
      if (!device_supports_placement_sparse(device)) {
        CAMLreturn(result_error_text(
            "device does not support placement sparse resources"));
      }
      if (!valid_sparse_page_size(page_size)) {
        CAMLreturn(result_error_text(
            "placement sparse buffer page size is invalid"));
      }
      if (@available(macOS 26.0, *)) {
        id<MTLBuffer> buffer = [device
            newBufferWithLength:static_cast<NSUInteger>(signed_length)
                         options:resource_options(Int_val(raw_options))
         placementSparsePageSize:static_cast<MTLSparsePageSize>(page_size)];
        if (buffer == nil || buffer.heap != nil) {
          CAMLreturn(result_error_text(
              "Metal rejected or changed the placement sparse buffer"));
        }
        const int sparse_tier = buffer_sparse_tier_or_unavailable(buffer);
        if (sparse_tier != -1 && sparse_tier != MTLBufferSparseTier1) {
          CAMLreturn(result_error_text(
              "Metal returned a non-sparse buffer from the placement sparse "
              "constructor"));
        }
        raw = allocate_handle(buffer, Handle_kind::Buffer);
      } else {
        CAMLreturn(result_error_text(
            "placement sparse buffers require macOS 26"));
      }
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_buffer_sparse_tier(value raw) {
  CAMLparam1(raw);
  id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
  CAMLreturn(Val_int(buffer_sparse_tier_or_unavailable(buffer)));
}

extern "C" CAMLprim value caml_prismel_metal_buffer_create_copy(
    value raw_device, value source, value raw_source_offset, value raw_length,
    value raw_options) {
  CAMLparam5(raw_device, source, raw_source_offset, raw_length, raw_options);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    const intnat source_offset = Long_val(raw_source_offset);
    const intnat length = Long_val(raw_length);
    const intnat source_length =
        static_cast<intnat>(caml_string_length(source));
    if (source_offset < 0 || length <= 0 || source_offset > source_length ||
        length > source_length - source_offset) {
      CAMLreturn(result_error_text("buffer copy range is invalid"));
    }
    const void *bytes =
        reinterpret_cast<const std::uint8_t *>(Bytes_val(source)) +
        source_offset;
    id<MTLBuffer> buffer =
        [device newBufferWithBytes:bytes
                            length:static_cast<NSUInteger>(length)
                           options:resource_options(Int_val(raw_options))];
    if (buffer == nil) {
      CAMLreturn(result_error_text("Metal failed to copy the buffer bytes"));
    }
    raw = allocate_handle(buffer, Handle_kind::Buffer);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_external_memory_page_size(
    value unit) {
  CAMLparam1(unit);
  const long page_size = sysconf(_SC_PAGESIZE);
  if (page_size <= 0 || page_size > Max_long) {
    caml_failwith("could not determine the native VM page size");
  }
  CAMLreturn(Val_long(page_size));
}

extern "C" CAMLprim value caml_prismel_metal_external_memory_create(
    value raw_length) {
  CAMLparam1(raw_length);
  CAMLlocal1(raw);
  @autoreleasepool {
    const std::int64_t signed_length = Int64_val(raw_length);
    const long page_size = sysconf(_SC_PAGESIZE);
    if (signed_length <= 0 || page_size <= 0 ||
        signed_length % page_size != 0) {
      CAMLreturn(result_error_text(
          "external memory must be a positive whole number of VM pages"));
    }
    PrismelMetalExternalMemory *memory =
        [[PrismelMetalExternalMemory alloc]
            initWithLength:static_cast<NSUInteger>(signed_length)
                 alignment:static_cast<NSUInteger>(page_size)];
    if (memory == nil) {
      CAMLreturn(result_error_text("native external-memory allocation failed"));
    }
    if (memory.length != static_cast<NSUInteger>(signed_length) ||
        memory.alignment != static_cast<NSUInteger>(page_size) ||
        reinterpret_cast<std::uintptr_t>(memory.bytes) %
                static_cast<std::uintptr_t>(page_size) !=
            0) {
      CAMLreturn(result_error_text(
          "native external memory does not meet its checked page layout"));
    }
    raw = allocate_handle(memory, Handle_kind::External_memory);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_external_memory_info(value raw) {
  CAMLparam1(raw);
  CAMLlocal3(result, length, alignment);
  PrismelMetalExternalMemory *memory = external_memory_of_handle(raw);
  result = caml_alloc_tuple(2);
  length = caml_copy_int64(static_cast<std::int64_t>(memory.length));
  alignment = caml_copy_int64(static_cast<std::int64_t>(memory.alignment));
  Store_field(result, 0, length);
  Store_field(result, 1, alignment);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_external_memory_write(
    value raw, value raw_offset, value source, value raw_source_offset,
    value raw_length) {
  CAMLparam5(raw, raw_offset, source, raw_source_offset, raw_length);
  PrismelMetalExternalMemory *memory = external_memory_of_handle(raw);
  const std::int64_t signed_offset = Int64_val(raw_offset);
  const intnat source_offset = Long_val(raw_source_offset);
  const intnat length = Long_val(raw_length);
  if (signed_offset < 0 || source_offset < 0 || length < 0 ||
      source_offset > static_cast<intnat>(caml_string_length(source)) ||
      length > static_cast<intnat>(caml_string_length(source)) - source_offset ||
      static_cast<std::uint64_t>(signed_offset) > memory.length ||
      static_cast<std::uint64_t>(length) >
          memory.length - static_cast<std::uint64_t>(signed_offset)) {
    CAMLreturn(result_error_text("external-memory write range is invalid"));
  }
  std::memcpy(static_cast<std::uint8_t *>(memory.bytes) + signed_offset,
              reinterpret_cast<const std::uint8_t *>(Bytes_val(source)) +
                  source_offset,
              static_cast<std::size_t>(length));
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_external_memory_read(
    value raw, value raw_offset, value raw_length) {
  CAMLparam3(raw, raw_offset, raw_length);
  CAMLlocal2(contents, result);
  PrismelMetalExternalMemory *memory = external_memory_of_handle(raw);
  const std::int64_t signed_offset = Int64_val(raw_offset);
  const intnat length = Long_val(raw_length);
  if (signed_offset < 0 || length < 0 ||
      static_cast<std::uint64_t>(signed_offset) > memory.length ||
      static_cast<std::uint64_t>(length) >
          memory.length - static_cast<std::uint64_t>(signed_offset)) {
    CAMLreturn(result_error_text("external-memory read range is invalid"));
  }
  contents = caml_alloc_string(static_cast<mlsize_t>(length));
  std::memcpy(Bytes_val(contents),
              static_cast<std::uint8_t *>(memory.bytes) + signed_offset,
              static_cast<std::size_t>(length));
  result = result_ok(contents);
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_buffer_create_no_copy(
    value raw_device, value raw_memory, value raw_options) {
  CAMLparam3(raw_device, raw_memory, raw_options);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    PrismelMetalExternalMemory *memory =
        external_memory_of_handle(raw_memory);
    const MTLResourceOptions options = resource_options(Int_val(raw_options));
    const MTLStorageMode storage =
        static_cast<MTLStorageMode>((Int_val(raw_options) >> 4) & 0xf);
    if (storage == MTLStorageModePrivate) {
      CAMLreturn(result_error_text(
          "no-copy buffers cannot use private storage"));
    }
    PrismelMetalExternalMemory *owner = memory;
    void (^deallocator)(void *, NSUInteger) =
        ^(void *pointer, NSUInteger length) {
          if (pointer != owner.bytes || length != owner.length) {
            external_deallocation_mismatch_count.fetch_add(
                1, std::memory_order_relaxed);
          }
          external_deallocation_count.fetch_add(1,
                                                std::memory_order_relaxed);
        };
    id<MTLBuffer> buffer =
        [device newBufferWithBytesNoCopy:memory.bytes
                                  length:memory.length
                                 options:options
                             deallocator:deallocator];
    if (buffer == nil) {
      CAMLreturn(result_error_text(
          "Metal rejected the page-aligned no-copy buffer"));
    }
    if (buffer.length != memory.length || buffer.contents != memory.bytes) {
      CAMLreturn(result_error_text(
          "Metal changed the checked no-copy buffer layout"));
    }
    raw = allocate_handle(buffer, Handle_kind::Buffer);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_buffer_texture_create(
    value raw_buffer, value raw_descriptor, value raw_offset,
    value raw_bytes_per_row, value raw_label) {
  CAMLparam5(raw_buffer, raw_descriptor, raw_offset, raw_bytes_per_row,
             raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLBuffer> buffer = object_of_handle(raw_buffer, Handle_kind::Buffer);
      MTLTextureDescriptor *descriptor = texture_descriptor(raw_descriptor);
      const std::int64_t signed_offset = Int64_val(raw_offset);
      const intnat signed_bytes_per_row = Long_val(raw_bytes_per_row);
      if (signed_offset < 0 || signed_bytes_per_row <= 0 ||
          (descriptor.textureType != MTLTextureType2D &&
           descriptor.textureType != MTLTextureTypeTextureBuffer) ||
          descriptor.depth != 1 || descriptor.arrayLength != 1 ||
          descriptor.mipmapLevelCount != 1 || descriptor.sampleCount != 1 ||
          !texture_supports_buffer_backing(descriptor.pixelFormat) ||
          descriptor.storageMode != buffer.storageMode ||
          descriptor.cpuCacheMode != buffer.cpuCacheMode ||
          descriptor.hazardTrackingMode != buffer.hazardTrackingMode) {
        CAMLreturn(result_error_text(
            "buffer-backed texture descriptor is invalid or does not match its buffer"));
      }
      id<MTLDevice> device = buffer.device;
      if ((descriptor.usage & MTLTextureUsageRenderTarget) != 0 &&
          ![device supportsFamily:MTLGPUFamilyApple1]) {
        CAMLreturn(result_error_text(
            "linear render-target textures require Apple GPU family 1 support"));
      }
      const NSUInteger alignment =
          descriptor.textureType == MTLTextureTypeTextureBuffer
              ? [device minimumTextureBufferAlignmentForPixelFormat:
                            descriptor.pixelFormat]
              : [device minimumLinearTextureAlignmentForPixelFormat:
                            descriptor.pixelFormat];
      const NSUInteger offset = static_cast<NSUInteger>(signed_offset);
      const NSUInteger bytes_per_row =
          static_cast<NSUInteger>(signed_bytes_per_row);
      const NSUInteger bytes_per_pixel =
          texture_bytes_per_pixel(descriptor.pixelFormat);
      if (alignment == 0 || offset % alignment != 0 ||
          bytes_per_row % alignment != 0 || bytes_per_pixel == 0 ||
          descriptor.width > NSUIntegerMax / bytes_per_pixel ||
          bytes_per_row < descriptor.width * bytes_per_pixel ||
          descriptor.height > NSUIntegerMax / bytes_per_row) {
        CAMLreturn(result_error_text(
            "buffer-backed texture alignment or row cardinality is invalid"));
      }
      const NSUInteger required = bytes_per_row * descriptor.height;
      if (offset > buffer.length || required > buffer.length - offset) {
        CAMLreturn(result_error_text(
            "buffer-backed texture storage exceeds the buffer"));
      }
      NSString *label = nil;
      if (Is_block(raw_label)) {
        label = string_from_ocaml(Field(raw_label, 0));
        if (label == nil) {
          CAMLreturn(result_error_text("texture label is not valid UTF-8"));
        }
      }
      id<MTLTexture> texture =
          [buffer newTextureWithDescriptor:descriptor
                                    offset:offset
                               bytesPerRow:bytes_per_row];
      if (texture == nil) {
        CAMLreturn(result_error_text(
            "Metal rejected the buffer-backed texture"));
      }
      if (texture.buffer != buffer || texture.bufferOffset != offset ||
          texture.bufferBytesPerRow != bytes_per_row) {
        CAMLreturn(result_error_text(
            "Metal changed the checked buffer-backed texture layout"));
      }
      if (label != nil) {
        texture.label = label;
      }
      raw = allocate_handle(texture, Handle_kind::Texture);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
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

extern "C" CAMLprim value caml_prismel_metal_buffer_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLBuffer> buffer = object_of_handle(raw, Handle_kind::Buffer);
    result = copy_optional_string(buffer.label);
  }
  CAMLreturn(result);
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

extern "C" CAMLprim value caml_prismel_metal_resource_set_purgeable_state(
    value raw, value raw_state) {
  CAMLparam2(raw, raw_state);
  @autoreleasepool {
    @try {
      id<MTLResource> resource = resource_of_handle(raw);
      const MTLPurgeableState previous =
          [resource setPurgeableState:purgeable_state(Int_val(raw_state))];
      CAMLreturn(result_ok(Val_int(static_cast<int>(previous))));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
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

extern "C" CAMLprim value
caml_prismel_metal_device_supports_texture_sample_count(value raw,
                                                         value raw_count) {
  CAMLparam2(raw, raw_count);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  const intnat count = Long_val(raw_count);
  if (count <= 0) {
    CAMLreturn(Val_false);
  }
  CAMLreturn(Val_bool(
      [device supportsTextureSampleCount:static_cast<NSUInteger>(count)]));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_depth24_stencil8(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.depth24Stencil8PixelFormatSupported));
}

extern "C" CAMLprim value
caml_prismel_metal_device_supports_bc_texture_compression(value raw) {
  CAMLparam1(raw);
  id<MTLDevice> device = object_of_handle(raw, Handle_kind::Device);
  CAMLreturn(Val_bool(device.supportsBCTextureCompression));
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

extern "C" CAMLprim value caml_prismel_metal_heap_set_label(
    value raw, value raw_label) {
  CAMLparam2(raw, raw_label);
  @autoreleasepool {
    id<MTLHeap> heap = object_of_handle(raw, Handle_kind::Heap);
    NSString *label = string_from_ocaml(raw_label);
    if (label == nil) {
      CAMLreturn(result_error_text("heap label is not valid UTF-8"));
    }
    heap.label = label;
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_heap_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLHeap> heap = object_of_handle(raw, Handle_kind::Heap);
    result = copy_optional_string(heap.label);
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_heap_set_purgeable_state(
    value raw, value raw_state) {
  CAMLparam2(raw, raw_state);
  @autoreleasepool {
    @try {
      id<MTLHeap> heap = object_of_handle(raw, Handle_kind::Heap);
      const MTLPurgeableState previous =
          [heap setPurgeableState:purgeable_state(Int_val(raw_state))];
      CAMLreturn(result_ok(Val_int(static_cast<int>(previous))));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
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

extern "C" CAMLprim value caml_prismel_metal_residency_set_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal2(label, result);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw, Handle_kind::Residency_set);
        label = copy_optional_string(residency_set.label);
        result = result_ok(label);
        CAMLreturn(result);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_residency_set_allocated_size(value raw) {
  CAMLparam1(raw);
  CAMLlocal2(size, result);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw, Handle_kind::Residency_set);
        const std::uint64_t allocated_size = residency_set.allocatedSize;
        if (allocated_size > static_cast<std::uint64_t>(INT64_MAX)) {
          CAMLreturn(result_error_text(
              "residency-set allocated size exceeds OCaml int64"));
        }
        size = caml_copy_int64(static_cast<std::int64_t>(allocated_size));
        result = result_ok(size);
        CAMLreturn(result);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_allocation_allocated_size(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal2(size, result);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        const std::uint64_t allocated_size =
            allocation_of_handle(raw).allocatedSize;
        if (allocated_size > static_cast<std::uint64_t>(INT64_MAX)) {
          CAMLreturn(result_error_text(
              "allocation size exceeds OCaml int64"));
        }
        size = caml_copy_int64(static_cast<std::int64_t>(allocated_size));
        result = result_ok(size);
        CAMLreturn(result);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("allocation size requires macOS 15"));
  }
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

extern "C" CAMLprim value
caml_prismel_metal_residency_set_remove_all(value raw) {
  CAMLparam1(raw);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw, Handle_kind::Residency_set);
        [residency_set removeAllAllocations];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_residency_set_contains(
    value raw_set, value raw_allocation) {
  CAMLparam2(raw_set, raw_allocation);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw_set, Handle_kind::Residency_set);
        const bool contains =
            [residency_set containsAllocation:allocation_of_handle(raw_allocation)];
        CAMLreturn(result_ok(Val_bool(contains)));
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_residency_set_commit(value raw) {
  CAMLparam1(raw);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw, Handle_kind::Residency_set);
        [residency_set commit];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_residency_set_request(value raw) {
  CAMLparam1(raw);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw, Handle_kind::Residency_set);
        [residency_set requestResidency];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_residency_set_end(value raw) {
  CAMLparam1(raw);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLResidencySet> residency_set =
            object_of_handle(raw, Handle_kind::Residency_set);
        [residency_set endResidency];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_io_surface_create(
    value raw_planar, value raw_layout, value raw_label) {
  CAMLparam3(raw_planar, raw_layout, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      const bool planar = Bool_val(raw_planar);
      const mlsize_t item_count = Wosize_val(raw_layout);
      if (item_count == 0 || item_count % 3 != 0 ||
          (!planar && item_count != 3)) {
        CAMLreturn(result_error_text("invalid IOSurface plane layout"));
      }
      NSString *label = nil;
      if (Is_block(raw_label)) {
        label = string_from_ocaml(Field(raw_label, 0));
        if (label == nil) {
          CAMLreturn(result_error_text("IOSurface label is not valid UTF-8"));
        }
      }
      NSMutableArray<NSDictionary<IOSurfacePropertyKey, id> *> *plane_info =
          [[NSMutableArray alloc] initWithCapacity:item_count / 3];
      for (mlsize_t index = 0; index < item_count; index += 3) {
        const intnat width = Long_val(Field(raw_layout, index));
        const intnat height = Long_val(Field(raw_layout, index + 1));
        const intnat bytes_per_element = Long_val(Field(raw_layout, index + 2));
        if (width <= 0 || height <= 0 || bytes_per_element <= 0) {
          CAMLreturn(result_error_text(
              "IOSurface plane dimensions must be positive"));
        }
        [plane_info addObject:@{
          IOSurfacePropertyKeyPlaneWidth : @(width),
          IOSurfacePropertyKeyPlaneHeight : @(height),
          IOSurfacePropertyKeyPlaneBytesPerElement : @(bytes_per_element),
        }];
      }
      NSMutableDictionary<IOSurfacePropertyKey, id> *properties =
          [[NSMutableDictionary alloc] init];
      NSDictionary<IOSurfacePropertyKey, id> *first = plane_info[0];
      properties[IOSurfacePropertyKeyWidth] =
          first[IOSurfacePropertyKeyPlaneWidth];
      properties[IOSurfacePropertyKeyHeight] =
          first[IOSurfacePropertyKeyPlaneHeight];
      if (planar) {
        properties[IOSurfacePropertyKeyPlaneInfo] = plane_info;
      } else {
        properties[IOSurfacePropertyKeyBytesPerElement] =
            first[IOSurfacePropertyKeyPlaneBytesPerElement];
      }
      if (label != nil) {
        properties[IOSurfacePropertyKeyName] = label;
      }
      IOSurface *surface =
          [[IOSurface alloc] initWithProperties:properties];
      if (surface == nil) {
        CAMLreturn(result_error_text("IOSurface rejected the checked layout"));
      }
      raw = allocate_handle(surface, Handle_kind::Io_surface);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_io_surface_info(value raw) {
  CAMLparam1(raw);
  CAMLlocal5(result, surface_id, allocation_size, layout, item);
  @autoreleasepool {
    IOSurface *surface = io_surface_of_handle(raw);
    IOSurfaceRef surface_ref = (__bridge IOSurfaceRef)surface;
    const std::size_t native_plane_count = IOSurfaceGetPlaneCount(surface_ref);
    const std::size_t plane_count =
        native_plane_count == 0 ? 1 : native_plane_count;
    if (plane_count > static_cast<std::size_t>(Max_long) / 4) {
      caml_failwith("IOSurface plane count exceeds OCaml array limits");
    }
    layout = caml_alloc(static_cast<mlsize_t>(plane_count * 4), 0);
    for (std::size_t index = 0; index < plane_count; ++index) {
      const std::array<std::size_t, 4> values = {
          IOSurfaceGetWidthOfPlane(surface_ref, index),
          IOSurfaceGetHeightOfPlane(surface_ref, index),
          IOSurfaceGetBytesPerElementOfPlane(surface_ref, index),
          IOSurfaceGetBytesPerRowOfPlane(surface_ref, index),
      };
      for (std::size_t property = 0; property < values.size(); ++property) {
        if (values[property] > static_cast<std::size_t>(Max_long)) {
          caml_failwith("IOSurface layout exceeds OCaml integer limits");
        }
        Store_field(layout, static_cast<mlsize_t>(index * 4 + property),
                    Val_long(values[property]));
      }
    }
    surface_id = caml_copy_int64(
        static_cast<std::int64_t>(IOSurfaceGetID(surface_ref)));
    allocation_size = caml_copy_int64(
        static_cast<std::int64_t>(IOSurfaceGetAllocSize(surface_ref)));
    result = caml_alloc_tuple(4);
    Store_field(result, 0, surface_id);
    Store_field(result, 1, allocation_size);
    Store_field(result, 2, Val_bool(native_plane_count != 0));
    Store_field(result, 3, layout);
    item = result;
  }
  CAMLreturn(item);
}

extern "C" CAMLprim value caml_prismel_metal_io_surface_write(
    value raw_surface, value raw_plane, value raw_offset, value raw_bytes,
    value raw_source_offset) {
  CAMLparam5(raw_surface, raw_plane, raw_offset, raw_bytes, raw_source_offset);
  @autoreleasepool {
    IOSurface *surface = io_surface_of_handle(raw_surface);
    const intnat source_offset = Long_val(raw_source_offset);
    const intnat source_size = caml_string_length(raw_bytes);
    if (source_offset < 0 || source_offset > source_size) {
      CAMLreturn(result_error_text("IOSurface source range is invalid"));
    }
    std::size_t plane = 0;
    std::size_t offset = 0;
    std::size_t length = 0;
    if (!io_surface_plane_range(surface, Long_val(raw_plane),
                                Int64_val(raw_offset),
                                source_size - source_offset, &plane, &offset,
                                &length)) {
      CAMLreturn(result_error_text("IOSurface write range is invalid"));
    }
    IOSurfaceRef surface_ref = (__bridge IOSurfaceRef)surface;
    const kern_return_t lock_status = IOSurfaceLock(surface_ref, 0, nullptr);
    if (lock_status != kIOSurfaceSuccess) {
      CAMLreturn(result_error([NSString stringWithFormat:
          @"IOSurface write lock failed (%d)", lock_status]));
    }
    void *base = IOSurfaceGetBaseAddressOfPlane(surface_ref, plane);
    if (base == nullptr) {
      (void)IOSurfaceUnlock(surface_ref, 0, nullptr);
      CAMLreturn(result_error_text("IOSurface plane has no base address"));
    }
    std::memcpy(static_cast<std::uint8_t *>(base) + offset,
                Bytes_val(raw_bytes) + source_offset, length);
    const kern_return_t unlock_status = IOSurfaceUnlock(surface_ref, 0, nullptr);
    if (unlock_status != kIOSurfaceSuccess) {
      CAMLreturn(result_error([NSString stringWithFormat:
          @"IOSurface write unlock failed (%d)", unlock_status]));
    }
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_io_surface_read(
    value raw_surface, value raw_plane, value raw_offset, value raw_length) {
  CAMLparam4(raw_surface, raw_plane, raw_offset, raw_length);
  CAMLlocal2(bytes, result);
  @autoreleasepool {
    IOSurface *surface = io_surface_of_handle(raw_surface);
    std::size_t plane = 0;
    std::size_t offset = 0;
    std::size_t length = 0;
    if (!io_surface_plane_range(surface, Long_val(raw_plane),
                                Int64_val(raw_offset), Long_val(raw_length),
                                &plane, &offset, &length)) {
      CAMLreturn(result_error_text("IOSurface read range is invalid"));
    }
    bytes = caml_alloc_string(static_cast<mlsize_t>(length));
    IOSurfaceRef surface_ref = (__bridge IOSurfaceRef)surface;
    const kern_return_t lock_status =
        IOSurfaceLock(surface_ref, kIOSurfaceLockReadOnly, nullptr);
    if (lock_status != kIOSurfaceSuccess) {
      CAMLreturn(result_error([NSString stringWithFormat:
          @"IOSurface read lock failed (%d)", lock_status]));
    }
    void *base = IOSurfaceGetBaseAddressOfPlane(surface_ref, plane);
    if (base == nullptr) {
      (void)IOSurfaceUnlock(surface_ref, kIOSurfaceLockReadOnly, nullptr);
      CAMLreturn(result_error_text("IOSurface plane has no base address"));
    }
    std::memcpy(Bytes_val(bytes),
                static_cast<std::uint8_t *>(base) + offset, length);
    const kern_return_t unlock_status =
        IOSurfaceUnlock(surface_ref, kIOSurfaceLockReadOnly, nullptr);
    if (unlock_status != kIOSurfaceSuccess) {
      CAMLreturn(result_error([NSString stringWithFormat:
          @"IOSurface read unlock failed (%d)", unlock_status]));
    }
    result = result_ok(bytes);
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_texture_io_surface_create(
    value raw_device, value raw_surface, value raw_plane,
    value raw_descriptor, value raw_label) {
  CAMLparam5(raw_device, raw_surface, raw_plane, raw_descriptor, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      IOSurface *surface = io_surface_of_handle(raw_surface);
      const intnat signed_plane = Long_val(raw_plane);
      IOSurfaceRef surface_ref = (__bridge IOSurfaceRef)surface;
      const std::size_t native_plane_count = IOSurfaceGetPlaneCount(surface_ref);
      const std::size_t plane_count =
          native_plane_count == 0 ? 1 : native_plane_count;
      if (signed_plane < 0 ||
          static_cast<std::size_t>(signed_plane) >= plane_count) {
        CAMLreturn(result_error_text("IOSurface plane index is out of range"));
      }
      const auto plane = static_cast<std::size_t>(signed_plane);
      MTLTextureDescriptor *descriptor = texture_descriptor(raw_descriptor);
      if (descriptor.textureType != MTLTextureType2D ||
          !texture_supports_buffer_backing(descriptor.pixelFormat) ||
          descriptor.depth != 1 || descriptor.arrayLength != 1 ||
          descriptor.mipmapLevelCount != 1 || descriptor.sampleCount != 1 ||
          descriptor.storageMode != MTLStorageModeShared ||
          descriptor.cpuCacheMode != MTLCPUCacheModeDefaultCache ||
          descriptor.width != IOSurfaceGetWidthOfPlane(surface_ref, plane) ||
          descriptor.height != IOSurfaceGetHeightOfPlane(surface_ref, plane) ||
          texture_bytes_per_pixel(descriptor.pixelFormat) !=
              IOSurfaceGetBytesPerElementOfPlane(surface_ref, plane)) {
        CAMLreturn(result_error_text(
            "texture descriptor does not match the IOSurface plane"));
      }
      NSString *label = nil;
      if (Is_block(raw_label)) {
        label = string_from_ocaml(Field(raw_label, 0));
        if (label == nil) {
          CAMLreturn(result_error_text("texture label is not valid UTF-8"));
        }
      }
      id<MTLTexture> texture =
          [device newTextureWithDescriptor:descriptor
                                 iosurface:surface_ref
                                     plane:plane];
      IOSurfaceRef actual_surface = texture.iosurface;
      if (texture == nil || actual_surface == nil ||
          IOSurfaceGetID(actual_surface) != IOSurfaceGetID(surface_ref) ||
          texture.iosurfacePlane != plane) {
        CAMLreturn(result_error_text(
            "Metal rejected or changed the IOSurface texture ancestry"));
      }
      if (label != nil) {
        texture.label = label;
      }
      raw = allocate_handle(texture, Handle_kind::Texture);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
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

extern "C" CAMLprim value
caml_prismel_metal_texture_placement_sparse_create(
    value raw_device, value raw_descriptor, value raw_page_size) {
  CAMLparam3(raw_device, raw_descriptor, raw_page_size);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device =
          object_of_handle(raw_device, Handle_kind::Device);
      const int page_size = Int_val(raw_page_size);
      if (!device_supports_placement_sparse(device)) {
        CAMLreturn(result_error_text(
            "device does not support placement sparse resources"));
      }
      if (!valid_sparse_page_size(page_size)) {
        CAMLreturn(result_error_text(
            "placement sparse texture page size is invalid"));
      }
      if (@available(macOS 26.0, *)) {
        MTLTextureDescriptor *descriptor = texture_descriptor(raw_descriptor);
        descriptor.placementSparsePageSize =
            static_cast<MTLSparsePageSize>(page_size);
        if (descriptor.placementSparsePageSize !=
            static_cast<MTLSparsePageSize>(page_size)) {
          CAMLreturn(result_error_text(
              "Metal changed the placement sparse texture page size"));
        }
        id<MTLTexture> texture =
            [device newTextureWithDescriptor:descriptor];
        if (texture == nil || texture.heap != nil ||
            !texture_is_sparse_resource(texture)) {
          CAMLreturn(result_error_text(
              "Metal rejected or changed the placement sparse texture"));
        }
        raw = allocate_handle(texture, Handle_kind::Texture);
      } else {
        CAMLreturn(result_error_text(
            "placement sparse textures require macOS 26"));
      }
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_texture_shared_create(
    value raw_device, value raw_descriptor, value raw_label) {
  CAMLparam3(raw_device, raw_descriptor, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      MTLTextureDescriptor *descriptor = texture_descriptor(raw_descriptor);
      if (descriptor.storageMode != MTLStorageModePrivate) {
        CAMLreturn(result_error_text(
            "shared textures require private storage"));
      }
      NSString *label = nil;
      if (Is_block(raw_label)) {
        label = string_from_ocaml(Field(raw_label, 0));
        if (label == nil) {
          CAMLreturn(result_error_text("texture label is not valid UTF-8"));
        }
      }
      id<MTLTexture> texture =
          [device newSharedTextureWithDescriptor:descriptor];
      if (texture == nil || !texture.shareable) {
        CAMLreturn(result_error_text(
            "Metal rejected the shareable texture descriptor"));
      }
      if (label != nil) {
        texture.label = label;
      }
      raw = allocate_handle(texture, Handle_kind::Texture);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
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

extern "C" CAMLprim value caml_prismel_metal_texture_sparse_tier(value raw) {
  CAMLparam1(raw);
  id<MTLTexture> texture = object_of_handle(raw, Handle_kind::Texture);
  CAMLreturn(Val_int(texture_sparse_tier_or_unavailable(texture)));
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

extern "C" CAMLprim value caml_prismel_metal_texture_shared_handle_create(
    value raw_texture) {
  CAMLparam1(raw_texture);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLTexture> texture =
          object_of_handle(raw_texture, Handle_kind::Texture);
      if (!texture.shareable) {
        CAMLreturn(result_error_text("texture is not shareable"));
      }
      MTLSharedTextureHandle *shared = [texture newSharedTextureHandle];
      if (shared == nil || shared.device.registryID != texture.device.registryID) {
        CAMLreturn(result_error_text(
            "Metal failed to create a matching shared texture handle"));
      }
      raw = allocate_handle(shared, Handle_kind::Shared_texture_handle);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_shared_texture_handle_info(
    value raw_handle) {
  CAMLparam1(raw_handle);
  CAMLlocal4(result, registry_id, label, info);
  @autoreleasepool {
    MTLSharedTextureHandle *shared =
        shared_texture_handle_of_handle(raw_handle);
    registry_id = caml_copy_int64(
        static_cast<std::int64_t>(shared.device.registryID));
    label = copy_optional_string(shared.label);
    info = caml_alloc_tuple(2);
    Store_field(info, 0, registry_id);
    Store_field(info, 1, label);
    result = info;
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_texture_shared_import(
    value raw_device, value raw_handle) {
  CAMLparam2(raw_device, raw_handle);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      MTLSharedTextureHandle *shared =
          shared_texture_handle_of_handle(raw_handle);
      if (shared.device.registryID != device.registryID) {
        CAMLreturn(result_error_text(
            "shared texture handle belongs to a different device"));
      }
      id<MTLTexture> texture = [device newSharedTextureWithHandle:shared];
      if (texture == nil || !texture.shareable ||
          texture.device.registryID != device.registryID) {
        CAMLreturn(result_error_text(
            "Metal rejected the shared texture handle"));
      }
      raw = allocate_handle(texture, Handle_kind::Texture);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_xpc_connect(
    value raw_resource_kind, value raw_service_name,
    value raw_max_payload_bytes) {
  CAMLparam3(raw_resource_kind, raw_service_name, raw_max_payload_bytes);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      NSString *service_name = string_from_ocaml(raw_service_name);
      const intnat max_payload_bytes = Long_val(raw_max_payload_bytes);
      PrismelMetalXpcResourceKind resource_kind{};
      if (!xpc_resource_kind_of_code(Long_val(raw_resource_kind),
                                     &resource_kind) ||
          service_name == nil || service_name.length == 0 ||
          [service_name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 255 ||
          max_payload_bytes <= 0 || max_payload_bytes > 64 * 1024 * 1024) {
        CAMLreturn(result_error_text(
            "Metal XPC connection configuration is invalid"));
      }
      PrismelMetalXpcConnection *connection =
          [[PrismelMetalXpcConnection alloc]
              initWithResourceKind:resource_kind
                       serviceName:service_name
                   maxPayloadBytes:static_cast<NSUInteger>(max_payload_bytes)];
      if (connection == nil || connection.connection == nil) {
        CAMLreturn(result_error_text(
            "failed to create the Metal XPC connection"));
      }
      raw = allocate_handle(connection, Handle_kind::Xpc_connection);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_xpc_call(
    value raw_connection, value raw_operation, value raw_handle,
    value raw_metadata, value raw_data, value raw_timeout_milliseconds) {
  CAMLparam5(raw_connection, raw_operation, raw_handle, raw_metadata, raw_data);
  CAMLxparam1(raw_timeout_milliseconds);
  CAMLlocal5(raw_reply, metadata, data, tuple, result);
  @autoreleasepool {
    @try {
      PrismelMetalXpcConnection *connection =
          xpc_connection_of_handle(raw_connection);
      id resource =
          xpc_resource_of_handle(raw_handle, connection.resourceKind);
      NSString *operation = string_from_ocaml(raw_operation);
      NSData *request_metadata = data_from_ocaml(raw_metadata);
      NSData *request_data = data_from_ocaml(raw_data);
      const intnat timeout_milliseconds = Long_val(raw_timeout_milliseconds);
      if (operation == nil || operation.length == 0 ||
          [operation lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 256 ||
          resource == nil || request_metadata.length == 0 ||
          request_metadata.length > 4096 ||
          request_data.length > connection.maxPayloadBytes ||
          timeout_milliseconds <= 0 || timeout_milliseconds > 300'000) {
        CAMLreturn(result_error_text(
            "Metal XPC call arguments are invalid"));
      }
      PrismelMetalXpcCallState *state =
          [[PrismelMetalXpcCallState alloc] init];
      id<PrismelMetalResourceXpc> proxy =
          [connection.connection
              remoteObjectProxyWithErrorHandler:^(NSError *error) {
                [state completeWithResource:nil
                                   metadata:nil
                                       data:nil
                                      error:error_description(
                                                error,
                                                @"Metal XPC call failed")];
              }];
      if (proxy == nil) {
        CAMLreturn(result_error_text(
            "Metal XPC could not create a remote proxy"));
      }
      [proxy exchangeOperation:operation
                      resource:resource
                      metadata:request_metadata
                          data:request_data
                     withReply:^(id reply_resource,
                                 NSData *reply_metadata,
                                 NSData *reply_data,
                                 NSString *error_message) {
                       [state completeWithResource:reply_resource
                                          metadata:reply_metadata
                                              data:reply_data
                                             error:error_message];
                     }];
      BOOL completed = NO;
      NSString *wait_failure = nil;
      caml_release_runtime_system();
      @try {
        completed = [state
            waitForMilliseconds:static_cast<NSUInteger>(timeout_milliseconds)];
      } @catch (NSException *exception) {
        wait_failure = [exception.reason copy];
      }
      caml_acquire_runtime_system();
      if (wait_failure != nil) {
        CAMLreturn(result_error(wait_failure));
      }
      if (!completed) {
        [connection shutdown];
        CAMLreturn(result_error_text("Metal XPC call timed out"));
      }
      if (state.errorMessage != nil) {
        CAMLreturn(result_error(state.errorMessage));
      }
      if (!PrismelMetalXpcResourceMatchesKind(
              state.resource, connection.resourceKind) ||
          state.metadata == nil || state.data == nil ||
          state.metadata.length == 0 || state.metadata.length > 4096 ||
          state.data.length > connection.maxPayloadBytes) {
        CAMLreturn(result_error_text(
            "Metal XPC service returned a malformed reply"));
      }
      raw_reply = allocate_handle(state.resource,
                                  xpc_resource_handle_kind(
                                      connection.resourceKind));
      metadata = copy_data(state.metadata);
      data = copy_data(state.data);
      tuple = caml_alloc_tuple(3);
      Store_field(tuple, 0, raw_reply);
      Store_field(tuple, 1, metadata);
      Store_field(tuple, 2, data);
      result = result_ok(tuple);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value
caml_prismel_metal_xpc_call_bytecode(value *argv, int argn) {
  (void)argn;
  return caml_prismel_metal_xpc_call(
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

extern "C" CAMLprim value
caml_prismel_metal_xpc_service_create(
    value raw_resource_kind, value raw_capacity,
    value raw_max_payload_bytes) {
  CAMLparam3(raw_resource_kind, raw_capacity, raw_max_payload_bytes);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      const intnat capacity = Long_val(raw_capacity);
      const intnat max_payload_bytes = Long_val(raw_max_payload_bytes);
      PrismelMetalXpcResourceKind resource_kind{};
      if (!xpc_resource_kind_of_code(Long_val(raw_resource_kind),
                                     &resource_kind) ||
          capacity <= 0 || capacity > 1024 || max_payload_bytes <= 0 ||
          max_payload_bytes > 64 * 1024 * 1024) {
        CAMLreturn(result_error_text(
            "Metal XPC service configuration is invalid"));
      }
      PrismelMetalXpcService *service =
          [[PrismelMetalXpcService alloc]
              initWithResourceKind:resource_kind
                          capacity:static_cast<NSUInteger>(capacity)
               maxPayloadBytes:static_cast<NSUInteger>(max_payload_bytes)];
      if (service == nil) {
        CAMLreturn(result_error_text(
            "failed to create the Metal XPC service"));
      }
      raw = allocate_handle(service, Handle_kind::Xpc_service);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_xpc_service_serve(
    value raw_service, value raw_callback) {
  CAMLparam2(raw_service, raw_callback);
  CAMLlocal1(result);
  @autoreleasepool {
    PrismelMetalXpcService *service =
        xpc_service_of_handle(raw_service);
    value *callback_root = new value(raw_callback);
    caml_register_generational_global_root(callback_root);
    NSString *failure = nil;
    BOOL runtime_released = NO;
    @try {
      [service setRequestHandler:^(PrismelMetalXpcRequest *request) {
        invoke_ocaml_xpc_handler(callback_root, request);
      }];
      caml_release_runtime_system();
      runtime_released = YES;
      [service run];
      caml_acquire_runtime_system();
      runtime_released = NO;
    } @catch (NSException *exception) {
      if (runtime_released) {
        caml_acquire_runtime_system();
        runtime_released = NO;
      }
      failure = exception.reason;
    }
    [service shutdown];
    [service setRequestHandler:nil];
    caml_remove_generational_global_root(callback_root);
    delete callback_root;
    result = failure == nil ? result_unit() : result_error(failure);
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value
caml_prismel_metal_xpc_request_reply(
    value raw_request, value raw_handle, value raw_metadata, value raw_data) {
  CAMLparam4(raw_request, raw_handle, raw_metadata, raw_data);
  @autoreleasepool {
    @try {
      PrismelMetalXpcRequest *request =
          xpc_request_of_handle(raw_request);
      id resource =
          xpc_resource_of_handle(raw_handle, request.resourceKind);
      NSData *metadata = data_from_ocaml(raw_metadata);
      NSData *data = data_from_ocaml(raw_data);
      if (metadata.length == 0 || metadata.length > 4096) {
        CAMLreturn(result_error_text(
            "Metal XPC reply metadata is malformed"));
      }
      if (![request replyWithResource:resource metadata:metadata data:data]) {
        CAMLreturn(result_error_text(
            "Metal XPC request was already completed"));
      }
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value
caml_prismel_metal_xpc_request_reject(
    value raw_request, value raw_message) {
  CAMLparam2(raw_request, raw_message);
  @autoreleasepool {
    @try {
      PrismelMetalXpcRequest *request =
          xpc_request_of_handle(raw_request);
      NSString *message = string_from_ocaml(raw_message);
      if (message == nil || message.length == 0 ||
          [message lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 4096) {
        CAMLreturn(result_error_text(
            "Metal XPC rejection message is invalid"));
      }
      if (![request rejectWithMessage:message]) {
        CAMLreturn(result_error_text(
            "Metal XPC request was already completed"));
      }
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_texture_set_label(
    value raw, value raw_label) {
  CAMLparam2(raw, raw_label);
  @autoreleasepool {
    id<MTLTexture> texture = object_of_handle(raw, Handle_kind::Texture);
    NSString *label = string_from_ocaml(raw_label);
    if (label == nil) {
      CAMLreturn(result_error_text("texture label is not valid UTF-8"));
    }
    texture.label = label;
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_texture_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLTexture> texture = object_of_handle(raw, Handle_kind::Texture);
    result = copy_optional_string(texture.label);
  }
  CAMLreturn(result);
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

extern "C" CAMLprim value caml_prismel_metal_sampler_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLSamplerState> sampler = object_of_handle(raw, Handle_kind::Sampler);
    result = copy_optional_string(sampler.label);
  }
  CAMLreturn(result);
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

extern "C" CAMLprim value caml_prismel_metal_depth_stencil_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLDepthStencilState> state =
        object_of_handle(raw, Handle_kind::Depth_stencil);
    result = copy_optional_string(state.label);
  }
  CAMLreturn(result);
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

extern "C" CAMLprim value caml_prismel_metal_indirect_command_buffer_size(value raw) {
  CAMLparam1(raw);
  id<MTLIndirectCommandBuffer> buffer =
      object_of_handle(raw, Handle_kind::Indirect_command_buffer);
  CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(buffer.size)));
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

extern "C" CAMLprim value caml_prismel_metal_indirect_compute_command(
    value raw, value raw_index) {
  CAMLparam2(raw, raw_index);
  CAMLlocal1(command_raw);
  @try {
    if (@available(macOS 11.0, *)) {
      NSUInteger index = 0;
      if (!nsuinteger_from_ocaml_int64(raw_index, &index))
        CAMLreturn(result_error_text("invalid indirect compute command index"));
      id<MTLIndirectCommandBuffer> buffer = object_of_handle(raw, Handle_kind::Indirect_command_buffer);
      id<MTLIndirectComputeCommand> command = [buffer indirectComputeCommandAtIndex:index];
      if (command == nil) CAMLreturn(result_error_text("Metal returned no indirect compute command"));
      command_raw = allocate_handle(command, Handle_kind::Indirect_compute_command);
    } else CAMLreturn(result_error_text("indirect compute commands require macOS 11 or newer"));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  CAMLreturn(result_ok(command_raw));
}

#define PRISMEL_ICB_COMMAND0(name, kind, selector) \
extern "C" CAMLprim value name(value raw) { CAMLparam1(raw); @try { \
  id command = object_of_handle(raw, kind); [command selector]; \
} @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
CAMLreturn(result_unit()); }

PRISMEL_ICB_COMMAND0(caml_prismel_metal_indirect_render_command_reset,
                     Handle_kind::Indirect_render_command, reset)
PRISMEL_ICB_COMMAND0(caml_prismel_metal_indirect_compute_command_reset,
                     Handle_kind::Indirect_compute_command, reset)

extern "C" CAMLprim value caml_prismel_metal_indirect_render_command_set_pipeline(value raw, value raw_pipeline) {
  CAMLparam2(raw, raw_pipeline); @try {
    id<MTLIndirectRenderCommand> command = object_of_handle(raw, Handle_kind::Indirect_render_command);
    id<MTLRenderPipelineState> pipeline = object_of_handle(raw_pipeline, Handle_kind::Render_pipeline);
    [command setRenderPipelineState:pipeline];
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_indirect_compute_command_set_pipeline(value raw, value raw_pipeline) {
  CAMLparam2(raw, raw_pipeline); @try {
    id<MTLIndirectComputeCommand> command = object_of_handle(raw, Handle_kind::Indirect_compute_command);
    id<MTLComputePipelineState> pipeline = object_of_handle(raw_pipeline, Handle_kind::Compute_pipeline);
    [command setComputePipelineState:pipeline];
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
extern "C" CAMLprim value caml_prismel_metal_indirect_compute_command_set_kernel_buffer(value a,value b,value c,value d) { return indirect_set_buffer(a,b,c,d,false,true); }

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

extern "C" CAMLprim value caml_prismel_metal_indirect_compute_command_dispatch_threads(value raw,value raw_threads,value raw_group) {
  CAMLparam3(raw,raw_threads,raw_group); @try {
    auto dimension=[](value tuple,int i)->NSUInteger { intnat v=Long_val(Field(tuple,i)); return v > 0 ? static_cast<NSUInteger>(v) : 0; };
    MTLSize threads=MTLSizeMake(dimension(raw_threads,0),dimension(raw_threads,1),dimension(raw_threads,2));
    MTLSize group=MTLSizeMake(dimension(raw_group,0),dimension(raw_group,1),dimension(raw_group,2));
    if (threads.width==0||threads.height==0||threads.depth==0||group.width==0||group.height==0||group.depth==0)
      CAMLreturn(result_error_text("indirect dispatch dimensions must be positive"));
    id<MTLIndirectComputeCommand> command=object_of_handle(raw,Handle_kind::Indirect_compute_command);
    [command concurrentDispatchThreads:threads threadsPerThreadgroup:group];
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_compute_encoder_execute_indirect_commands(
    value raw_encoder, value raw_icb, value raw_location, value raw_length) {
  CAMLparam4(raw_encoder, raw_icb, raw_location, raw_length);
  @try {
    NSUInteger location=0,length=0;
    if (!nsuinteger_from_ocaml_int64(raw_location,&location) ||
        !nsuinteger_from_ocaml_int64(raw_length,&length))
      CAMLreturn(result_error_text("invalid indirect command execution range"));
    id<MTLComputeCommandEncoder> encoder=object_of_handle(raw_encoder,Handle_kind::Compute_encoder);
    id<MTLIndirectCommandBuffer> buffer=object_of_handle(raw_icb,Handle_kind::Indirect_command_buffer);
    [encoder executeCommandsInBuffer:buffer withRange:NSMakeRange(location,length)];
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
  CAMLreturn(result_unit());
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

extern "C" CAMLprim value caml_prismel_metal_library_load_file(
    value raw_device, value raw_path, value raw_label) {
  CAMLparam3(raw_device, raw_path, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      NSString *path = string_from_ocaml(raw_path);
      if (!valid_absolute_path(path)) {
        CAMLreturn(result_error_text(
            "Metal library path must be a nonempty absolute UTF-8 path"));
      }
      NSURL *url = [NSURL fileURLWithPath:path];
      NSString *expected_label = nil;
      if (Is_block(raw_label)) {
        expected_label = string_from_ocaml(Field(raw_label, 0));
        if (expected_label == nil) {
          CAMLreturn(result_error_text("Metal library label is not valid UTF-8"));
        }
      }
      NSError *error = nil;
      id<MTLLibrary> library = [device newLibraryWithURL:url error:&error];
      if (library == nil) {
        CAMLreturn(result_error(labeled_error_description(
            expected_label ?: path.lastPathComponent, error,
            @"Metal library loading failed without NSError")));
      }
      library.label = expected_label;
      if (library.device.registryID != device.registryID ||
          ((expected_label == nil) != (library.label == nil)) ||
          (expected_label != nil &&
           ![library.label isEqualToString:expected_label])) {
        CAMLreturn(result_error_text(
            "Metal changed checked loaded-library properties"));
      }
      raw = allocate_handle(library, Handle_kind::Library);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_library_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLLibrary> library = object_of_handle(raw, Handle_kind::Library);
    result = copy_optional_string(library.label);
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_library_kind(value raw) {
  CAMLparam1(raw);
  id<MTLLibrary> library = object_of_handle(raw, Handle_kind::Library);
  CAMLreturn(Val_long(static_cast<intnat>(library.type)));
}

extern "C" CAMLprim value caml_prismel_metal_library_install_name(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLLibrary> library = object_of_handle(raw, Handle_kind::Library);
    result = copy_optional_string(library.installName);
  }
  CAMLreturn(result);
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

extern "C" CAMLprim value caml_prismel_metal_function_create_descriptor(
    value raw_library, value raw_name, value raw_specialized_name,
    value raw_constants, value raw_options) {
  CAMLparam5(raw_library, raw_name, raw_specialized_name, raw_constants,
             raw_options);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      if (@available(macOS 11.0, *)) {
        id<MTLLibrary> library =
            object_of_handle(raw_library, Handle_kind::Library);
        NSString *name = string_from_ocaml(raw_name);
        if (name == nil) {
          CAMLreturn(result_error_text(
              "Metal function descriptor name is not valid UTF-8"));
        }
        NSString *specialized_name = nil;
        if (Is_block(raw_specialized_name)) {
          specialized_name =
              string_from_ocaml(Field(raw_specialized_name, 0));
          if (specialized_name == nil) {
            CAMLreturn(result_error_text(
                "Metal specialized function name is not valid UTF-8"));
          }
        }
        const intnat options_code = Long_val(raw_options);
        if (options_code < 0 || options_code > 1) {
          CAMLreturn(result_error_text(
              "Metal function descriptor options are invalid"));
        }
        MTLFunctionConstantValues *constant_values =
            [[MTLFunctionConstantValues alloc] init];
        NSMutableSet<NSString *> *constant_names = [NSMutableSet set];
        const mlsize_t count = Wosize_val(raw_constants);
        for (mlsize_t index = 0; index < count; ++index) {
          value raw_constant = Field(raw_constants, index);
          NSString *constant_name =
              string_from_ocaml(Field(raw_constant, 0));
          if (constant_name == nil) {
            CAMLreturn(result_error_text(
                "Metal function-constant name is not valid UTF-8"));
          }
          if ([constant_names containsObject:constant_name]) {
            CAMLreturn(result_error_text(
                "Metal function-constant list contains a duplicate name"));
          }
          [constant_names addObject:constant_name];
          const intnat tag = Long_val(Field(raw_constant, 1));
          const std::int64_t integral = Int64_val(Field(raw_constant, 2));
          const double floating = Double_val(Field(raw_constant, 3));
#define PRISMEL_SET_FUNCTION_CONSTANT(type_, metal_type_, expression_)         \
  do {                                                                         \
    const type_ constant = expression_;                                        \
    [constant_values setConstantValue:&constant                                \
                                     type:metal_type_                           \
                                 withName:constant_name];                       \
  } while (false)
          switch (tag) {
          case 0:
            PRISMEL_SET_FUNCTION_CONSTANT(bool, MTLDataTypeBool,
                                          integral != 0);
            break;
          case 1:
            PRISMEL_SET_FUNCTION_CONSTANT(std::int8_t, MTLDataTypeChar,
                                          static_cast<std::int8_t>(integral));
            break;
          case 2:
            PRISMEL_SET_FUNCTION_CONSTANT(std::uint8_t, MTLDataTypeUChar,
                                          static_cast<std::uint8_t>(integral));
            break;
          case 3:
            PRISMEL_SET_FUNCTION_CONSTANT(std::int16_t, MTLDataTypeShort,
                                          static_cast<std::int16_t>(integral));
            break;
          case 4:
            PRISMEL_SET_FUNCTION_CONSTANT(std::uint16_t, MTLDataTypeUShort,
                                          static_cast<std::uint16_t>(integral));
            break;
          case 5:
            PRISMEL_SET_FUNCTION_CONSTANT(std::int32_t, MTLDataTypeInt,
                                          static_cast<std::int32_t>(integral));
            break;
          case 6:
            PRISMEL_SET_FUNCTION_CONSTANT(std::uint32_t, MTLDataTypeUInt,
                                          static_cast<std::uint32_t>(integral));
            break;
          case 7:
            PRISMEL_SET_FUNCTION_CONSTANT(std::int64_t, MTLDataTypeLong,
                                          integral);
            break;
          case 8:
            PRISMEL_SET_FUNCTION_CONSTANT(std::uint64_t, MTLDataTypeULong,
                                          static_cast<std::uint64_t>(integral));
            break;
          case 9:
            PRISMEL_SET_FUNCTION_CONSTANT(_Float16, MTLDataTypeHalf,
                                          static_cast<_Float16>(floating));
            break;
          case 10:
            PRISMEL_SET_FUNCTION_CONSTANT(float, MTLDataTypeFloat,
                                          static_cast<float>(floating));
            break;
          default:
#undef PRISMEL_SET_FUNCTION_CONSTANT
            CAMLreturn(result_error_text(
                "Metal function-constant type tag is invalid"));
          }
#undef PRISMEL_SET_FUNCTION_CONSTANT
        }
        MTLFunctionDescriptor *descriptor =
            [MTLFunctionDescriptor functionDescriptor];
        descriptor.name = name;
        descriptor.specializedName = specialized_name;
        descriptor.constantValues = count == 0 ? nil : constant_values;
        descriptor.options = options_code == 1
                                 ? MTLFunctionOptionCompileToBinary
                                 : MTLFunctionOptionNone;
        if (![descriptor.name isEqualToString:name] ||
            ((specialized_name == nil) !=
             (descriptor.specializedName == nil)) ||
            (specialized_name != nil &&
             ![descriptor.specializedName isEqualToString:specialized_name]) ||
            ((count == 0) != (descriptor.constantValues == nil)) ||
            descriptor.options !=
                (options_code == 1 ? MTLFunctionOptionCompileToBinary
                                   : MTLFunctionOptionNone)) {
          CAMLreturn(result_error_text(
              "Metal changed checked function descriptor properties"));
        }
        NSError *error = nil;
        id<MTLFunction> function =
            [library newFunctionWithDescriptor:descriptor error:&error];
        if (function == nil) {
          CAMLreturn(result_error(labeled_error_description(
              specialized_name ?: name, error,
              @"Metal function descriptor creation failed without NSError")));
        }
        NSString *expected_name = specialized_name ?: name;
        if (function.device.registryID != library.device.registryID ||
            ![function.name isEqualToString:expected_name]) {
          CAMLreturn(result_error_text(
              "Metal changed checked function descriptor result"));
        }
        raw = allocate_handle(function, Handle_kind::Function);
        CAMLreturn(result_ok(raw));
      }
      CAMLreturn(result_error_text(
          "Metal function descriptors require macOS 11"));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
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

extern "C" CAMLprim value caml_prismel_metal_function_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLFunction> function = object_of_handle(raw, Handle_kind::Function);
    result = copy_optional_string(function.label);
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_function_kind(value raw) {
  CAMLparam1(raw);
  id<MTLFunction> function = object_of_handle(raw, Handle_kind::Function);
  CAMLreturn(Val_long(static_cast<intnat>(function.functionType)));
}

extern "C" CAMLprim value caml_prismel_metal_function_constants(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLFunction> function = object_of_handle(raw, Handle_kind::Function);
    result = copy_function_constants(function);
  }
  CAMLreturn(result);
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

extern "C" CAMLprim value caml_prismel_metal_dynamic_library_label(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLDynamicLibrary> library =
        object_of_handle(raw, Handle_kind::Dynamic_library);
    result = copy_optional_string(library.label);
  }
  CAMLreturn(result);
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

extern "C" CAMLprim value caml_prismel_metal_binary_archive_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLBinaryArchive> archive =
        object_of_handle(raw, Handle_kind::Binary_archive);
    result = copy_optional_string(archive.label);
  }
  CAMLreturn(result);
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

extern "C" CAMLprim value caml_prismel_metal_pipeline_dataset_create(
    value raw_device, value raw_configuration) {
  CAMLparam2(raw_device, raw_configuration);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTLDevice> device =
            object_of_handle(raw_device, Handle_kind::Device);
        if (!device_supports_metal4_compiler(device)) {
          CAMLreturn(result_error_text(
              "Metal 4 pipeline datasets are unsupported by the device"));
        }
        const intnat configuration_code = Long_val(raw_configuration);
        if (configuration_code <= 0 || (configuration_code & ~3) != 0) {
          CAMLreturn(result_error_text(
              "Metal 4 pipeline-dataset configuration is invalid"));
        }
        const auto configuration =
            static_cast<MTL4PipelineDataSetSerializerConfiguration>(
                configuration_code);
        MTL4PipelineDataSetSerializerDescriptor *descriptor =
            [[MTL4PipelineDataSetSerializerDescriptor alloc] init];
        descriptor.configuration = configuration;
        if (descriptor.configuration != configuration) {
          CAMLreturn(result_error_text(
              "Metal changed checked pipeline-dataset descriptor properties"));
        }
        id<MTL4PipelineDataSetSerializer> serializer =
            [device newPipelineDataSetSerializerWithDescriptor:descriptor];
        if (serializer == nil) {
          CAMLreturn(result_error_text(
              "Metal failed to create a pipeline-dataset serializer"));
        }
        raw = allocate_handle(serializer, Handle_kind::Pipeline_dataset);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 pipeline datasets require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_pipeline_dataset_serialize_script(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(bytes);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4PipelineDataSetSerializer> serializer =
            object_of_handle(raw, Handle_kind::Pipeline_dataset);
        NSError *error = nil;
        NSData *data =
            [serializer serializeAsPipelinesScriptWithError:&error];
        if (data == nil) {
          CAMLreturn(result_error(error_description(
              error, @"Metal pipeline-script serialization failed without NSError")));
        }
        bytes = copy_data(data);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 pipeline scripts require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(bytes));
}

extern "C" CAMLprim value
caml_prismel_metal_pipeline_dataset_serialize_archive(value raw,
                                                       value raw_path) {
  CAMLparam2(raw, raw_path);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4PipelineDataSetSerializer> serializer =
            object_of_handle(raw, Handle_kind::Pipeline_dataset);
        NSString *path = string_from_ocaml(raw_path);
        if (!valid_absolute_path(path)) {
          CAMLreturn(result_error_text(
              "Metal pipeline-dataset archive path must be a nonempty absolute UTF-8 path"));
        }
        NSError *error = nil;
        if (![serializer
                serializeAsArchiveAndFlushToURL:[NSURL fileURLWithPath:path]
                                          error:&error]) {
          CAMLreturn(result_error(labeled_error_description(
              path.lastPathComponent, error,
              @"Metal pipeline-archive serialization failed without NSError")));
        }
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 pipeline archives require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(Val_unit));
}

extern "C" CAMLprim value caml_prismel_metal_pipeline_archive_load_file(
    value raw_device, value raw_path, value raw_label) {
  CAMLparam3(raw_device, raw_path, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTLDevice> device =
            object_of_handle(raw_device, Handle_kind::Device);
        if (!device_supports_metal4_compiler(device)) {
          CAMLreturn(result_error_text(
              "Metal 4 pipeline archives are unsupported by the device"));
        }
        NSString *path = string_from_ocaml(raw_path);
        if (!valid_absolute_path(path)) {
          CAMLreturn(result_error_text(
              "Metal pipeline-archive path must be a nonempty absolute UTF-8 path"));
        }
        NSString *expected_label = nil;
        if (Is_block(raw_label)) {
          expected_label = string_from_ocaml(Field(raw_label, 0));
          if (expected_label == nil) {
            CAMLreturn(result_error_text(
                "Metal pipeline-archive label is not valid UTF-8"));
          }
        }
        NSError *error = nil;
        id<MTL4Archive> archive =
            [device newArchiveWithURL:[NSURL fileURLWithPath:path]
                                error:&error];
        if (archive == nil) {
          CAMLreturn(result_error(labeled_error_description(
              expected_label ?: path.lastPathComponent, error,
              @"Metal pipeline-archive loading failed without NSError")));
        }
        if (expected_label != nil) {
          archive.label = expected_label;
        }
        if (((expected_label == nil) != (archive.label == nil)) ||
            (expected_label != nil &&
             ![archive.label isEqualToString:expected_label])) {
          CAMLreturn(result_error_text(
              "Metal changed checked pipeline-archive properties"));
        }
        raw = allocate_handle(archive, Handle_kind::Pipeline_archive);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 pipeline archives require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_pipeline_archive_label(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      id<MTL4Archive> archive =
          object_of_handle(raw, Handle_kind::Pipeline_archive);
      result = copy_optional_string(archive.label);
    } else {
      CAMLreturn(Val_none);
    }
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value
caml_prismel_metal_pipeline_archive_load_binary_function(
    value raw_archive, value raw_descriptor) {
  CAMLparam2(raw_archive, raw_descriptor);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Archive> archive =
            object_of_handle(raw_archive, Handle_kind::Pipeline_archive);
        id<MTLLibrary> library = object_of_handle(
            Field(raw_descriptor, 0), Handle_kind::Library);
        NSArray<id<MTL4Archive>> *lookup_archives = nil;
        NSString *validation_failure = nil;
        MTL4BinaryFunctionDescriptor *descriptor =
            checked_binary_function_descriptor(
                raw_descriptor, library.device, &lookup_archives,
                &validation_failure);
        if (descriptor == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        if (lookup_archives.count != 0) {
          CAMLreturn(result_error_text(
              "direct Metal 4 archive lookup cannot contain nested lookup archives"));
        }
        NSError *error = nil;
        id<MTL4BinaryFunction> function =
            [archive newBinaryFunctionWithDescriptor:descriptor error:&error];
        if (function == nil) {
          CAMLreturn(result_error(labeled_error_description(
              descriptor.name, error,
              @"Metal pipeline-archive binary-function lookup failed without NSError")));
        }
        raw = allocate_handle(function, Handle_kind::Binary_function);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 binary functions require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
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

extern "C" CAMLprim value caml_prismel_metal_compiler_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      id<MTL4Compiler> compiler =
          object_of_handle(raw, Handle_kind::Compiler);
      result = copy_optional_string(compiler.label);
    } else {
      CAMLreturn(Val_none);
    }
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_compiler_compile_library(
    value raw_compiler, value raw_source, value raw_name) {
  CAMLparam3(raw_compiler, raw_source, raw_name);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *expected_name = nil;
        NSString *validation_failure = nil;
        MTL4LibraryDescriptor *descriptor =
            checked_compiler_library_descriptor(
                raw_source, raw_name, &expected_name, &validation_failure);
        if (descriptor == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        NSError *error = nil;
        id<MTLLibrary> library =
            [compiler newLibraryWithDescriptor:descriptor error:&error];
        if (library == nil) {
          CAMLreturn(result_error(labeled_error_description(
              expected_name, error,
              @"Metal 4 library compilation failed without NSError")));
        }
        if (!checked_compiler_library_result(
                library, compiler, expected_name, &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        raw = allocate_handle(library, Handle_kind::Library);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 library compilation requires macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_compile_library_async(
    value raw_compiler, value raw_source, value raw_name) {
  CAMLparam3(raw_compiler, raw_source, raw_name);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *expected_name = nil;
        NSString *validation_failure = nil;
        MTL4LibraryDescriptor *descriptor =
            checked_compiler_library_descriptor(
                raw_source, raw_name, &expected_name, &validation_failure);
        if (descriptor == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        PrismelMetalCompilerTaskState *state =
            [[PrismelMetalCompilerTaskState alloc]
                initWithKind:PrismelMetalCompilerResultLibrary
                         label:expected_name
           reflectionRequested:NO];
        __weak PrismelMetalCompilerTaskState *weak_state = state;
        state.retainedInputs = descriptor;
        MTL4LibraryDescriptor *retained_descriptor = descriptor;
        id<MTL4CompilerTask> task =
            [compiler newLibraryWithDescriptor:descriptor
                             completionHandler:^(id<MTLLibrary> library,
                                                 NSError *error) {
                               (void)retained_descriptor;
                               PrismelMetalCompilerTaskState *strong_state =
                                   weak_state;
                               [strong_state finishWithObject:library
                                                        error:error];
                             }];
        if (task == nil) {
          CAMLreturn(result_error(labeled_error_description(
              expected_name, nil,
              @"Metal 4 asynchronous library task creation failed")));
        }
        state.task = task;
        if (state.identifier == 0 || task.compiler.device.registryID !=
                                         compiler.device.registryID) {
          CAMLreturn(result_error_text(
              "Metal changed checked asynchronous compiler task properties"));
        }
        raw = allocate_handle(state, Handle_kind::Compiler_task);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 compilation requires macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_task_id(value raw) {
  CAMLparam1(raw);
  std::int64_t identifier = 0;
  if (@available(macOS 26.0, *)) {
    PrismelMetalCompilerTaskState *state =
        object_of_handle(raw, Handle_kind::Compiler_task);
    identifier = static_cast<std::int64_t>(state.identifier);
  }
  CAMLreturn(caml_copy_int64(identifier));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_task_status(value raw) {
  CAMLparam1(raw);
  int result = 0;
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      PrismelMetalCompilerTaskState *state =
          object_of_handle(raw, Handle_kind::Compiler_task);
      result = static_cast<int>(state.task.status);
    }
  }
  CAMLreturn(Val_int(result));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_task_wait(value raw) {
  CAMLparam1(raw);
  if (@available(macOS 26.0, *)) {
    PrismelMetalCompilerTaskState *state =
        object_of_handle(raw, Handle_kind::Compiler_task);
    id<MTL4CompilerTask> task = state.task;
    caml_enter_blocking_section();
    @autoreleasepool {
      [task waitUntilCompleted];
    }
    caml_leave_blocking_section();
  }
  CAMLreturn(Val_unit);
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_task_take_library(value raw) {
  CAMLparam1(raw);
  CAMLlocal3(raw_library, completion, option);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetalCompilerTaskState *state =
            object_of_handle(raw, Handle_kind::Compiler_task);
        if (state.resultKind != PrismelMetalCompilerResultLibrary) {
          CAMLreturn(result_error_text(
              "compiler task does not contain a library result"));
        }
        id result_object = nil;
        NSError *result_error_value = nil;
        const PrismelMetalCompilerResultState result_state =
            [state takeObject:&result_object error:&result_error_value];
        if (result_state == PrismelMetalCompilerResultPending) {
          CAMLreturn(result_ok(Val_none));
        }
        if (result_state == PrismelMetalCompilerResultConsumed) {
          CAMLreturn(result_error_text(
              "compiler task completion was already consumed"));
        }
        if (result_state == PrismelMetalCompilerResultFailure) {
          completion = result_error(labeled_error_description(
              state.label, result_error_value,
              @"Metal 4 asynchronous library compilation failed without NSError"));
        } else {
          id<MTLLibrary> library = static_cast<id<MTLLibrary>>(result_object);
          NSString *validation_failure = nil;
          if (!checked_compiler_library_result(
                  library, state.task.compiler, state.label,
                  &validation_failure)) {
            completion = result_error(validation_failure);
          } else {
            raw_library = allocate_handle(library, Handle_kind::Library);
            completion = result_ok(raw_library);
          }
        }
        option = caml_alloc(1, 0);
        Store_field(option, 0, completion);
        CAMLreturn(result_ok(option));
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 compilation requires macOS 26 or newer"));
    }
  }
  CAMLreturn(result_error_text("unreachable compiler-task result"));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_create_dynamic_library(
    value raw_compiler, value raw_library, value raw_label) {
  CAMLparam3(raw_compiler, raw_library, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *expected_label = nil;
        if (Is_block(raw_label)) {
          expected_label = string_from_ocaml(Field(raw_label, 0));
          if (expected_label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 dynamic-library label is not valid UTF-8"));
          }
        }
        NSString *expected_install_name = nil;
        NSString *validation_failure = nil;
        id<MTLLibrary> source = checked_compiler_dynamic_library_source(
            raw_library, compiler, &expected_install_name,
            &validation_failure);
        if (source == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        NSError *error = nil;
        id<MTLDynamicLibrary> library =
            [compiler newDynamicLibrary:source error:&error];
        if (library == nil) {
          CAMLreturn(result_error(labeled_error_description(
              expected_label ?: expected_install_name, error,
              @"Metal 4 dynamic-library compilation failed without NSError")));
        }
        if (!checked_compiler_dynamic_library_result(
                library, compiler, expected_label, expected_install_name,
                &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        raw = allocate_handle(library, Handle_kind::Dynamic_library);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 dynamic libraries require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_load_dynamic_library(
    value raw_compiler, value raw_path, value raw_label) {
  CAMLparam3(raw_compiler, raw_path, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *path = string_from_ocaml(raw_path);
        if (!valid_absolute_path(path)) {
          CAMLreturn(result_error_text(
              "Metal 4 dynamic-library path must be a nonempty absolute UTF-8 path"));
        }
        NSString *expected_label = nil;
        if (Is_block(raw_label)) {
          expected_label = string_from_ocaml(Field(raw_label, 0));
          if (expected_label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 dynamic-library label is not valid UTF-8"));
          }
        }
        NSError *error = nil;
        id<MTLDynamicLibrary> library =
            [compiler newDynamicLibraryWithURL:[NSURL fileURLWithPath:path]
                                         error:&error];
        if (library == nil) {
          CAMLreturn(result_error(labeled_error_description(
              expected_label ?: path.lastPathComponent, error,
              @"Metal 4 dynamic-library loading failed without NSError")));
        }
        NSString *validation_failure = nil;
        if (!checked_compiler_dynamic_library_result(
                library, compiler, expected_label, nil,
                &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        raw = allocate_handle(library, Handle_kind::Dynamic_library);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 dynamic libraries require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_create_dynamic_library_async(
    value raw_compiler, value raw_library, value raw_label) {
  CAMLparam3(raw_compiler, raw_library, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *expected_label = nil;
        if (Is_block(raw_label)) {
          expected_label = string_from_ocaml(Field(raw_label, 0));
          if (expected_label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 dynamic-library label is not valid UTF-8"));
          }
        }
        NSString *expected_install_name = nil;
        NSString *validation_failure = nil;
        id<MTLLibrary> source = checked_compiler_dynamic_library_source(
            raw_library, compiler, &expected_install_name,
            &validation_failure);
        if (source == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        PrismelMetalCompilerTaskState *state =
            [[PrismelMetalCompilerTaskState alloc]
                initWithKind:PrismelMetalCompilerResultDynamicLibrary
                         label:expected_label
           reflectionRequested:NO];
        state.expectedInstallName = expected_install_name;
        state.diagnosticIdentity =
            expected_label ?: expected_install_name;
        state.retainedInputs = source;
        __weak PrismelMetalCompilerTaskState *weak_state = state;
        id<MTLLibrary> retained_source = source;
        id<MTL4CompilerTask> task =
            [compiler newDynamicLibrary:source
                      completionHandler:^(id<MTLDynamicLibrary> library,
                                          NSError *error) {
                        (void)retained_source;
                        PrismelMetalCompilerTaskState *strong_state = weak_state;
                        [strong_state finishWithObject:library error:error];
                      }];
        if (task == nil) {
          CAMLreturn(result_error(labeled_error_description(
              expected_label ?: expected_install_name, nil,
              @"Metal 4 asynchronous dynamic-library task creation failed")));
        }
        state.task = task;
        if (state.identifier == 0 || task.compiler.device.registryID !=
                                         compiler.device.registryID) {
          CAMLreturn(result_error_text(
              "Metal changed checked asynchronous compiler task properties"));
        }
        raw = allocate_handle(state, Handle_kind::Compiler_task);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 dynamic libraries require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_load_dynamic_library_async(
    value raw_compiler, value raw_path, value raw_label) {
  CAMLparam3(raw_compiler, raw_path, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *path = string_from_ocaml(raw_path);
        if (!valid_absolute_path(path)) {
          CAMLreturn(result_error_text(
              "Metal 4 dynamic-library path must be a nonempty absolute UTF-8 path"));
        }
        NSString *expected_label = nil;
        if (Is_block(raw_label)) {
          expected_label = string_from_ocaml(Field(raw_label, 0));
          if (expected_label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 dynamic-library label is not valid UTF-8"));
          }
        }
        NSURL *url = [NSURL fileURLWithPath:path];
        PrismelMetalCompilerTaskState *state =
            [[PrismelMetalCompilerTaskState alloc]
                initWithKind:PrismelMetalCompilerResultDynamicLibrary
                         label:expected_label
           reflectionRequested:NO];
        state.retainedInputs = url;
        state.diagnosticIdentity =
            expected_label ?: path.lastPathComponent;
        __weak PrismelMetalCompilerTaskState *weak_state = state;
        NSURL *retained_url = url;
        id<MTL4CompilerTask> task =
            [compiler newDynamicLibraryWithURL:url
                            completionHandler:^(id<MTLDynamicLibrary> library,
                                                NSError *error) {
                              (void)retained_url;
                              PrismelMetalCompilerTaskState *strong_state =
                                  weak_state;
                              [strong_state finishWithObject:library
                                                       error:error];
                            }];
        if (task == nil) {
          CAMLreturn(result_error(labeled_error_description(
              expected_label ?: path.lastPathComponent, nil,
              @"Metal 4 asynchronous dynamic-library load task creation failed")));
        }
        state.task = task;
        if (state.identifier == 0 || task.compiler.device.registryID !=
                                         compiler.device.registryID) {
          CAMLreturn(result_error_text(
              "Metal changed checked asynchronous compiler task properties"));
        }
        raw = allocate_handle(state, Handle_kind::Compiler_task);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 dynamic libraries require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_task_take_dynamic_library(value raw) {
  CAMLparam1(raw);
  CAMLlocal3(raw_library, completion, option);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetalCompilerTaskState *state =
            object_of_handle(raw, Handle_kind::Compiler_task);
        if (state.resultKind != PrismelMetalCompilerResultDynamicLibrary) {
          CAMLreturn(result_error_text(
              "compiler task does not contain a dynamic-library result"));
        }
        id result_object = nil;
        NSError *result_error_value = nil;
        const PrismelMetalCompilerResultState result_state =
            [state takeObject:&result_object error:&result_error_value];
        if (result_state == PrismelMetalCompilerResultPending) {
          CAMLreturn(result_ok(Val_none));
        }
        if (result_state == PrismelMetalCompilerResultConsumed) {
          CAMLreturn(result_error_text(
              "compiler task completion was already consumed"));
        }
        if (result_state == PrismelMetalCompilerResultFailure) {
          completion = result_error(labeled_error_description(
              state.diagnosticIdentity, result_error_value,
              @"Metal 4 asynchronous dynamic-library operation failed without NSError"));
        } else {
          id<MTLDynamicLibrary> library =
              static_cast<id<MTLDynamicLibrary>>(result_object);
          NSString *validation_failure = nil;
          if (!checked_compiler_dynamic_library_result(
                  library, state.task.compiler, state.label,
                  state.expectedInstallName, &validation_failure)) {
            completion = result_error(validation_failure);
          } else {
            raw_library =
                allocate_handle(library, Handle_kind::Dynamic_library);
            completion = result_ok(raw_library);
          }
        }
        option = caml_alloc(1, 0);
        Store_field(option, 0, completion);
        CAMLreturn(result_ok(option));
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 dynamic libraries require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_error_text("unreachable dynamic-library task result"));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_completion_drain(
    value raw_limit) {
  CAMLparam1(raw_limit);
  CAMLlocal2(array, identifier);
  const intnat requested = Long_val(raw_limit);
  const std::size_t limit = requested <= 0
      ? 0
      : std::min(static_cast<std::size_t>(requested),
                 kCompilerCompletionCapacity);
  std::vector<std::uint64_t> drained;
  {
    std::lock_guard<std::mutex> lock(compiler_completion_mutex);
    const std::size_t count = std::min(limit, compiler_completion_count);
    drained.reserve(count);
    for (std::size_t index = 0; index < count; ++index) {
      drained.push_back(compiler_completion_ids[compiler_completion_head]);
      compiler_completion_head =
          (compiler_completion_head + 1) % kCompilerCompletionCapacity;
      --compiler_completion_count;
    }
  }
  array = caml_alloc(drained.size(), 0);
  for (std::size_t index = 0; index < drained.size(); ++index) {
    identifier = caml_copy_int64(static_cast<std::int64_t>(drained[index]));
    Store_field(array, index, identifier);
  }
  CAMLreturn(array);
}

extern "C" CAMLprim value caml_prismel_metal_compiler_completion_dropped(
    value raw_unit) {
  CAMLparam1(raw_unit);
  (void)raw_unit;
  CAMLreturn(caml_copy_int64(
      static_cast<std::int64_t>(
          compiler_completion_dropped.load(std::memory_order_relaxed))));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_completion_pending(
    value raw_unit) {
  CAMLparam1(raw_unit);
  (void)raw_unit;
  std::size_t pending = 0;
  {
    std::lock_guard<std::mutex> lock(compiler_completion_mutex);
    pending = compiler_completion_count;
  }
  CAMLreturn(Val_int(pending));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_completion_capacity(
    value raw_unit) {
  CAMLparam1(raw_unit);
  (void)raw_unit;
  CAMLreturn(Val_int(kCompilerCompletionCapacity));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_create_binary_function(
    value raw_compiler, value raw_descriptor) {
  CAMLparam2(raw_compiler, raw_descriptor);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSArray<id<MTL4Archive>> *lookup_archives = nil;
        NSString *validation_failure = nil;
        MTL4BinaryFunctionDescriptor *descriptor =
            checked_binary_function_descriptor(
                raw_descriptor, compiler.device, &lookup_archives,
                &validation_failure);
        if (descriptor == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        MTL4CompilerTaskOptions *task_options =
            checked_compiler_task_options(lookup_archives,
                                          &validation_failure);
        if (lookup_archives.count != 0 && task_options == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        NSError *error = nil;
        id<MTL4BinaryFunction> function =
            [compiler newBinaryFunctionWithDescriptor:descriptor
                                  compilerTaskOptions:task_options
                                                error:&error];
        if (function == nil) {
          CAMLreturn(result_error(labeled_error_description(
              descriptor.name, error,
              @"Metal 4 binary-function compilation failed without NSError")));
        }
        raw = allocate_handle(function, Handle_kind::Binary_function);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 binary functions require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_create_binary_function_async(
    value raw_compiler, value raw_descriptor) {
  CAMLparam2(raw_compiler, raw_descriptor);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSArray<id<MTL4Archive>> *lookup_archives = nil;
        NSString *validation_failure = nil;
        MTL4BinaryFunctionDescriptor *descriptor =
            checked_binary_function_descriptor(
                raw_descriptor, compiler.device, &lookup_archives,
                &validation_failure);
        if (descriptor == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        MTL4CompilerTaskOptions *task_options =
            checked_compiler_task_options(lookup_archives,
                                          &validation_failure);
        if (lookup_archives.count != 0 && task_options == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        PrismelMetalCompilerTaskState *state =
            [[PrismelMetalCompilerTaskState alloc]
                initWithKind:PrismelMetalCompilerResultBinaryFunction
                         label:descriptor.name
           reflectionRequested:NO];
        __weak PrismelMetalCompilerTaskState *weak_state = state;
        state.retainedInputs =
            task_options == nil ? @[ descriptor ]
                                : @[ descriptor, task_options ];
        MTL4BinaryFunctionDescriptor *retained_descriptor = descriptor;
        MTL4CompilerTaskOptions *retained_task_options = task_options;
        id<MTL4CompilerTask> task =
            [compiler newBinaryFunctionWithDescriptor:descriptor
                                  compilerTaskOptions:task_options
                                    completionHandler:^(id<MTL4BinaryFunction> function,
                                                        NSError *error) {
                                      (void)retained_descriptor;
                                      (void)retained_task_options;
                                      PrismelMetalCompilerTaskState *strong_state =
                                          weak_state;
                                      [strong_state finishWithObject:function
                                                               error:error];
                                    }];
        if (task == nil) {
          CAMLreturn(result_error(labeled_error_description(
              descriptor.name, nil,
              @"Metal 4 asynchronous binary-function task creation failed")));
        }
        state.task = task;
        if (state.identifier == 0 || task.compiler.device.registryID !=
                                         compiler.device.registryID) {
          CAMLreturn(result_error_text(
              "Metal changed checked asynchronous compiler task properties"));
        }
        raw = allocate_handle(state, Handle_kind::Compiler_task);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 binary functions require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_task_take_binary_function(value raw) {
  CAMLparam1(raw);
  CAMLlocal3(raw_function, completion, option);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetalCompilerTaskState *state =
            object_of_handle(raw, Handle_kind::Compiler_task);
        if (state.resultKind != PrismelMetalCompilerResultBinaryFunction) {
          CAMLreturn(result_error_text(
              "compiler task does not contain a binary-function result"));
        }
        id result_object = nil;
        NSError *result_error_value = nil;
        const PrismelMetalCompilerResultState result_state =
            [state takeObject:&result_object error:&result_error_value];
        if (result_state == PrismelMetalCompilerResultPending) {
          CAMLreturn(result_ok(Val_none));
        }
        if (result_state == PrismelMetalCompilerResultConsumed) {
          CAMLreturn(result_error_text(
              "compiler task completion was already consumed"));
        }
        if (result_state == PrismelMetalCompilerResultFailure) {
          completion = result_error(labeled_error_description(
              state.label, result_error_value,
              @"Metal 4 asynchronous binary-function compilation failed without NSError"));
        } else {
          id<MTL4BinaryFunction> function =
              static_cast<id<MTL4BinaryFunction>>(result_object);
          if (function == nil) {
            completion = result_error_text(
                "Metal returned no asynchronous binary function");
          } else {
            raw_function =
                allocate_handle(function, Handle_kind::Binary_function);
            completion = result_ok(raw_function);
          }
        }
        option = caml_alloc(1, 0);
        Store_field(option, 0, completion);
        CAMLreturn(result_ok(option));
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 binary functions require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_error_text("unreachable binary compiler-task result"));
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

API_AVAILABLE(macos(26.0))
PrismelMetalCompilerTaskState *start_checked_render_pipeline_task(
    id<MTL4Compiler> compiler, PrismelMetalCheckedRenderRequest *request,
    NSString *__autoreleasing *failure) {
  PrismelMetalCompilerTaskState *state =
      [[PrismelMetalCompilerTaskState alloc]
          initWithKind:PrismelMetalCompilerResultRenderPipeline
                   label:request.label
     reflectionRequested:request.reflectionRequested];
  state.retainedInputs = request;
  __weak PrismelMetalCompilerTaskState *weak_state = state;
  PrismelMetalCheckedRenderRequest *retained_request = request;
  MTLNewRenderPipelineStateCompletionHandler completion_handler =
      ^(id<MTLRenderPipelineState> pipeline, NSError *error) {
        (void)retained_request;
        PrismelMetalCompilerTaskState *strong_state = weak_state;
        [strong_state finishWithObject:pipeline error:error];
      };
  id<MTL4CompilerTask> task = request.dynamicLinking == nil
      ? [compiler newRenderPipelineStateWithDescriptor:request.descriptor
                                   compilerTaskOptions:request.taskOptions
                                     completionHandler:completion_handler]
      : [compiler newRenderPipelineStateWithDescriptor:request.descriptor
                              dynamicLinkingDescriptor:request.dynamicLinking
                                   compilerTaskOptions:request.taskOptions
                                     completionHandler:completion_handler];
  if (task == nil) {
    *failure = labeled_error_description(
        request.label, nil,
        @"Metal 4 asynchronous render-pipeline task creation failed");
    return nil;
  }
  state.task = task;
  if (state.identifier == 0 ||
      task.compiler.device.registryID != compiler.device.registryID) {
    *failure = @"Metal changed checked asynchronous compiler task properties";
    return nil;
  }
  return state;
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_create_compute_pipeline(value raw_compiler,
                                                      value raw_descriptor) {
  CAMLparam2(raw_compiler, raw_descriptor);
  CAMLlocal3(raw, bindings, pair);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *validation_failure = nil;
        PrismelMetalCheckedComputeRequest *request =
            checked_compute_request(raw_descriptor, compiler,
                                    &validation_failure);
        if (request == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        MTL4ComputePipelineDescriptor *descriptor = request.descriptor;
        MTL4PipelineStageDynamicLinkingDescriptor *dynamic_linking =
            request.dynamicLinking;
        MTL4CompilerTaskOptions *task_options = request.taskOptions;
        NSString *expected_label = request.label;
        const bool reflection_requested = request.reflectionRequested;
        NSError *error = nil;
        id<MTLComputePipelineState> pipeline = dynamic_linking == nil
            ? [compiler newComputePipelineStateWithDescriptor:descriptor
                                          compilerTaskOptions:task_options
                                                        error:&error]
            : [compiler newComputePipelineStateWithDescriptor:descriptor
                                     dynamicLinkingDescriptor:dynamic_linking
                                          compilerTaskOptions:task_options
                                                        error:&error];
        if (pipeline == nil) {
          CAMLreturn(result_error(labeled_error_description(
              expected_label, error,
              @"Metal 4 compute-pipeline compilation failed without NSError")));
        }
        MTLComputePipelineReflection *reflection = pipeline.reflection;
        if (reflection_requested && reflection == nil) {
          CAMLreturn(result_error_text(
              "Metal 4 omitted requested compute-pipeline reflection"));
        }
        if (pipeline.device.registryID != compiler.device.registryID ||
            ((expected_label == nil) != (pipeline.label == nil)) ||
            (expected_label != nil &&
             ![pipeline.label isEqualToString:expected_label])) {
          CAMLreturn(result_error_text(
              "Metal changed checked Metal 4 compute-pipeline properties"));
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
    } else {
      CAMLreturn(result_error_text(
          "Metal 4 compute compilation requires macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(pair));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_create_compute_pipeline_async(
    value raw_compiler, value raw_descriptor) {
  CAMLparam2(raw_compiler, raw_descriptor);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *validation_failure = nil;
        PrismelMetalCheckedComputeRequest *request =
            checked_compute_request(raw_descriptor, compiler,
                                    &validation_failure);
        if (request == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        PrismelMetalCompilerTaskState *state =
            [[PrismelMetalCompilerTaskState alloc]
                initWithKind:PrismelMetalCompilerResultComputePipeline
                         label:request.label
           reflectionRequested:request.reflectionRequested];
        __weak PrismelMetalCompilerTaskState *weak_state = state;
        state.retainedInputs = request;
        PrismelMetalCheckedComputeRequest *retained_request = request;
        MTLNewComputePipelineStateCompletionHandler completion_handler =
            ^(id<MTLComputePipelineState> pipeline, NSError *error) {
              (void)retained_request;
              PrismelMetalCompilerTaskState *strong_state = weak_state;
              [strong_state finishWithObject:pipeline error:error];
            };
        id<MTL4CompilerTask> task = request.dynamicLinking == nil
            ? [compiler newComputePipelineStateWithDescriptor:request.descriptor
                                          compilerTaskOptions:request.taskOptions
                                            completionHandler:completion_handler]
            : [compiler newComputePipelineStateWithDescriptor:request.descriptor
                                     dynamicLinkingDescriptor:request.dynamicLinking
                                          compilerTaskOptions:request.taskOptions
                                            completionHandler:completion_handler];
        if (task == nil) {
          CAMLreturn(result_error(labeled_error_description(
              request.label, nil,
              @"Metal 4 asynchronous compute-pipeline task creation failed")));
        }
        state.task = task;
        if (state.identifier == 0 || task.compiler.device.registryID !=
                                         compiler.device.registryID) {
          CAMLreturn(result_error_text(
              "Metal changed checked asynchronous compiler task properties"));
        }
        raw = allocate_handle(state, Handle_kind::Compiler_task);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 compute compilation requires macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_task_take_compute_pipeline(value raw) {
  CAMLparam1(raw);
  CAMLlocal5(raw_pipeline, bindings, pair, completion, option);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetalCompilerTaskState *state =
            object_of_handle(raw, Handle_kind::Compiler_task);
        if (state.resultKind != PrismelMetalCompilerResultComputePipeline) {
          CAMLreturn(result_error_text(
              "compiler task does not contain a compute-pipeline result"));
        }
        id result_object = nil;
        NSError *result_error_value = nil;
        const PrismelMetalCompilerResultState result_state =
            [state takeObject:&result_object error:&result_error_value];
        if (result_state == PrismelMetalCompilerResultPending) {
          CAMLreturn(result_ok(Val_none));
        }
        if (result_state == PrismelMetalCompilerResultConsumed) {
          CAMLreturn(result_error_text(
              "compiler task completion was already consumed"));
        }
        if (result_state == PrismelMetalCompilerResultFailure) {
          completion = result_error(labeled_error_description(
              state.label, result_error_value,
              @"Metal 4 asynchronous compute-pipeline compilation failed without NSError"));
        } else {
          id<MTLComputePipelineState> pipeline =
              static_cast<id<MTLComputePipelineState>>(result_object);
          MTLComputePipelineReflection *reflection = pipeline.reflection;
          if (state.reflectionRequested && reflection == nil) {
            completion = result_error_text(
                "Metal 4 omitted requested asynchronous compute-pipeline reflection");
          } else if (pipeline.device.registryID !=
                         state.task.compiler.device.registryID ||
                     ((state.label == nil) != (pipeline.label == nil)) ||
                     (state.label != nil &&
                      ![pipeline.label isEqualToString:state.label])) {
            completion = result_error_text(
                "Metal changed checked asynchronous compute-pipeline properties");
          } else {
            raw_pipeline =
                allocate_handle(pipeline, Handle_kind::Compute_pipeline);
            bindings = state.reflectionRequested
                ? copy_bindings(reflection.bindings)
                : caml_alloc(0, 0);
            pair = caml_alloc_tuple(2);
            Store_field(pair, 0, raw_pipeline);
            Store_field(pair, 1, bindings);
            completion = result_ok(pair);
          }
        }
        option = caml_alloc(1, 0);
        Store_field(option, 0, completion);
        CAMLreturn(result_ok(option));
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 compute compilation requires macOS 26 or newer"));
    }
  }
  CAMLreturn(result_error_text("unreachable compute compiler-task result"));
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

extern "C" CAMLprim value
caml_prismel_metal_compiler_create_render_pipeline_async(
    value raw_compiler, value raw_descriptor) {
  CAMLparam2(raw_compiler, raw_descriptor);
  CAMLlocal1(raw);
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
        PrismelMetalCompilerTaskState *state =
            start_checked_render_pipeline_task(compiler, request,
                                               &validation_failure);
        if (state == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        raw = allocate_handle(state, Handle_kind::Compiler_task);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 render pipelines require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_create_mesh_pipeline(
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
            checked_mesh_request(raw_descriptor, compiler,
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
          "Metal 4 mesh pipelines require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(pair));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_create_mesh_pipeline_async(
    value raw_compiler, value raw_descriptor) {
  CAMLparam2(raw_compiler, raw_descriptor);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *validation_failure = nil;
        PrismelMetalCheckedRenderRequest *request =
            checked_mesh_request(raw_descriptor, compiler,
                                 &validation_failure);
        if (request == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        PrismelMetalCompilerTaskState *state =
            start_checked_render_pipeline_task(compiler, request,
                                               &validation_failure);
        if (state == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        raw = allocate_handle(state, Handle_kind::Compiler_task);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 mesh pipelines require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_compiler_create_tile_pipeline(
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
            checked_tile_request(raw_descriptor, compiler,
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
          "Metal 4 tile pipelines require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(pair));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_create_tile_pipeline_async(
    value raw_compiler, value raw_descriptor) {
  CAMLparam2(raw_compiler, raw_descriptor);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4Compiler> compiler =
            object_of_handle(raw_compiler, Handle_kind::Compiler);
        NSString *validation_failure = nil;
        PrismelMetalCheckedRenderRequest *request =
            checked_tile_request(raw_descriptor, compiler,
                                 &validation_failure);
        if (request == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        PrismelMetalCompilerTaskState *state =
            start_checked_render_pipeline_task(compiler, request,
                                               &validation_failure);
        if (state == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        raw = allocate_handle(state, Handle_kind::Compiler_task);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 tile pipelines require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_compiler_task_take_render_pipeline(value raw) {
  CAMLparam1(raw);
  CAMLlocal4(raw_pipeline, reflection, pair, completion);
  CAMLlocal1(option);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetalCompilerTaskState *state =
            object_of_handle(raw, Handle_kind::Compiler_task);
        if (state.resultKind != PrismelMetalCompilerResultRenderPipeline) {
          CAMLreturn(result_error_text(
              "compiler task does not contain a render-pipeline result"));
        }
        id result_object = nil;
        NSError *result_error_value = nil;
        const PrismelMetalCompilerResultState result_state =
            [state takeObject:&result_object error:&result_error_value];
        if (result_state == PrismelMetalCompilerResultPending) {
          CAMLreturn(result_ok(Val_none));
        }
        if (result_state == PrismelMetalCompilerResultConsumed) {
          CAMLreturn(result_error_text(
              "compiler task completion was already consumed"));
        }
        if (result_state == PrismelMetalCompilerResultFailure) {
          completion = result_error(labeled_error_description(
              state.label, result_error_value,
              @"Metal 4 asynchronous render-pipeline compilation failed without NSError"));
        } else {
          id<MTLRenderPipelineState> pipeline =
              static_cast<id<MTLRenderPipelineState>>(result_object);
          NSString *validation_failure = nil;
          if (!checked_render_pipeline_result(
                  pipeline, state.task.compiler, state.label,
                  state.reflectionRequested, &validation_failure)) {
            completion = result_error(validation_failure);
          } else {
            raw_pipeline =
                allocate_handle(pipeline, Handle_kind::Render_pipeline);
            reflection = copy_render_reflection(pipeline.reflection);
            pair = caml_alloc_tuple(2);
            Store_field(pair, 0, raw_pipeline);
            Store_field(pair, 1, reflection);
            completion = result_ok(pair);
          }
        }
        option = caml_alloc(1, 0);
        Store_field(option, 0, completion);
        CAMLreturn(result_ok(option));
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    } else {
      CAMLreturn(result_error_text(
          "asynchronous Metal 4 render pipelines require macOS 26 or newer"));
    }
  }
  CAMLreturn(result_error_text("unreachable render compiler-task result"));
}

extern "C" CAMLprim value caml_prismel_metal_render_pipeline_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLRenderPipelineState> pipeline =
        object_of_handle(raw, Handle_kind::Render_pipeline);
    result = copy_optional_string(pipeline.label);
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value caml_prismel_metal_render_pipeline_mesh_limits(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal2(limits, result);
  @autoreleasepool {
    if (@available(macOS 13.0, *)) {
      @try {
        id<MTLRenderPipelineState> pipeline =
            object_of_handle(raw, Handle_kind::Render_pipeline);
        const NSUInteger observed[5] = {
            pipeline.maxTotalThreadsPerObjectThreadgroup,
            pipeline.maxTotalThreadsPerMeshThreadgroup,
            pipeline.objectThreadExecutionWidth,
            pipeline.meshThreadExecutionWidth,
            pipeline.maxTotalThreadgroupsPerMeshGrid,
        };
        for (NSUInteger index = 0; index < 5; ++index) {
          if (observed[index] > static_cast<NSUInteger>(Max_long)) {
            CAMLreturn(result_error_text(
                "Metal mesh-pipeline limits exceed the OCaml integer range"));
          }
        }
        limits = caml_alloc_tuple(5);
        for (mlsize_t index = 0; index < 5; ++index) {
          Store_field(limits, index,
                      Val_long(static_cast<intnat>(observed[index])));
        }
        result = result_ok(limits);
        CAMLreturn(result);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text(
        "Metal mesh-pipeline limits require macOS 13 or newer"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_render_pipeline_tile_limits(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal2(limits, result);
  @autoreleasepool {
    if (@available(macOS 11.0, *)) {
      @try {
        id<MTLRenderPipelineState> pipeline =
            object_of_handle(raw, Handle_kind::Render_pipeline);
        const NSUInteger maximum = pipeline.maxTotalThreadsPerThreadgroup;
        if (maximum > static_cast<NSUInteger>(Max_long)) {
          CAMLreturn(result_error_text(
              "Metal tile-pipeline limit exceeds the OCaml integer range"));
        }
        limits = caml_alloc_tuple(2);
        Store_field(limits, 0, Val_long(static_cast<intnat>(maximum)));
        Store_field(limits, 1,
                    Val_bool(pipeline.threadgroupSizeMatchesTileSize));
        result = result_ok(limits);
        CAMLreturn(result);
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text(
        "Metal tile-pipeline limits require macOS 11 or newer"));
  }
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
            linked.functionType != MTLFunctionTypeVisible ||
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
      descriptor.binaryArchives = archive_array;
      descriptor.supportIndirectCommandBuffers = Bool_val(Field(raw_descriptor, 6));
      if (descriptor.computeFunction != function ||
          ((expected_label == nil) != (descriptor.label == nil)) ||
          (expected_label != nil &&
           ![descriptor.label isEqualToString:expected_label]) ||
          descriptor.preloadedLibraries.count != preloaded_array.count ||
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

extern "C" CAMLprim value caml_prismel_metal_compute_pipeline_label(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    id<MTLComputePipelineState> pipeline =
        object_of_handle(raw, Handle_kind::Compute_pipeline);
    result = copy_optional_string(pipeline.label);
  }
  CAMLreturn(result);
}

extern "C" CAMLprim value
caml_prismel_metal_compute_pipeline_thread_execution_width(value raw) {
  CAMLparam1(raw);
  id<MTLComputePipelineState> pipeline =
      object_of_handle(raw, Handle_kind::Compute_pipeline);
  CAMLreturn(Val_long(pipeline.threadExecutionWidth));
}

extern "C" CAMLprim value
caml_prismel_metal_compute_pipeline_max_total_threads(value raw) {
  CAMLparam1(raw);
  id<MTLComputePipelineState> pipeline =
      object_of_handle(raw, Handle_kind::Compute_pipeline);
  CAMLreturn(Val_long(pipeline.maxTotalThreadsPerThreadgroup));
}

extern "C" CAMLprim value caml_prismel_metal_command4_allocator_create(
    value raw_device, value raw_label) {
  CAMLparam2(raw_device, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device =
          object_of_handle(raw_device, Handle_kind::Device);
      if (!device_supports_metal4_commands(device)) {
        CAMLreturn(result_error_text(
            "device does not support the checked Metal 4 command API"));
      }
      if (@available(macOS 26.0, *)) {
        MTL4CommandAllocatorDescriptor *descriptor =
            [[MTL4CommandAllocatorDescriptor alloc] init];
        if (Is_block(raw_label)) {
          NSString *label = string_from_ocaml(Field(raw_label, 0));
          if (label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 command-allocator label is not valid UTF-8"));
          }
          descriptor.label = label;
        }
        NSError *error = nil;
        id<MTL4CommandAllocator> allocator =
            [device newCommandAllocatorWithDescriptor:descriptor error:&error];
        if (allocator == nil ||
            allocator.device.registryID != device.registryID ||
            ((descriptor.label == nil) != (allocator.label == nil)) ||
            (descriptor.label != nil &&
             ![allocator.label isEqualToString:descriptor.label])) {
          CAMLreturn(result_error(error_description(
              error, @"Metal rejected the checked Metal 4 command allocator")));
        }
        raw = allocate_handle(allocator, Handle_kind::Command_allocator4);
        CAMLreturn(result_ok(raw));
      }
      CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_allocator_label(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      id<MTL4CommandAllocator> allocator =
          object_of_handle(raw, Handle_kind::Command_allocator4);
      result = copy_optional_string(allocator.label);
      CAMLreturn(result);
    }
    caml_failwith("Metal 4 commands require macOS 26");
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_allocator_allocated_size(value raw) {
  CAMLparam1(raw);
  if (@available(macOS 26.0, *)) {
    id<MTL4CommandAllocator> allocator =
        object_of_handle(raw, Handle_kind::Command_allocator4);
    CAMLreturn(caml_copy_int64(static_cast<std::int64_t>(allocator.allocatedSize)));
  }
  caml_failwith("Metal 4 commands require macOS 26");
}

extern "C" CAMLprim value caml_prismel_metal_command4_allocator_reset(
    value raw) {
  CAMLparam1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4CommandAllocator> allocator =
            object_of_handle(raw, Handle_kind::Command_allocator4);
        [allocator reset];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_queue_create(
    value raw_device, value raw_label) {
  CAMLparam2(raw_device, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device =
          object_of_handle(raw_device, Handle_kind::Device);
      if (!device_supports_metal4_commands(device)) {
        CAMLreturn(result_error_text(
            "device does not support the checked Metal 4 command API"));
      }
      if (@available(macOS 26.0, *)) {
        MTL4CommandQueueDescriptor *descriptor =
            [[MTL4CommandQueueDescriptor alloc] init];
        if (Is_block(raw_label)) {
          NSString *label = string_from_ocaml(Field(raw_label, 0));
          if (label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 command-queue label is not valid UTF-8"));
          }
          descriptor.label = label;
        }
        NSError *error = nil;
        id<MTL4CommandQueue> queue =
            [device newMTL4CommandQueueWithDescriptor:descriptor error:&error];
        if (queue == nil || queue.device.registryID != device.registryID ||
            ((descriptor.label == nil) != (queue.label == nil)) ||
            (descriptor.label != nil &&
             ![queue.label isEqualToString:descriptor.label])) {
          CAMLreturn(result_error(error_description(
              error, @"Metal rejected the checked Metal 4 command queue")));
        }
        raw = allocate_handle(queue, Handle_kind::Command_queue4);
        CAMLreturn(result_ok(raw));
      }
      CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_queue_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      id<MTL4CommandQueue> queue =
          object_of_handle(raw, Handle_kind::Command_queue4);
      result = copy_optional_string(queue.label);
      CAMLreturn(result);
    }
    caml_failwith("Metal 4 commands require macOS 26");
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_argument_table_create(
    value raw_device, value raw_descriptor) {
  CAMLparam2(raw_device, raw_descriptor);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device =
          object_of_handle(raw_device, Handle_kind::Device);
      if (!device_supports_metal4_commands(device)) {
        CAMLreturn(result_error_text(
            "device does not support the checked Metal 4 argument-table API"));
      }
      if (@available(macOS 26.0, *)) {
        const intnat max_buffers = Long_val(Field(raw_descriptor, 0));
        const intnat max_textures = Long_val(Field(raw_descriptor, 1));
        const intnat max_samplers = Long_val(Field(raw_descriptor, 2));
        const BOOL initialize_bindings = Bool_val(Field(raw_descriptor, 3));
        const BOOL support_attribute_strides =
            Bool_val(Field(raw_descriptor, 4));
        if (max_buffers < 0 || max_buffers > 31 || max_textures < 0 ||
            max_textures > 128 || max_samplers < 0 || max_samplers > 16 ||
            (max_buffers == 0 && max_textures == 0 && max_samplers == 0)) {
          CAMLreturn(result_error_text(
              "Metal 4 argument-table capacities are invalid"));
        }
        MTL4ArgumentTableDescriptor *descriptor =
            [[MTL4ArgumentTableDescriptor alloc] init];
        descriptor.maxBufferBindCount = static_cast<NSUInteger>(max_buffers);
        descriptor.maxTextureBindCount = static_cast<NSUInteger>(max_textures);
        descriptor.maxSamplerStateBindCount =
            static_cast<NSUInteger>(max_samplers);
        descriptor.initializeBindings = initialize_bindings;
        descriptor.supportAttributeStrides = support_attribute_strides;
        if (Is_block(Field(raw_descriptor, 5))) {
          NSString *label =
              string_from_ocaml(Field(Field(raw_descriptor, 5), 0));
          if (label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 argument-table label is not valid UTF-8"));
          }
          descriptor.label = label;
        }
        NSError *error = nil;
        id<MTL4ArgumentTable> table =
            [device newArgumentTableWithDescriptor:descriptor error:&error];
        if (table == nil || table.device.registryID != device.registryID ||
            descriptor.maxBufferBindCount !=
                static_cast<NSUInteger>(max_buffers) ||
            descriptor.maxTextureBindCount !=
                static_cast<NSUInteger>(max_textures) ||
            descriptor.maxSamplerStateBindCount !=
                static_cast<NSUInteger>(max_samplers) ||
            descriptor.initializeBindings != initialize_bindings ||
            descriptor.supportAttributeStrides != support_attribute_strides ||
            ((descriptor.label == nil) != (table.label == nil)) ||
            (descriptor.label != nil &&
             ![table.label isEqualToString:descriptor.label])) {
          CAMLreturn(result_error(error_description(
              error, @"Metal rejected the checked Metal 4 argument table")));
        }
        PrismelMetal4ArgumentTableState *state =
            [[PrismelMetal4ArgumentTableState alloc]
                     initWithArgumentTable:table
                            maxBufferCount:static_cast<NSUInteger>(max_buffers)
                           maxTextureCount:static_cast<NSUInteger>(max_textures)
                           maxSamplerCount:static_cast<NSUInteger>(max_samplers)
                    supportAttributeStrides:support_attribute_strides];
        raw = allocate_handle(state, Handle_kind::Argument_table4);
        CAMLreturn(result_ok(raw));
      }
      CAMLreturn(result_error_text("Metal 4 argument tables require macOS 26"));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_argument_table_label(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      PrismelMetal4ArgumentTableState *state =
          argument_table4_state_of_handle(raw);
      result = copy_optional_string(state.argumentTable.label);
      CAMLreturn(result);
    }
    caml_failwith("Metal 4 argument tables require macOS 26");
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_argument_table_set_buffer(
    value raw_table, value raw_buffer, value raw_binding) {
  CAMLparam3(raw_table, raw_buffer, raw_binding);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetal4ArgumentTableState *state =
            argument_table4_state_of_handle(raw_table);
        const intnat index = Long_val(Field(raw_binding, 0));
        const std::int64_t offset = Int64_val(Field(raw_binding, 1));
        value raw_stride = Field(raw_binding, 2);
        if (index < 0 ||
            static_cast<NSUInteger>(index) >= state.maxBufferBindCount ||
            offset < 0) {
          CAMLreturn(result_error_text(
              "Metal 4 argument-table buffer binding is out of range"));
        }
        if (!Is_block(raw_buffer)) {
          if (Is_block(raw_stride)) {
            CAMLreturn(result_error_text(
                "a cleared Metal 4 buffer binding cannot have a stride"));
          }
          [state.argumentTable setAddress:0
                                  atIndex:static_cast<NSUInteger>(index)];
          [state setBoundBuffer:nil atIndex:static_cast<NSUInteger>(index)];
          CAMLreturn(result_unit());
        }
        id<MTLBuffer> buffer = object_of_handle(
            Field(raw_buffer, 0), Handle_kind::Buffer);
        if (buffer.device.registryID !=
                state.argumentTable.device.registryID ||
            static_cast<std::uint64_t>(offset) >= buffer.length) {
          CAMLreturn(result_error_text(
              "Metal 4 argument-table buffer failed native validation"));
        }
        const MTLGPUAddress address = buffer.gpuAddress;
        const std::uint64_t unsigned_offset =
            static_cast<std::uint64_t>(offset);
        if (address == 0 ||
            unsigned_offset >
                std::numeric_limits<MTLGPUAddress>::max() - address) {
          CAMLreturn(result_error_text(
              "Metal buffer exposes no usable GPU address at this offset"));
        }
        if (Is_block(raw_stride)) {
          const intnat stride = Long_val(Field(raw_stride, 0));
          if (!state.supportAttributeStrides || stride <= 0) {
            CAMLreturn(result_error_text(
                "Metal 4 argument-table attribute stride is invalid"));
          }
          [state.argumentTable
                    setAddress:address + unsigned_offset
               attributeStride:static_cast<NSUInteger>(stride)
                       atIndex:static_cast<NSUInteger>(index)];
        } else {
          [state.argumentTable setAddress:address + unsigned_offset
                                  atIndex:static_cast<NSUInteger>(index)];
        }
        [state setBoundBuffer:buffer atIndex:static_cast<NSUInteger>(index)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 argument tables require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_argument_table_set_texture(
    value raw_table, value raw_texture, value raw_index) {
  CAMLparam3(raw_table, raw_texture, raw_index);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetal4ArgumentTableState *state =
            argument_table4_state_of_handle(raw_table);
        const intnat index = Long_val(raw_index);
        if (index < 0 ||
            static_cast<NSUInteger>(index) >= state.maxTextureBindCount) {
          CAMLreturn(result_error_text(
              "Metal 4 argument-table texture binding is out of range"));
        }
        MTLResourceID resource_id = {};
        id<MTLTexture> texture = nil;
        if (Is_block(raw_texture)) {
          texture = object_of_handle(Field(raw_texture, 0), Handle_kind::Texture);
          if (texture.device.registryID !=
              state.argumentTable.device.registryID) {
            CAMLreturn(result_error_text(
                "Metal 4 argument-table texture belongs to another device"));
          }
          resource_id = texture.gpuResourceID;
          if (resource_id._impl == 0) {
            CAMLreturn(result_error_text(
                "Metal texture exposes no usable GPU resource ID"));
          }
        }
        [state.argumentTable setTexture:resource_id
                                atIndex:static_cast<NSUInteger>(index)];
        [state setBoundTexture:texture atIndex:static_cast<NSUInteger>(index)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 argument tables require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_argument_table_set_sampler(
    value raw_table, value raw_sampler, value raw_index) {
  CAMLparam3(raw_table, raw_sampler, raw_index);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetal4ArgumentTableState *state =
            argument_table4_state_of_handle(raw_table);
        const intnat index = Long_val(raw_index);
        if (index < 0 ||
            static_cast<NSUInteger>(index) >= state.maxSamplerStateBindCount) {
          CAMLreturn(result_error_text(
              "Metal 4 argument-table sampler binding is out of range"));
        }
        MTLResourceID resource_id = {};
        id<MTLSamplerState> sampler = nil;
        if (Is_block(raw_sampler)) {
          sampler = object_of_handle(Field(raw_sampler, 0), Handle_kind::Sampler);
          if (sampler.device.registryID !=
              state.argumentTable.device.registryID) {
            CAMLreturn(result_error_text(
                "Metal 4 argument-table sampler belongs to another device"));
          }
          resource_id = sampler.gpuResourceID;
          if (resource_id._impl == 0) {
            CAMLreturn(result_error_text(
                "Metal sampler exposes no usable GPU resource ID"));
          }
        }
        [state.argumentTable setSamplerState:resource_id
                                     atIndex:static_cast<NSUInteger>(index)];
        [state setBoundSampler:sampler atIndex:static_cast<NSUInteger>(index)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 argument tables require macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_buffer_create(
    value raw_allocator, value raw_label) {
  CAMLparam2(raw_allocator, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4CommandAllocator> allocator =
            object_of_handle(raw_allocator, Handle_kind::Command_allocator4);
        id<MTLDevice> device = allocator.device;
        id<MTL4CommandBuffer> command_buffer = [device newCommandBuffer];
        if (command_buffer == nil ||
            command_buffer.device.registryID != device.registryID) {
          CAMLreturn(result_error_text(
              "Metal failed to create a checked Metal 4 command buffer"));
        }
        if (Is_block(raw_label)) {
          NSString *label = string_from_ocaml(Field(raw_label, 0));
          if (label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 command-buffer label is not valid UTF-8"));
          }
          command_buffer.label = label;
          if (![command_buffer.label isEqualToString:label]) {
            CAMLreturn(result_error_text(
                "Metal changed the checked Metal 4 command-buffer label"));
          }
        }
        [command_buffer beginCommandBufferWithAllocator:allocator];
        PrismelMetal4CommandBufferState *state =
            [[PrismelMetal4CommandBufferState alloc]
                initWithCommandBuffer:command_buffer
                             allocator:allocator];
        raw = allocate_handle(state, Handle_kind::Command_buffer4);
        CAMLreturn(result_ok(raw));
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_buffer_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      PrismelMetal4CommandBufferState *state =
          command_buffer4_state_of_handle(raw);
      result = copy_optional_string(state.commandBuffer.label);
      CAMLreturn(result);
    }
    caml_failwith("Metal 4 commands require macOS 26");
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_buffer_end(value raw) {
  CAMLparam1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetal4CommandBufferState *state =
            command_buffer4_state_of_handle(raw);
        [state.commandBuffer endCommandBuffer];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_compute_encoder_create(
    value raw_buffer, value raw_label) {
  CAMLparam2(raw_buffer, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetal4CommandBufferState *state =
            command_buffer4_state_of_handle(raw_buffer);
        NSString *expected_label = nil;
        if (Is_block(raw_label)) {
          expected_label = string_from_ocaml(Field(raw_label, 0));
          if (expected_label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 compute-encoder label is not valid UTF-8"));
          }
        }
        id<MTL4ComputeCommandEncoder> encoder =
            state.commandBuffer.computeCommandEncoder;
        if (encoder == nil || encoder.commandBuffer != state.commandBuffer) {
          CAMLreturn(result_error_text(
              "Metal failed to create a checked Metal 4 compute encoder"));
        }
        if (expected_label != nil) {
          encoder.label = expected_label;
          if (![encoder.label isEqualToString:expected_label]) {
            [encoder endEncoding];
            CAMLreturn(result_error_text(
                "Metal changed the checked Metal 4 compute-encoder label"));
          }
        }
        raw = allocate_handle(encoder, Handle_kind::Compute_encoder4);
        CAMLreturn(result_ok(raw));
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_compute_encoder_set_pipeline(
    value raw_encoder, value raw_buffer, value raw_pipeline) {
  CAMLparam3(raw_encoder, raw_buffer, raw_pipeline);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4ComputeCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Compute_encoder4);
        PrismelMetal4CommandBufferState *state =
            command_buffer4_state_of_handle(raw_buffer);
        id<MTLComputePipelineState> pipeline =
            object_of_handle(raw_pipeline, Handle_kind::Compute_pipeline);
        if (encoder.commandBuffer != state.commandBuffer ||
            pipeline.device.registryID !=
                state.commandBuffer.device.registryID) {
          CAMLreturn(result_error_text(
              "Metal 4 compute pipeline belongs to another command graph"));
        }
        [encoder setComputePipelineState:pipeline];
        [state retainEncodedObject:pipeline];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_compute_encoder_set_argument_table(
    value raw_encoder, value raw_buffer, value raw_table) {
  CAMLparam3(raw_encoder, raw_buffer, raw_table);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4ComputeCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Compute_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        if (encoder.commandBuffer != command_buffer.commandBuffer) {
          CAMLreturn(result_error_text(
              "Metal 4 compute encoder belongs to another command graph"));
        }
        id<MTL4ArgumentTable> table = nil;
        PrismelMetal4ArgumentTableState *table_state = nil;
        if (Is_block(raw_table)) {
          table_state =
              argument_table4_state_of_handle(Field(raw_table, 0));
          table = table_state.argumentTable;
          if (table.device.registryID !=
              command_buffer.commandBuffer.device.registryID) {
            CAMLreturn(result_error_text(
                "Metal 4 argument table belongs to another command graph"));
          }
        }
        [encoder setArgumentTable:table];
        if (table_state != nil) {
          [command_buffer retainEncodedObject:table_state];
        }
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 argument tables require macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_compute_encoder_dispatch(
    value raw_encoder, value raw_buffer, value raw_table, value raw_sizes) {
  CAMLparam4(raw_encoder, raw_buffer, raw_table, raw_sizes);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4ComputeCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Compute_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        const intnat grid_x = Long_val(Field(raw_sizes, 0));
        const intnat grid_y = Long_val(Field(raw_sizes, 1));
        const intnat grid_z = Long_val(Field(raw_sizes, 2));
        const intnat group_x = Long_val(Field(raw_sizes, 3));
        const intnat group_y = Long_val(Field(raw_sizes, 4));
        const intnat group_z = Long_val(Field(raw_sizes, 5));
        if (encoder.commandBuffer != command_buffer.commandBuffer || grid_x <= 0 ||
            grid_y <= 0 || grid_z <= 0 || group_x <= 0 || group_y <= 0 ||
            group_z <= 0) {
          CAMLreturn(result_error_text(
              "Metal 4 compute dispatch dimensions are invalid"));
        }
        if (Is_block(raw_table)) {
          PrismelMetal4ArgumentTableState *table =
              argument_table4_state_of_handle(Field(raw_table, 0));
          if (table.argumentTable.device.registryID !=
              command_buffer.commandBuffer.device.registryID) {
            CAMLreturn(result_error_text(
                "Metal 4 dispatch argument table belongs to another device"));
          }
          [command_buffer retainEncodedObject:table];
          [table retainBoundObjectsInCommandBuffer:command_buffer];
        }
        [encoder
                  dispatchThreads:MTLSizeMake(static_cast<NSUInteger>(grid_x),
                                              static_cast<NSUInteger>(grid_y),
                                              static_cast<NSUInteger>(grid_z))
            threadsPerThreadgroup:
                MTLSizeMake(static_cast<NSUInteger>(group_x),
                            static_cast<NSUInteger>(group_y),
                            static_cast<NSUInteger>(group_z))];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_compute_encoder_end(
    value raw) {
  CAMLparam1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4ComputeCommandEncoder> encoder =
            object_of_handle(raw, Handle_kind::Compute_encoder4);
        [encoder endEncoding];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_render_encoder_create(
    value raw_buffer, value raw_descriptor) {
  CAMLparam2(raw_buffer, raw_descriptor);
  CAMLlocal2(raw, created);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        PrismelMetal4CommandBufferState *state =
            command_buffer4_state_of_handle(raw_buffer);
        if (!Is_block(raw_descriptor) || Tag_val(raw_descriptor) != 0 ||
            Wosize_val(raw_descriptor) != 9) {
          CAMLreturn(result_error_text(
              "Metal 4 render-pass descriptor shape is invalid"));
        }
        value raw_attachments = Field(raw_descriptor, 0);
        value raw_depth_attachment = Field(raw_descriptor, 1);
        value raw_stencil_attachment = Field(raw_descriptor, 2);
        value raw_width = Field(raw_descriptor, 3);
        value raw_height = Field(raw_descriptor, 4);
        value raw_label = Field(raw_descriptor, 5);
        value raw_support_color_attachment_mapping = Field(raw_descriptor, 6);
        value raw_visibility_result_buffer = Field(raw_descriptor, 7);
        value raw_visibility_result_type = Field(raw_descriptor, 8);
        if (!Is_long(raw_support_color_attachment_mapping) ||
            !Is_long(raw_visibility_result_type) ||
            !((Is_long(raw_visibility_result_buffer) &&
               Long_val(raw_visibility_result_buffer) == 0) ||
              (Is_block(raw_visibility_result_buffer) &&
               Tag_val(raw_visibility_result_buffer) == 0 &&
               Wosize_val(raw_visibility_result_buffer) == 1))) {
          CAMLreturn(result_error_text(
              "Metal 4 render-pass descriptor fields are invalid"));
        }
        const intnat support_color_attachment_mapping_code =
            Long_val(raw_support_color_attachment_mapping);
        const intnat visibility_result_type_code =
            Long_val(raw_visibility_result_type);
        const mlsize_t count = Wosize_val(raw_attachments);
        const intnat width = Long_val(raw_width);
        const intnat height = Long_val(raw_height);
        NSString *expected_label = nil;
        if (Is_block(raw_label)) {
          expected_label = string_from_ocaml(Field(raw_label, 0));
          if (expected_label == nil) {
            CAMLreturn(result_error_text(
                "Metal 4 render-encoder label is not valid UTF-8"));
          }
        }
        if (count == 0 || count > 8 || width <= 0 || height <= 0 ||
            support_color_attachment_mapping_code < 0 ||
            support_color_attachment_mapping_code > 1 ||
            (visibility_result_type_code != MTLVisibilityResultTypeReset &&
             visibility_result_type_code !=
                 MTLVisibilityResultTypeAccumulate)) {
          CAMLreturn(result_error_text(
              "Metal 4 render-pass attachments or dimensions are invalid"));
        }
        const bool support_color_attachment_mapping =
            support_color_attachment_mapping_code == 1;
        id<MTLBuffer> visibility_result_buffer = nil;
        if (Is_block(raw_visibility_result_buffer)) {
          visibility_result_buffer = object_of_handle(
              Field(raw_visibility_result_buffer, 0), Handle_kind::Buffer);
          if (visibility_result_buffer.device.registryID !=
                  state.commandBuffer.device.registryID ||
              visibility_result_buffer.length < 8) {
            CAMLreturn(result_error_text(
                "Metal 4 visibility-result buffer failed native validation"));
          }
        }
        const MTLVisibilityResultType visibility_result_type =
            static_cast<MTLVisibilityResultType>(visibility_result_type_code);
        MTL4RenderPassDescriptor *descriptor =
            [[MTL4RenderPassDescriptor alloc] init];
        if (descriptor.visibilityResultBuffer != nil ||
            descriptor.visibilityResultType != MTLVisibilityResultTypeReset ||
            descriptor.supportColorAttachmentMapping) {
          CAMLreturn(result_error_text(
              "Metal changed checked Metal 4 render-pass defaults"));
        }
        descriptor.supportColorAttachmentMapping = YES;
        if (!descriptor.supportColorAttachmentMapping) {
          CAMLreturn(result_error_text(
              "Metal discarded checked render-pass mapping support"));
        }
        descriptor.renderTargetWidth = static_cast<NSUInteger>(width);
        descriptor.renderTargetHeight = static_cast<NSUInteger>(height);
        descriptor.defaultRasterSampleCount = 1;
        descriptor.supportColorAttachmentMapping =
            support_color_attachment_mapping;
        descriptor.visibilityResultBuffer = visibility_result_buffer;
        descriptor.visibilityResultType = visibility_result_type;
        NSMutableArray<id<MTLTexture>> *textures =
            [[NSMutableArray alloc] initWithCapacity:count];
        for (mlsize_t index = 0; index < count; ++index) {
          value attachment_value = Field(raw_attachments, index);
          id<MTLTexture> texture = object_of_handle(
              Field(attachment_value, 0), Handle_kind::Texture);
          const intnat load_action = Long_val(Field(attachment_value, 1));
          const intnat store_action = Long_val(Field(attachment_value, 2));
          const double clear_red = Double_val(Field(attachment_value, 3));
          const double clear_green = Double_val(Field(attachment_value, 4));
          const double clear_blue = Double_val(Field(attachment_value, 5));
          const double clear_alpha = Double_val(Field(attachment_value, 6));
          if (texture.device.registryID != state.commandBuffer.device.registryID ||
              texture.textureType != MTLTextureType2D ||
              texture.sampleCount != 1 ||
              texture.width != static_cast<NSUInteger>(width) ||
              texture.height != static_cast<NSUInteger>(height) ||
              (texture.usage & MTLTextureUsageRenderTarget) == 0 ||
              (load_action != MTLLoadActionDontCare &&
               load_action != MTLLoadActionLoad &&
               load_action != MTLLoadActionClear) ||
              (store_action != MTLStoreActionDontCare &&
               store_action != MTLStoreActionStore &&
               store_action != MTLStoreActionUnknown)) {
            CAMLreturn(result_error_text(
                "Metal 4 color attachment failed native validation"));
          }
          MTLRenderPassColorAttachmentDescriptor *attachment =
              descriptor.colorAttachments[index];
          attachment.texture = texture;
          attachment.loadAction = static_cast<MTLLoadAction>(load_action);
          attachment.storeAction = static_cast<MTLStoreAction>(store_action);
          attachment.clearColor = MTLClearColorMake(
              clear_red, clear_green, clear_blue, clear_alpha);
          if (attachment.texture != texture ||
              attachment.loadAction != static_cast<MTLLoadAction>(load_action) ||
              attachment.storeAction !=
                  static_cast<MTLStoreAction>(store_action) ||
              attachment.clearColor.red != clear_red ||
              attachment.clearColor.green != clear_green ||
              attachment.clearColor.blue != clear_blue ||
              attachment.clearColor.alpha != clear_alpha) {
            CAMLreturn(result_error_text(
                "Metal changed checked Metal 4 color attachment properties"));
          }
          [textures addObject:texture];
        }
        if (Is_block(raw_depth_attachment)) {
          value attachment_value = Field(raw_depth_attachment, 0);
          id<MTLTexture> texture = object_of_handle(
              Field(attachment_value, 0), Handle_kind::Texture);
          const intnat load_action = Long_val(Field(attachment_value, 1));
          const intnat store_action = Long_val(Field(attachment_value, 2));
          const double clear_depth = Double_val(Field(attachment_value, 3));
          const bool depth_format =
              texture.pixelFormat == MTLPixelFormatDepth16Unorm ||
              texture.pixelFormat == MTLPixelFormatDepth32Float ||
              texture.pixelFormat == MTLPixelFormatDepth24Unorm_Stencil8 ||
              texture.pixelFormat == MTLPixelFormatDepth32Float_Stencil8;
          if (texture.device.registryID != state.commandBuffer.device.registryID ||
              texture.textureType != MTLTextureType2D ||
              texture.sampleCount != 1 ||
              texture.width != static_cast<NSUInteger>(width) ||
              texture.height != static_cast<NSUInteger>(height) ||
              (texture.usage & MTLTextureUsageRenderTarget) == 0 ||
              !depth_format || !std::isfinite(clear_depth) ||
              clear_depth < 0.0 || clear_depth > 1.0 ||
              (load_action != MTLLoadActionDontCare &&
               load_action != MTLLoadActionLoad &&
               load_action != MTLLoadActionClear) ||
              (store_action != MTLStoreActionDontCare &&
               store_action != MTLStoreActionStore &&
               store_action != MTLStoreActionUnknown)) {
            CAMLreturn(result_error_text(
                "Metal 4 depth attachment failed native validation"));
          }
          MTLRenderPassDepthAttachmentDescriptor *attachment =
              descriptor.depthAttachment;
          attachment.texture = texture;
          attachment.loadAction = static_cast<MTLLoadAction>(load_action);
          attachment.storeAction = static_cast<MTLStoreAction>(store_action);
          attachment.clearDepth = clear_depth;
          if (attachment.texture != texture ||
              attachment.loadAction != static_cast<MTLLoadAction>(load_action) ||
              attachment.storeAction !=
                  static_cast<MTLStoreAction>(store_action) ||
              attachment.clearDepth != clear_depth) {
            CAMLreturn(result_error_text(
                "Metal changed checked Metal 4 depth attachment properties"));
          }
          [textures addObject:texture];
        }
        if (Is_block(raw_stencil_attachment)) {
          value attachment_value = Field(raw_stencil_attachment, 0);
          id<MTLTexture> texture = object_of_handle(
              Field(attachment_value, 0), Handle_kind::Texture);
          const intnat load_action = Long_val(Field(attachment_value, 1));
          const intnat store_action = Long_val(Field(attachment_value, 2));
          const std::uint32_t clear_stencil =
              static_cast<std::uint32_t>(
                  Int32_val(Field(attachment_value, 3)));
          const bool stencil_format =
              texture.pixelFormat == MTLPixelFormatStencil8 ||
              texture.pixelFormat == MTLPixelFormatDepth24Unorm_Stencil8 ||
              texture.pixelFormat == MTLPixelFormatDepth32Float_Stencil8 ||
              texture.pixelFormat == MTLPixelFormatX32_Stencil8 ||
              texture.pixelFormat == MTLPixelFormatX24_Stencil8;
          if (texture.device.registryID != state.commandBuffer.device.registryID ||
              texture.textureType != MTLTextureType2D ||
              texture.sampleCount != 1 ||
              texture.width != static_cast<NSUInteger>(width) ||
              texture.height != static_cast<NSUInteger>(height) ||
              (texture.usage & MTLTextureUsageRenderTarget) == 0 ||
              !stencil_format ||
              (load_action != MTLLoadActionDontCare &&
               load_action != MTLLoadActionLoad &&
               load_action != MTLLoadActionClear) ||
              (store_action != MTLStoreActionDontCare &&
               store_action != MTLStoreActionStore &&
               store_action != MTLStoreActionUnknown)) {
            CAMLreturn(result_error_text(
                "Metal 4 stencil attachment failed native validation"));
          }
          MTLRenderPassStencilAttachmentDescriptor *attachment =
              descriptor.stencilAttachment;
          attachment.texture = texture;
          attachment.loadAction = static_cast<MTLLoadAction>(load_action);
          attachment.storeAction = static_cast<MTLStoreAction>(store_action);
          attachment.clearStencil = clear_stencil;
          if (attachment.texture != texture ||
              attachment.loadAction != static_cast<MTLLoadAction>(load_action) ||
              attachment.storeAction !=
                  static_cast<MTLStoreAction>(store_action) ||
              attachment.clearStencil != clear_stencil) {
            CAMLreturn(result_error_text(
                "Metal changed checked Metal 4 stencil attachment properties"));
          }
          [textures addObject:texture];
        }
        if (descriptor.renderTargetWidth != static_cast<NSUInteger>(width) ||
            descriptor.renderTargetHeight != static_cast<NSUInteger>(height) ||
            descriptor.defaultRasterSampleCount != 1 ||
            descriptor.supportColorAttachmentMapping !=
                support_color_attachment_mapping ||
            descriptor.visibilityResultBuffer != visibility_result_buffer ||
            descriptor.visibilityResultType != visibility_result_type) {
          CAMLreturn(result_error_text(
              "Metal changed checked Metal 4 render-pass properties"));
        }
        id<MTL4RenderCommandEncoder> encoder =
            [state.commandBuffer renderCommandEncoderWithDescriptor:descriptor];
        if (encoder == nil || encoder.commandBuffer != state.commandBuffer) {
          CAMLreturn(result_error_text(
              "Metal failed to create a checked Metal 4 render encoder"));
        }
        if (expected_label != nil) {
          encoder.label = expected_label;
          if (![encoder.label isEqualToString:expected_label]) {
            [encoder endEncoding];
            CAMLreturn(result_error_text(
                "Metal changed the checked Metal 4 render-encoder label"));
          }
        }
        const NSUInteger tile_width = encoder.tileWidth;
        const NSUInteger tile_height = encoder.tileHeight;
        if (tile_width == 0 || tile_height == 0 ||
            tile_width > static_cast<NSUInteger>(Max_long) ||
            tile_height > static_cast<NSUInteger>(Max_long)) {
          [encoder endEncoding];
          CAMLreturn(result_error_text(
              "Metal returned invalid render-encoder tile dimensions"));
        }
        for (id<MTLTexture> texture in textures) {
          [state retainEncodedObject:texture];
        }
        if (visibility_result_buffer != nil) {
          [state retainEncodedObject:visibility_result_buffer];
        }
        raw = allocate_handle(encoder, Handle_kind::Render_encoder4);
        created = caml_alloc_tuple(3);
        Store_field(created, 0, raw);
        Store_field(created, 1,
                    Val_long(static_cast<intnat>(tile_width)));
        Store_field(created, 2,
                    Val_long(static_cast<intnat>(tile_height)));
        CAMLreturn(result_ok(created));
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_pipeline(
    value raw_encoder, value raw_buffer, value raw_pipeline) {
  CAMLparam3(raw_encoder, raw_buffer, raw_pipeline);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *state =
            command_buffer4_state_of_handle(raw_buffer);
        id<MTLRenderPipelineState> pipeline =
            object_of_handle(raw_pipeline, Handle_kind::Render_pipeline);
        if (encoder.commandBuffer != state.commandBuffer ||
            pipeline.device.registryID != state.commandBuffer.device.registryID) {
          CAMLreturn(result_error_text(
              "Metal 4 render pipeline belongs to a different command graph"));
        }
        [encoder setRenderPipelineState:pipeline];
        [state retainEncodedObject:pipeline];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_depth_stencil(
    value raw_encoder, value raw_buffer, value raw_state) {
  CAMLparam3(raw_encoder, raw_buffer, raw_state);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        id<MTLDepthStencilState> state = nil;
        if (Is_block(raw_state)) {
          state = object_of_handle(Field(raw_state, 0),
                                   Handle_kind::Depth_stencil);
          if (state.device.registryID !=
              command_buffer.commandBuffer.device.registryID) {
            CAMLreturn(result_error_text(
                "Metal 4 depth/stencil state belongs to another device"));
          }
        }
        if (encoder.commandBuffer != command_buffer.commandBuffer) {
          CAMLreturn(result_error_text(
              "Metal 4 depth/stencil encoder belongs to another buffer"));
        }
        [encoder setDepthStencilState:state];
        if (state != nil) {
          [command_buffer retainEncodedObject:state];
        }
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_stencil_reference(
    value raw_encoder, value raw_buffer, value raw_reference) {
  CAMLparam3(raw_encoder, raw_buffer, raw_reference);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        if (encoder.commandBuffer != command_buffer.commandBuffer) {
          CAMLreturn(result_error_text(
              "Metal 4 stencil-reference encoder belongs to another buffer"));
        }
        [encoder setStencilReferenceValue:static_cast<std::uint32_t>(
                                              Int32_val(raw_reference))];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_stencil_references(
    value raw_encoder, value raw_buffer, value raw_front, value raw_back) {
  CAMLparam4(raw_encoder, raw_buffer, raw_front, raw_back);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        if (encoder.commandBuffer != command_buffer.commandBuffer) {
          CAMLreturn(result_error_text(
              "Metal 4 stencil-reference encoder belongs to another buffer"));
        }
        [encoder
            setStencilFrontReferenceValue:static_cast<std::uint32_t>(
                                               Int32_val(raw_front))
                       backReferenceValue:static_cast<std::uint32_t>(
                                              Int32_val(raw_back))];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_blend_color(
    value raw_encoder, value raw_buffer, value raw_color) {
  CAMLparam3(raw_encoder, raw_buffer, raw_color);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        const double red = Double_val(Field(raw_color, 0));
        const double green = Double_val(Field(raw_color, 1));
        const double blue = Double_val(Field(raw_color, 2));
        const double alpha = Double_val(Field(raw_color, 3));
        const double float_max = std::numeric_limits<float>::max();
        if (encoder.commandBuffer != command_buffer.commandBuffer ||
            !std::isfinite(red) || !std::isfinite(green) ||
            !std::isfinite(blue) || !std::isfinite(alpha) ||
            std::abs(red) > float_max || std::abs(green) > float_max ||
            std::abs(blue) > float_max || std::abs(alpha) > float_max) {
          CAMLreturn(result_error_text(
              "Metal 4 blend color is invalid for this command buffer"));
        }
        [encoder setBlendColorRed:static_cast<float>(red)
                            green:static_cast<float>(green)
                             blue:static_cast<float>(blue)
                            alpha:static_cast<float>(alpha)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

bool checked_metal4_store_action(value raw_action,
                                 MTLStoreAction *store_action) {
  if (!Is_long(raw_action)) {
    return false;
  }
  const intnat code = Long_val(raw_action);
  if (code != MTLStoreActionDontCare && code != MTLStoreActionStore) {
    return false;
  }
  *store_action = static_cast<MTLStoreAction>(code);
  return true;
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_color_store_action(
    value raw_encoder, value raw_store_action, value raw_index) {
  CAMLparam3(raw_encoder, raw_store_action, raw_index);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        MTLStoreAction store_action;
        if (!Is_long(raw_index) ||
            !checked_metal4_store_action(raw_store_action, &store_action)) {
          CAMLreturn(result_error_text(
              "Metal 4 color store-action arguments are invalid"));
        }
        const intnat index = Long_val(raw_index);
        if (index < 0 || index > 7) {
          CAMLreturn(result_error_text(
              "Metal 4 color store-action index is invalid"));
        }
        [encoder setColorStoreAction:store_action
                             atIndex:static_cast<NSUInteger>(index)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_depth_store_action(
    value raw_encoder, value raw_store_action) {
  CAMLparam2(raw_encoder, raw_store_action);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        MTLStoreAction store_action;
        if (!checked_metal4_store_action(raw_store_action, &store_action)) {
          CAMLreturn(result_error_text(
              "Metal 4 depth store-action argument is invalid"));
        }
        [encoder setDepthStoreAction:store_action];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_stencil_store_action(
    value raw_encoder, value raw_store_action) {
  CAMLparam2(raw_encoder, raw_store_action);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        MTLStoreAction store_action;
        if (!checked_metal4_store_action(raw_store_action, &store_action)) {
          CAMLreturn(result_error_text(
              "Metal 4 stencil store-action argument is invalid"));
        }
        [encoder setStencilStoreAction:store_action];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_visibility_result_mode(
    value raw_encoder, value raw_mode, value raw_offset) {
  CAMLparam3(raw_encoder, raw_mode, raw_offset);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        if (!Is_long(raw_mode) || !Is_block(raw_offset) ||
            Tag_val(raw_offset) != Custom_tag) {
          CAMLreturn(result_error_text(
              "Metal 4 visibility-result arguments are invalid"));
        }
        const intnat mode = Long_val(raw_mode);
        const std::int64_t signed_offset = Int64_val(raw_offset);
        if ((mode != MTLVisibilityResultModeDisabled &&
             mode != MTLVisibilityResultModeBoolean &&
             mode != MTLVisibilityResultModeCounting) ||
            signed_offset < 0) {
          CAMLreturn(result_error_text(
              "Metal 4 visibility-result arguments are invalid"));
        }
        const std::uint64_t offset =
            static_cast<std::uint64_t>(signed_offset);
        if (offset > std::numeric_limits<NSUInteger>::max() ||
            (offset & 7u) != 0) {
          CAMLreturn(result_error_text(
              "Metal 4 visibility-result offset is invalid"));
        }
        [encoder
            setVisibilityResultMode:static_cast<MTLVisibilityResultMode>(mode)
                               offset:static_cast<NSUInteger>(offset)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_argument_table(
    value raw_encoder, value raw_buffer, value raw_table, value raw_stages) {
  CAMLparam4(raw_encoder, raw_buffer, raw_table, raw_stages);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        const intnat stages = Long_val(raw_stages);
        if (encoder.commandBuffer != command_buffer.commandBuffer || stages <= 0 ||
            (stages & ~static_cast<intnat>(31)) != 0) {
          CAMLreturn(result_error_text(
              "Metal 4 render argument-table stages are invalid"));
        }
        id<MTL4ArgumentTable> table = nil;
        PrismelMetal4ArgumentTableState *table_state = nil;
        if (Is_block(raw_table)) {
          table_state =
              argument_table4_state_of_handle(Field(raw_table, 0));
          table = table_state.argumentTable;
          if (table.device.registryID !=
              command_buffer.commandBuffer.device.registryID) {
            CAMLreturn(result_error_text(
                "Metal 4 argument table belongs to another command graph"));
          }
        }
        [encoder setArgumentTable:table
                         atStages:static_cast<MTLRenderStages>(stages)];
        if (table_state != nil) {
          [command_buffer retainEncodedObject:table_state];
        }
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 argument tables require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_viewport(
    value raw_encoder, value raw_viewport) {
  CAMLparam2(raw_encoder, raw_viewport);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        const MTLViewport viewport = {
            Double_val(Field(raw_viewport, 0)),
            Double_val(Field(raw_viewport, 1)),
            Double_val(Field(raw_viewport, 2)),
            Double_val(Field(raw_viewport, 3)),
            Double_val(Field(raw_viewport, 4)),
            Double_val(Field(raw_viewport, 5)),
        };
        [encoder setViewport:viewport];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
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

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_depth_bias(
    value raw_encoder, value raw_bias) {
  CAMLparam2(raw_encoder, raw_bias);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        float depth_bias = 0.0f;
        float slope_scale = 0.0f;
        float clamp = 0.0f;
        if (!checked_ocaml_float32(Field(raw_bias, 0), &depth_bias) ||
            !checked_ocaml_float32(Field(raw_bias, 1), &slope_scale) ||
            !checked_ocaml_float32(Field(raw_bias, 2), &clamp)) {
          CAMLreturn(result_error_text("Metal 4 depth bias is invalid"));
        }
        [encoder setDepthBias:depth_bias slopeScale:slope_scale clamp:clamp];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_depth_test_bounds(
    value raw_encoder, value raw_bounds) {
  CAMLparam2(raw_encoder, raw_bounds);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        const double minimum = Double_val(Field(raw_bounds, 0));
        const double maximum = Double_val(Field(raw_bounds, 1));
        if (!std::isfinite(minimum) || !std::isfinite(maximum) ||
            minimum < 0.0 || minimum > 1.0 || maximum < 0.0 ||
            maximum > 1.0 || minimum > maximum) {
          CAMLreturn(result_error_text(
              "Metal 4 depth-test bounds are invalid"));
        }
        if ((minimum != 0.0 || maximum != 1.0) &&
            ![encoder.commandBuffer.device
                supportsFamily:MTLGPUFamilyApple10]) {
          CAMLreturn(result_error_text(
              "active Metal 4 depth-test bounds require Apple GPU family 10"));
        }
        [encoder setDepthTestMinBound:static_cast<float>(minimum)
                              maxBound:static_cast<float>(maximum)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_scissor_rect(
    value raw_encoder, value raw_rect) {
  CAMLparam2(raw_encoder, raw_rect);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        MTLScissorRect rect = {};
        if (!checked_metal4_scissor_rect(raw_rect, &rect)) {
          CAMLreturn(result_error_text(
              "Metal 4 scissor rectangle is invalid"));
        }
        [encoder setScissorRect:rect];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_scissor_rects(
    value raw_encoder, value raw_rects) {
  CAMLparam2(raw_encoder, raw_rects);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        const mlsize_t count = Wosize_val(raw_rects);
        if (count == 0 || count > 16) {
          CAMLreturn(result_error_text(
              "Metal 4 scissor-rectangle count is invalid"));
        }
        std::array<MTLScissorRect, 16> rects{};
        for (mlsize_t index = 0; index < count; ++index) {
          if (!checked_metal4_scissor_rect(Field(raw_rects, index),
                                           &rects[index])) {
            CAMLreturn(result_error_text(
                "Metal 4 scissor rectangle is invalid"));
          }
        }
        [encoder setScissorRects:rects.data()
                           count:static_cast<NSUInteger>(count)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_viewports(
    value raw_encoder, value raw_viewports) {
  CAMLparam2(raw_encoder, raw_viewports);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        const mlsize_t count = Wosize_val(raw_viewports);
        if (count == 0 || count > 16) {
          CAMLreturn(result_error_text(
              "Metal 4 viewport count is invalid"));
        }
        std::array<MTLViewport, 16> viewports{};
        for (mlsize_t index = 0; index < count; ++index) {
          if (!checked_metal4_viewport(Field(raw_viewports, index),
                                       &viewports[index])) {
            CAMLreturn(result_error_text("Metal 4 viewport is invalid"));
          }
        }
        [encoder setViewports:viewports.data()
                        count:static_cast<NSUInteger>(count)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_vertex_amplification_count(
    value raw_encoder, value raw_buffer, value raw_count,
    value raw_mappings) {
  CAMLparam4(raw_encoder, raw_buffer, raw_count, raw_mappings);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        const intnat count = Long_val(raw_count);
        if (encoder.commandBuffer != command_buffer.commandBuffer || count < 1 ||
            count > 2) {
          CAMLreturn(result_error_text(
              "Metal 4 vertex amplification arguments are invalid"));
        }
        std::array<MTLVertexAmplificationViewMapping, 2> mappings{};
        const MTLVertexAmplificationViewMapping *mapping_pointer = nullptr;
        if (Is_block(raw_mappings)) {
          value raw_mapping_array = Field(raw_mappings, 0);
          if (Wosize_val(raw_mapping_array) !=
              static_cast<mlsize_t>(count)) {
            CAMLreturn(result_error_text(
                "Metal 4 vertex amplification mapping count is invalid"));
          }
          for (intnat index = 0; index < count; ++index) {
            value raw_mapping =
                Field(raw_mapping_array, static_cast<mlsize_t>(index));
            const std::int64_t viewport_offset =
                Int64_val(Field(raw_mapping, 0));
            const std::int64_t render_target_offset =
                Int64_val(Field(raw_mapping, 1));
            if (viewport_offset < 0 || render_target_offset < 0 ||
                static_cast<std::uint64_t>(viewport_offset) >
                    std::numeric_limits<std::uint32_t>::max() ||
                static_cast<std::uint64_t>(render_target_offset) >
                    std::numeric_limits<std::uint32_t>::max()) {
              CAMLreturn(result_error_text(
                  "Metal 4 vertex amplification mapping is out of range"));
            }
            MTLVertexAmplificationViewMapping &mapping =
                mappings[static_cast<std::size_t>(index)];
            mapping.viewportArrayIndexOffset =
                static_cast<std::uint32_t>(viewport_offset);
            mapping.renderTargetArrayIndexOffset =
                static_cast<std::uint32_t>(render_target_offset);
          }
          mapping_pointer = mappings.data();
        }
        [encoder
            setVertexAmplificationCount:static_cast<NSUInteger>(count)
                             viewMappings:mapping_pointer];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
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

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_set_color_attachment_map(
    value raw_encoder, value raw_buffer, value raw_map) {
  CAMLparam3(raw_encoder, raw_buffer, raw_map);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        if (encoder.commandBuffer != command_buffer.commandBuffer) {
          CAMLreturn(result_error_text(
              "Metal 4 color-attachment map belongs to another command buffer"));
        }
        std::array<NSUInteger, 8> expected_mapping{};
        for (NSUInteger index = 0; index < expected_mapping.size(); ++index) {
          expected_mapping[index] = index;
        }
        if (Is_block(raw_map)) {
          value raw_indices = Field(raw_map, 0);
          const mlsize_t count = Wosize_val(raw_indices);
          if (count == 0 || count > 8) {
            CAMLreturn(result_error_text(
                "Metal 4 color-attachment mapping count is invalid"));
          }
          std::array<bool, 8> physical_indices_seen{};
          for (mlsize_t logical_index = 0; logical_index < count;
               ++logical_index) {
            const intnat physical_index =
                Long_val(Field(raw_indices, logical_index));
            if (physical_index < 0 ||
                physical_index >= static_cast<intnat>(count) ||
                physical_indices_seen[
                    static_cast<std::size_t>(physical_index)]) {
              CAMLreturn(result_error_text(
                  "Metal 4 color-attachment mapping is not a permutation"));
            }
            physical_indices_seen[static_cast<std::size_t>(physical_index)] =
                true;
            expected_mapping[logical_index] =
                static_cast<NSUInteger>(physical_index);
          }
        }
        NSString *validation_failure = nil;
        MTLLogicalToPhysicalColorAttachmentMap *mapping =
            new_checked_color_attachment_map(expected_mapping,
                                             &validation_failure);
        if (mapping == nil) {
          CAMLreturn(result_error(validation_failure));
        }
        [encoder setColorAttachmentMap:mapping];
        [command_buffer retainEncodedObject:mapping];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
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

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_draw_primitives(
    value raw_encoder, value raw_buffer, value raw_tables, value raw_draw) {
  CAMLparam4(raw_encoder, raw_buffer, raw_tables, raw_draw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        const intnat primitive = Long_val(Field(raw_draw, 0));
        const intnat start = Long_val(Field(raw_draw, 1));
        const intnat count = Long_val(Field(raw_draw, 2));
        if (encoder.commandBuffer != command_buffer.commandBuffer ||
            primitive < 0 || primitive > 4 || start < 0 || count <= 0) {
          CAMLreturn(result_error_text(
              "Metal 4 primitive draw arguments are invalid"));
        }
        NSString *validation_failure = nil;
        if (!retain_metal4_render_argument_tables(
                raw_tables, command_buffer, &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        [encoder drawPrimitives:static_cast<MTLPrimitiveType>(primitive)
                     vertexStart:static_cast<NSUInteger>(start)
                     vertexCount:static_cast<NSUInteger>(count)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_draw_primitives_instanced(
    value raw_encoder, value raw_buffer, value raw_tables, value raw_draw) {
  CAMLparam4(raw_encoder, raw_buffer, raw_tables, raw_draw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        const intnat primitive = Long_val(Field(raw_draw, 0));
        const intnat start = Long_val(Field(raw_draw, 1));
        const intnat count = Long_val(Field(raw_draw, 2));
        const intnat instance_count = Long_val(Field(raw_draw, 3));
        const intnat base_instance = Long_val(Field(raw_draw, 4));
        if (encoder.commandBuffer != command_buffer.commandBuffer ||
            primitive < 0 || primitive > 4 || start < 0 || count <= 0 ||
            instance_count <= 0 || base_instance < 0 ||
            static_cast<NSUInteger>(start) >
                std::numeric_limits<NSUInteger>::max() -
                    (static_cast<NSUInteger>(count) - 1) ||
            static_cast<NSUInteger>(base_instance) >
                std::numeric_limits<NSUInteger>::max() -
                    (static_cast<NSUInteger>(instance_count) - 1)) {
          CAMLreturn(result_error_text(
              "Metal 4 instanced primitive-draw arguments are invalid"));
        }
        NSString *validation_failure = nil;
        if (!retain_metal4_render_argument_tables(
                raw_tables, command_buffer, &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        [encoder drawPrimitives:static_cast<MTLPrimitiveType>(primitive)
                     vertexStart:static_cast<NSUInteger>(start)
                     vertexCount:static_cast<NSUInteger>(count)
                   instanceCount:static_cast<NSUInteger>(instance_count)
                    baseInstance:static_cast<NSUInteger>(base_instance)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 instanced draws require macOS 26"));
  }
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
caml_prismel_metal_command4_render_encoder_draw_indexed_primitives(
    value raw_encoder, value raw_buffer, value raw_tables,
    value raw_index_buffer, value raw_draw) {
  CAMLparam5(raw_encoder, raw_buffer, raw_tables, raw_index_buffer, raw_draw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        id<MTLBuffer> index_buffer =
            object_of_handle(raw_index_buffer, Handle_kind::Buffer);
        PrismelMetal4IndexedDraw draw;
        NSString *validation_failure = nil;
        if (encoder.commandBuffer != command_buffer.commandBuffer ||
            !prismel_metal4_indexed_draw(raw_draw, index_buffer, command_buffer,
                                         &draw, &validation_failure)) {
          CAMLreturn(result_error(
              validation_failure != nil
                  ? validation_failure
                  : @"Metal 4 indexed encoder belongs to another buffer"));
        }
        if (!retain_metal4_render_argument_tables(
                raw_tables, command_buffer, &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        [command_buffer retainEncodedObject:index_buffer];
        [encoder
            drawIndexedPrimitives:draw.primitive
                       indexCount:draw.index_count
                        indexType:draw.index_type
                      indexBuffer:draw.index_address
                indexBufferLength:draw.index_length];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 indexed draws require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_draw_indexed_primitives_instanced(
    value raw_encoder, value raw_buffer, value raw_tables,
    value raw_index_buffer, value raw_draw) {
  CAMLparam5(raw_encoder, raw_buffer, raw_tables, raw_index_buffer, raw_draw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        id<MTLBuffer> index_buffer =
            object_of_handle(raw_index_buffer, Handle_kind::Buffer);
        PrismelMetal4IndexedDraw draw;
        NSString *validation_failure = nil;
        const intnat instance_count = Long_val(Field(raw_draw, 4));
        const intnat base_vertex = Long_val(Field(raw_draw, 5));
        const intnat base_instance = Long_val(Field(raw_draw, 6));
        if (encoder.commandBuffer != command_buffer.commandBuffer ||
            !prismel_metal4_indexed_draw(raw_draw, index_buffer, command_buffer,
                                         &draw, &validation_failure) ||
            instance_count <= 0 || base_instance < 0 ||
            static_cast<NSUInteger>(base_instance) >
                std::numeric_limits<NSUInteger>::max() -
                    (static_cast<NSUInteger>(instance_count) - 1)) {
          CAMLreturn(result_error(
              validation_failure != nil
                  ? validation_failure
                  : @"Metal 4 instanced indexed-draw arguments are invalid"));
        }
        if (!retain_metal4_render_argument_tables(
                raw_tables, command_buffer, &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        [command_buffer retainEncodedObject:index_buffer];
        [encoder drawIndexedPrimitives:draw.primitive
                             indexCount:draw.index_count
                              indexType:draw.index_type
                            indexBuffer:draw.index_address
                      indexBufferLength:draw.index_length
                          instanceCount:static_cast<NSUInteger>(instance_count)
                             baseVertex:static_cast<NSInteger>(base_vertex)
                           baseInstance:static_cast<NSUInteger>(base_instance)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 instanced draws require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_draw_primitives_indirect(
    value raw_encoder, value raw_buffer, value raw_tables,
    value raw_indirect_buffer, value raw_draw) {
  CAMLparam5(raw_encoder, raw_buffer, raw_tables, raw_indirect_buffer, raw_draw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        id<MTLBuffer> indirect_buffer =
            object_of_handle(raw_indirect_buffer, Handle_kind::Buffer);
        const intnat primitive = Long_val(Field(raw_draw, 0));
        const std::int64_t indirect_offset = Int64_val(Field(raw_draw, 1));
        PrismelMetal4BufferRange indirect_range;
        NSString *validation_failure = nil;
        if (encoder.commandBuffer != command_buffer.commandBuffer ||
            primitive < 0 || primitive > 4 ||
            !prismel_metal4_explicit_buffer_range(
                indirect_buffer, command_buffer, indirect_offset, 16, 4,
                &indirect_range, &validation_failure)) {
          CAMLreturn(result_error(
              validation_failure != nil
                  ? validation_failure
                  : @"Metal 4 indirect primitive-draw arguments are invalid"));
        }
        if (!retain_metal4_render_argument_tables(
                raw_tables, command_buffer, &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        [command_buffer retainEncodedObject:indirect_buffer];
        [encoder drawPrimitives:static_cast<MTLPrimitiveType>(primitive)
                    indirectBuffer:indirect_range.address];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 indirect draws require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_draw_indexed_primitives_indirect(
    value raw_encoder, value raw_buffer, value raw_tables, value raw_buffers,
    value raw_draw) {
  CAMLparam5(raw_encoder, raw_buffer, raw_tables, raw_buffers, raw_draw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        id<MTLBuffer> index_buffer =
            object_of_handle(Field(raw_buffers, 0), Handle_kind::Buffer);
        id<MTLBuffer> indirect_buffer =
            object_of_handle(Field(raw_buffers, 1), Handle_kind::Buffer);
        const intnat primitive = Long_val(Field(raw_draw, 0));
        const intnat index_type = Long_val(Field(raw_draw, 1));
        const std::int64_t index_offset = Int64_val(Field(raw_draw, 2));
        const std::int64_t index_length = Int64_val(Field(raw_draw, 3));
        const std::int64_t indirect_offset = Int64_val(Field(raw_draw, 4));
        PrismelMetal4BufferRange index_range;
        PrismelMetal4BufferRange indirect_range;
        NSString *validation_failure = nil;
        const NSUInteger index_alignment = index_type == 0 ? 2 : 4;
        if (encoder.commandBuffer != command_buffer.commandBuffer ||
            primitive < 0 || primitive > 4 || index_type < 0 ||
            index_type > 1 ||
            !prismel_metal4_explicit_buffer_range(
                index_buffer, command_buffer, index_offset, index_length,
                index_alignment, &index_range, &validation_failure) ||
            !prismel_metal4_explicit_buffer_range(
                indirect_buffer, command_buffer, indirect_offset, 20, 4,
                &indirect_range, &validation_failure)) {
          CAMLreturn(result_error(
              validation_failure != nil
                  ? validation_failure
                  : @"Metal 4 indexed indirect-draw arguments are invalid"));
        }
        if (!retain_metal4_render_argument_tables(
                raw_tables, command_buffer, &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        [command_buffer retainEncodedObject:index_buffer];
        [command_buffer retainEncodedObject:indirect_buffer];
        [encoder drawIndexedPrimitives:static_cast<MTLPrimitiveType>(primitive)
                                 indexType:static_cast<MTLIndexType>(index_type)
                               indexBuffer:index_range.address
                         indexBufferLength:index_range.length
                              indirectBuffer:indirect_range.address];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 indirect draws require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_draw_mesh_threadgroups(
    value raw_encoder, value raw_buffer, value raw_tables, value raw_draw) {
  CAMLparam4(raw_encoder, raw_buffer, raw_tables, raw_draw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        intnat dimensions[9];
        for (mlsize_t index = 0; index < 9; ++index) {
          dimensions[index] = Long_val(Field(raw_draw, index));
          if (dimensions[index] <= 0) {
            CAMLreturn(result_error_text(
                "Metal 4 mesh draw dimensions are invalid"));
          }
        }
        if (encoder.commandBuffer != command_buffer.commandBuffer) {
          CAMLreturn(result_error_text(
              "Metal 4 mesh draw belongs to another command graph"));
        }
        NSString *validation_failure = nil;
        if (!retain_metal4_render_argument_tables(
                raw_tables, command_buffer, &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        [encoder
                  drawMeshThreadgroups:
                      MTLSizeMake(static_cast<NSUInteger>(dimensions[0]),
                                  static_cast<NSUInteger>(dimensions[1]),
                                  static_cast<NSUInteger>(dimensions[2]))
             threadsPerObjectThreadgroup:
                 MTLSizeMake(static_cast<NSUInteger>(dimensions[3]),
                             static_cast<NSUInteger>(dimensions[4]),
                             static_cast<NSUInteger>(dimensions[5]))
               threadsPerMeshThreadgroup:
                   MTLSizeMake(static_cast<NSUInteger>(dimensions[6]),
                               static_cast<NSUInteger>(dimensions[7]),
                               static_cast<NSUInteger>(dimensions[8]))];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 mesh draws require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_command4_render_encoder_dispatch_threads_per_tile(
    value raw_encoder, value raw_buffer, value raw_tables, value raw_threads) {
  CAMLparam4(raw_encoder, raw_buffer, raw_tables, raw_threads);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw_encoder, Handle_kind::Render_encoder4);
        PrismelMetal4CommandBufferState *command_buffer =
            command_buffer4_state_of_handle(raw_buffer);
        const intnat width = Long_val(Field(raw_threads, 0));
        const intnat height = Long_val(Field(raw_threads, 1));
        const intnat depth = Long_val(Field(raw_threads, 2));
        if (encoder.commandBuffer != command_buffer.commandBuffer || width <= 0 ||
            height <= 0 || depth != 1 ||
            static_cast<NSUInteger>(width) > encoder.tileWidth ||
            static_cast<NSUInteger>(height) > encoder.tileHeight) {
          CAMLreturn(result_error_text(
              "Metal 4 tile-dispatch dimensions are invalid"));
        }
        NSString *validation_failure = nil;
        if (!retain_metal4_render_argument_tables(
                raw_tables, command_buffer, &validation_failure)) {
          CAMLreturn(result_error(validation_failure));
        }
        [encoder dispatchThreadsPerTile:
                     MTLSizeMake(static_cast<NSUInteger>(width),
                                 static_cast<NSUInteger>(height), 1)];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 tile dispatch requires macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_render_encoder_end(
    value raw) {
  CAMLparam1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4RenderCommandEncoder> encoder =
            object_of_handle(raw, Handle_kind::Render_encoder4);
        [encoder endEncoding];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_queue_commit(
    value raw_queue, value raw_buffers) {
  CAMLparam2(raw_queue, raw_buffers);
  CAMLlocal1(raw);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      @try {
        id<MTL4CommandQueue> queue =
            object_of_handle(raw_queue, Handle_kind::Command_queue4);
        const mlsize_t count = Wosize_val(raw_buffers);
        if (count == 0 || count > 64) {
          CAMLreturn(result_error_text(
              "Metal 4 submissions require between one and 64 command buffers"));
        }
        std::vector<id<MTL4CommandBuffer>> command_buffers;
        command_buffers.reserve(count);
        NSMutableArray<PrismelMetal4CommandBufferState *> *states =
            [[NSMutableArray alloc] initWithCapacity:count];
        for (mlsize_t index = 0; index < count; ++index) {
          PrismelMetal4CommandBufferState *state =
              command_buffer4_state_of_handle(Field(raw_buffers, index));
          if (state.commandBuffer.device.registryID != queue.device.registryID) {
            CAMLreturn(result_error_text(
                "Metal 4 command buffer belongs to a different queue device"));
          }
          command_buffers.push_back(state.commandBuffer);
          [states addObject:state];
        }
        PrismelMetal4SubmissionState *submission =
            [[PrismelMetal4SubmissionState alloc] initWithQueue:queue
                                                       buffers:states];
        MTL4CommitOptions *options = [[MTL4CommitOptions alloc] init];
        [options addFeedbackHandler:^(id<MTL4CommitFeedback> feedback) {
          [submission finishWithFeedback:feedback];
        }];
        [queue commit:command_buffers.data()
                 count:command_buffers.size()
               options:options];
        raw = allocate_handle(submission, Handle_kind::Submission4);
        CAMLreturn(result_ok(raw));
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value caml_prismel_metal_command4_submission_wait(
    value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      PrismelMetal4SubmissionState *submission =
          submission4_state_of_handle(raw);
      __block NSError *gpu_error = nil;
      __block NSString *wait_failure = nil;
      caml_release_runtime_system();
      @try {
        gpu_error = [submission waitUntilCompleted];
      } @catch (NSException *exception) {
        wait_failure = [exception.reason copy];
      }
      caml_acquire_runtime_system();
      if (wait_failure != nil) {
        result = result_error(wait_failure);
      } else if (gpu_error != nil) {
        result = result_error(error_description(
            gpu_error, @"Metal 4 command submission failed"));
      } else {
        result = result_unit();
      }
      CAMLreturn(result);
    }
    CAMLreturn(result_error_text("Metal 4 commands require macOS 26"));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_placement_mapping_queue_create(value raw_device,
                                                   value raw_label) {
  CAMLparam2(raw_device, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLDevice> device =
          object_of_handle(raw_device, Handle_kind::Device);
      if (!device_supports_placement_sparse(device)) {
        CAMLreturn(result_error_text(
            "device does not support Metal 4 placement mappings"));
      }
      if (@available(macOS 26.0, *)) {
        MTL4CommandQueueDescriptor *descriptor =
            [[MTL4CommandQueueDescriptor alloc] init];
        if (Is_block(raw_label)) {
          NSString *label = string_from_ocaml(Field(raw_label, 0));
          if (label == nil) {
            CAMLreturn(result_error_text(
                "placement-mapping queue label is not valid UTF-8"));
          }
          descriptor.label = label;
        }
        NSError *error = nil;
        id<MTL4CommandQueue> queue =
            [device newMTL4CommandQueueWithDescriptor:descriptor error:&error];
        if (queue == nil || queue.device.registryID != device.registryID ||
            (descriptor.label != nil &&
             ![queue.label isEqualToString:descriptor.label]) ||
            ![queue respondsToSelector:
                @selector(updateBufferMappings:heap:operations:count:)] ||
            ![queue respondsToSelector:
                @selector(updateTextureMappings:heap:operations:count:)] ||
            ![queue respondsToSelector:@selector(commit:count:)] ||
            ![queue respondsToSelector:@selector(signalEvent:value:)]) {
          CAMLreturn(result_error(error_description(
              error, @"Metal rejected the placement-mapping queue")));
        }
        raw = allocate_handle(queue, Handle_kind::Placement_mapping_queue);
        CAMLreturn(result_ok(raw));
      }
      CAMLreturn(result_error_text(
          "Metal 4 placement mappings require macOS 26"));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value
caml_prismel_metal_placement_mapping_queue_label(value raw) {
  CAMLparam1(raw);
  CAMLlocal1(result);
  @autoreleasepool {
    if (@available(macOS 26.0, *)) {
      id<MTL4CommandQueue> queue = placement_mapping_queue_of_handle(raw);
      result = copy_optional_string(queue.label);
      CAMLreturn(result);
    }
    caml_failwith("Metal 4 placement mappings require macOS 26");
  }
}

extern "C" CAMLprim value
caml_prismel_metal_placement_mapping_update_buffer(
    value raw_queue, value raw_buffer, value raw_heap, value raw_mode,
    value raw_operation) {
  CAMLparam5(raw_queue, raw_buffer, raw_heap, raw_mode, raw_operation);
  @autoreleasepool {
    @try {
      if (@available(macOS 26.0, *)) {
        id<MTL4CommandQueue> queue =
            placement_mapping_queue_of_handle(raw_queue);
        id<MTLBuffer> buffer =
            object_of_handle(raw_buffer, Handle_kind::Buffer);
        id<MTLHeap> heap = Is_block(raw_heap)
                               ? object_of_handle(Field(raw_heap, 0),
                                                  Handle_kind::Heap)
                               : nil;
        const intnat mode = Long_val(raw_mode);
        const std::int64_t range_offset =
            Int64_val(Field(raw_operation, 0));
        const std::int64_t range_length =
            Int64_val(Field(raw_operation, 1));
        const std::int64_t heap_offset =
            Int64_val(Field(raw_operation, 2));
        const int page_size = Int_val(Field(raw_operation, 3));
        const int sparse_tier = buffer_sparse_tier_or_unavailable(buffer);
        if (!device_supports_placement_sparse(queue.device) ||
            queue.device.registryID != buffer.device.registryID ||
            (heap != nil &&
             queue.device.registryID != heap.device.registryID) ||
            (mode != MTLSparseTextureMappingModeMap &&
             mode != MTLSparseTextureMappingModeUnmap) ||
            (mode == MTLSparseTextureMappingModeMap && heap == nil) ||
            (mode == MTLSparseTextureMappingModeUnmap && heap != nil) ||
            (heap != nil && heap.type != MTLHeapTypePlacement) ||
            (heap != nil &&
             (heap.storageMode != buffer.storageMode ||
              heap.cpuCacheMode != buffer.cpuCacheMode)) ||
            sparse_tier == MTLBufferSparseTierNone ||
            sparse_tier > MTLBufferSparseTier1 ||
            !valid_sparse_page_size(page_size) || range_offset < 0 ||
            range_length <= 0 || heap_offset < 0) {
          CAMLreturn(result_error_text(
              "placement sparse buffer mapping arguments are invalid"));
        }
        const NSUInteger page_bytes = [queue.device
            sparseTileSizeInBytesForSparsePageSize:
                static_cast<MTLSparsePageSize>(page_size)];
        if (page_bytes == 0 ||
            static_cast<std::uint64_t>(range_offset) >
                std::numeric_limits<NSUInteger>::max() ||
            static_cast<std::uint64_t>(range_length) >
                std::numeric_limits<NSUInteger>::max() ||
            static_cast<std::uint64_t>(heap_offset) >
                std::numeric_limits<NSUInteger>::max()) {
          CAMLreturn(result_error_text(
              "placement sparse buffer mapping values exceed native limits"));
        }
        const NSUInteger buffer_tiles =
            buffer.length / page_bytes +
            (buffer.length % page_bytes == 0 ? 0 : 1);
        const NSUInteger virtual_offset =
            static_cast<NSUInteger>(range_offset);
        const NSUInteger virtual_length =
            static_cast<NSUInteger>(range_length);
        const NSUInteger physical_offset =
            static_cast<NSUInteger>(heap_offset);
        if (virtual_offset > buffer_tiles ||
            virtual_length > buffer_tiles - virtual_offset ||
            (heap != nil &&
             (physical_offset > heap.size / page_bytes ||
              virtual_length > heap.size / page_bytes - physical_offset))) {
          CAMLreturn(result_error_text(
              "placement sparse buffer mapping exceeds its resource"));
        }
        const MTL4UpdateSparseBufferMappingOperation operation = {
            static_cast<MTLSparseTextureMappingMode>(mode),
            NSMakeRange(virtual_offset, virtual_length), physical_offset};
        NSString *failure = nil;
        const bool completed = synchronize_placement_mapping(
            queue,
            ^{
              placement_mapping_operation_count.fetch_add(
                  1, std::memory_order_relaxed);
              [queue updateBufferMappings:buffer
                                      heap:heap
                                operations:&operation
                                     count:1];
            },
            &failure);
        if (!completed) {
          CAMLreturn(result_error(failure));
        }
        CAMLreturn(result_unit());
      }
      CAMLreturn(result_error_text(
          "Metal 4 placement mappings require macOS 26"));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value
caml_prismel_metal_placement_mapping_update_texture(
    value raw_queue, value raw_texture, value raw_heap, value raw_operation) {
  CAMLparam4(raw_queue, raw_texture, raw_heap, raw_operation);
  @autoreleasepool {
    @try {
      if (@available(macOS 26.0, *)) {
        id<MTL4CommandQueue> queue =
            placement_mapping_queue_of_handle(raw_queue);
        id<MTLTexture> texture =
            object_of_handle(raw_texture, Handle_kind::Texture);
        id<MTLHeap> heap = Is_block(raw_heap)
                               ? object_of_handle(Field(raw_heap, 0),
                                                  Handle_kind::Heap)
                               : nil;
        const intnat mode = Long_val(Field(raw_operation, 0));
        value raw_region = Field(raw_operation, 1);
        const intnat x = Long_val(Field(raw_region, 0));
        const intnat y = Long_val(Field(raw_region, 1));
        const intnat z = Long_val(Field(raw_region, 2));
        const intnat width = Long_val(Field(raw_region, 3));
        const intnat height = Long_val(Field(raw_region, 4));
        const intnat depth = Long_val(Field(raw_region, 5));
        const intnat level = Long_val(Field(raw_operation, 2));
        const intnat slice = Long_val(Field(raw_operation, 3));
        const std::int64_t heap_offset =
            Int64_val(Field(raw_operation, 4));
        const int page_size = Int_val(Field(raw_operation, 5));
        if (!device_supports_placement_sparse(queue.device) ||
            queue.device.registryID != texture.device.registryID ||
            (heap != nil &&
             queue.device.registryID != heap.device.registryID) ||
            !texture_is_sparse_resource(texture) ||
            (mode != MTLSparseTextureMappingModeMap &&
             mode != MTLSparseTextureMappingModeUnmap) ||
            (mode == MTLSparseTextureMappingModeMap && heap == nil) ||
            (mode == MTLSparseTextureMappingModeUnmap && heap != nil) ||
            (heap != nil && heap.type != MTLHeapTypePlacement) ||
            (heap != nil &&
             (heap.storageMode != texture.storageMode ||
              heap.cpuCacheMode != texture.cpuCacheMode)) ||
            !valid_sparse_page_size(page_size) || x < 0 || y < 0 || z < 0 ||
            width <= 0 || height <= 0 || depth <= 0 || level < 0 ||
            slice < 0 || heap_offset < 0 ||
            static_cast<NSUInteger>(level) >= texture.mipmapLevelCount ||
            static_cast<NSUInteger>(slice) >= texture_slice_count(texture)) {
          CAMLreturn(result_error_text(
              "placement sparse texture mapping arguments are invalid"));
        }
        const auto sparse_page_size =
            static_cast<MTLSparsePageSize>(page_size);
        const NSUInteger page_bytes = [queue.device
            sparseTileSizeInBytesForSparsePageSize:sparse_page_size];
        const MTLSize tile = [queue.device
            sparseTileSizeWithTextureType:texture.textureType
                                pixelFormat:texture.pixelFormat
                                sampleCount:texture.sampleCount
                             sparsePageSize:sparse_page_size];
        const NSUInteger mip_width = std::max<NSUInteger>(1, texture.width >> level);
        const NSUInteger mip_height = std::max<NSUInteger>(1, texture.height >> level);
        const NSUInteger mip_depth = std::max<NSUInteger>(1, texture.depth >> level);
        if (page_bytes == 0 || tile.width == 0 || tile.height == 0 ||
            tile.depth == 0 ||
            static_cast<std::uint64_t>(heap_offset) >
                std::numeric_limits<NSUInteger>::max()) {
          CAMLreturn(result_error_text(
              "placement sparse texture mapping layout is invalid"));
        }
        const NSUInteger tiles_x = mip_width / tile.width +
            (mip_width % tile.width == 0 ? 0 : 1);
        const NSUInteger tiles_y = mip_height / tile.height +
            (mip_height % tile.height == 0 ? 0 : 1);
        const NSUInteger tiles_z = mip_depth / tile.depth +
            (mip_depth % tile.depth == 0 ? 0 : 1);
        const NSUInteger ux = static_cast<NSUInteger>(x);
        const NSUInteger uy = static_cast<NSUInteger>(y);
        const NSUInteger uz = static_cast<NSUInteger>(z);
        const NSUInteger uw = static_cast<NSUInteger>(width);
        const NSUInteger uh = static_cast<NSUInteger>(height);
        const NSUInteger ud = static_cast<NSUInteger>(depth);
        const NSUInteger first_tail = texture.firstMipmapInTail;
        const bool tail = static_cast<NSUInteger>(level) == first_tail;
        if (static_cast<NSUInteger>(level) > first_tail || ux > tiles_x ||
            uw > tiles_x - ux || uy > tiles_y || uh > tiles_y - uy ||
            uz > tiles_z || ud > tiles_z - uz ||
            (tail && (ux != 0 || uy != 0 || uz != 0 || uw != 1 ||
                      uh != 1 || ud != 1)) ||
            uw > std::numeric_limits<NSUInteger>::max() / uh ||
            uw * uh > std::numeric_limits<NSUInteger>::max() / ud) {
          CAMLreturn(result_error_text(
              "placement sparse texture mapping exceeds its mip level"));
        }
        NSUInteger physical_tiles = uw * uh * ud;
        if (tail) {
          const NSUInteger tail_bytes = texture.tailSizeInBytes;
          physical_tiles = tail_bytes / page_bytes +
              (tail_bytes % page_bytes == 0 ? 0 : 1);
        }
        const NSUInteger physical_offset =
            static_cast<NSUInteger>(heap_offset);
        if (physical_tiles == 0 ||
            (heap != nil &&
             (physical_offset > heap.size / page_bytes ||
              physical_tiles > heap.size / page_bytes - physical_offset))) {
          CAMLreturn(result_error_text(
              "placement sparse texture mapping exceeds its heap"));
        }
        const MTL4UpdateSparseTextureMappingOperation operation = {
            static_cast<MTLSparseTextureMappingMode>(mode),
            MTLRegionMake3D(ux, uy, uz, uw, uh, ud),
            static_cast<NSUInteger>(level), static_cast<NSUInteger>(slice),
            physical_offset};
        NSString *failure = nil;
        const bool completed = synchronize_placement_mapping(
            queue,
            ^{
              placement_mapping_operation_count.fetch_add(
                  1, std::memory_order_relaxed);
              [queue updateTextureMappings:texture
                                       heap:heap
                                 operations:&operation
                                      count:1];
            },
            &failure);
        if (!completed) {
          CAMLreturn(result_error(failure));
        }
        CAMLreturn(result_unit());
      }
      CAMLreturn(result_error_text(
          "Metal 4 placement mappings require macOS 26"));
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_command_queue_create(
    value raw_device) {
  CAMLparam1(raw_device);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    id<MTLCommandQueue> queue = [device newCommandQueue];
    if (queue == nil) {
      CAMLreturn(result_error_text("Metal failed to create a command queue"));
    }
    raw = allocate_handle(queue, Handle_kind::Command_queue);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_command_queue_add_residency_set(
    value raw_queue, value raw_set) {
  CAMLparam2(raw_queue, raw_set);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLCommandQueue> queue =
            object_of_handle(raw_queue, Handle_kind::Command_queue);
        id<MTLResidencySet> residency_set =
            object_of_handle(raw_set, Handle_kind::Residency_set);
        [queue addResidencySet:residency_set];
        CAMLreturn(result_unit());
      } @catch (NSException *exception) {
        CAMLreturn(result_error(exception.reason));
      }
    }
    CAMLreturn(result_error_text("residency sets require macOS 15"));
  }
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
caml_prismel_metal_command_queue_remove_residency_set(
    value raw_queue, value raw_set) {
  CAMLparam2(raw_queue, raw_set);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLCommandQueue> queue =
            object_of_handle(raw_queue, Handle_kind::Command_queue);
        id<MTLResidencySet> residency_set =
            object_of_handle(raw_set, Handle_kind::Residency_set);
        [queue removeResidencySet:residency_set];
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

extern "C" CAMLprim value caml_prismel_metal_command_buffer_create(
    value raw_queue) {
  CAMLparam1(raw_queue);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLCommandQueue> queue =
        object_of_handle(raw_queue, Handle_kind::Command_queue);
    id<MTLCommandBuffer> buffer = [queue commandBuffer];
    if (buffer == nil) {
      CAMLreturn(result_error_text("Metal failed to create a command buffer"));
    }
    raw = allocate_handle(buffer, Handle_kind::Command_buffer);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_set_label(
    value raw, value raw_label) {
  CAMLparam2(raw, raw_label);
  @autoreleasepool {
    id<MTLCommandBuffer> buffer =
        object_of_handle(raw, Handle_kind::Command_buffer);
    NSString *label = string_from_ocaml(raw_label);
    if (label == nil) {
      CAMLreturn(result_error_text("command-buffer label is not valid UTF-8"));
    }
    buffer.label = label;
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value
caml_prismel_metal_command_buffer_use_residency_set(
    value raw_buffer, value raw_set) {
  CAMLparam2(raw_buffer, raw_set);
  @autoreleasepool {
    if (@available(macOS 15.0, *)) {
      @try {
        id<MTLCommandBuffer> buffer =
            object_of_handle(raw_buffer, Handle_kind::Command_buffer);
        id<MTLResidencySet> residency_set =
            object_of_handle(raw_set, Handle_kind::Residency_set);
        [buffer useResidencySet:residency_set];
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

extern "C" CAMLprim value caml_prismel_metal_command_buffer_compute_encoder(
    value raw_buffer) {
  CAMLparam1(raw_buffer);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLCommandBuffer> buffer =
        object_of_handle(raw_buffer, Handle_kind::Command_buffer);
    id<MTLComputeCommandEncoder> encoder = [buffer computeCommandEncoder];
    if (encoder == nil) {
      CAMLreturn(result_error_text("Metal failed to create a compute encoder"));
    }
    raw = allocate_handle(encoder, Handle_kind::Compute_encoder);
  }
  CAMLreturn(result_ok(raw));
}

static MTLPrimitiveAccelerationStructureDescriptor *
acceleration_triangle_descriptor_of_ocaml(value raw_descriptor) {
  id<MTLBuffer> vertex_buffer =
      object_of_handle(Field(raw_descriptor, 0), Handle_kind::Buffer);
  MTLAccelerationStructureTriangleGeometryDescriptor *geometry =
      [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
  geometry.vertexBuffer = vertex_buffer;
  geometry.vertexBufferOffset = Int64_val(Field(raw_descriptor, 1));
  geometry.vertexStride = Int64_val(Field(raw_descriptor, 2));
  geometry.triangleCount = Int64_val(Field(raw_descriptor, 3));
  value raw_index = Field(raw_descriptor, 4);
  if (Is_block(raw_index)) {
    geometry.indexBuffer =
        object_of_handle(Field(raw_index, 0), Handle_kind::Buffer);
    geometry.indexBufferOffset = Int64_val(Field(raw_descriptor, 5));
    geometry.indexType = MTLIndexTypeUInt32;
  }
  MTLPrimitiveAccelerationStructureDescriptor *descriptor =
      [MTLPrimitiveAccelerationStructureDescriptor descriptor];
  descriptor.geometryDescriptors = @[ geometry ];
  descriptor.usage = MTLAccelerationStructureUsageRefit;
  return descriptor;
}

extern "C" CAMLprim value caml_prismel_metal_acceleration_structure_sizes(
    value raw_device, value raw_descriptor) {
  CAMLparam2(raw_device, raw_descriptor);
  CAMLlocal4(result, tuple, first, second);
  CAMLlocal1(third);
  @autoreleasepool {
    @try {
      id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
      MTLAccelerationStructureSizes sizes =
          [device accelerationStructureSizesWithDescriptor:
                      acceleration_triangle_descriptor_of_ocaml(raw_descriptor)];
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

extern "C" CAMLprim value
caml_prismel_metal_command_buffer_acceleration_encoder(value raw_buffer) {
  CAMLparam1(raw_buffer);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLCommandBuffer> buffer =
        object_of_handle(raw_buffer, Handle_kind::Command_buffer);
    id<MTLAccelerationStructureCommandEncoder> encoder =
        [buffer accelerationStructureCommandEncoder];
    if (encoder == nil)
      CAMLreturn(result_error_text("Metal failed to create an acceleration encoder"));
    raw = allocate_handle(encoder, Handle_kind::Acceleration_encoder);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_acceleration_encoder_build(
    value raw_encoder, value raw_acceleration, value raw_descriptor,
    value raw_scratch, value raw_scratch_offset) {
  CAMLparam5(raw_encoder, raw_acceleration, raw_descriptor, raw_scratch,
             raw_scratch_offset);
  @autoreleasepool {
    @try {
      id<MTLAccelerationStructureCommandEncoder> encoder =
          object_of_handle(raw_encoder, Handle_kind::Acceleration_encoder);
      id<MTLAccelerationStructure> acceleration = object_of_handle(
          raw_acceleration, Handle_kind::Acceleration_structure);
      id<MTLBuffer> scratch =
          object_of_handle(raw_scratch, Handle_kind::Buffer);
      [encoder buildAccelerationStructure:acceleration
                               descriptor:acceleration_triangle_descriptor_of_ocaml(raw_descriptor)
                            scratchBuffer:scratch
                      scratchBufferOffset:Int64_val(raw_scratch_offset)];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_acceleration_encoder_refit(
    value raw_encoder, value raw_source, value raw_destination,
    value raw_descriptor, value raw_scratch, value raw_scratch_offset) {
  CAMLparam5(raw_encoder, raw_source, raw_destination, raw_descriptor,
             raw_scratch);
  CAMLxparam1(raw_scratch_offset);
  @autoreleasepool {
    @try {
      id<MTLAccelerationStructureCommandEncoder> encoder =
          object_of_handle(raw_encoder, Handle_kind::Acceleration_encoder);
      id<MTLAccelerationStructure> source = object_of_handle(
          raw_source, Handle_kind::Acceleration_structure);
      id<MTLAccelerationStructure> destination = object_of_handle(
          raw_destination, Handle_kind::Acceleration_structure);
      id<MTLBuffer> scratch =
          object_of_handle(raw_scratch, Handle_kind::Buffer);
      [encoder refitAccelerationStructure:source
                              descriptor:acceleration_triangle_descriptor_of_ocaml(raw_descriptor)
                             destination:destination
                           scratchBuffer:scratch
                     scratchBufferOffset:Int64_val(raw_scratch_offset)];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_acceleration_encoder_refit_bytecode(
    value *argv, int argn) {
  (void)argn;
  return caml_prismel_metal_acceleration_encoder_refit(
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
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
caml_prismel_metal_acceleration_encoder_write_compacted_size(
    value raw_encoder, value raw_source, value raw_buffer, value raw_offset) {
  CAMLparam4(raw_encoder, raw_source, raw_buffer, raw_offset);
  @autoreleasepool {
    @try {
      id<MTLAccelerationStructureCommandEncoder> encoder =
          object_of_handle(raw_encoder, Handle_kind::Acceleration_encoder);
      [encoder writeCompactedAccelerationStructureSize:
                   object_of_handle(raw_source, Handle_kind::Acceleration_structure)
                                             toBuffer:
                   object_of_handle(raw_buffer, Handle_kind::Buffer)
                                               offset:Int64_val(raw_offset)];
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

extern "C" CAMLprim value
caml_prismel_metal_acceleration_encoder_end(value raw_encoder) {
  CAMLparam1(raw_encoder);
  @autoreleasepool {
    @try {
      id<MTLAccelerationStructureCommandEncoder> encoder =
          object_of_handle(raw_encoder, Handle_kind::Acceleration_encoder);
      [encoder endEncoding];
      CAMLreturn(result_unit());
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_render_encoder(
    value raw_buffer, value raw_texture, value raw_clear) {
  CAMLparam3(raw_buffer, raw_texture, raw_clear);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      id<MTLCommandBuffer> buffer =
          object_of_handle(raw_buffer, Handle_kind::Command_buffer);
      id<MTLTexture> texture =
          object_of_handle(raw_texture, Handle_kind::Texture);
      const double red = Double_val(Field(raw_clear, 0));
      const double green = Double_val(Field(raw_clear, 1));
      const double blue = Double_val(Field(raw_clear, 2));
      const double alpha = Double_val(Field(raw_clear, 3));
      if (!std::isfinite(red) || !std::isfinite(green) ||
          !std::isfinite(blue) || !std::isfinite(alpha) ||
          texture.sampleCount != 1 ||
          (texture.usage & MTLTextureUsageRenderTarget) == 0) {
        CAMLreturn(result_error_text("render-pass target is invalid"));
      }
      MTLRenderPassDescriptor *pass =
          [MTLRenderPassDescriptor renderPassDescriptor];
      pass.colorAttachments[0].texture = texture;
      pass.colorAttachments[0].loadAction = MTLLoadActionClear;
      pass.colorAttachments[0].storeAction = MTLStoreActionStore;
      pass.colorAttachments[0].clearColor =
          MTLClearColorMake(red, green, blue, alpha);
      id<MTLRenderCommandEncoder> encoder =
          [buffer renderCommandEncoderWithDescriptor:pass];
      if (encoder == nil) {
        CAMLreturn(result_error_text("Metal failed to create a render encoder"));
      }
      raw = allocate_handle(encoder, Handle_kind::Render_encoder);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

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

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_fill_mode(
    value raw_encoder, value raw_mode) {
  CAMLparam2(raw_encoder, raw_mode);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  static const MTLTriangleFillMode values[] = {MTLTriangleFillModeFill, MTLTriangleFillModeLines};
  [encoder setTriangleFillMode:values[Long_val(raw_mode)]];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_blend_color(
    value raw_encoder, value raw_color) {
  CAMLparam2(raw_encoder, raw_color);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  [encoder setBlendColorRed:(float)Double_val(Field(raw_color, 0))
                      green:(float)Double_val(Field(raw_color, 1))
                       blue:(float)Double_val(Field(raw_color, 2))
                      alpha:(float)Double_val(Field(raw_color, 3))];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_depth_bias(
    value raw_encoder, value raw_bias) {
  CAMLparam2(raw_encoder, raw_bias);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  [encoder setDepthBias:(float)Double_val(Field(raw_bias, 0))
             slopeScale:(float)Double_val(Field(raw_bias, 1))
                  clamp:(float)Double_val(Field(raw_bias, 2))];
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

extern "C" CAMLprim value caml_prismel_metal_render_encoder_set_visibility(
    value raw_encoder, value raw_mode, value raw_offset) {
  CAMLparam3(raw_encoder, raw_mode, raw_offset);
  id<MTLRenderCommandEncoder> encoder = object_of_handle(raw_encoder, Handle_kind::Render_encoder);
  static const MTLVisibilityResultMode modes[] = {
      MTLVisibilityResultModeDisabled, MTLVisibilityResultModeBoolean,
      MTLVisibilityResultModeCounting};
  [encoder setVisibilityResultMode:modes[Long_val(raw_mode)]
                            offset:(NSUInteger)Int64_val(raw_offset)];
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

extern "C" CAMLprim value caml_prismel_metal_render_encoder_end(value raw) {
  CAMLparam1(raw);
  id<MTLRenderCommandEncoder> encoder =
      object_of_handle(raw, Handle_kind::Render_encoder);
  [encoder endEncoding];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value
caml_prismel_metal_command_buffer_resource_state_encoder(value raw_buffer) {
  CAMLparam1(raw_buffer);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLCommandBuffer> buffer =
        object_of_handle(raw_buffer, Handle_kind::Command_buffer);
    id<MTLResourceStateCommandEncoder> encoder =
        [buffer resourceStateCommandEncoder];
    if (encoder == nil) {
      CAMLreturn(result_error_text(
          "Metal failed to create a resource-state encoder"));
    }
    raw = allocate_handle(encoder, Handle_kind::Resource_state_encoder);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_blit_encoder(
    value raw_buffer) {
  CAMLparam1(raw_buffer);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLCommandBuffer> buffer =
        object_of_handle(raw_buffer, Handle_kind::Command_buffer);
    id<MTLBlitCommandEncoder> encoder = [buffer blitCommandEncoder];
    if (encoder == nil) {
      CAMLreturn(result_error_text("Metal failed to create a blit encoder"));
    }
    raw = allocate_handle(encoder, Handle_kind::Blit_encoder);
  }
  CAMLreturn(result_ok(raw));
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

extern "C" CAMLprim value caml_prismel_metal_compute_encoder_end(value raw) {
  CAMLparam1(raw);
  id<MTLComputeCommandEncoder> encoder =
      object_of_handle(raw, Handle_kind::Compute_encoder);
  [encoder endEncoding];
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
caml_prismel_metal_resource_state_encoder_end(value raw) {
  CAMLparam1(raw);
  id<MTLResourceStateCommandEncoder> encoder =
      object_of_handle(raw, Handle_kind::Resource_state_encoder);
  [encoder endEncoding];
  CAMLreturn(result_unit());
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

extern "C" CAMLprim value caml_prismel_metal_blit_encoder_end(value raw) {
  CAMLparam1(raw);
  id<MTLBlitCommandEncoder> encoder =
      object_of_handle(raw, Handle_kind::Blit_encoder);
  [encoder endEncoding];
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value caml_prismel_metal_command_buffer_commit(value raw) {
  CAMLparam1(raw);
  id<MTLCommandBuffer> buffer =
      object_of_handle(raw, Handle_kind::Command_buffer);
  [buffer commit];
  CAMLreturn(result_unit());
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

extern "C" CAMLprim value caml_prismel_metal_command_buffer_status(value raw) {
  CAMLparam1(raw);
  id<MTLCommandBuffer> buffer =
      object_of_handle(raw, Handle_kind::Command_buffer);
  CAMLreturn(Val_int(static_cast<int>(buffer.status)));
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

#include "metal_bridge_generated.inc"
