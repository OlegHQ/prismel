/* Typed enablers for the final Resource100 ownership graphs.  This include is
   intentionally standalone until the shared bridge owner yields integration. */
extern "C" CAMLprim value caml_prismel_metal_resource_layout_array_create(value unit) {
  CAMLparam1(unit); CAMLlocal2(raw,result); @try {
    MTLBufferLayoutDescriptorArray *array=[MTLBufferLayoutDescriptorArray new];
    if(array==nil) CAMLreturn(result_error_text("buffer-layout array construction returned nil"));
    raw=allocate_handle(array,Handle_kind::Buffer_layout_descriptor_array);
    result=result_ok(raw); CAMLreturn(result);
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));}
}

extern "C" CAMLprim value caml_prismel_metal_resource_texture_view_descriptor_create(
    value format,value type,value level_location,value level_length,
    value slice_location,value slice_length) {
  CAMLparam5(format,type,level_location,level_length,slice_location);
  CAMLxparam1(slice_length); CAMLlocal2(raw,result); @try {
    if(@available(macOS 26.0,*)) {
      int64_t ll=Int64_val(level_length),sl=Int64_val(slice_length);
      if(ll<=0||sl<=0) CAMLreturn(result_error_text("texture-view ranges must be nonempty"));
      MTLTextureViewDescriptor *descriptor=[MTLTextureViewDescriptor new];
      descriptor.pixelFormat=(MTLPixelFormat)Int64_val(format);
      descriptor.textureType=(MTLTextureType)Int64_val(type);
      descriptor.levelRange=NSMakeRange(Int64_val(level_location),ll);
      descriptor.sliceRange=NSMakeRange(Int64_val(slice_location),sl);
      raw=allocate_handle(descriptor,Handle_kind::Texture_view_descriptor);
      result=result_ok(raw); CAMLreturn(result);
    }
    CAMLreturn(result_error_text("texture-view descriptors require macOS 26.0"));
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_resource_texture_view_descriptor_create_bytecode(
    value *argv,int argc){(void)argc;return caml_prismel_metal_resource_texture_view_descriptor_create(argv[0],argv[1],argv[2],argv[3],argv[4],argv[5]);}

extern "C" CAMLprim value caml_prismel_metal_resource_heap_acceleration_triangle(
    value heap,value descriptor,value offset) {
  CAMLparam3(heap,descriptor,offset); CAMLlocal2(raw,result); @try {
    if(@available(macOS 13.0,*)) {
      id<MTLHeap> object=object_of_handle(heap,Handle_kind::Heap);
      MTLPrimitiveAccelerationStructureDescriptor *materialized=
        acceleration_triangle_descriptor_of_ocaml(descriptor);
      id<MTLAccelerationStructure> acceleration=Is_none(offset)
        ?[object newAccelerationStructureWithDescriptor:materialized]
        :[object newAccelerationStructureWithDescriptor:materialized
                                               offset:Int64_val(Field(offset,0))];
      if(acceleration==nil) CAMLreturn(result_error_text("heap acceleration allocation returned nil"));
      raw=allocate_handle(acceleration,Handle_kind::Acceleration_structure);
      result=result_ok(raw); CAMLreturn(result);
    }
    CAMLreturn(result_error_text("heap acceleration structures require macOS 13.0"));
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));}
}

static value prismel_resource_size_align(MTLSizeAndAlign size_and_align) {
  CAMLparam0(); CAMLlocal1(pair); pair=caml_alloc_tuple(2);
  Store_field(pair,0,caml_copy_int64(size_and_align.size));
  Store_field(pair,1,caml_copy_int64(size_and_align.align)); CAMLreturn(pair);
}
extern "C" CAMLprim value caml_prismel_metal_resource_heap_acceleration_size_align(
    value heap,value size) {
  CAMLparam2(heap,size); CAMLlocal2(pair,result); @try {
    if(@available(macOS 13.0,*)) {
      id<MTLHeap> object=object_of_handle(heap,Handle_kind::Heap);
      pair=prismel_resource_size_align(
        [object.device heapAccelerationStructureSizeAndAlignWithSize:Int64_val(size)]);
      result=result_ok(pair); CAMLreturn(result);
    }
    CAMLreturn(result_error_text("heap acceleration structures require macOS 13.0"));
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));}
}
extern "C" CAMLprim value caml_prismel_metal_resource_heap_acceleration_triangle_size_align(
    value heap,value descriptor) {
  CAMLparam2(heap,descriptor); CAMLlocal2(pair,result); @try {
    if(@available(macOS 13.0,*)) {
      id<MTLHeap> object=object_of_handle(heap,Handle_kind::Heap);
      pair=prismel_resource_size_align(
        [object.device heapAccelerationStructureSizeAndAlignWithDescriptor:
          acceleration_triangle_descriptor_of_ocaml(descriptor)]);
      result=result_ok(pair); CAMLreturn(result);
    }
    CAMLreturn(result_error_text("heap acceleration structures require macOS 13.0"));
  } @catch(NSException *exception){CAMLreturn(result_error(exception.reason));}
}
