/* Isolated typed ownership shard for the 57 non-mechanical mesh/tile IDs.
   The includer supplies retain_handle/release_handle and converts NSError. */
enum class PrismelMeshTileKind { Function, BinaryArchive, DynamicLibrary,
  LinkedFunctions, BufferDescriptor, ColorAttachment, MeshDescriptor,
  TileDescriptor };

struct PrismelMeshTileObjects {
  id<MTLFunction> objectFunction;
  id<MTLFunction> meshFunction;
  id<MTLFunction> fragmentFunction;
  id<MTLFunction> tileFunction;
  NSArray<id<MTLBinaryArchive>> *binaryArchives;
  NSArray<id<MTLDynamicLibrary>> *preloadedLibraries;
  MTLLinkedFunctions *objectLinkedFunctions;
  MTLLinkedFunctions *meshLinkedFunctions;
  MTLLinkedFunctions *fragmentLinkedFunctions;
  MTLLinkedFunctions *tileLinkedFunctions;
};

static NSString *prismel_mesh_tile_validate_objects(PrismelMeshTileObjects v,
                                                     bool tile) {
  if (tile && v.tileFunction == nil) return @"tile function is required";
  if (!tile && v.meshFunction == nil) return @"mesh function is required";
  for (id x in v.binaryArchives) if (x == nil) return @"nil binary archive";
  for (id x in v.preloadedLibraries) if (x == nil) return @"nil dynamic library";
  return nil;
}

static MTLMeshRenderPipelineDescriptor *
prismel_materialize_mesh_descriptor(PrismelMeshTileObjects v,
                                    NSString **failure) {
  NSString *bad=prismel_mesh_tile_validate_objects(v,false); if(bad){*failure=bad;return nil;}
  MTLMeshRenderPipelineDescriptor *d=[MTLMeshRenderPipelineDescriptor new];
  @try { d.objectFunction=v.objectFunction; d.meshFunction=v.meshFunction;
    d.fragmentFunction=v.fragmentFunction; d.binaryArchives=v.binaryArchives;
    d.objectLinkedFunctions=v.objectLinkedFunctions;
    d.meshLinkedFunctions=v.meshLinkedFunctions;
    d.fragmentLinkedFunctions=v.fragmentLinkedFunctions; return d;
  } @catch(NSException *x) { *failure=x.reason; return nil; }
}

static MTLTileRenderPipelineDescriptor *
prismel_materialize_tile_descriptor(PrismelMeshTileObjects v,
                                    NSString **failure) {
  NSString *bad=prismel_mesh_tile_validate_objects(v,true); if(bad){*failure=bad;return nil;}
  MTLTileRenderPipelineDescriptor *d=[MTLTileRenderPipelineDescriptor new];
  @try { d.tileFunction=v.tileFunction; d.binaryArchives=v.binaryArchives;
    d.preloadedLibraries=v.preloadedLibraries; d.linkedFunctions=v.tileLinkedFunctions;
    return d;
  } @catch(NSException *x) { *failure=x.reason; return nil; }
}

static bool prismel_mesh_tile_set_buffer(MTLPipelineBufferDescriptorArray *a,
                                         NSUInteger i, MTLPipelineBufferDescriptor *v,
                                         NSString **failure) {
  if(i>=31){*failure=@"buffer index out of range";return false;}
  @try { [a setObject:v atIndexedSubscript:i]; return true; }
  @catch(NSException*x){*failure=x.reason;return false;}
}
static bool prismel_mesh_tile_set_attachment(MTLRenderPipelineColorAttachmentDescriptorArray *a,
                                             NSUInteger i, MTLRenderPipelineColorAttachmentDescriptor *v,
                                             NSString **failure) {
  if(i>=8){*failure=@"attachment index out of range";return false;}
  @try { [a setObject:v atIndexedSubscript:i]; return true; }
  @catch(NSException*x){*failure=x.reason;return false;}
}

/* Shared bridge hookup. Keeping this conditional makes the isolated native
   fixture compile without depending on Prismel's handle runtime. */
#ifdef PRISMEL_MESH_TILE_CAML_BRIDGE
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
extern bool prismel_mesh_tile_objects_from_value(value, bool,
                                                 PrismelMeshTileObjects *,
                                                 NSString **);
extern value prismel_mesh_tile_owned_handle(id, PrismelMeshTileKind);
extern value prismel_mesh_tile_error(NSString *);

extern "C" CAMLprim value caml_prismel_mesh_pipeline_descriptor(value raw) {
  CAMLparam1(raw); CAMLlocal1(result); @autoreleasepool {
    PrismelMeshTileObjects objects={}; NSString *failure=nil;
    if(!prismel_mesh_tile_objects_from_value(raw,false,&objects,&failure))
      CAMLreturn(prismel_mesh_tile_error(failure));
    MTLMeshRenderPipelineDescriptor *descriptor=
      prismel_materialize_mesh_descriptor(objects,&failure);
    if(!descriptor) CAMLreturn(prismel_mesh_tile_error(failure));
    result=prismel_mesh_tile_owned_handle(descriptor,
      PrismelMeshTileKind::MeshDescriptor); CAMLreturn(result);
  }
}
extern "C" CAMLprim value caml_prismel_tile_pipeline_descriptor(value raw) {
  CAMLparam1(raw); CAMLlocal1(result); @autoreleasepool {
    PrismelMeshTileObjects objects={}; NSString *failure=nil;
    if(!prismel_mesh_tile_objects_from_value(raw,true,&objects,&failure))
      CAMLreturn(prismel_mesh_tile_error(failure));
    MTLTileRenderPipelineDescriptor *descriptor=
      prismel_materialize_tile_descriptor(objects,&failure);
    if(!descriptor) CAMLreturn(prismel_mesh_tile_error(failure));
    result=prismel_mesh_tile_owned_handle(descriptor,
      PrismelMeshTileKind::TileDescriptor); CAMLreturn(result);
  }
}
#endif
