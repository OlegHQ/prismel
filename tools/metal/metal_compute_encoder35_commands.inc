static MTLSize prismel_compute35_size(value v){return MTLSizeMake(Long_val(Field(v,0)),Long_val(Field(v,1)),Long_val(Field(v,2)));}
static MTLRegion prismel_compute35_region(value v){return MTLRegionMake3D(Int64_val(Field(v,0)),Int64_val(Field(v,1)),Int64_val(Field(v,2)),Int64_val(Field(v,3)),Int64_val(Field(v,4)),Int64_val(Field(v,5)));}
static std::vector<id<MTLResource>> prismel_compute35_resources(value handles,value kinds){mlsize_t n=Wosize_val(handles);if(Wosize_val(kinds)!=n)@throw[NSException exceptionWithName:NSInvalidArgumentException reason:@"resource kind cardinality mismatch" userInfo:nil];std::vector<id<MTLResource>>r;r.reserve(n);for(mlsize_t i=0;i<n;i++){Handle_kind k=Bool_val(Field(kinds,i))?Handle_kind::Texture:Handle_kind::Buffer;r.push_back(object_of_handle(Field(handles,i),k));}return r;}
#define C35_ENTRY(NAME) extern "C" CAMLprim value NAME
#define C35_ENCODER(V) id<MTLComputeCommandEncoder> e=object_of_handle((V),Handle_kind::Compute_encoder)
#define C35_CATCH }@catch(NSException*x){CAMLreturn(result_error(x.reason));}
C35_ENTRY(caml_prismel_metal_compute35_dispatch_groups)(value re,value rg,value rt){CAMLparam3(re,rg,rt);@try{C35_ENCODER(re);[e dispatchThreadgroups:prismel_compute35_size(rg) threadsPerThreadgroup:prismel_compute35_size(rt)];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_dispatch_indirect)(value re,value rb,value ro,value rt){CAMLparam4(re,rb,ro,rt);@try{C35_ENCODER(re);id<MTLBuffer>b=object_of_handle(rb,Handle_kind::Buffer);[e dispatchThreadgroupsWithIndirectBuffer:b indirectBufferOffset:Int64_val(ro) threadsPerThreadgroup:prismel_compute35_size(rt)];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_dispatch_type)(value re){CAMLparam1(re);CAMLlocal2(v,r);@try{C35_ENCODER(re);v=Val_long(e.dispatchType);r=result_ok(v);CAMLreturn(r);C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_execute_indirect)(value re,value ri,value rb,value ro){CAMLparam4(re,ri,rb,ro);@try{C35_ENCODER(re);[e executeCommandsInBuffer:object_of_handle(ri,Handle_kind::Indirect_command_buffer) indirectBuffer:object_of_handle(rb,Handle_kind::Buffer) indirectBufferOffset:Int64_val(ro)];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_barrier_resources)(value re,value rh,value rk){CAMLparam3(re,rh,rk);@try{C35_ENCODER(re);auto r=prismel_compute35_resources(rh,rk);[e memoryBarrierWithResources:r.data() count:r.size()];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_barrier_scope)(value re,value rs){CAMLparam2(re,rs);@try{C35_ENCODER(re);[e memoryBarrierWithScope:(MTLBarrierScope)Int64_val(rs)];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_sample_counters)(value re,value rb,value ri,value barrier){CAMLparam4(re,rb,ri,barrier);@try{C35_ENCODER(re);[e sampleCountersInBuffer:object_of_handle(rb,Handle_kind::Counter_sample_buffer) atSampleIndex:Int64_val(ri) withBarrier:Bool_val(barrier)];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_supports_stage_counters)(value rd){CAMLparam1(rd);CAMLlocal2(v,r);@try{id<MTLDevice>d=object_of_handle(rd,Handle_kind::Device);v=Val_bool([d supportsCounterSampling:MTLCounterSamplingPointAtDispatchBoundary]);r=result_ok(v);CAMLreturn(r);C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_bytes_plain)(value re,value rb,value ri){CAMLparam3(re,rb,ri);@try{C35_ENCODER(re);[e setBytes:Bytes_val(rb) length:caml_string_length(rb) atIndex:Int64_val(ri)];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_imageblock)(value re,value rw,value rh){CAMLparam3(re,rw,rh);@try{C35_ENCODER(re);[e setImageblockWidth:Int64_val(rw) height:Int64_val(rh)];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_stage_region)(value re,value rr){CAMLparam2(re,rr);@try{C35_ENCODER(re);[e setStageInRegion:prismel_compute35_region(rr)];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_stage_indirect)(value re,value rb,value ro){CAMLparam3(re,rb,ro);@try{C35_ENCODER(re);[e setStageInRegionWithIndirectBuffer:object_of_handle(rb,Handle_kind::Buffer) indirectBufferOffset:Int64_val(ro)];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_threadgroup_memory)(value re,value rl,value ri){CAMLparam3(re,rl,ri);@try{C35_ENCODER(re);[e setThreadgroupMemoryLength:Int64_val(rl) atIndex:Int64_val(ri)];CAMLreturn(result_unit());C35_CATCH}
#define C35_FENCE(NAME,SELECTOR) C35_ENTRY(NAME)(value re,value rf){CAMLparam2(re,rf);@try{C35_ENCODER(re);[e SELECTOR:object_of_handle(rf,Handle_kind::Fence)];CAMLreturn(result_unit());C35_CATCH}
C35_FENCE(caml_prismel_metal_compute35_update_fence,updateFence)
C35_FENCE(caml_prismel_metal_compute35_wait_fence,waitForFence)
#undef C35_FENCE
C35_ENTRY(caml_prismel_metal_compute35_heaps)(value re,value ra){CAMLparam2(re,ra);@try{C35_ENCODER(re);mlsize_t n=Wosize_val(ra);std::vector<id<MTLHeap>>h;h.reserve(n);for(mlsize_t i=0;i<n;i++)h.push_back(object_of_handle(Field(ra,i),Handle_kind::Heap));if(n==1)[e useHeap:h[0]];else[e useHeaps:h.data() count:n];CAMLreturn(result_unit());C35_CATCH}
C35_ENTRY(caml_prismel_metal_compute35_resources)(value re,value rh,value rk,value usage){CAMLparam4(re,rh,rk,usage);@try{C35_ENCODER(re);auto r=prismel_compute35_resources(rh,rk);if(r.size()==1)[e useResource:r[0] usage:(MTLResourceUsage)Int64_val(usage)];else[e useResources:r.data() count:r.size() usage:(MTLResourceUsage)Int64_val(usage)];CAMLreturn(result_unit());C35_CATCH}
#undef C35_ENTRY
#undef C35_ENCODER
#undef C35_CATCH
