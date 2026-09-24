/* Final exact MTLDevice selector closure: two function handles, one immutable
   argument-descriptor array constructor, and the synchronous render pipeline
   constructor. */
extern "C" CAMLprim value caml_prismel_metal_device_function_handle(
    value raw_device, value raw_function, value raw_binary) {
  CAMLparam3(raw_device, raw_function, raw_binary); CAMLlocal3(result,raw,option);
  @try {
    id<MTLDevice> device=object_of_handle(raw_device,Handle_kind::Device);
    id<MTLFunctionHandle> handle = Bool_val(raw_binary)
      ? [device functionHandleWithBinaryFunction:object_of_handle(raw_function,Handle_kind::Binary_function)]
      : [device functionHandleWithFunction:object_of_handle(raw_function,Handle_kind::Function)];
    if(handle==nil)CAMLreturn(result_ok(Val_none));raw=allocate_handle(handle,Handle_kind::Function_handle);option=caml_alloc(1,0);Store_field(option,0,raw);result=result_ok(option);CAMLreturn(result);
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));}
}

extern "C" CAMLprim value caml_prismel_metal_device_argument_encoder(
    value raw_device, value raw_descriptors) {
  CAMLparam2(raw_device,raw_descriptors);CAMLlocal3(handle,tuple,result);
  mlsize_t count=Wosize_val(raw_descriptors);
  if(count==0)CAMLreturn(result_error_text("argument descriptor list is empty"));
  @try {
    NSMutableArray<MTLArgumentDescriptor*>*descriptors=[NSMutableArray arrayWithCapacity:count];
    for(mlsize_t i=0;i<count;i++){
      value item=Field(raw_descriptors,i);int64_t data=Int64_val(Field(item,0)),index=Int64_val(Field(item,1)),length=Int64_val(Field(item,2)),access=Int64_val(Field(item,3)),texture=Int64_val(Field(item,4)),alignment=Int64_val(Field(item,5));
      if(data<0||index<0||length<=0||access<0||access>2||texture<0||alignment<0)
        CAMLreturn(result_error_text("argument descriptor metadata is invalid"));
      MTLArgumentDescriptor*d=[MTLArgumentDescriptor argumentDescriptor];d.dataType=(MTLDataType)data;d.index=index;d.arrayLength=length;d.access=(MTLBindingAccess)access;d.textureType=(MTLTextureType)texture;d.constantBlockAlignment=alignment;[descriptors addObject:d];
    }
    id<MTLDevice>device=object_of_handle(raw_device,Handle_kind::Device);id<MTLArgumentEncoder>encoder=[device newArgumentEncoderWithArguments:descriptors];
    if(!encoder)CAMLreturn(result_error_text("Metal returned no argument encoder"));
    handle=allocate_handle(encoder,Handle_kind::Shader_argument_encoder);tuple=caml_alloc_tuple(4);Store_field(tuple,0,handle);Store_field(tuple,1,caml_copy_int64(encoder.encodedLength));Store_field(tuple,2,caml_copy_int64(encoder.alignment));Store_field(tuple,3,caml_copy_int64(device.registryID));result=result_ok(tuple);CAMLreturn(result);
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));}
}

extern "C" CAMLprim value caml_prismel_metal_device_render_pipeline_simple(
    value raw_device,value raw_descriptor){CAMLparam2(raw_device,raw_descriptor);CAMLlocal2(handle,result);@try{id<MTLDevice>device=object_of_handle(raw_device,Handle_kind::Device);MTLRenderPipelineDescriptor*descriptor=object_of_handle(raw_descriptor,Handle_kind::Render_pipeline_descriptor);NSError*error=nil;id<MTLRenderPipelineState>pipeline=[device newRenderPipelineStateWithDescriptor:descriptor error:&error];if(!pipeline)CAMLreturn(result_error(error_description(error,@"render pipeline creation failed")));handle=allocate_handle(pipeline,Handle_kind::Render_pipeline);result=result_ok(handle);CAMLreturn(result);}@catch(NSException*exception){CAMLreturn(result_error(exception.reason));}}
