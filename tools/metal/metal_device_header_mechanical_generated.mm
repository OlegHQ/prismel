#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

/* Exact mechanical MTLDevice.h shard; direct typed calls only. */
static MTLBindingAccess prismel_device_header_mtlargumentdescriptor_access(MTLArgumentDescriptor * receiver) { return [receiver access]; } /* method:-[MTLArgumentDescriptor access] */
static NSUInteger prismel_device_header_mtlargumentdescriptor_arraylength(MTLArgumentDescriptor * receiver) { return [receiver arrayLength]; } /* method:-[MTLArgumentDescriptor arrayLength] */
static NSUInteger prismel_device_header_mtlargumentdescriptor_constantblockalignment(MTLArgumentDescriptor * receiver) { return [receiver constantBlockAlignment]; } /* method:-[MTLArgumentDescriptor constantBlockAlignment] */
static MTLDataType prismel_device_header_mtlargumentdescriptor_datatype(MTLArgumentDescriptor * receiver) { return [receiver dataType]; } /* method:-[MTLArgumentDescriptor dataType] */
static NSUInteger prismel_device_header_mtlargumentdescriptor_index(MTLArgumentDescriptor * receiver) { return [receiver index]; } /* method:-[MTLArgumentDescriptor index] */
static void prismel_device_header_mtlargumentdescriptor_setaccess_(MTLArgumentDescriptor * receiver, MTLBindingAccess arg0) { [receiver setAccess:arg0]; } /* method:-[MTLArgumentDescriptor setAccess:] */
static void prismel_device_header_mtlargumentdescriptor_setarraylength_(MTLArgumentDescriptor * receiver, NSUInteger arg0) { [receiver setArrayLength:arg0]; } /* method:-[MTLArgumentDescriptor setArrayLength:] */
static void prismel_device_header_mtlargumentdescriptor_setconstantblockalignment_(MTLArgumentDescriptor * receiver, NSUInteger arg0) { [receiver setConstantBlockAlignment:arg0]; } /* method:-[MTLArgumentDescriptor setConstantBlockAlignment:] */
static void prismel_device_header_mtlargumentdescriptor_setdatatype_(MTLArgumentDescriptor * receiver, MTLDataType arg0) { [receiver setDataType:arg0]; } /* method:-[MTLArgumentDescriptor setDataType:] */
static void prismel_device_header_mtlargumentdescriptor_setindex_(MTLArgumentDescriptor * receiver, NSUInteger arg0) { [receiver setIndex:arg0]; } /* method:-[MTLArgumentDescriptor setIndex:] */
static void prismel_device_header_mtlargumentdescriptor_settexturetype_(MTLArgumentDescriptor * receiver, MTLTextureType arg0) { [receiver setTextureType:arg0]; } /* method:-[MTLArgumentDescriptor setTextureType:] */
static MTLTextureType prismel_device_header_mtlargumentdescriptor_texturetype(MTLArgumentDescriptor * receiver) { return [receiver textureType]; } /* method:-[MTLArgumentDescriptor textureType] */
static BOOL prismel_device_header_mtldevice_arebarycentriccoordssupported(id<MTLDevice> receiver) { return [receiver areBarycentricCoordsSupported]; } /* method:-[MTLDevice areBarycentricCoordsSupported] */
static MTLSize prismel_device_header_mtldevice_maxthreadsperthreadgroup(id<MTLDevice> receiver) { return [receiver maxThreadsPerThreadgroup]; } /* method:-[MTLDevice maxThreadsPerThreadgroup] */
static uint64_t prismel_device_header_mtldevice_querytimestampfrequency(id<MTLDevice> receiver) { return [receiver queryTimestampFrequency]; } /* method:-[MTLDevice queryTimestampFrequency] */
static void prismel_device_header_mtldevice_setshouldmaximizeconcurrentcompilation_(id<MTLDevice> receiver, BOOL arg0) { [receiver setShouldMaximizeConcurrentCompilation:arg0]; } /* method:-[MTLDevice setShouldMaximizeConcurrentCompilation:] */
static BOOL prismel_device_header_mtldevice_shouldmaximizeconcurrentcompilation(id<MTLDevice> receiver) { return [receiver shouldMaximizeConcurrentCompilation]; } /* method:-[MTLDevice shouldMaximizeConcurrentCompilation] */
static NSUInteger prismel_device_header_mtldevice_sizeofcounterheapentry_(id<MTLDevice> receiver, MTL4CounterHeapType arg0) { return [receiver sizeOfCounterHeapEntry:arg0]; } /* method:-[MTLDevice sizeOfCounterHeapEntry:] */
static BOOL prismel_device_header_mtldevice_supportscountersampling_(id<MTLDevice> receiver, MTLCounterSamplingPoint arg0) { return [receiver supportsCounterSampling:arg0]; } /* method:-[MTLDevice supportsCounterSampling:] */
static BOOL prismel_device_header_mtldevice_supportsfeatureset_(id<MTLDevice> receiver, MTLFeatureSet arg0) { return [receiver supportsFeatureSet:arg0]; } /* method:-[MTLDevice supportsFeatureSet:] */
static BOOL prismel_device_header_mtldevice_supportsrasterizationratemapwithlayercount_(id<MTLDevice> receiver, NSUInteger arg0) { return [receiver supportsRasterizationRateMapWithLayerCount:arg0]; } /* method:-[MTLDevice supportsRasterizationRateMapWithLayerCount:] */
