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

extern "C" CAMLprim value caml_prismel_metal_render93_descriptor_label(value raw,value kind_raw,value set_raw,value replacement) {
  CAMLparam4(raw,kind_raw,set_raw,replacement); CAMLlocal2(copied,result);
  @try {
    NSString *label=Is_none(replacement)?nil:string_from_ocaml(Field(replacement,0));
    if(!Is_none(replacement)&&label==nil)CAMLreturn(result_error_text("render pipeline label is not valid UTF-8"));
    switch(Long_val(kind_raw)) {
      case 0: { MTLRenderPipelineDescriptor*d=object_of_handle(raw,Handle_kind::Render_pipeline_descriptor); if(Bool_val(set_raw))d.label=label; copied=copy_optional_string(d.label); break; }
      case 1: { MTLMeshRenderPipelineDescriptor*d=object_of_handle(raw,Handle_kind::Mesh_pipeline_descriptor); if(Bool_val(set_raw))d.label=label; copied=copy_optional_string(d.label); break; }
      case 2: { MTLTileRenderPipelineDescriptor*d=object_of_handle(raw,Handle_kind::Tile_pipeline_descriptor); if(Bool_val(set_raw))d.label=label; copied=copy_optional_string(d.label); break; }
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

extern "C" CAMLprim value caml_prismel_metal_render93_color_at(value descriptor_raw,value index_raw,value set_raw,value replacement) {
  CAMLparam4(descriptor_raw,index_raw,set_raw,replacement); CAMLlocal3(handle,result,option);
  int64_t index=Int64_val(index_raw);
  if(index<0||index>=8)CAMLreturn(result_error_text("render pipeline color attachment index is out of range"));
  @try {
    MTLRenderPipelineDescriptor*d=object_of_handle(descriptor_raw,Handle_kind::Render_pipeline_descriptor);
    if(Bool_val(set_raw))d.colorAttachments[(NSUInteger)index]=Is_none(replacement)?nil:object_of_handle(Field(replacement,0),Handle_kind::Color_attachment_descriptor);
    MTLRenderPipelineColorAttachmentDescriptor*color=d.colorAttachments[(NSUInteger)index];
    if(color==nil||color.pixelFormat==MTLPixelFormatInvalid)CAMLreturn(result_ok(Val_none));
    handle=allocate_handle(color,Handle_kind::Color_attachment_descriptor);
    option=caml_alloc(1,0); Store_field(option,0,handle); result=result_ok(option); CAMLreturn(result);
  } @catch(NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

/* operation 0 binary archives, 1 object function, 2 mesh function,
   3 fragment function. [expected] is also the replacement when [set_raw]. */
extern "C" CAMLprim value caml_prismel_metal_render93_mesh_graph(value descriptor_raw,value operation_raw,value set_raw,value expected) {
  CAMLparam4(descriptor_raw,operation_raw,set_raw,expected);
  @try {
    MTLMeshRenderPipelineDescriptor*d=object_of_handle(descriptor_raw,Handle_kind::Mesh_pipeline_descriptor);
    int operation=Long_val(operation_raw);
    if(operation==0){
      NSMutableArray<id<MTLBinaryArchive>>*items=[NSMutableArray arrayWithCapacity:Wosize_val(expected)];
      for(mlsize_t i=0;i<Wosize_val(expected);i++)[items addObject:object_of_handle(Field(expected,i),Handle_kind::Binary_archive)];
      if(Bool_val(set_raw))d.binaryArchives=items;
      if(d.binaryArchives.count!=items.count)CAMLreturn(result_error_text("mesh binary archive graph changed"));
      for(NSUInteger i=0;i<items.count;i++)if(d.binaryArchives[i]!=items[i])CAMLreturn(result_error_text("mesh binary archive identity changed"));
    }else if(operation>=1&&operation<=3){
      if(Wosize_val(expected)>1)CAMLreturn(result_error_text("mesh function graph cardinality is invalid"));
      id<MTLFunction>function=Wosize_val(expected)==0?nil:object_of_handle(Field(expected,0),Handle_kind::Function);
      if(operation==1){if(Bool_val(set_raw))d.objectFunction=function;if(d.objectFunction!=function)CAMLreturn(result_error_text("mesh object function identity changed"));}
      if(operation==2){if(Bool_val(set_raw))d.meshFunction=function;if(d.meshFunction!=function)CAMLreturn(result_error_text("mesh function identity changed"));}
      if(operation==3){if(Bool_val(set_raw))d.fragmentFunction=function;if(d.fragmentFunction!=function)CAMLreturn(result_error_text("mesh fragment function identity changed"));}
    }else CAMLreturn(result_error_text("unknown mesh pipeline graph operation"));
    CAMLreturn(result_unit());
  } @catch(NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

/* operation 0 binary archives, 1 preloaded libraries, 2 tile function. */
extern "C" CAMLprim value caml_prismel_metal_render93_tile_graph(value descriptor_raw,value operation_raw,value set_raw,value expected) {
  CAMLparam4(descriptor_raw,operation_raw,set_raw,expected);
  @try {
    MTLTileRenderPipelineDescriptor*d=object_of_handle(descriptor_raw,Handle_kind::Tile_pipeline_descriptor);
    int operation=Long_val(operation_raw);
    if(operation==0){
      NSMutableArray<id<MTLBinaryArchive>>*items=[NSMutableArray arrayWithCapacity:Wosize_val(expected)];
      for(mlsize_t i=0;i<Wosize_val(expected);i++)[items addObject:object_of_handle(Field(expected,i),Handle_kind::Binary_archive)];
      if(Bool_val(set_raw))d.binaryArchives=items;
      if(d.binaryArchives.count!=items.count)CAMLreturn(result_error_text("tile binary archive graph changed"));
      for(NSUInteger i=0;i<items.count;i++)if(d.binaryArchives[i]!=items[i])CAMLreturn(result_error_text("tile binary archive identity changed"));
    }else if(operation==1){
      NSMutableArray<id<MTLDynamicLibrary>>*items=[NSMutableArray arrayWithCapacity:Wosize_val(expected)];
      for(mlsize_t i=0;i<Wosize_val(expected);i++)[items addObject:object_of_handle(Field(expected,i),Handle_kind::Dynamic_library)];
      if(Bool_val(set_raw))d.preloadedLibraries=items;
      if(d.preloadedLibraries.count!=items.count)CAMLreturn(result_error_text("tile preloaded library graph changed"));
      for(NSUInteger i=0;i<items.count;i++)if(d.preloadedLibraries[i]!=items[i])CAMLreturn(result_error_text("tile preloaded library identity changed"));
    }else if(operation==2){
      if(Wosize_val(expected)>1)CAMLreturn(result_error_text("tile function graph cardinality is invalid"));
      id<MTLFunction>function=Wosize_val(expected)==0?nil:object_of_handle(Field(expected,0),Handle_kind::Function);
      if(Bool_val(set_raw))d.tileFunction=function;
      if(d.tileFunction!=function)CAMLreturn(result_error_text("tile function identity changed"));
    }else CAMLreturn(result_error_text("unknown tile pipeline graph operation"));
    CAMLreturn(result_unit());
  } @catch(NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}
