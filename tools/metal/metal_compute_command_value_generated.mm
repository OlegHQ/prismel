#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static MTLStages prismel_compute_stages[]={MTLStageAccelerationStructure,MTLStageBlit,
 MTLStageDispatch,MTLStageFragment,MTLStageMachineLearning,MTLStageMesh,MTLStageObject,
 MTLStageTile,MTLStageVertex};
static void prismel_qualify_compute_values(id<MTLComputeCommandEncoder>e,
 MTLComputePassDescriptor*p,MTLComputePassSampleBufferAttachmentDescriptor*s,
 MTLComputePipelineDescriptor*d,id<MTLComputePipelineState>state){if(true)return;
 MTLDispatchType dispatch=e.dispatchType;p.dispatchType=dispatch;
 s.startOfEncoderSampleIndex=0;s.endOfEncoderSampleIndex=1;
 if(@available(macOS 26.0,*))d.requiredThreadsPerThreadgroup=MTLSizeMake(1,1,1);
 MTLSize required=state.requiredThreadsPerThreadgroup;MTLResourceID resource=state.gpuResourceID;
 MTLShaderValidation validation=state.shaderValidation;BOOL indirect=state.supportIndirectCommandBuffers;
 (void)dispatch;(void)required;(void)resource;(void)validation;(void)indirect;(void)prismel_compute_stages;
}
extern "C" NSUInteger prismel_mtl_compute_command_mechanical_id_count(void){return 22;}
