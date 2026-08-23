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

@protocol PrismelMetalSharedTextureXpc
- (void)exchangeOperation:(NSString *)operation
                   handle:(MTLSharedTextureHandle *)handle
                 metadata:(NSData *)metadata
                     data:(NSData *)data
                withReply:(void (^)(MTLSharedTextureHandle *, NSData *,
                                    NSData *, NSString *))reply;
@end

using PrismelMetalXpcReply =
    void (^)(MTLSharedTextureHandle *, NSData *, NSData *, NSString *);

static thread_local bool prismel_metal_xpc_main_executor = false;

@interface PrismelMetalXpcRequest : NSObject
@property(nonatomic, readonly) NSString *operation;
@property(nonatomic, readonly) MTLSharedTextureHandle *handle;
@property(nonatomic, readonly) NSData *metadata;
@property(nonatomic, readonly) NSData *data;
@property(nonatomic, readonly, getter=isFinished) BOOL finished;
- (instancetype)initWithOperation:(NSString *)operation
                           handle:(MTLSharedTextureHandle *)handle
                         metadata:(NSData *)metadata
                             data:(NSData *)data
                            reply:(PrismelMetalXpcReply)reply;
- (BOOL)replyWithHandle:(MTLSharedTextureHandle *)handle
               metadata:(NSData *)metadata
                   data:(NSData *)data;
- (BOOL)rejectWithMessage:(NSString *)message;
@end

@implementation PrismelMetalXpcRequest {
  NSString *_operation;
  MTLSharedTextureHandle *_handle;
  NSData *_metadata;
  NSData *_data;
  PrismelMetalXpcReply _reply;
  std::mutex _replyMutex;
  BOOL _finished;
}

- (instancetype)initWithOperation:(NSString *)operation
                           handle:(MTLSharedTextureHandle *)handle
                         metadata:(NSData *)metadata
                             data:(NSData *)data
                            reply:(PrismelMetalXpcReply)reply {
  self = [super init];
  if (self != nil) {
    _operation = [operation copy];
    _handle = handle;
    _metadata = [metadata copy];
    _data = [data copy];
    _reply = [reply copy];
    _finished = NO;
  }
  return self;
}

- (NSString *)operation { return _operation; }
- (MTLSharedTextureHandle *)handle { return _handle; }
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

- (BOOL)replyWithHandle:(MTLSharedTextureHandle *)handle
               metadata:(NSData *)metadata
                   data:(NSData *)data {
  PrismelMetalXpcReply reply = [self takeReply];
  if (reply == nil) {
    return NO;
  }
  reply(handle, metadata, data, nil);
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
  (void)[self rejectWithMessage:@"shared-texture XPC request was abandoned"];
}

@end

static NSXPCInterface *PrismelMetalSharedTextureInterface(void) {
  return [NSXPCInterface interfaceWithProtocol:
                             @protocol(PrismelMetalSharedTextureXpc)];
}

using PrismelMetalXpcHandler = void (^)(PrismelMetalXpcRequest *);

@interface PrismelMetalXpcService
    : NSObject <NSXPCListenerDelegate, PrismelMetalSharedTextureXpc>
- (instancetype)initWithCapacity:(NSUInteger)capacity
                  maxPayloadBytes:(NSUInteger)maxPayloadBytes;
- (void)setRequestHandler:(PrismelMetalXpcHandler)handler;
- (void)run;
@end

@implementation PrismelMetalXpcService {
  NSUInteger _capacity;
  NSUInteger _activeRequests;
  NSUInteger _maxPayloadBytes;
  NSXPCListener *_listener;
  NSHashTable<NSXPCConnection *> *_connections;
  std::mutex _mutex;
  BOOL _closed;
  PrismelMetalXpcHandler _handler;
}

