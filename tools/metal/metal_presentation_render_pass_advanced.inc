extern "C" CAMLprim value caml_prismel_metal_render_pass_advanced_set(value raw,value values){
  CAMLparam2(raw,values);@try{
    if(!Is_block(values)||Wosize_val(values)!=7)CAMLreturn(result_error_text("advanced render-pass tuple shape is invalid"));
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);
    int64_t image=Int64_val(Field(values,0)),memory=Int64_val(Field(values,1)),tw=Int64_val(Field(values,2)),th=Int64_val(Field(values,3)),visibility=Int64_val(Field(values,4));
    if(image<0||memory<0||tw<0||th<0||(visibility!=0&&visibility!=1))CAMLreturn(result_error_text("advanced render-pass values are invalid"));
    p.imageblockSampleLength=image;p.threadgroupMemoryLength=memory;p.tileWidth=tw;p.tileHeight=th;
    if(@available(macOS 26.0,*)){p.visibilityResultType=(MTLVisibilityResultType)visibility;p.supportColorAttachmentMapping=Bool_val(Field(values,5));}
    else if(visibility!=0||Bool_val(Field(values,5)))CAMLreturn(result_error_text("visibility and color mapping require macOS 26"));
    value samples=Field(values,6);mlsize_t count=Wosize_val(samples);
    if(count!=0&&count!=2&&count!=4&&count!=8)CAMLreturn(result_error_text("sample count must be 0, 2, 4, or 8"));
    std::vector<MTLSamplePosition>positions(count);for(mlsize_t i=0;i<count;++i){value pair=Field(samples,i);double x=Double_val(Field(pair,0)),y=Double_val(Field(pair,1));if(!std::isfinite(x)||!std::isfinite(y)||x<0||x>1||y<0||y>1)CAMLreturn(result_error_text("sample position is invalid"));positions[i]=MTLSamplePositionMake(x,y);}
    [p setSamplePositions:count==0?nullptr:positions.data() count:count];CAMLreturn(result_unit());
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_pass_advanced_get(value raw){
  CAMLparam1(raw);CAMLlocal4(tuple,samples,pair,result);@try{
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);NSUInteger count=[p getSamplePositions:nullptr count:0];std::vector<MTLSamplePosition>positions(count);if([p getSamplePositions:count==0?nullptr:positions.data() count:count]!=count)CAMLreturn(result_error_text("sample-position copy failed"));
    samples=caml_alloc(count,0);for(NSUInteger i=0;i<count;++i){pair=caml_alloc_tuple(2);Store_field(pair,0,caml_copy_double(positions[i].x));Store_field(pair,1,caml_copy_double(positions[i].y));Store_field(samples,i,pair);}
    int64_t visibility=0;bool mapping=false;if(@available(macOS 26.0,*)){visibility=p.visibilityResultType;mapping=p.supportColorAttachmentMapping;}
    tuple=caml_alloc_tuple(7);Store_field(tuple,0,caml_copy_int64(p.imageblockSampleLength));Store_field(tuple,1,caml_copy_int64(p.threadgroupMemoryLength));Store_field(tuple,2,caml_copy_int64(p.tileWidth));Store_field(tuple,3,caml_copy_int64(p.tileHeight));Store_field(tuple,4,caml_copy_int64(visibility));Store_field(tuple,5,Val_bool(mapping));Store_field(tuple,6,samples);result=result_ok(tuple);CAMLreturn(result);
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_pass_reset_depth_stencil(value raw){CAMLparam1(raw);@try{MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);p.depthAttachment=nil;p.stencilAttachment=nil;if(p.depthAttachment==nil||p.stencilAttachment==nil)CAMLreturn(result_error_text("Metal changed null-reset attachment behavior"));CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_pass_sample_attachments(value raw){CAMLparam1(raw);CAMLlocal2(handle,result);@try{MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);handle=allocate_handle(p.sampleBufferAttachments,Handle_kind::Render_sample_attachment_array);result=result_ok(handle);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_pass_set_rate_map(value raw,value map){CAMLparam2(raw,map);@try{MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);p.rasterizationRateMap=Is_none(map)?nil:object_of_handle(Field(map,0),Handle_kind::Raster_rate_map);CAMLreturn(result_unit());}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}
extern "C" CAMLprim value caml_prismel_metal_render_pass_sizes(value raw){CAMLparam1(raw);CAMLlocal2(tuple,result);@try{MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);tuple=caml_alloc_tuple(4);Store_field(tuple,0,caml_copy_int64(p.renderTargetWidth));Store_field(tuple,1,caml_copy_int64(p.renderTargetHeight));Store_field(tuple,2,caml_copy_int64(p.renderTargetArrayLength));Store_field(tuple,3,caml_copy_int64(p.defaultRasterSampleCount));result=result_ok(tuple);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}

extern "C" CAMLprim value caml_prismel_metal_render_pass_sample_set(
    value raw,value raw_index,value raw_buffer,value raw_sv,value raw_ev,
    value raw_sf,value raw_ef){
  CAMLparam5(raw,raw_index,raw_buffer,raw_sv,raw_ev);CAMLxparam2(raw_sf,raw_ef);
  int64_t index=Int64_val(raw_index);
  if(index<0||index>=4)CAMLreturn(result_error_text("render sample attachment index is outside [0,4)"));
  @try{
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);
    MTLRenderPassSampleBufferAttachmentDescriptor*source=nil;
    if(!Is_none(raw_buffer)){
      source=[MTLRenderPassSampleBufferAttachmentDescriptor new];
      source.sampleBuffer=object_of_handle(Field(raw_buffer,0),Handle_kind::Counter_sample_buffer);
      source.startOfVertexSampleIndex=(NSUInteger)Int64_val(raw_sv);
      source.endOfVertexSampleIndex=(NSUInteger)Int64_val(raw_ev);
      source.startOfFragmentSampleIndex=(NSUInteger)Int64_val(raw_sf);
      source.endOfFragmentSampleIndex=(NSUInteger)Int64_val(raw_ef);
    }
    [p.sampleBufferAttachments setObject:source atIndexedSubscript:(NSUInteger)index];
    MTLRenderPassSampleBufferAttachmentDescriptor*stored=
      [p.sampleBufferAttachments objectAtIndexedSubscript:(NSUInteger)index];
    if(stored==nil||stored==source)CAMLreturn(result_error_text("Metal changed render sample attachment copy/reset semantics"));
    if(source!=nil&&(stored.sampleBuffer!=source.sampleBuffer||
       stored.startOfVertexSampleIndex!=source.startOfVertexSampleIndex||
       stored.endOfVertexSampleIndex!=source.endOfVertexSampleIndex||
       stored.startOfFragmentSampleIndex!=source.startOfFragmentSampleIndex||
       stored.endOfFragmentSampleIndex!=source.endOfFragmentSampleIndex))
      CAMLreturn(result_error_text("Metal changed render sample attachment values"));
    if(source==nil&&stored.sampleBuffer!=nil)
      CAMLreturn(result_error_text("Metal failed to reset render sample attachment"));
    CAMLreturn(result_unit());
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_render_pass_sample_set_bytecode(value*argv,int argc){(void)argc;return caml_prismel_metal_render_pass_sample_set(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5],argv[6]);}

extern "C" CAMLprim value caml_prismel_metal_render_pass_resolve_texture(
    value raw,value replacement,value set_raw){
  CAMLparam3(raw,replacement,set_raw);CAMLlocal3(handle,option,result);
  @try{
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);
    MTLRenderPassColorAttachmentDescriptor*color=p.colorAttachments[0];
    if(Bool_val(set_raw))color.resolveTexture=Is_none(replacement)?nil:object_of_handle(Field(replacement,0),Handle_kind::Texture);
    id<MTLTexture>texture=color.resolveTexture;
    if(texture==nil)option=Val_none;else{handle=allocate_handle(texture,Handle_kind::Texture);option=caml_alloc(1,0);Store_field(option,0,handle);}
    result=result_ok(option);CAMLreturn(result);
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_render_pass_color_store_action(value raw,value action){
  CAMLparam2(raw,action);
  @try{
    MTLRenderPassDescriptor*p=object_of_handle(raw,Handle_kind::Render_pass_descriptor);
    p.colorAttachments[0].storeAction=(MTLStoreAction)Int_val(action);
    CAMLreturn(result_unit());
  }@catch(NSException*x){CAMLreturn(result_error(x.reason));}
}
