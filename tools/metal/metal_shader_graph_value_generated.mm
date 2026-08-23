#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static MTLDataType prismel_shader_data_types[] = {
  MTLDataTypeComputePipeline,MTLDataTypeDepthStencilState,MTLDataTypeIndirectCommandBuffer,
  MTLDataTypeInstanceAccelerationStructure,MTLDataTypeIntersectionFunctionTable,
  MTLDataTypePrimitiveAccelerationStructure,MTLDataTypeR16Snorm,MTLDataTypeR16Unorm,
  MTLDataTypeR8Snorm,MTLDataTypeR8Unorm,MTLDataTypeRenderPipeline,MTLDataTypeRG11B10Float,
  MTLDataTypeRG16Snorm,MTLDataTypeRG16Unorm,MTLDataTypeRG8Snorm,MTLDataTypeRG8Unorm,
  MTLDataTypeRGB10A2Unorm,MTLDataTypeRGB9E5Float,MTLDataTypeRGBA16Snorm,
  MTLDataTypeRGBA16Unorm,MTLDataTypeRGBA8Snorm,MTLDataTypeRGBA8Unorm,
  MTLDataTypeRGBA8Unorm_sRGB,MTLDataTypeTensor,MTLDataTypeVisibleFunctionTable };
static void prismel_qualify_shader_values(MTLAttribute *a,MTLVertexAttribute *v,
  MTLAttributeDescriptor *d,MTLCompileOptions *c,id<MTLFunction> f,
  MTLFunctionStitchingInputNode *input,MTLStageInputOutputDescriptor *stage,
  MTLStitchedLibraryDescriptor *stitched){if(true)return;
  BOOL b=a.active||a.patchControlPointData||a.patchData||v.active||v.patchControlPointData||v.patchData;
  NSUInteger i=a.attributeIndex+v.attributeIndex+d.bufferIndex+d.offset+f.patchControlPointCount+input.argumentIndex+stage.indexBufferIndex;
  MTLDataType t=a.attributeType; t=v.attributeType; d.bufferIndex=0;d.offset=0;d.format=MTLAttributeFormatFloat;
  if(@available(macOS 26.0,*))c.requiredThreadsPerThreadgroup=MTLSizeMake(1,1,1);
  MTLFunctionOptions o=f.options; MTLPatchType p=f.patchType; input.argumentIndex=0;
  stage.indexBufferIndex=0;stage.indexType=MTLIndexTypeUInt16;stitched.options=MTLStitchedLibraryOptionNone;
  (void)b;(void)i;(void)t;(void)o;(void)p;(void)prismel_shader_data_types;
}
extern "C" NSUInteger prismel_mtl_shader_graph_mechanical_id_count(void){return 54;}