- (instancetype)initWithCapacity:(NSUInteger)capacity
                  maxPayloadBytes:(NSUInteger)maxPayloadBytes {
  self = [super init];
  if (self != nil) {
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
  connection.exportedInterface = PrismelMetalSharedTextureInterface();
  connection.exportedObject = self;
  [connection activate];
  return YES;
}

- (void)exchangeOperation:(NSString *)operation
                   handle:(MTLSharedTextureHandle *)handle
                 metadata:(NSData *)metadata
                     data:(NSData *)data
                withReply:(PrismelMetalXpcReply)reply {
  NSString *validationError = nil;
  const NSUInteger operationBytes =
      [operation lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  if (operation == nil || operation.length == 0 || operationBytes == 0 ||
      operationBytes > 256) {
    validationError = @"shared-texture XPC operation must contain 1-256 UTF-8 bytes";
  } else {
    for (NSUInteger index = 0; index < operation.length; ++index) {
      if ([operation characterAtIndex:index] == 0) {
        validationError = @"shared-texture XPC operation contains a NUL character";
        break;
      }
    }
  }
  if (validationError == nil && handle == nil) {
    validationError = @"shared-texture XPC request has no handle";
  }
  if (validationError == nil &&
      (metadata == nil || metadata.length == 0 || metadata.length > 4096)) {
    validationError = @"shared-texture XPC metadata is malformed";
  }
  if (validationError == nil &&
      (data == nil || data.length > _maxPayloadBytes)) {
    validationError = @"shared-texture XPC payload exceeds its configured bound";
  }
  if (validationError != nil) {
    reply(nil, [NSData data], [NSData data], validationError);
    return;
  }
  PrismelMetalXpcRequest *request =
      [[PrismelMetalXpcRequest alloc] initWithOperation:operation
                                                handle:handle
                                              metadata:metadata
                                                  data:data
                                                 reply:reply];
  PrismelMetalXpcHandler handler = nil;
  {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_closed) {
      validationError = @"shared-texture XPC service is closed";
    } else if (_activeRequests >= _capacity) {
      validationError = @"shared-texture XPC request capacity is exhausted";
    } else {
      handler = _handler;
      if (handler == nil) {
        validationError = @"shared-texture XPC service has no request handler";
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
    (void)[request rejectWithMessage:
                       @"shared-texture XPC handler returned without a reply"];
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
- (instancetype)initWithServiceName:(NSString *)serviceName
                     maxPayloadBytes:(NSUInteger)maxPayloadBytes;
- (void)shutdown;
@end

@implementation PrismelMetalXpcConnection {
  NSXPCConnection *_connection;
  NSUInteger _maxPayloadBytes;
}

- (instancetype)initWithServiceName:(NSString *)serviceName
                     maxPayloadBytes:(NSUInteger)maxPayloadBytes {
  self = [super init];
  if (self != nil) {
    _maxPayloadBytes = maxPayloadBytes;
    _connection =
        [[NSXPCConnection alloc] initWithServiceName:serviceName];
    _connection.remoteObjectInterface = PrismelMetalSharedTextureInterface();
    [_connection activate];
  }
  return self;
}

- (NSXPCConnection *)connection { return _connection; }
- (NSUInteger)maxPayloadBytes { return _maxPayloadBytes; }
- (void)shutdown { [_connection invalidate]; }
- (void)dealloc { [self shutdown]; }

@end

@interface PrismelMetalXpcCallState : NSObject
@property(nonatomic, readonly) MTLSharedTextureHandle *handle;
@property(nonatomic, readonly) NSData *metadata;
@property(nonatomic, readonly) NSData *data;
@property(nonatomic, readonly) NSString *errorMessage;
- (void)completeWithHandle:(MTLSharedTextureHandle *)handle
                  metadata:(NSData *)metadata
                      data:(NSData *)data
                     error:(NSString *)errorMessage;
- (BOOL)waitForMilliseconds:(NSUInteger)milliseconds;
@end

@implementation PrismelMetalXpcCallState {
  NSCondition *_condition;
  BOOL _completed;
  MTLSharedTextureHandle *_handle;
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

- (void)completeWithHandle:(MTLSharedTextureHandle *)handle
                  metadata:(NSData *)metadata
                      data:(NSData *)data
                     error:(NSString *)errorMessage {
  [_condition lock];
  if (!_completed) {
    _completed = YES;
    _handle = handle;
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

- (MTLSharedTextureHandle *)handle { return _handle; }
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
  Shared_texture_xpc_connection,
  Shared_texture_xpc_service,
  Shared_texture_xpc_request,
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

PrismelMetalXpcConnection *shared_texture_xpc_connection_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Shared_texture_xpc_connection);
}

PrismelMetalXpcService *shared_texture_xpc_service_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Shared_texture_xpc_service);
}

PrismelMetalXpcRequest *shared_texture_xpc_request_of_handle(value raw) {
  return object_of_handle(raw, Handle_kind::Shared_texture_xpc_request);
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
      stringWithFormat:@"%@ (domain=%@ code=%ld)",
                       error.localizedDescription ?: error.description,
                       error.domain, static_cast<long>(error.code)];
}

NSString *string_from_ocaml(value text) {
  return [[NSString alloc]
      initWithBytes:String_val(text)
             length:caml_string_length(text)
           encoding:NSUTF8StringEncoding];
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
               @selector(setMaxCompatiblePlacementSparsePageSize:)];
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

std::size_t tuple_dimension(value tuple, mlsize_t index) {
  const intnat dimension = Long_val(Field(tuple, index));
  if (dimension <= 0) {
    caml_invalid_argument("Metal dimensions must be positive");
  }
  return static_cast<std::size_t>(dimension);
}

MTLTextureDescriptor *texture_descriptor(value raw_descriptor) {
  MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
  descriptor.textureType =
      static_cast<MTLTextureType>(Long_val(Field(raw_descriptor, 0)));
  descriptor.pixelFormat =
      static_cast<MTLPixelFormat>(Long_val(Field(raw_descriptor, 1)));
  descriptor.width = tuple_dimension(raw_descriptor, 2);
  descriptor.height = tuple_dimension(raw_descriptor, 3);
  descriptor.depth = tuple_dimension(raw_descriptor, 4);
  descriptor.mipmapLevelCount = tuple_dimension(raw_descriptor, 5);
  descriptor.sampleCount = tuple_dimension(raw_descriptor, 6);
  descriptor.arrayLength = tuple_dimension(raw_descriptor, 7);
  descriptor.storageMode =
      static_cast<MTLStorageMode>(Long_val(Field(raw_descriptor, 8)));
  descriptor.cpuCacheMode =
      static_cast<MTLCPUCacheMode>(Long_val(Field(raw_descriptor, 9)));
  descriptor.hazardTrackingMode =
      static_cast<MTLHazardTrackingMode>(Long_val(Field(raw_descriptor, 10)));
  descriptor.usage =
      static_cast<MTLTextureUsage>(Long_val(Field(raw_descriptor, 11)));
  descriptor.allowGPUOptimizedContents = Bool_val(Field(raw_descriptor, 12));
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

static void invoke_ocaml_shared_texture_xpc_handler_with_runtime(
    value *callback_root, PrismelMetalXpcRequest *request) {
  CAMLparam0();
  CAMLlocal5(raw_request, operation, raw_handle, metadata, data);
  CAMLlocal1(callback_result);
  raw_request = allocate_handle(request,
                                Handle_kind::Shared_texture_xpc_request);
  operation = caml_copy_string(request.operation.UTF8String);
  raw_handle = allocate_handle(request.handle,
                               Handle_kind::Shared_texture_handle);
  metadata = copy_data(request.metadata);
  data = copy_data(request.data);
  value arguments[5] = {raw_request, operation, raw_handle, metadata, data};
  callback_result = caml_callbackN_exn(*callback_root, 5, arguments);
  if (Is_exception_result(callback_result) && !request.finished) {
    (void)[request rejectWithMessage:
                       @"shared-texture XPC OCaml handler raised an exception"];
  }
  CAMLreturn0;
}

static void invoke_ocaml_shared_texture_xpc_handler(
    value *callback_root, PrismelMetalXpcRequest *request) {
  if (caml_c_thread_register() == 0) {
    (void)[request rejectWithMessage:
                       @"shared-texture XPC could not register its callback thread"];
    return;
  }
  caml_acquire_runtime_system();
  prismel_metal_xpc_main_executor = true;
  invoke_ocaml_shared_texture_xpc_handler_with_runtime(callback_root, request);
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
  result = caml_alloc(12, 0);
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

extern "C" CAMLprim value caml_prismel_metal_shared_texture_xpc_connect(
    value raw_service_name, value raw_max_payload_bytes) {
  CAMLparam2(raw_service_name, raw_max_payload_bytes);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      NSString *service_name = string_from_ocaml(raw_service_name);
      const intnat max_payload_bytes = Long_val(raw_max_payload_bytes);
      if (service_name == nil || service_name.length == 0 ||
          [service_name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 255 ||
          max_payload_bytes <= 0 || max_payload_bytes > 64 * 1024 * 1024) {
        CAMLreturn(result_error_text(
            "shared-texture XPC connection configuration is invalid"));
      }
      PrismelMetalXpcConnection *connection =
          [[PrismelMetalXpcConnection alloc]
              initWithServiceName:service_name
                   maxPayloadBytes:static_cast<NSUInteger>(max_payload_bytes)];
      if (connection == nil || connection.connection == nil) {
        CAMLreturn(result_error_text(
            "failed to create the shared-texture XPC connection"));
      }
      raw = allocate_handle(connection,
                            Handle_kind::Shared_texture_xpc_connection);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_shared_texture_xpc_call(
    value raw_connection, value raw_operation, value raw_handle,
    value raw_metadata, value raw_data, value raw_timeout_milliseconds) {
  CAMLparam5(raw_connection, raw_operation, raw_handle, raw_metadata, raw_data);
  CAMLxparam1(raw_timeout_milliseconds);
  CAMLlocal5(raw_reply, metadata, data, tuple, result);
  @autoreleasepool {
    @try {
      PrismelMetalXpcConnection *connection =
          shared_texture_xpc_connection_of_handle(raw_connection);
      MTLSharedTextureHandle *handle =
          shared_texture_handle_of_handle(raw_handle);
      NSString *operation = string_from_ocaml(raw_operation);
      NSData *request_metadata = data_from_ocaml(raw_metadata);
      NSData *request_data = data_from_ocaml(raw_data);
      const intnat timeout_milliseconds = Long_val(raw_timeout_milliseconds);
      if (operation == nil || operation.length == 0 ||
          [operation lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 256 ||
          handle == nil || request_metadata.length == 0 ||
          request_metadata.length > 4096 ||
          request_data.length > connection.maxPayloadBytes ||
          timeout_milliseconds <= 0 || timeout_milliseconds > 300'000) {
        CAMLreturn(result_error_text(
            "shared-texture XPC call arguments are invalid"));
      }
      PrismelMetalXpcCallState *state =
          [[PrismelMetalXpcCallState alloc] init];
      id<PrismelMetalSharedTextureXpc> proxy =
          [connection.connection
              remoteObjectProxyWithErrorHandler:^(NSError *error) {
                [state completeWithHandle:nil
                                 metadata:nil
                                     data:nil
                                    error:error_description(
                                              error,
                                              @"shared-texture XPC call failed")];
              }];
      if (proxy == nil) {
        CAMLreturn(result_error_text(
            "shared-texture XPC could not create a remote proxy"));
      }
      [proxy exchangeOperation:operation
                        handle:handle
                      metadata:request_metadata
                          data:request_data
                     withReply:^(MTLSharedTextureHandle *reply_handle,
                                 NSData *reply_metadata,
                                 NSData *reply_data,
                                 NSString *error_message) {
                       [state completeWithHandle:reply_handle
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
        CAMLreturn(result_error_text("shared-texture XPC call timed out"));
      }
      if (state.errorMessage != nil) {
        CAMLreturn(result_error(state.errorMessage));
      }
      if (state.handle == nil || state.metadata == nil || state.data == nil ||
          state.metadata.length == 0 || state.metadata.length > 4096 ||
          state.data.length > connection.maxPayloadBytes) {
        CAMLreturn(result_error_text(
            "shared-texture XPC service returned a malformed reply"));
      }
      raw_reply = allocate_handle(state.handle,
                                  Handle_kind::Shared_texture_handle);
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
caml_prismel_metal_shared_texture_xpc_call_bytecode(value *argv, int argn) {
  (void)argn;
  return caml_prismel_metal_shared_texture_xpc_call(
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

extern "C" CAMLprim value
caml_prismel_metal_shared_texture_xpc_service_create(
    value raw_capacity, value raw_max_payload_bytes) {
  CAMLparam2(raw_capacity, raw_max_payload_bytes);
  CAMLlocal1(raw);
  @autoreleasepool {
    @try {
      const intnat capacity = Long_val(raw_capacity);
      const intnat max_payload_bytes = Long_val(raw_max_payload_bytes);
      if (capacity <= 0 || capacity > 1024 || max_payload_bytes <= 0 ||
          max_payload_bytes > 64 * 1024 * 1024) {
        CAMLreturn(result_error_text(
            "shared-texture XPC service configuration is invalid"));
      }
      PrismelMetalXpcService *service =
          [[PrismelMetalXpcService alloc]
              initWithCapacity:static_cast<NSUInteger>(capacity)
               maxPayloadBytes:static_cast<NSUInteger>(max_payload_bytes)];
      if (service == nil) {
        CAMLreturn(result_error_text(
            "failed to create the shared-texture XPC service"));
      }
      raw = allocate_handle(service,
                            Handle_kind::Shared_texture_xpc_service);
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value
caml_prismel_metal_shared_texture_xpc_service_serve(
    value raw_service, value raw_callback) {
  CAMLparam2(raw_service, raw_callback);
  CAMLlocal1(result);
  @autoreleasepool {
    PrismelMetalXpcService *service =
        shared_texture_xpc_service_of_handle(raw_service);
    value *callback_root = new value(raw_callback);
    caml_register_generational_global_root(callback_root);
    NSString *failure = nil;
    BOOL runtime_released = NO;
    @try {
      [service setRequestHandler:^(PrismelMetalXpcRequest *request) {
        invoke_ocaml_shared_texture_xpc_handler(callback_root, request);
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
caml_prismel_metal_shared_texture_xpc_request_reply(
    value raw_request, value raw_handle, value raw_metadata, value raw_data) {
  CAMLparam4(raw_request, raw_handle, raw_metadata, raw_data);
  @autoreleasepool {
    @try {
      PrismelMetalXpcRequest *request =
          shared_texture_xpc_request_of_handle(raw_request);
      MTLSharedTextureHandle *handle =
          shared_texture_handle_of_handle(raw_handle);
      NSData *metadata = data_from_ocaml(raw_metadata);
      NSData *data = data_from_ocaml(raw_data);
      if (metadata.length == 0 || metadata.length > 4096) {
        CAMLreturn(result_error_text(
            "shared-texture XPC reply metadata is malformed"));
      }
      if (![request replyWithHandle:handle metadata:metadata data:data]) {
        CAMLreturn(result_error_text(
            "shared-texture XPC request was already completed"));
      }
    } @catch (NSException *exception) {
      CAMLreturn(result_error(exception.reason));
    }
  }
  CAMLreturn(result_unit());
}

extern "C" CAMLprim value
caml_prismel_metal_shared_texture_xpc_request_reject(
    value raw_request, value raw_message) {
  CAMLparam2(raw_request, raw_message);
  @autoreleasepool {
    @try {
      PrismelMetalXpcRequest *request =
          shared_texture_xpc_request_of_handle(raw_request);
      NSString *message = string_from_ocaml(raw_message);
      if (message == nil || message.length == 0 ||
          [message lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 4096) {
        CAMLreturn(result_error_text(
            "shared-texture XPC rejection message is invalid"));
      }
      if (![request rejectWithMessage:message]) {
        CAMLreturn(result_error_text(
            "shared-texture XPC request was already completed"));
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
    id<MTLTexture> parent = object_of_handle(raw_parent, Handle_kind::Texture);
    const intnat format = Long_val(Field(raw_descriptor, 0));
    const intnat kind = Long_val(Field(raw_descriptor, 1));
    const intnat base_level = Long_val(Field(raw_descriptor, 2));
    const intnat level_count = Long_val(Field(raw_descriptor, 3));
    const intnat base_slice = Long_val(Field(raw_descriptor, 4));
    const intnat slice_count = Long_val(Field(raw_descriptor, 5));
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
    id<MTLTexture> view = [parent
        newTextureViewWithPixelFormat:static_cast<MTLPixelFormat>(format)
                         textureType:static_cast<MTLTextureType>(kind)
                              levels:NSMakeRange(
                                         static_cast<NSUInteger>(base_level),
                                         static_cast<NSUInteger>(level_count))
                              slices:NSMakeRange(
                                         static_cast<NSUInteger>(base_slice),
                                         static_cast<NSUInteger>(slice_count))];
    if (view == nil) {
      CAMLreturn(result_error_text("Metal rejected the texture view"));
    }
    if (Is_block(raw_label)) {
      NSString *label = string_from_ocaml(Field(raw_label, 0));
      if (label == nil) {
        CAMLreturn(result_error_text("texture-view label is not valid UTF-8"));
      }
      view.label = label;
    }
    raw = allocate_handle(view, Handle_kind::Texture);
  }
  CAMLreturn(result_ok(raw));
}

extern "C" CAMLprim value caml_prismel_metal_sampler_create(
    value raw_device, value raw_descriptor, value raw_label) {
  CAMLparam3(raw_device, raw_descriptor, raw_label);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    const intnat anisotropy = Long_val(Field(raw_descriptor, 3));
    const double lod_min = Double_val(Field(raw_descriptor, 9));
    const double lod_max = Double_val(Field(raw_descriptor, 10));
    if (anisotropy < 1 || anisotropy > 16 || !std::isfinite(lod_min) ||
        !std::isfinite(lod_max) || lod_min < 0.0 || lod_max < lod_min) {
      CAMLreturn(result_error_text("sampler descriptor values are invalid"));
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
    descriptor.normalizedCoordinates = Bool_val(Field(raw_descriptor, 8));
    descriptor.lodMinClamp = static_cast<float>(lod_min);
    descriptor.lodMaxClamp = static_cast<float>(lod_max);
    descriptor.lodAverage = Bool_val(Field(raw_descriptor, 11));
    descriptor.compareFunction =
        static_cast<MTLCompareFunction>(Long_val(Field(raw_descriptor, 12)));
    descriptor.supportArgumentBuffers = Bool_val(Field(raw_descriptor, 13));
    if (Is_block(raw_label)) {
      NSString *label = string_from_ocaml(Field(raw_label, 0));
      if (label == nil) {
        CAMLreturn(result_error_text("sampler label is not valid UTF-8"));
      }
      descriptor.label = label;
    }
    id<MTLSamplerState> sampler =
        [device newSamplerStateWithDescriptor:descriptor];
    if (sampler == nil) {
      CAMLreturn(result_error_text("Metal rejected the sampler descriptor"));
    }
    raw = allocate_handle(sampler, Handle_kind::Sampler);
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
    value raw_device, value raw_source) {
  CAMLparam2(raw_device, raw_source);
  CAMLlocal1(raw);
  @autoreleasepool {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    NSString *source = string_from_ocaml(raw_source);
    if (source == nil) {
      CAMLreturn(result_error_text("Metal source is not valid UTF-8"));
    }
    MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
    options.fastMathEnabled = NO;
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source
                                                  options:options
                                                    error:&error];
    if (library == nil) {
      CAMLreturn(result_error(error_description(
          error, @"Metal source compilation failed without NSError")));
    }
    raw = allocate_handle(library, Handle_kind::Library);
  }
  CAMLreturn(result_ok(raw));
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
      MTLSizeMake(tuple_dimension(raw_threads, 0),
                  tuple_dimension(raw_threads, 1),
                  tuple_dimension(raw_threads, 2));
  const MTLSize threadgroup =
      MTLSizeMake(tuple_dimension(raw_threadgroup, 0),
                  tuple_dimension(raw_threadgroup, 1),
                  tuple_dimension(raw_threadgroup, 2));
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
