#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
int main(){@autoreleasepool{
  if(!@available(macOS 12.0,*))return 77;
  id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;
  NSError*error=nil;
  NSString*source=@"#include <metal_stdlib>\nusing namespace metal; [[ stitchable ]] float add(float a,float b){return a+b;}";
  id<MTLLibrary>base=[d newLibraryWithSource:source options:nil error:&error];
  if(!base)return 77;
  id<MTLFunction>function=[base newFunctionWithName:@"add"];
  MTLFunctionStitchingInputNode*a=[[MTLFunctionStitchingInputNode alloc]initWithArgumentIndex:0];
  MTLFunctionStitchingInputNode*b=[[MTLFunctionStitchingInputNode alloc]initWithArgumentIndex:1];
  MTLFunctionStitchingFunctionNode*node=[[MTLFunctionStitchingFunctionNode alloc]initWithName:@"add" arguments:@[a,b] controlDependencies:@[]];
  MTLFunctionStitchingGraph*graph=[[MTLFunctionStitchingGraph alloc]initWithFunctionName:@"add2" nodes:@[node] outputNode:node attributes:@[[MTLFunctionStitchingAttributeAlwaysInline new]]];
  MTLStitchedLibraryDescriptor*descriptor=[MTLStitchedLibraryDescriptor new];
  descriptor.functions=@[function];descriptor.functionGraphs=@[graph];
  id<MTLLibrary>stitched=[d newLibraryWithStitchedDescriptor:descriptor error:&error];
  if(!stitched){
    NSString*message=error.localizedDescription?:@"";
    if([message containsString:@"unsupported"]||[message containsString:@"not support"])return 77;
    return 1;
  }
  if(![stitched newFunctionWithName:@"add2"])return 2;
  return 0;
}}
