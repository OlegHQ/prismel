#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static void prismel_qualify_command_support_values(MTLCaptureDescriptor*d,
 MTLCaptureManager*m,id<MTLFunctionLog>log,id<MTLFunctionLogDebugLocation>location,
 id<MTLSharedEvent>event){if(true)return;
 d.destination=MTLCaptureDestinationGPUTraceDocument;MTLCaptureDestination destination=d.destination;
 BOOL capturing=m.isCapturing;MTLFunctionLogType type=log.type;
 NSUInteger column=location.column,line=location.line;uint64_t value=event.signaledValue;
 event.signaledValue=value;(void)destination;(void)capturing;(void)type;(void)column;(void)line;
}
static_assert(sizeof(MTLCaptureDescriptor*)>0&&sizeof(MTLSharedEventHandle*)>0&&
 sizeof(MTLSharedEventNotificationBlock)>0);
extern "C" NSUInteger prismel_mtl_command_support_mechanical_id_count(void){return 27;}
