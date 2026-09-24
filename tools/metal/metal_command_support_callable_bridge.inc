/* Corrected Command-support121 handwritten callable shard (18/103 split).
   Callback capture/event notification, function-log enumeration and complex
   blit copies remain blocked until their roots and full range schemas exist. */

static bool prismel_command_nonnegative(value raw, int64_t *out) {
  *out = Int64_val(raw);
  return *out >= 0;
}
static MTLSize prismel_command_size(value raw) {
  return MTLSizeMake(static_cast<NSUInteger>(Int64_val(Field(raw, 0))),
                     static_cast<NSUInteger>(Int64_val(Field(raw, 1))),
                     static_cast<NSUInteger>(Int64_val(Field(raw, 2))));
}
static MTLRegion prismel_command_region(value raw) {
  return MTLRegionMake3D(Int64_val(Field(raw, 0)), Int64_val(Field(raw, 1)),
                         Int64_val(Field(raw, 2)), Int64_val(Field(raw, 3)),
                         Int64_val(Field(raw, 4)), Int64_val(Field(raw, 5)));
}

extern "C" CAMLprim value caml_prismel_metal_capture_manager_shared(value unit) {
  CAMLparam1(unit); CAMLlocal2(handle, result); @try {
    handle = allocate_handle([MTLCaptureManager sharedCaptureManager], Handle_kind::Capture_manager);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_capture_descriptor_create(value unit) {
  CAMLparam1(unit); CAMLlocal2(handle, result); @try {
    handle = allocate_handle([MTLCaptureDescriptor new], Handle_kind::Capture_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_capture_supports_destination(value raw, value destination) {
  CAMLparam2(raw, destination); @try {
    MTLCaptureManager *manager = object_of_handle(raw, Handle_kind::Capture_manager);
    CAMLreturn(result_ok(Val_bool([manager supportsDestination:(MTLCaptureDestination)Long_val(destination)])));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_capture_start(value manager_raw, value descriptor_raw) {
  CAMLparam2(manager_raw, descriptor_raw); @try {
    MTLCaptureManager *manager = object_of_handle(manager_raw, Handle_kind::Capture_manager);
    MTLCaptureDescriptor *descriptor = object_of_handle(descriptor_raw, Handle_kind::Capture_descriptor);
    NSError *error = nil;
    if (![manager startCaptureWithDescriptor:descriptor error:&error])
      CAMLreturn(result_error(error_description(error, @"Metal capture failed without NSError")));
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_capture_stop(value raw) {
  CAMLparam1(raw); @try { [object_of_handle(raw, Handle_kind::Capture_manager) stopCapture];
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_event_label(value raw) {
  CAMLparam1(raw); CAMLlocal2(label, result); @try {
    id<MTLEvent> event = object_of_handle(raw, Handle_kind::Event);
    label = copy_optional_string(event.label); result = result_ok(label); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_event_set_label(value raw, value option) {
  CAMLparam2(raw, option); @try {
    id<MTLEvent> event = object_of_handle(raw, Handle_kind::Event);
    NSString *label = Is_block(option) ? string_from_ocaml(Field(option, 0)) : nil;
    if (Is_block(option) && label == nil) CAMLreturn(result_error_text("event label is not valid UTF-8"));
    event.label = label; CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
extern "C" CAMLprim value caml_prismel_metal_event_device_id(value raw) {
  CAMLparam1(raw); CAMLlocal2(identifier, result); @try {
    id<MTLEvent> event = object_of_handle(raw, Handle_kind::Event);
    identifier = caml_copy_int64(event.device.registryID); result = result_ok(identifier); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

#define PRISMEL_INDIRECT0(NAME, KIND, TYPE, CALL) \
extern "C" CAMLprim value NAME(value raw){CAMLparam1(raw);@try{TYPE command=object_of_handle(raw,KIND);[command CALL];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
#define PRISMEL_INDIRECT_ENUM(NAME, KIND, TYPE, CALL, ENUM) \
extern "C" CAMLprim value NAME(value raw,value input){CAMLparam2(raw,input);@try{TYPE command=object_of_handle(raw,KIND);[command CALL:(ENUM)Long_val(input)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
PRISMEL_INDIRECT0(caml_prismel_metal_support_indirect_compute_clear_barrier,Handle_kind::Indirect_compute_command,id<MTLIndirectComputeCommand>,clearBarrier)
PRISMEL_INDIRECT0(caml_prismel_metal_support_indirect_compute_set_barrier,Handle_kind::Indirect_compute_command,id<MTLIndirectComputeCommand>,setBarrier)
PRISMEL_INDIRECT0(caml_prismel_metal_support_indirect_render_clear_barrier,Handle_kind::Indirect_render_command,id<MTLIndirectRenderCommand>,clearBarrier)
PRISMEL_INDIRECT0(caml_prismel_metal_support_indirect_render_set_barrier,Handle_kind::Indirect_render_command,id<MTLIndirectRenderCommand>,setBarrier)
PRISMEL_INDIRECT_ENUM(caml_prismel_metal_support_indirect_render_set_cull,Handle_kind::Indirect_render_command,id<MTLIndirectRenderCommand>,setCullMode,MTLCullMode)
PRISMEL_INDIRECT_ENUM(caml_prismel_metal_support_indirect_render_set_depth_clip,Handle_kind::Indirect_render_command,id<MTLIndirectRenderCommand>,setDepthClipMode,MTLDepthClipMode)
PRISMEL_INDIRECT_ENUM(caml_prismel_metal_support_indirect_render_set_front_winding,Handle_kind::Indirect_render_command,id<MTLIndirectRenderCommand>,setFrontFacingWinding,MTLWinding)
PRISMEL_INDIRECT_ENUM(caml_prismel_metal_support_indirect_render_set_fill,Handle_kind::Indirect_render_command,id<MTLIndirectRenderCommand>,setTriangleFillMode,MTLTriangleFillMode)

extern "C" CAMLprim value caml_prismel_metal_support_indirect_compute_imageblock(value raw,value width,value height){
  CAMLparam3(raw,width,height);int64_t w,h;if(!prismel_command_nonnegative(width,&w)||!prismel_command_nonnegative(height,&h))CAMLreturn(result_error_text("imageblock dimensions must be non-negative"));
  @try{[object_of_handle(raw,Handle_kind::Indirect_compute_command) setImageblockWidth:w height:h];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_support_indirect_compute_stage_region(value raw,value region){CAMLparam2(raw,region);@try{[object_of_handle(raw,Handle_kind::Indirect_compute_command) setStageInRegion:prismel_command_region(region)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_support_indirect_compute_memory(value raw,value length,value index){CAMLparam3(raw,length,index);int64_t l,i;if(!prismel_command_nonnegative(length,&l)||!prismel_command_nonnegative(index,&i))CAMLreturn(result_error_text("threadgroup memory arguments must be non-negative"));@try{[object_of_handle(raw,Handle_kind::Indirect_compute_command) setThreadgroupMemoryLength:l atIndex:i];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_support_indirect_compute_dispatch_groups(value raw,value groups,value threads){CAMLparam3(raw,groups,threads);@try{[object_of_handle(raw,Handle_kind::Indirect_compute_command) concurrentDispatchThreadgroups:prismel_command_size(groups) threadsPerThreadgroup:prismel_command_size(threads)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_support_indirect_render_depth_bias(value raw,value bias,value slope,value clamp){CAMLparam4(raw,bias,slope,clamp);@try{[object_of_handle(raw,Handle_kind::Indirect_render_command) setDepthBias:Double_val(bias) slopeScale:Double_val(slope) clamp:Double_val(clamp)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_support_indirect_render_depth_stencil(value raw,value state_raw){CAMLparam2(raw,state_raw);@try{[object_of_handle(raw,Handle_kind::Indirect_render_command) setDepthStencilState:object_of_handle(state_raw,Handle_kind::Depth_stencil)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_support_indirect_render_object_memory(value raw,value length,value index){CAMLparam3(raw,length,index);int64_t l,i;if(!prismel_command_nonnegative(length,&l)||!prismel_command_nonnegative(index,&i))CAMLreturn(result_error_text("object memory arguments must be non-negative"));@try{[object_of_handle(raw,Handle_kind::Indirect_render_command) setObjectThreadgroupMemoryLength:l atIndex:i];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_support_indirect_render_mesh_groups(value raw,value groups,value object_threads,value mesh_threads){CAMLparam4(raw,groups,object_threads,mesh_threads);@try{[object_of_handle(raw,Handle_kind::Indirect_render_command) drawMeshThreadgroups:prismel_command_size(groups) threadsPerObjectThreadgroup:prismel_command_size(object_threads) threadsPerMeshThreadgroup:prismel_command_size(mesh_threads)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_support_indirect_render_mesh_threads(value raw,value threads,value object_threads,value mesh_threads){CAMLparam4(raw,threads,object_threads,mesh_threads);@try{[object_of_handle(raw,Handle_kind::Indirect_render_command) drawMeshThreads:prismel_command_size(threads) threadsPerObjectThreadgroup:prismel_command_size(object_threads) threadsPerMeshThreadgroup:prismel_command_size(mesh_threads)];CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

#undef PRISMEL_INDIRECT0
#undef PRISMEL_INDIRECT_ENUM
