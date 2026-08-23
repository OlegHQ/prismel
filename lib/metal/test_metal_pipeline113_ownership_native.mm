#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#include "../../tools/metal/metal_pipeline_ownership_materializers.inc"
#pragma clang diagnostic pop

static void require(bool ok, NSString *message) {
  if (!ok) @throw [NSException exceptionWithName:@"Pipeline113Ownership"
                                            reason:message userInfo:nil];
}
int main(){@autoreleasepool{
  id<MTLDevice> device=MTLCreateSystemDefaultDevice();if(!device)return 77;
  NSError*error=nil;NSString*source=@"#include <metal_stdlib>\nusing namespace metal; struct O{float4 p[[position]];}; vertex O v(uint i[[vertex_id]]){float2 q[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return{float4(q[i],0,1)};} fragment float4 f(){return float4(1);} kernel void k(device uint*out[[buffer(0)]]){out[0]=1;}";
  id<MTLLibrary>library=[device newLibraryWithSource:source options:nil error:&error];require(library!=nil,error.localizedDescription?:@"library");
  PrismelRenderPipelineObjects ro={};ro.device=device;ro.vertexFunction=[library newFunctionWithName:@"v"];ro.fragmentFunction=[library newFunctionWithName:@"f"];ro.binaryArchives=@[];ro.vertexLibraries=@[];ro.fragmentLibraries=@[];NSString*failure=nil;
  MTLRenderPipelineDescriptor*rd=prismel_materialize_render_pipeline(ro,&failure);require(rd!=nil,failure?:@"render descriptor");rd.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;MTLRenderPipelineReflection*rr=nil;id<MTLRenderPipelineState>rp=[device newRenderPipelineStateWithDescriptor:rd options:MTLPipelineOptionBindingInfo reflection:&rr error:&error];require(rp!=nil,error.localizedDescription?:@"render compile");require(rp.device.registryID==device.registryID,@"render identity");
  PrismelComputePipelineObjects co={};co.device=device;co.computeFunction=[library newFunctionWithName:@"k"];co.libraries=@[];failure=nil;MTLComputePipelineDescriptor*cd=prismel_materialize_compute_pipeline(co,&failure);require(cd!=nil,failure?:@"compute descriptor");MTLComputePipelineReflection*cr=nil;id<MTLComputePipelineState>cp=[device newComputePipelineStateWithDescriptor:cd options:MTLPipelineOptionBindingInfo reflection:&cr error:&error];require(cp!=nil,error.localizedDescription?:@"compute compile");require(cp.device.registryID==device.registryID&&cr.bindings.count>0,@"compute identity/reflection");
  PrismelRenderPipelineObjects bad={};bad.device=device;failure=nil;require(prismel_materialize_render_pipeline(bad,&failure)==nil&&failure!=nil,@"required vertex rejection");
  NSLog(@"pipeline113 ownership: render/compute descriptor, reflection, sync compile and rejection green");return 0;
}}
