/* Encoder/resource continuation for authoritative Metal4 lifecycle190. */
static bool prismel_metal4_aligned_range(id<MTLBuffer>buffer,NSUInteger offset,
                                        NSUInteger size,NSUInteger alignment,
                                        NSString **failure) {
  if(!buffer){*failure=@"buffer is required";return false;}
  if(alignment==0||(offset%alignment)!=0||(size%alignment)!=0){*failure=@"buffer range alignment mismatch";return false;}
  if(offset>buffer.length||size>buffer.length-offset){*failure=@"buffer range out of bounds";return false;}
  return true;
}
static bool prismel_metal4_copy_buffer(id<MTL4ComputeCommandEncoder>encoder,
 id<MTLBuffer>source,NSUInteger sourceOffset,id<MTLBuffer>destination,
 NSUInteger destinationOffset,NSUInteger size,NSUInteger alignment,NSString **failure){
 if(!encoder){*failure=@"compute encoder is required";return false;}
 if(!prismel_metal4_aligned_range(source,sourceOffset,size,alignment,failure)||
    !prismel_metal4_aligned_range(destination,destinationOffset,size,alignment,failure))return false;
 if(source.device!=destination.device){*failure=@"buffers belong to different devices";return false;}
 @try{[encoder copyFromBuffer:source sourceOffset:sourceOffset toBuffer:destination destinationOffset:destinationOffset size:size];return true;}@catch(NSException*x){*failure=x.reason;return false;}}
static bool prismel_metal4_queue_residency(id<MTL4CommandQueue>queue,id<MTLResidencySet>set,NSString **failure){
 if(!queue||!set){*failure=@"queue and residency set are required";return false;}
 @try{[queue addResidencySet:set];return true;}@catch(NSException*x){*failure=x.reason;return false;}}
static bool prismel_metal4_queue_drawable(id<MTL4CommandQueue>queue,id<MTLDrawable>drawable,bool signal,NSString **failure){
 if(!queue||!drawable){*failure=@"queue and drawable are required";return false;}
 @try{if(signal)[queue signalDrawable:drawable];else[queue waitForDrawable:drawable];return true;}@catch(NSException*x){*failure=x.reason;return false;}}

typedef void (^PrismelMetal4RenderCompletion)(id<MTLRenderPipelineState>,NSError*);
static id<MTL4CompilerTask> prismel_metal4_compile_render(id<MTL4Compiler>compiler,
 MTL4PipelineDescriptor *descriptor,MTL4CompilerTaskOptions *options,
 PrismelMetal4RenderCompletion completion,NSString **failure){
 if(!compiler||!descriptor||!completion){*failure=@"compiler, descriptor and callback are required";return nil;}
 @try{return[compiler newRenderPipelineStateWithDescriptor:descriptor compilerTaskOptions:options completionHandler:completion];}@catch(NSException*x){*failure=x.reason;return nil;}}
