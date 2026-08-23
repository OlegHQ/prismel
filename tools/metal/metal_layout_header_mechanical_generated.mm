#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
/* exact tensor/raster layout mechanical shard */
static MTLSize prismel_layout_mtlrasterizationratelayerdescriptor_maxsamplecount(MTLRasterizationRateLayerDescriptor * receiver){return [receiver maxSampleCount];}/*method:-[MTLRasterizationRateLayerDescriptor maxSampleCount]*/
static MTLSize prismel_layout_mtlrasterizationratelayerdescriptor_samplecount(MTLRasterizationRateLayerDescriptor * receiver){return [receiver sampleCount];}/*method:-[MTLRasterizationRateLayerDescriptor sampleCount]*/
static void prismel_layout_mtlrasterizationratelayerdescriptor_setsamplecount_(MTLRasterizationRateLayerDescriptor * receiver, MTLSize a0){[receiver setSampleCount:a0];}/*method:-[MTLRasterizationRateLayerDescriptor setSampleCount:]*/
static NSUInteger prismel_layout_mtlrasterizationratemap_layercount(id<MTLRasterizationRateMap> receiver){return [receiver layerCount];}/*method:-[MTLRasterizationRateMap layerCount]*/
static MTLCoordinate2D prismel_layout_mtlrasterizationratemap_mapphysicaltoscreencoordinates_forlayer_(id<MTLRasterizationRateMap> receiver, MTLCoordinate2D a0, NSUInteger a1){return [receiver mapPhysicalToScreenCoordinates:a0 forLayer:a1];}/*method:-[MTLRasterizationRateMap mapPhysicalToScreenCoordinates:forLayer:]*/
static MTLCoordinate2D prismel_layout_mtlrasterizationratemap_mapscreentophysicalcoordinates_forlayer_(id<MTLRasterizationRateMap> receiver, MTLCoordinate2D a0, NSUInteger a1){return [receiver mapScreenToPhysicalCoordinates:a0 forLayer:a1];}/*method:-[MTLRasterizationRateMap mapScreenToPhysicalCoordinates:forLayer:]*/
static MTLSize prismel_layout_mtlrasterizationratemap_physicalgranularity(id<MTLRasterizationRateMap> receiver){return [receiver physicalGranularity];}/*method:-[MTLRasterizationRateMap physicalGranularity]*/
static MTLSize prismel_layout_mtlrasterizationratemap_physicalsizeforlayer_(id<MTLRasterizationRateMap> receiver, NSUInteger a0){return [receiver physicalSizeForLayer:a0];}/*method:-[MTLRasterizationRateMap physicalSizeForLayer:]*/
static MTLSize prismel_layout_mtlrasterizationratemap_screensize(id<MTLRasterizationRateMap> receiver){return [receiver screenSize];}/*method:-[MTLRasterizationRateMap screenSize]*/
static NSUInteger prismel_layout_mtlrasterizationratemapdescriptor_layercount(MTLRasterizationRateMapDescriptor * receiver){return [receiver layerCount];}/*method:-[MTLRasterizationRateMapDescriptor layerCount]*/
static MTLSize prismel_layout_mtlrasterizationratemapdescriptor_screensize(MTLRasterizationRateMapDescriptor * receiver){return [receiver screenSize];}/*method:-[MTLRasterizationRateMapDescriptor screenSize]*/
static void prismel_layout_mtlrasterizationratemapdescriptor_setscreensize_(MTLRasterizationRateMapDescriptor * receiver, MTLSize a0){[receiver setScreenSize:a0];}/*method:-[MTLRasterizationRateMapDescriptor setScreenSize:]*/
static NSUInteger prismel_layout_mtltensor_bufferoffset(id<MTLTensor> receiver){return [receiver bufferOffset];}/*method:-[MTLTensor bufferOffset]*/
static MTLTensorDataType prismel_layout_mtltensor_datatype(id<MTLTensor> receiver){return [receiver dataType];}/*method:-[MTLTensor dataType]*/
static MTLResourceID prismel_layout_mtltensor_gpuresourceid(id<MTLTensor> receiver){return [receiver gpuResourceID];}/*method:-[MTLTensor gpuResourceID]*/
static MTLTensorUsage prismel_layout_mtltensor_usage(id<MTLTensor> receiver){return [receiver usage];}/*method:-[MTLTensor usage]*/
static MTLCPUCacheMode prismel_layout_mtltensordescriptor_cpucachemode(MTLTensorDescriptor * receiver){return [receiver cpuCacheMode];}/*method:-[MTLTensorDescriptor cpuCacheMode]*/
static MTLTensorDataType prismel_layout_mtltensordescriptor_datatype(MTLTensorDescriptor * receiver){return [receiver dataType];}/*method:-[MTLTensorDescriptor dataType]*/
static MTLHazardTrackingMode prismel_layout_mtltensordescriptor_hazardtrackingmode(MTLTensorDescriptor * receiver){return [receiver hazardTrackingMode];}/*method:-[MTLTensorDescriptor hazardTrackingMode]*/
static MTLResourceOptions prismel_layout_mtltensordescriptor_resourceoptions(MTLTensorDescriptor * receiver){return [receiver resourceOptions];}/*method:-[MTLTensorDescriptor resourceOptions]*/
static void prismel_layout_mtltensordescriptor_setcpucachemode_(MTLTensorDescriptor * receiver, MTLCPUCacheMode a0){[receiver setCpuCacheMode:a0];}/*method:-[MTLTensorDescriptor setCpuCacheMode:]*/
static void prismel_layout_mtltensordescriptor_setdatatype_(MTLTensorDescriptor * receiver, MTLTensorDataType a0){[receiver setDataType:a0];}/*method:-[MTLTensorDescriptor setDataType:]*/
static void prismel_layout_mtltensordescriptor_sethazardtrackingmode_(MTLTensorDescriptor * receiver, MTLHazardTrackingMode a0){[receiver setHazardTrackingMode:a0];}/*method:-[MTLTensorDescriptor setHazardTrackingMode:]*/
static void prismel_layout_mtltensordescriptor_setresourceoptions_(MTLTensorDescriptor * receiver, MTLResourceOptions a0){[receiver setResourceOptions:a0];}/*method:-[MTLTensorDescriptor setResourceOptions:]*/
static void prismel_layout_mtltensordescriptor_setstoragemode_(MTLTensorDescriptor * receiver, MTLStorageMode a0){[receiver setStorageMode:a0];}/*method:-[MTLTensorDescriptor setStorageMode:]*/
static void prismel_layout_mtltensordescriptor_setusage_(MTLTensorDescriptor * receiver, MTLTensorUsage a0){[receiver setUsage:a0];}/*method:-[MTLTensorDescriptor setUsage:]*/
static MTLStorageMode prismel_layout_mtltensordescriptor_storagemode(MTLTensorDescriptor * receiver){return [receiver storageMode];}/*method:-[MTLTensorDescriptor storageMode]*/
static MTLTensorUsage prismel_layout_mtltensordescriptor_usage(MTLTensorDescriptor * receiver){return [receiver usage];}/*method:-[MTLTensorDescriptor usage]*/
static NSInteger prismel_layout_mtltensorextents_extentatdimensionindex_(MTLTensorExtents * receiver, NSUInteger a0){return [receiver extentAtDimensionIndex:a0];}/*method:-[MTLTensorExtents extentAtDimensionIndex:]*/
static NSUInteger prismel_layout_mtltensorextents_rank(MTLTensorExtents * receiver){return [receiver rank];}/*method:-[MTLTensorExtents rank]*/
