#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static MTLStages prismel_compute_stages[]={MTLStageAccelerationStructure,MTLStageBlit,
 MTLStageDispatch,MTLStageFragment,MTLStageMachineLearning,MTLStageMesh,MTLStageObject,
 MTLStageTile,MTLStageVertex};
static void prismel_qualify_compute_values(id<MTLComputeCommandEncoder>e,
 MTLComputePassDescriptor*p,MTLComputePassSampleBufferAttachmentDescriptor*s){if(true)return;
 MTLDispatchType dispatch=e.dispatchType;p.dispatchType=dispatch;
 s.startOfEncoderSampleIndex=0;s.endOfEncoderSampleIndex=1;
 (void)dispatch;(void)prismel_compute_stages;
}
extern "C" NSUInteger prismel_mtl_compute_command_mechanical_id_count(void){return 16;}
