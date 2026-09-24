template<class T> static std::vector<T> prismel_compute_handles(value a, Handle_kind kind) {
  mlsize_t n = Wosize_val(a); std::vector<T> values; values.reserve(n);
  for (mlsize_t i = 0; i < n; ++i)
    values.push_back(Is_none(Field(a,i)) ? nil : object_of_handle(Field(Field(a,i),0), kind));
  return values;
}
static std::vector<NSUInteger> prismel_compute_uints(value a) {
  mlsize_t n = Wosize_val(a); std::vector<NSUInteger> values(n);
  for (mlsize_t i = 0; i < n; ++i) values[i] = Int64_val(Field(a,i));
  return values;
}
static std::vector<float> prismel_compute_floats(value a) {
  mlsize_t n = Wosize_val(a); std::vector<float> values(n);
  for (mlsize_t i = 0; i < n; ++i) values[i] = Double_val(Field(a,i));
  return values;
}
#define COMPUTE_ENTRY(NAME) extern "C" CAMLprim value NAME
#define COMPUTE_ENCODER(V) id<MTLComputeCommandEncoder> e = object_of_handle((V), Handle_kind::Compute_encoder)
#define COMPUTE_CATCH } @catch (NSException *x) { CAMLreturn(result_error(x.reason)); }

