/* Isolated resource100 descriptor-owned shard.  Transplant after adding the
   three explicit Handle_kind cases named below. */
extern "C" CAMLprim value caml_prismel_metal_resource_buffer_layout_create(value unit){
  CAMLparam1(unit); CAMLlocal2(raw,result); @autoreleasepool { @try {
    raw=allocate_handle([MTLBufferLayoutDescriptor new],Handle_kind::Buffer_layout_descriptor);
    result=result_ok(raw); CAMLreturn(result);
  } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
}
#define PRISMEL_LAYOUT_GET(NAME,PROP) extern "C" CAMLprim value NAME(value raw){ CAMLparam1(raw); CAMLlocal2(v,result); @try { MTLBufferLayoutDescriptor *d=object_of_handle(raw,Handle_kind::Buffer_layout_descriptor); v=caml_copy_int64((int64_t)d.PROP); result=result_ok(v); CAMLreturn(result); } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
#define PRISMEL_LAYOUT_SET(NAME,PROP) extern "C" CAMLprim value NAME(value raw,value v){ CAMLparam2(raw,v); @try { MTLBufferLayoutDescriptor *d=object_of_handle(raw,Handle_kind::Buffer_layout_descriptor); d.PROP=(NSUInteger)Int64_val(v); CAMLreturn(result_unit()); } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
PRISMEL_LAYOUT_GET(caml_prismel_metal_resource_buffer_layout_stride,stride)
PRISMEL_LAYOUT_SET(caml_prismel_metal_resource_buffer_layout_set_stride,stride)
PRISMEL_LAYOUT_GET(caml_prismel_metal_resource_buffer_layout_step_rate,stepRate)
PRISMEL_LAYOUT_SET(caml_prismel_metal_resource_buffer_layout_set_step_rate,stepRate)
PRISMEL_LAYOUT_GET(caml_prismel_metal_resource_buffer_layout_step_function,stepFunction)
extern "C" CAMLprim value caml_prismel_metal_resource_buffer_layout_set_step_function(value raw,value v){ CAMLparam2(raw,v); @try { MTLBufferLayoutDescriptor*d=object_of_handle(raw,Handle_kind::Buffer_layout_descriptor); d.stepFunction=(MTLStepFunction)Int64_val(v); CAMLreturn(result_unit()); } @catch(NSException*e){CAMLreturn(result_error(e.reason));} }
#undef PRISMEL_LAYOUT_GET
#undef PRISMEL_LAYOUT_SET

extern "C" CAMLprim value caml_prismel_metal_resource_sample_attachment_create(value unit){
  CAMLparam1(unit); CAMLlocal2(raw,result); @autoreleasepool { @try {
    raw=allocate_handle([MTLResourceStatePassSampleBufferAttachmentDescriptor new],Handle_kind::Resource_state_sample_attachment_descriptor);
    result=result_ok(raw); CAMLreturn(result);
  } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
}
#define PRISMEL_SAMPLE_GET(NAME,PROP) extern "C" CAMLprim value NAME(value raw){ CAMLparam1(raw); CAMLlocal2(v,result); @try { MTLResourceStatePassSampleBufferAttachmentDescriptor *d=object_of_handle(raw,Handle_kind::Resource_state_sample_attachment_descriptor); v=caml_copy_int64((int64_t)d.PROP); result=result_ok(v); CAMLreturn(result); } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
#define PRISMEL_SAMPLE_SET(NAME,PROP) extern "C" CAMLprim value NAME(value raw,value v){ CAMLparam2(raw,v); @try { MTLResourceStatePassSampleBufferAttachmentDescriptor *d=object_of_handle(raw,Handle_kind::Resource_state_sample_attachment_descriptor); d.PROP=(NSUInteger)Int64_val(v); CAMLreturn(result_unit()); } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
PRISMEL_SAMPLE_GET(caml_prismel_metal_resource_sample_attachment_start,startOfEncoderSampleIndex)
PRISMEL_SAMPLE_SET(caml_prismel_metal_resource_sample_attachment_set_start,startOfEncoderSampleIndex)
PRISMEL_SAMPLE_GET(caml_prismel_metal_resource_sample_attachment_end,endOfEncoderSampleIndex)
PRISMEL_SAMPLE_SET(caml_prismel_metal_resource_sample_attachment_set_end,endOfEncoderSampleIndex)
#undef PRISMEL_SAMPLE_GET
#undef PRISMEL_SAMPLE_SET

extern "C" CAMLprim value caml_prismel_metal_resource_view_pool_descriptor_create(value unit){
  CAMLparam1(unit); CAMLlocal2(raw,result); @autoreleasepool { @try {
    if(@available(macOS 26.0,*)){ raw=allocate_handle([MTLResourceViewPoolDescriptor new],Handle_kind::Resource_view_pool_descriptor); result=result_ok(raw); CAMLreturn(result); }
    CAMLreturn(result_error_text("MTLResourceViewPoolDescriptor requires macOS 26.0"));
  } @catch(NSException *e){ CAMLreturn(result_error(e.reason)); } }
}
extern "C" CAMLprim value caml_prismel_metal_resource_view_pool_descriptor_count(value raw){
  CAMLparam1(raw); CAMLlocal2(v,result); @try { if(@available(macOS 26.0,*)){ MTLResourceViewPoolDescriptor*d=object_of_handle(raw,Handle_kind::Resource_view_pool_descriptor); v=caml_copy_int64((int64_t)d.resourceViewCount); result=result_ok(v); CAMLreturn(result); } CAMLreturn(result_error_text("resource view pools require macOS 26.0")); } @catch(NSException*e){CAMLreturn(result_error(e.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_resource_view_pool_descriptor_set_count(value raw,value count){
  CAMLparam2(raw,count); @try { if(@available(macOS 26.0,*)){ MTLResourceViewPoolDescriptor*d=object_of_handle(raw,Handle_kind::Resource_view_pool_descriptor); d.resourceViewCount=(NSUInteger)Int64_val(count); CAMLreturn(result_unit()); } CAMLreturn(result_error_text("resource view pools require macOS 26.0")); } @catch(NSException*e){CAMLreturn(result_error(e.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_resource_view_pool_descriptor_label(value raw){
  CAMLparam1(raw); CAMLlocal3(v,option,result); @try { if(@available(macOS 26.0,*)){ MTLResourceViewPoolDescriptor*d=object_of_handle(raw,Handle_kind::Resource_view_pool_descriptor); if(!d.label)CAMLreturn(result_ok(Val_none)); v=caml_copy_string(d.label.UTF8String); option=caml_alloc(1,0); Store_field(option,0,v); result=result_ok(option); CAMLreturn(result); } CAMLreturn(result_error_text("resource view pools require macOS 26.0")); } @catch(NSException*e){CAMLreturn(result_error(e.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_resource_view_pool_descriptor_set_label(value raw,value label){
  CAMLparam2(raw,label); @try { if(@available(macOS 26.0,*)){ MTLResourceViewPoolDescriptor*d=object_of_handle(raw,Handle_kind::Resource_view_pool_descriptor); d.label=Is_none(label)?nil:[NSString stringWithUTF8String:String_val(Field(label,0))]; CAMLreturn(result_unit()); } CAMLreturn(result_error_text("resource view pools require macOS 26.0")); } @catch(NSException*e){CAMLreturn(result_error(e.reason));}
}
