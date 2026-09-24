/* Ownership half of IO/counter/blit-pass111; 38 scalar IDs remain generated. */
enum class PrismelIOKind { IOQueue, IOCommandBuffer, IOFileHandle, Buffer,
  Texture, Event, CounterSet, CounterDescriptor, CounterSampleBuffer, BlitPassDescriptor };
static bool prismel_io_range(NSUInteger length,NSUInteger offset,NSUInteger size){return offset<=length&&size<=length-offset;}
static MTLCounterSampleBufferDescriptor *prismel_counter_descriptor(id<MTLCounterSet>set,NSUInteger count,NSString*label,NSString**failure){
 if(!set){*failure=@"counter set is required";return nil;}if(count==0){*failure=@"sample count must be positive";return nil;}
 @try{MTLCounterSampleBufferDescriptor*d=[MTLCounterSampleBufferDescriptor new];d.counterSet=set;d.sampleCount=count;d.label=label;return d;}@catch(NSException*x){*failure=x.reason;return nil;}}
static MTLBlitPassDescriptor *prismel_blit_pass(id<MTLCounterSampleBuffer>samples,NSUInteger start,NSUInteger end,NSString**failure){
 if(samples&& (start>=samples.sampleCount||end>=samples.sampleCount)){*failure=@"counter sample index out of range";return nil;}
 @try{MTLBlitPassDescriptor*d=[MTLBlitPassDescriptor blitPassDescriptor];if(samples){MTLBlitPassSampleBufferAttachmentDescriptor*a=d.sampleBufferAttachments[0];a.sampleBuffer=samples;a.startOfEncoderSampleIndex=start;a.endOfEncoderSampleIndex=end;}return d;}@catch(NSException*x){*failure=x.reason;return nil;}}
static bool prismel_io_load_buffer(id<MTLIOCommandBuffer>commands,id<MTLBuffer>destination,NSUInteger destinationOffset,NSUInteger size,id<MTLIOFileHandle>source,NSUInteger sourceOffset,NSString**failure){
 if(!commands||!destination||!source){*failure=@"IO command, destination and source are required";return false;}if(!prismel_io_range(destination.length,destinationOffset,size)){*failure=@"destination range out of bounds";return false;}
 @try{[commands loadBuffer:destination offset:destinationOffset size:size sourceHandle:source sourceHandleOffset:sourceOffset];return true;}@catch(NSException*x){*failure=x.reason;return false;}}
#ifdef PRISMEL_IO_CAML_BRIDGE
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
extern id prismel_io_handle(value,PrismelIOKind,NSString**);extern value prismel_io_error(NSString*);extern value prismel_io_owned_handle(id,PrismelIOKind);
extern "C" CAMLprim value caml_prismel_counter_descriptor(value rs,value rc,value rl){CAMLparam3(rs,rc,rl);CAMLlocal1(r);NSString*f=nil;id set=prismel_io_handle(rs,PrismelIOKind::CounterSet,&f);if(!set)CAMLreturn(prismel_io_error(f));id d=prismel_counter_descriptor(set,Long_val(rc),nil,&f);if(!d)CAMLreturn(prismel_io_error(f));r=prismel_io_owned_handle(d,PrismelIOKind::CounterDescriptor);CAMLreturn(r);}
extern "C" CAMLprim value caml_prismel_io_load_buffer(value rc,value rd,value ro,value rz,value rs,value rso){CAMLparam5(rc,rd,ro,rz,rs);CAMLxparam1(rso);NSString*f=nil;id c=prismel_io_handle(rc,PrismelIOKind::IOCommandBuffer,&f);id d=prismel_io_handle(rd,PrismelIOKind::Buffer,&f);id s=prismel_io_handle(rs,PrismelIOKind::IOFileHandle,&f);if(!c||!d||!s||!prismel_io_load_buffer(c,d,Long_val(ro),Long_val(rz),s,Long_val(rso),&f))CAMLreturn(prismel_io_error(f));CAMLreturn(Val_unit);}
#endif