COMPUTE_ENTRY(caml_prismel_metal_compute35_buffer_stride)(value re,value rb,value ro,value rs,value ri){CAMLparam5(re,rb,ro,rs,ri);@try{COMPUTE_ENCODER(re);id<MTLBuffer>b=Is_none(rb)?nil:object_of_handle(Field(rb,0),Handle_kind::Buffer);[e setBuffer:b offset:Int64_val(ro) attributeStride:Int64_val(rs) atIndex:Int64_val(ri)];CAMLreturn(result_unit());COMPUTE_CATCH}
COMPUTE_ENTRY(caml_prismel_metal_compute35_buffer_offset)(value re,value ro,value ri){CAMLparam3(re,ro,ri);@try{COMPUTE_ENCODER(re);[e setBufferOffset:Int64_val(ro) atIndex:Int64_val(ri)];CAMLreturn(result_unit());COMPUTE_CATCH}
COMPUTE_ENTRY(caml_prismel_metal_compute35_buffer_offset_stride)(value re,value ro,value rs,value ri){CAMLparam4(re,ro,rs,ri);@try{COMPUTE_ENCODER(re);[e setBufferOffset:Int64_val(ro) attributeStride:Int64_val(rs) atIndex:Int64_val(ri)];CAMLreturn(result_unit());COMPUTE_CATCH}
COMPUTE_ENTRY(caml_prismel_metal_compute35_buffers_bytecode)(value*argv,int argc){(void)argc;CAMLparam0();@try{COMPUTE_ENCODER(argv[0]);auto b=prismel_compute_handles<id<MTLBuffer>>(argv[1],Handle_kind::Buffer);auto o=prismel_compute_uints(argv[2]);auto s=prismel_compute_uints(argv[3]);if(b.size()!=o.size()||(!s.empty()&&s.size()!=b.size()))CAMLreturn(result_error_text("compute buffer binding cardinality mismatch"));NSRange r=NSMakeRange(Int64_val(argv[4]),b.size());if(s.empty())[e setBuffers:b.data() offsets:o.data() withRange:r];else[e setBuffers:b.data() offsets:o.data() attributeStrides:s.data() withRange:r];CAMLreturn(result_unit());COMPUTE_CATCH}
COMPUTE_ENTRY(caml_prismel_metal_compute35_buffers)(value a,value b,value c,value d,value e){value argv[]={a,b,c,d,e};return caml_prismel_metal_compute35_buffers_bytecode(argv,5);}
COMPUTE_ENTRY(caml_prismel_metal_compute35_bytes)(value re,value rb,value rs,value ri){CAMLparam4(re,rb,rs,ri);@try{COMPUTE_ENCODER(re);[e setBytes:Bytes_val(rb) length:caml_string_length(rb) attributeStride:Int64_val(rs) atIndex:Int64_val(ri)];CAMLreturn(result_unit());COMPUTE_CATCH}
COMPUTE_ENTRY(caml_prismel_metal_compute35_textures)(value re,value ra,value rstart){CAMLparam3(re,ra,rstart);@try{COMPUTE_ENCODER(re);auto a=prismel_compute_handles<id<MTLTexture>>(ra,Handle_kind::Texture);[e setTextures:a.data() withRange:NSMakeRange(Int64_val(rstart),a.size())];CAMLreturn(result_unit());COMPUTE_CATCH}
COMPUTE_ENTRY(caml_prismel_metal_compute35_sampler)(value re,value rs,value rlod,value ri){CAMLparam4(re,rs,rlod,ri);@try{COMPUTE_ENCODER(re);id<MTLSamplerState>s=Is_none(rs)?nil:object_of_handle(Field(rs,0),Handle_kind::Sampler);NSUInteger i=Int64_val(ri);if(Is_none(rlod))[e setSamplerState:s atIndex:i];else{value p=Field(rlod,0);[e setSamplerState:s lodMinClamp:Double_val(Field(p,0)) lodMaxClamp:Double_val(Field(p,1)) atIndex:i];}CAMLreturn(result_unit());COMPUTE_CATCH}
COMPUTE_ENTRY(caml_prismel_metal_compute35_samplers)(value re,value ra,value rlo,value rhi,value rstart){CAMLparam5(re,ra,rlo,rhi,rstart);@try{COMPUTE_ENCODER(re);auto a=prismel_compute_handles<id<MTLSamplerState>>(ra,Handle_kind::Sampler);NSRange r=NSMakeRange(Int64_val(rstart),a.size());if(Is_none(rlo)&&Is_none(rhi))[e setSamplerStates:a.data() withRange:r];else if(!Is_none(rlo)&&!Is_none(rhi)){auto lo=prismel_compute_floats(Field(rlo,0));auto hi=prismel_compute_floats(Field(rhi,0));if(lo.size()!=a.size()||hi.size()!=a.size())CAMLreturn(result_error_text("compute sampler LOD cardinality mismatch"));[e setSamplerStates:a.data() lodMinClamps:lo.data() lodMaxClamps:hi.data() withRange:r];}else CAMLreturn(result_error_text("compute sampler LOD arrays must both be present"));CAMLreturn(result_unit());COMPUTE_CATCH}
COMPUTE_ENTRY(caml_prismel_metal_compute35_acceleration)(value re,value ra,value ri){CAMLparam3(re,ra,ri);@try{COMPUTE_ENCODER(re);id<MTLAccelerationStructure>a=Is_none(ra)?nil:object_of_handle(Field(ra,0),Handle_kind::Acceleration_structure);[e setAccelerationStructure:a atBufferIndex:Int64_val(ri)];CAMLreturn(result_unit());COMPUTE_CATCH}
#define COMPUTE_TABLE_ONE(NAME,TYPE,KIND,SELECTOR) COMPUTE_ENTRY(NAME)(value re,value rx,value ri){CAMLparam3(re,rx,ri);@try{COMPUTE_ENCODER(re);TYPE x=Is_none(rx)?nil:object_of_handle(Field(rx,0),KIND);[e SELECTOR:x atBufferIndex:Int64_val(ri)];CAMLreturn(result_unit());COMPUTE_CATCH}
#define COMPUTE_TABLE_MANY(NAME,TYPE,KIND,SELECTOR) COMPUTE_ENTRY(NAME)(value re,value ra,value ri){CAMLparam3(re,ra,ri);@try{COMPUTE_ENCODER(re);auto a=prismel_compute_handles<TYPE>(ra,KIND);[e SELECTOR:a.data() withBufferRange:NSMakeRange(Int64_val(ri),a.size())];CAMLreturn(result_unit());COMPUTE_CATCH}
COMPUTE_TABLE_ONE(caml_prismel_metal_compute35_visible,id<MTLVisibleFunctionTable>,Handle_kind::Visible_function_table,setVisibleFunctionTable)
COMPUTE_TABLE_MANY(caml_prismel_metal_compute35_visibles,id<MTLVisibleFunctionTable>,Handle_kind::Visible_function_table,setVisibleFunctionTables)
COMPUTE_TABLE_ONE(caml_prismel_metal_compute35_intersection,id<MTLIntersectionFunctionTable>,Handle_kind::Intersection_function_table,setIntersectionFunctionTable)
COMPUTE_TABLE_MANY(caml_prismel_metal_compute35_intersections,id<MTLIntersectionFunctionTable>,Handle_kind::Intersection_function_table,setIntersectionFunctionTables)
#undef COMPUTE_TABLE_ONE
#undef COMPUTE_TABLE_MANY
#undef COMPUTE_ENTRY
#undef COMPUTE_ENCODER
#undef COMPUTE_CATCH
