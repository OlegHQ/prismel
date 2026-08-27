/* Exact final three MTLDevice constructors. */
extern "C" CAMLprim value caml_prismel_metal_device_compute_reflection_pipeline(
    value raw_device, value raw_function) {
  CAMLparam2(raw_device, raw_function); CAMLlocal2(raw, result);
  @try {
    id<MTLDevice> device=object_of_handle(raw_device,Handle_kind::Device);
    id<MTLFunction> function=object_of_handle(raw_function,Handle_kind::Function);
    MTLComputePipelineReflection *reflection=nil; NSError *failure=nil;
    id<MTLComputePipelineState> pipeline=[device
      newComputePipelineStateWithFunction:function options:MTLPipelineOptionBindingInfo
      reflection:&reflection error:&failure];
    (void)reflection;
    if(!pipeline)CAMLreturn(result_error(error_description(failure,@"compute reflection pipeline failed")));
    raw=allocate_handle(pipeline,Handle_kind::Compute_pipeline);
    result=result_ok(raw);CAMLreturn(result);
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));}
}

extern "C" CAMLprim value caml_prismel_metal_device_argument_encoder_binding(
    value raw_device,value raw_function,value raw_index){
  CAMLparam3(raw_device,raw_function,raw_index);CAMLlocal3(raw,tuple,result);
  int64_t index=Int64_val(raw_index);
  if(index<0)CAMLreturn(result_error_text("buffer binding index is negative"));
  @try{
    id<MTLDevice>device=object_of_handle(raw_device,Handle_kind::Device);
    id<MTLFunction>function=object_of_handle(raw_function,Handle_kind::Function);
    MTLComputePipelineReflection*reflection=nil;NSError*failure=nil;
    id<MTLComputePipelineState>pipeline=[device
      newComputePipelineStateWithFunction:function options:MTLPipelineOptionBindingInfo
      reflection:&reflection error:&failure];
    if(!pipeline)CAMLreturn(result_error(error_description(failure,@"buffer binding reflection failed")));
    id<MTLBufferBinding>binding=nil;
    for(id<MTLBinding>candidate in reflection.bindings)
      if(candidate.type==MTLBindingTypeBuffer&&(int64_t)candidate.index==index){binding=(id<MTLBufferBinding>)candidate;break;}
    if(!binding)CAMLreturn(result_error_text("no reflected buffer binding at index"));
    id<MTLArgumentEncoder>encoder=[device newArgumentEncoderWithBufferBinding:binding];
    if(!encoder)CAMLreturn(result_error_text("Metal returned no argument encoder"));
    raw=allocate_handle(encoder,Handle_kind::Shader_argument_encoder);
    tuple=caml_alloc_tuple(4);Store_field(tuple,0,raw);
    Store_field(tuple,1,caml_copy_int64(encoder.encodedLength));
    Store_field(tuple,2,caml_copy_int64(encoder.alignment));
    Store_field(tuple,3,caml_copy_int64(device.registryID));
    result=result_ok(tuple);CAMLreturn(result);
  }@catch(NSException*exception){CAMLreturn(result_error(exception.reason));}
}

extern "C" CAMLprim value caml_prismel_metal_device_shared_event_handle(
    value raw_device,value raw_handle){
  CAMLparam2(raw_device,raw_handle);CAMLlocal3(raw,pair,result);
  @try{id<MTLDevice>device=object_of_handle(raw_device,Handle_kind::Device);
    MTLSharedEventHandle*handle=object_of_handle(raw_handle,Handle_kind::Shared_event_handle);
    id<MTLSharedEvent>event=[device newSharedEventWithHandle:handle];
    if(!event)CAMLreturn(result_error_text("Metal returned no shared event"));
    raw=allocate_handle(event,Handle_kind::Shared_event);pair=caml_alloc_tuple(2);
    Store_field(pair,0,raw);Store_field(pair,1,caml_copy_int64(device.registryID));
    result=result_ok(pair);CAMLreturn(result);
  }@catch(NSException*exception){CAMLreturn(result_error(exception.reason));}
}
