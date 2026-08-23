extern "C" CAMLprim value caml_prismel_metal_render_pass_advanced_set(value raw,value values){
  CAMLparam2(raw,values);@try{
    if(!Is_block(values)||Wosize_val(values)!=7)CAMLreturn(result_error_text("advanced render-pass tuple shape is invalid"));
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);
    int64_t image=Int64_val(Field(values,0)),memory=Int64_val(Field(values,1)),tw=Int64_val(Field(values,2)),th=Int64_val(Field(values,3)),visibility=Int64_val(Field(values,4));
    if(image<0||memory<0||tw<0||th<0||(visibility!=0&&visibility!=1))CAMLreturn(result_error_text("advanced render-pass values are invalid"));
    p.imageblockSampleLength=image;p.threadgroupMemoryLength=memory;p.tileWidth=tw;p.tileHeight=th;
    if(@available(macOS 26.0,*)){p.visibilityResultType=(MTLVisibilityResultType)visibility;p.supportColorAttachmentMapping=Bool_val(Field(values,5));}
    else if(visibility!=0||Bool_val(Field(values,5)))CAMLreturn(result_error_text("visibility and color mapping require macOS 26"));
    p.rasterizationRateMap=nil;value samples=Field(values,6);mlsize_t count=Wosize_val(samples);
    if(count!=0&&count!=2&&count!=4&&count!=8)CAMLreturn(result_error_text("sample count must be 0, 2, 4, or 8"));
    std::vector<MTLSamplePosition>positions(count);for(mlsize_t i=0;i<count;++i){value pair=Field(samples,i);double x=Double_val(Field(pair,0)),y=Double_val(Field(pair,1));if(!std::isfinite(x)||!std::isfinite(y)||x<0||x>1||y<0||y>1)CAMLreturn(result_error_text("sample position is invalid"));positions[i]=MTLSamplePositionMake(x,y);}
    [p setSamplePositions:count==0?nullptr:positions.data() count:count];CAMLreturn(result_unit());
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_pass_advanced_get(value raw){
  CAMLparam1(raw);CAMLlocal4(tuple,samples,pair,result);@try{
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);NSUInteger count=[p getSamplePositions:nullptr count:0];std::vector<MTLSamplePosition>positions(count);if([p getSamplePositions:count==0?nullptr:positions.data() count:count]!=count)CAMLreturn(result_error_text("sample-position copy failed"));
    samples=caml_alloc(count,0);for(NSUInteger i=0;i<count;++i){pair=caml_alloc_tuple(2);Store_field(pair,0,caml_copy_double(positions[i].x));Store_field(pair,1,caml_copy_double(positions[i].y));Store_field(samples,i,pair);}
    int64_t visibility=0;bool mapping=false;if(@available(macOS 26.0,*)){visibility=p.visibilityResultType;mapping=p.supportColorAttachmentMapping;}
    tuple=caml_alloc_tuple(7);Store_field(tuple,0,caml_copy_int64(p.imageblockSampleLength));Store_field(tuple,1,caml_copy_int64(p.threadgroupMemoryLength));Store_field(tuple,2,caml_copy_int64(p.tileWidth));Store_field(tuple,3,caml_copy_int64(p.tileHeight));Store_field(tuple,4,caml_copy_int64(visibility));Store_field(tuple,5,Val_bool(mapping));Store_field(tuple,6,samples);if(p.rasterizationRateMap!=nil)CAMLreturn(result_error_text("unchecked rasterization-rate map graph"));result=result_ok(tuple);CAMLreturn(result);
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_pass_reset_depth_stencil(value raw){CAMLparam1(raw);@try{MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);p.depthAttachment=nil;p.stencilAttachment=nil;if(p.depthAttachment==nil||p.stencilAttachment==nil)CAMLreturn(result_error_text("Metal changed null-reset attachment behavior"));CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_pass_sample_attachments(value raw){CAMLparam1(raw);CAMLlocal2(handle,result);@try{MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);handle=allocate_handle(p.sampleBufferAttachments,Handle_kind::Render_sample_attachment_array);result=result_ok(handle);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
