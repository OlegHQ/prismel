/* RenderPipeline93 mechanical descriptor foundation. The OCaml safe layer
   owns graph semantics; these direct calls only construct/reset descriptors,
   copy labels, and access the checked color-attachment array. */
extern "C" CAMLprim value caml_prismel_metal_render93_descriptor_create(value kind_raw) {
  CAMLparam1(kind_raw); CAMLlocal2(handle,result);
  @try {
    switch (Long_val(kind_raw)) {
      case 0: handle=allocate_handle([MTLRenderPipelineDescriptor new],Handle_kind::Render_pipeline_descriptor); break;
      case 1: handle=allocate_handle([MTLMeshRenderPipelineDescriptor new],Handle_kind::Mesh_pipeline_descriptor); break;
      case 2: handle=allocate_handle([MTLTileRenderPipelineDescriptor new],Handle_kind::Tile_pipeline_descriptor); break;
      default: CAMLreturn(result_error_text("unknown render pipeline descriptor kind"));
    }
    result=result_ok(handle); CAMLreturn(result);
  } @catch(NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_render93_descriptor_label(value raw,value kind_raw,value replacement) {
  CAMLparam3(raw,kind_raw,replacement); CAMLlocal2(copied,result);
  @try {
    NSString *label=Is_none(replacement)?nil:string_from_ocaml(Field(replacement,0));
    if(!Is_none(replacement)&&label==nil)CAMLreturn(result_error_text("render pipeline label is not valid UTF-8"));
    switch(Long_val(kind_raw)) {
      case 0: { MTLRenderPipelineDescriptor*d=object_of_handle(raw,Handle_kind::Render_pipeline_descriptor); d.label=label; copied=copy_optional_string(d.label); break; }
      case 1: { MTLMeshRenderPipelineDescriptor*d=object_of_handle(raw,Handle_kind::Mesh_pipeline_descriptor); d.label=label; copied=copy_optional_string(d.label); break; }
      case 2: { MTLTileRenderPipelineDescriptor*d=object_of_handle(raw,Handle_kind::Tile_pipeline_descriptor); d.label=label; copied=copy_optional_string(d.label); break; }
      default: CAMLreturn(result_error_text("unknown render pipeline descriptor kind"));
    }
    result=result_ok(copied); CAMLreturn(result);
  } @catch(NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_render93_descriptor_reset(value raw,value kind_raw) {
  CAMLparam2(raw,kind_raw);
  @try {
    switch(Long_val(kind_raw)) {
      case 0: [object_of_handle(raw,Handle_kind::Render_pipeline_descriptor) reset]; break;
      case 1: [object_of_handle(raw,Handle_kind::Mesh_pipeline_descriptor) reset]; break;
      case 2: [object_of_handle(raw,Handle_kind::Tile_pipeline_descriptor) reset]; break;
      default: CAMLreturn(result_error_text("unknown render pipeline descriptor kind"));
    }
    CAMLreturn(result_unit());
  } @catch(NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_render93_color_at(value descriptor_raw,value index_raw,value replacement) {
  CAMLparam3(descriptor_raw,index_raw,replacement); CAMLlocal3(handle,result,option);
  int64_t index=Int64_val(index_raw);
  if(index<0||index>=8)CAMLreturn(result_error_text("render pipeline color attachment index is out of range"));
  @try {
    MTLRenderPipelineDescriptor*d=object_of_handle(descriptor_raw,Handle_kind::Render_pipeline_descriptor);
    if(Is_block(replacement))d.colorAttachments[(NSUInteger)index]=object_of_handle(Field(replacement,0),Handle_kind::Mesh_color_attachment);
    MTLRenderPipelineColorAttachmentDescriptor*color=d.colorAttachments[(NSUInteger)index];
    if(color==nil)CAMLreturn(result_ok(Val_none));
    handle=allocate_handle(color,Handle_kind::Mesh_color_attachment);
    option=caml_alloc(1,0); Store_field(option,0,handle); result=result_ok(option); CAMLreturn(result);
  } @catch(NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
