#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <type_traits>

static const char *const kIds[] = {
  "class:MTLArgumentDescriptor", "+argumentDescriptor", "access", "arrayLength",
  "constantBlockAlignment", "dataType", "index", "setAccess:", "setArrayLength:",
  "setConstantBlockAlignment:", "setDataType:", "setIndex:", "setTextureType:",
  "textureType", "property:access", "property:arrayLength",
  "property:constantBlockAlignment", "property:dataType", "property:index",
  "property:textureType", "class:MTLArchitecture", "architecture.name",
  "property:architecture.name", "device.architecture", "property:device.architecture"
};
static_assert(sizeof(kIds)/sizeof(kIds[0])==25,"Device value25 drift");
static_assert(std::is_same_v<decltype(((id<MTLDevice>)nil).architecture),
                             MTLArchitecture *>);

int main(){@autoreleasepool{
  (void)kIds;
  MTLArgumentDescriptor*d=[MTLArgumentDescriptor argumentDescriptor];
  if(!d)return 1;
  d.access=MTLArgumentAccessReadWrite;
  d.arrayLength=7;
  d.constantBlockAlignment=16;
  d.dataType=MTLDataTypeUInt;
  d.index=3;
  d.textureType=MTLTextureType2D;
  if(d.access!=MTLArgumentAccessReadWrite||d.arrayLength!=7||
     d.constantBlockAlignment!=16||d.dataType!=MTLDataTypeUInt||
     d.index!=3||d.textureType!=MTLTextureType2D)return 2;
  id<MTLDevice>device=MTLCreateSystemDefaultDevice();if(!device)return 77;
  if(@available(macOS 14.0,*)){
    MTLArchitecture*architecture=device.architecture;
    if(!architecture||architecture.name.length==0)return 3;
    NSString*copy=[architecture.name copy];
    if(copy.length==0)return 4;
  }
  return 0;
}}
