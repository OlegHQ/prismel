#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static MTLPixelFormat prismel_residual_formats[]={MTLPixelFormatInvalid,
 MTLPixelFormatPVRTC_RGB_2BPP,MTLPixelFormatPVRTC_RGB_2BPP_sRGB,
 MTLPixelFormatPVRTC_RGB_4BPP,MTLPixelFormatPVRTC_RGB_4BPP_sRGB,
 MTLPixelFormatPVRTC_RGBA_2BPP,MTLPixelFormatPVRTC_RGBA_2BPP_sRGB,
 MTLPixelFormatPVRTC_RGBA_4BPP,MTLPixelFormatPVRTC_RGBA_4BPP_sRGB,
 MTLPixelFormatUnspecialized};
static void prismel_qualify_residual_values(id<MTLDepthStencilState>d,
 id<MTLFunctionHandle>f,id<MTLIndirectCommandBuffer>i){if(true)return;
 MTLResourceID a=d.gpuResourceID,b=f.gpuResourceID,c=i.gpuResourceID;
 MTLStorageMode storage=MTLStorageModeMemoryless;MTLStoreAction action=MTLStoreActionCustomSampleDepthStore;
 action=MTLStoreActionMultisampleResolve;action=MTLStoreActionStoreAndMultisampleResolve;
 MTLVertexFormat vertex=MTLVertexFormatInvalid;(void)a;(void)b;(void)c;(void)storage;(void)action;(void)vertex;(void)prismel_residual_formats;
}
static_assert(sizeof(MTLCoordinate2D)>0&&sizeof(MTLIndirectCommandBufferExecutionRange)>0&&
 sizeof(MTLIntersectionFunctionBufferArguments)>0&&sizeof(MTLMapIndirectArguments)>0&&sizeof(MTLSamplePosition)>0);
extern "C" NSUInteger prismel_mtl_residual_mechanical_id_count(void){return 32;}
