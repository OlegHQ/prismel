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

API_AVAILABLE(macos(26.0))
@interface PrismelMetal4CommandBufferOptionsState : NSObject
@property(nonatomic, strong) MTL4CommandBufferOptions *options;
@property(nonatomic, strong) id<MTLDevice> device;
@property(nonatomic, strong, nullable) PrismelMetalLogStateState *logState;
@end
@implementation PrismelMetal4CommandBufferOptionsState @end

extern "C" CAMLprim value caml_prismel_metal4_command_buffer_options_create(value raw_device) {
  CAMLparam1(raw_device); CAMLlocal1(raw);
  if (@available(macOS 26.0,*)) { @try {
    id<MTLDevice> device=object_of_handle(raw_device,Handle_kind::Device);
    PrismelMetal4CommandBufferOptionsState *state=[PrismelMetal4CommandBufferOptionsState new];
    state.options=prismel_metal4_command_buffer_options_create(); state.device=device;
    raw=allocate_handle(state,Handle_kind::Command_buffer_options4); CAMLreturn(result_ok(raw));
  } @catch(NSException*x){CAMLreturn(result_error(x.reason));} }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_command_buffer_options_log_state(value raw_options,value raw_log) {
  CAMLparam2(raw_options,raw_log);
  if (@available(macOS 26.0,*)) { @try {
    PrismelMetal4CommandBufferOptionsState *state=object_of_handle(raw_options,Handle_kind::Command_buffer_options4);
    PrismelMetalLogStateState *log=nil; if(Is_block(raw_log))log=object_of_handle(Field(raw_log,0),Handle_kind::Log_state);
    NSString *failure=nil; if(!prismel_metal4_command_buffer_options_set_log_state(state.options,log.state,log.registryID,state.device.registryID,&failure))CAMLreturn(result_error(failure));
    state.logState=log; CAMLreturn(result_unit());
  } @catch(NSException*x){CAMLreturn(result_error(x.reason));} }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}

extern "C" CAMLprim value caml_prismel_metal4_command_buffer_create_options(value raw_allocator,value raw_label,value raw_options) {
  CAMLparam3(raw_allocator,raw_label,raw_options); CAMLlocal1(raw);
  if (@available(macOS 26.0,*)) { @try {
    id<MTL4CommandAllocator> allocator=object_of_handle(raw_allocator,Handle_kind::Command_allocator4);
    PrismelMetal4CommandBufferOptionsState *options=object_of_handle(raw_options,Handle_kind::Command_buffer_options4);
    if(allocator.device.registryID!=options.device.registryID)CAMLreturn(result_error_text("Metal 4 command-buffer options belong to another device"));
    id<MTL4CommandBuffer> buffer=[allocator.device newCommandBuffer]; NSString *failure=nil;
    if(!prismel_metal4_command_buffer_begin_with_options(buffer,allocator,options.options,options.logState.registryID,&failure))CAMLreturn(result_error(failure));
    if(Is_block(raw_label))buffer.label=string_from_ocaml(Field(raw_label,0));
    PrismelMetal4CommandBufferState *state=[[PrismelMetal4CommandBufferState alloc]initWithCommandBuffer:buffer allocator:allocator];
    [state retainEncodedObject:options]; raw=allocate_handle(state,Handle_kind::Command_buffer4); CAMLreturn(result_ok(raw));
  } @catch(NSException*x){CAMLreturn(result_error(x.reason));} }
  CAMLreturn(result_error_text("Metal 4 requires macOS 26"));
}
