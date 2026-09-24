#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cmath>
int main(){@autoreleasepool{
 id<MTLDevice>device=MTLCreateSystemDefaultDevice();if(!device)return 77;
 if(![device supportsRasterizationRateMapWithLayerCount:1])return 77;
 MTLSize count=MTLSizeMake(2,2,0);float horizontal[2]={1.0f,0.5f},vertical[2]={0.75f,1.0f};
 MTLRasterizationRateLayerDescriptor*layer=[[MTLRasterizationRateLayerDescriptor alloc]initWithSampleCount:count horizontal:horizontal vertical:vertical];
 if(!layer||layer.sampleCount.width!=2||layer.horizontalSampleStorage[1]!=0.5f)return 1;
 layer.horizontal[1]=@(0.625f);if(std::fabs(layer.horizontal[1].doubleValue-0.625)>1e-6)return 2;
 MTLRasterizationRateMapDescriptor*descriptor=[MTLRasterizationRateMapDescriptor rasterizationRateMapDescriptorWithScreenSize:MTLSizeMake(64,32,0) layer:layer];descriptor.label=@"rate55";
 if(descriptor.layerCount!=1||descriptor.layers[0]!=layer||![descriptor.label isEqual:@"rate55"])return 3;
 id<MTLRasterizationRateMap>map=[device newRasterizationRateMapWithDescriptor:descriptor];if(!map)return 4;
 if(map.layerCount!=1||map.screenSize.width!=64||map.parameterBufferSizeAndAlign.size==0||map.device!=device)return 5;
 MTLCoordinate2D screen={8,8};MTLCoordinate2D physical=[map mapScreenToPhysicalCoordinates:screen forLayer:0];MTLCoordinate2D roundtrip=[map mapPhysicalToScreenCoordinates:physical forLayer:0];if(!std::isfinite(roundtrip.x)||!std::isfinite(roundtrip.y))return 6;
 id<MTLBuffer>parameters=[device newBufferWithLength:map.parameterBufferSizeAndAlign.size options:MTLResourceStorageModeShared];if(!parameters)return 7;[map copyParameterDataToBuffer:parameters offset:0];
 return 0;
}}
