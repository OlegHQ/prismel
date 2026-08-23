#define CAML_NAME_SPACE

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
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

value copy_pipeline_bindings(MTLComputePipelineReflection *reflection) {
  CAMLparam0();
  CAMLlocal4(array, tuple, name, item);
  NSArray<id<MTLBinding>> *bindings = reflection.bindings;
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
    tuple = caml_alloc_tuple(17);
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
    Store_field(array, static_cast<mlsize_t>(index), tuple);
  }
  CAMLreturn(array);
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
MTL4StaticLinkingDescriptor *checked_static_linking_descriptor(
    value raw_option, id<MTLDevice> device,
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
      !device.supportsFunctionPointers) {
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
  if (descriptor.functionDescriptors.count != functions.count ||
      descriptor.privateFunctionDescriptors.count != private_functions.count ||
      descriptor.groups.count != groups.count) {
    *failure = @"Metal changed checked static-linking descriptor properties";
    return nil;
  }
  for (NSString *name in groups) {
    if (descriptor.groups[name].count != groups[name].count) {
      *failure = @"Metal changed checked static-link group properties";
      return nil;
    }
  }
  return descriptor;
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
  std::vector<id<MTL4Archive>> lookup_archives =
      pipeline_archives_of_array(Field(raw_descriptor, 13));
  NSMutableArray<id<MTL4Archive>> *archive_array =
      [NSMutableArray arrayWithCapacity:lookup_archives.size()];
  NSMutableSet<id<MTL4Archive>> *archive_set = [NSMutableSet set];
  for (id<MTL4Archive> archive : lookup_archives) {
    if ([archive_set containsObject:archive]) {
      *failure = @"Metal 4 lookup archive is duplicated";
      return nil;
    }
    [archive_set addObject:archive];
    [archive_array addObject:archive];
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
          raw_static_linking, compiler.device, &static_linking_failure);
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
      checked_compiler_task_options(archive_array, &task_options_failure);
  if (archive_array.count != 0 && task_options == nil) {
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
        dynamic_linking.preloadedLibraries.count != preloaded_array.count)) ||
      (task_options != nil &&
       task_options.lookupArchives.count != archive_array.count)) {
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
        bindings = reflection_requested ? copy_pipeline_bindings(reflection)
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
                ? copy_pipeline_bindings(reflection)
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
      if (descriptor.computeFunction != function ||
          ((expected_label == nil) != (descriptor.label == nil)) ||
          (expected_label != nil &&
           ![descriptor.label isEqualToString:expected_label]) ||
          descriptor.preloadedLibraries.count != preloaded_array.count ||
          descriptor.binaryArchives.count != archive_array.count) {
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
      bindings = reflection_requested ? copy_pipeline_bindings(reflection)
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
