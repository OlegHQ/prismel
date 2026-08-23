/* Ownership half of pipeline113. The 44 scalar/property IDs remain in
   metal_pipeline_header_mechanical_generated.mm. */
enum class PrismelPipelineKind { Function, BinaryArchive, DynamicLibrary,
  LinkedFunctions, VertexDescriptor, StageDescriptor, RenderDescriptor,
  ComputeDescriptor, RenderPipeline, ComputePipeline, Reflection };

struct PrismelRenderPipelineObjects {
  id<MTLDevice> device;
  id<MTLFunction> vertexFunction;
  id<MTLFunction> fragmentFunction;
  NSArray<id<MTLBinaryArchive>> *binaryArchives;
  NSArray<id<MTLDynamicLibrary>> *vertexLibraries;
  NSArray<id<MTLDynamicLibrary>> *fragmentLibraries;
  MTLLinkedFunctions *vertexLinked;
  MTLLinkedFunctions *fragmentLinked;
  MTLVertexDescriptor *vertexDescriptor;
};
struct PrismelComputePipelineObjects {
  id<MTLDevice> device;
  id<MTLFunction> computeFunction;
  NSArray<id<MTLDynamicLibrary>> *libraries;
  MTLStageInputOutputDescriptor *stageInput;
};

static NSString *prismel_pipeline_validate_array(NSArray *values,
                                                  NSString *label) {
  for(id value in values) if(value==nil)
    return [NSString stringWithFormat:@"nil object in %@",label];
  return nil;
}
static MTLRenderPipelineDescriptor *
prismel_materialize_render_pipeline(PrismelRenderPipelineObjects v,
                                    NSString **failure) {
  if(v.device==nil){*failure=@"render pipeline device is required";return nil;}
  if(v.vertexFunction==nil){*failure=@"vertex function is required";return nil;}
  NSString *bad=prismel_pipeline_validate_array(v.binaryArchives,@"binary archives");
  if(!bad)bad=prismel_pipeline_validate_array(v.vertexLibraries,@"vertex libraries");
  if(!bad)bad=prismel_pipeline_validate_array(v.fragmentLibraries,@"fragment libraries");
  if(bad){*failure=bad;return nil;}
  MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
  @try { d.vertexFunction=v.vertexFunction;d.fragmentFunction=v.fragmentFunction;
    d.binaryArchives=v.binaryArchives;d.vertexPreloadedLibraries=v.vertexLibraries;
    d.fragmentPreloadedLibraries=v.fragmentLibraries;d.vertexLinkedFunctions=v.vertexLinked;
    d.fragmentLinkedFunctions=v.fragmentLinked;d.vertexDescriptor=v.vertexDescriptor;return d;
  } @catch(NSException*x){*failure=x.reason;return nil;}
}
static MTLComputePipelineDescriptor *
prismel_materialize_compute_pipeline(PrismelComputePipelineObjects v,
                                     NSString **failure) {
  if(v.device==nil){*failure=@"compute pipeline device is required";return nil;}
  if(v.computeFunction==nil){*failure=@"compute function is required";return nil;}
  NSString *bad=prismel_pipeline_validate_array(v.libraries,@"compute libraries");
  if(bad){*failure=bad;return nil;}
  MTLComputePipelineDescriptor *d=[MTLComputePipelineDescriptor new];
  @try { d.computeFunction=v.computeFunction;d.insertLibraries=v.libraries;
    d.stageInputDescriptor=v.stageInput;return d;
  } @catch(NSException*x){*failure=x.reason;return nil;}
}

#ifdef PRISMEL_PIPELINE_CAML_BRIDGE
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
extern bool prismel_render_pipeline_objects(value,PrismelRenderPipelineObjects*,NSString**);
extern bool prismel_compute_pipeline_objects(value,PrismelComputePipelineObjects*,NSString**);
extern value prismel_pipeline_owned_handle(id,PrismelPipelineKind);
extern value prismel_pipeline_error(NSString*);
extern "C" CAMLprim value caml_prismel_render_pipeline_descriptor(value raw){
  CAMLparam1(raw);CAMLlocal1(result);@autoreleasepool{PrismelRenderPipelineObjects v={};NSString*f=nil;
  if(!prismel_render_pipeline_objects(raw,&v,&f))CAMLreturn(prismel_pipeline_error(f));
  id d=prismel_materialize_render_pipeline(v,&f);if(!d)CAMLreturn(prismel_pipeline_error(f));
  result=prismel_pipeline_owned_handle(d,PrismelPipelineKind::RenderDescriptor);CAMLreturn(result);}}
extern "C" CAMLprim value caml_prismel_compute_pipeline_descriptor(value raw){
  CAMLparam1(raw);CAMLlocal1(result);@autoreleasepool{PrismelComputePipelineObjects v={};NSString*f=nil;
  if(!prismel_compute_pipeline_objects(raw,&v,&f))CAMLreturn(prismel_pipeline_error(f));
  id d=prismel_materialize_compute_pipeline(v,&f);if(!d)CAMLreturn(prismel_pipeline_error(f));
  result=prismel_pipeline_owned_handle(d,PrismelPipelineKind::ComputeDescriptor);CAMLreturn(result);}}
#endif
