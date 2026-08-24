/* CaptureScope12 isolated shard. Integration uses the exact Capture_scope
   handle already introduced by CaptureManager21. Balanced state is tracked per
   retained Objective-C scope; failed native transitions do not alter it. */
static std::mutex prismel_capture_scope_mutex;
static std::unordered_set<void *> prismel_active_capture_scopes;

extern "C" CAMLprim value caml_prismel_metal_capture_scope_snapshot(value raw) {
  CAMLparam1(raw); CAMLlocal5(tuple,label,classic,metal4,temporary); @try {
    id<MTLCaptureScope> scope=object_of_handle(raw,Handle_kind::Capture_scope);
    label=copy_optional_string(scope.label);
    if(scope.commandQueue==nil)classic=Val_none;else{temporary=allocate_handle(scope.commandQueue,Handle_kind::Command_queue);classic=caml_alloc(1,0);Store_field(classic,0,temporary);}
    metal4=Val_none;
    if(@available(macOS 26.0,*)){if(scope.mtl4CommandQueue!=nil){temporary=allocate_handle(scope.mtl4CommandQueue,Handle_kind::Command_queue4);metal4=caml_alloc(1,0);Store_field(metal4,0,temporary);}}
    tuple=caml_alloc_tuple(4);Store_field(tuple,0,label);Store_field(tuple,1,caml_copy_int64(scope.device.registryID));Store_field(tuple,2,classic);Store_field(tuple,3,metal4);CAMLreturn(result_ok(tuple));
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_capture_scope_set_label(value raw,value option){
  CAMLparam2(raw,option);@try{NSString*label=Is_none(option)?nil:string_from_ocaml(Field(option,0));if(!Is_none(option)&&label==nil)CAMLreturn(result_error_text("capture scope label is not valid UTF-8"));id<MTLCaptureScope>scope=object_of_handle(raw,Handle_kind::Capture_scope);scope.label=label;CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_capture_scope_transition(value raw,value begin_raw){
  CAMLparam2(raw,begin_raw);@try{id<MTLCaptureScope>scope=object_of_handle(raw,Handle_kind::Capture_scope);void*identity=(__bridge void*)scope;std::lock_guard<std::mutex>lock(prismel_capture_scope_mutex);bool active=prismel_active_capture_scopes.count(identity)!=0;if(Bool_val(begin_raw)){if(active)CAMLreturn(result_error_text("capture scope is already active"));[scope beginScope];prismel_active_capture_scopes.insert(identity);}else{if(!active)CAMLreturn(result_error_text("capture scope is not active"));[scope endScope];prismel_active_capture_scopes.erase(identity);}CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_capture_scope_queue_identity(value raw,value metal4_raw){
  CAMLparam2(raw,metal4_raw);CAMLlocal3(option,handle,result);@try{id<MTLCaptureScope>scope=object_of_handle(raw,Handle_kind::Capture_scope);if(Bool_val(metal4_raw)){if(@available(macOS 26.0,*)){id<MTL4CommandQueue>queue=scope.mtl4CommandQueue;if(queue==nil)option=Val_none;else{handle=allocate_handle(queue,Handle_kind::Command_queue4);option=caml_alloc(1,0);Store_field(option,0,handle);}}else CAMLreturn(result_error_text("Metal4 capture scope queues require macOS 26"));}else{id<MTLCommandQueue>queue=scope.commandQueue;if(queue==nil)option=Val_none;else{handle=allocate_handle(queue,Handle_kind::Command_queue);option=caml_alloc(1,0);Store_field(option,0,handle);}}result=result_ok(option);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
