/* Ownership/state half of authoritative Metal4 lifecycle190 (39 mechanical,
   151 handwritten). */
enum class PrismelMetal4Kind { Device, CommandQueue, CommandAllocator,
  CommandBuffer, CommandEncoder, Buffer, Texture, Fence, Event, ResidencySet,
  CounterHeap, ArgumentTable, PipelineDescriptor, PipelineState, CompilerTask };
static bool prismel_metal4_range(NSUInteger length,NSRange r){return r.location<=length&&r.length<=length-r.location;}
static bool prismel_metal4_begin(id<MTL4CommandBuffer>buffer,id<MTL4CommandAllocator>allocator,MTL4CommandBufferOptions*options,NSString**failure){
 if(!buffer||!allocator){*failure=@"command buffer and allocator are required";return false;}
 @try{[buffer beginCommandBufferWithAllocator:allocator options:options?:[MTL4CommandBufferOptions new]];return true;}@catch(NSException*x){*failure=x.reason;return false;}}
static bool prismel_metal4_wait_event(id<MTL4CommandQueue>queue,id<MTLEvent>event,uint64_t value,NSString**failure){
 if(!queue||!event){*failure=@"queue and event are required";return false;}@try{[queue waitForEvent:event value:value];return true;}@catch(NSException*x){*failure=x.reason;return false;}}
static bool prismel_metal4_wait_fence(id<MTL4CommandEncoder>encoder,id<MTLFence>fence,MTLStages stages,NSString**failure){
 if(!encoder||!fence){*failure=@"encoder and fence are required";return false;}@try{[encoder waitForFence:fence beforeEncoderStages:stages];return true;}@catch(NSException*x){*failure=x.reason;return false;}}
#ifdef PRISMEL_METAL4_CAML_BRIDGE
#include <caml/memory.h>
#include <caml/mlvalues.h>
extern id prismel_metal4_handle(value,PrismelMetal4Kind,NSString**);extern value prismel_metal4_error(NSString*);
extern "C" CAMLprim value caml_prismel_metal4_begin(value rb,value ra,value ro){CAMLparam3(rb,ra,ro);NSString*f=nil;id b=prismel_metal4_handle(rb,PrismelMetal4Kind::CommandBuffer,&f);id a=prismel_metal4_handle(ra,PrismelMetal4Kind::CommandAllocator,&f);if(!b||!a||!prismel_metal4_begin(b,a,nil,&f))CAMLreturn(prismel_metal4_error(f));CAMLreturn(Val_unit);}
extern "C" CAMLprim value caml_prismel_metal4_wait_event(value rq,value re,value rv){CAMLparam3(rq,re,rv);NSString*f=nil;id q=prismel_metal4_handle(rq,PrismelMetal4Kind::CommandQueue,&f);id e=prismel_metal4_handle(re,PrismelMetal4Kind::Event,&f);if(!q||!e||!prismel_metal4_wait_event(q,e,Int64_val(rv),&f))CAMLreturn(prismel_metal4_error(f));CAMLreturn(Val_unit);}
#endif
