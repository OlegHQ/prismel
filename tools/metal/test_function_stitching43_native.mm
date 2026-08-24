#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
int main(){@autoreleasepool{
 if(@available(macOS 12.0,*)){
  MTLFunctionStitchingInputNode*input=[[MTLFunctionStitchingInputNode alloc]initWithArgumentIndex:0];
  MTLFunctionStitchingFunctionNode*node=[[MTLFunctionStitchingFunctionNode alloc]initWithName:@"identity" arguments:@[input] controlDependencies:@[]];
  if(!node||node.arguments.count!=1||node.controlDependencies.count||![node.name isEqual:@"identity"])return 1;
  MTLFunctionStitchingGraph*graph=[[MTLFunctionStitchingGraph alloc]initWithFunctionName:@"stitched" nodes:@[node] outputNode:node attributes:@[[MTLFunctionStitchingAttributeAlwaysInline new]]];
  if(!graph||graph.outputNode!=node||graph.nodes.count!=1||graph.attributes.count!=1)return 2;
  graph.functionName=@"renamed";graph.nodes=@[node];graph.outputNode=nil;graph.attributes=@[];
  if(![graph.functionName isEqual:@"renamed"]||graph.outputNode||graph.attributes.count)return 3;
  MTLStitchedLibraryDescriptor*descriptor=[MTLStitchedLibraryDescriptor new];descriptor.functions=@[];descriptor.functionGraphs=@[graph];
  if(descriptor.functions.count||descriptor.functionGraphs.count!=1)return 4;
  if(@available(macOS 15.0,*)){descriptor.binaryArchives=@[];descriptor.options=MTLStitchedLibraryOptionFailOnBinaryArchiveMiss;if(descriptor.options!=1)return 5;}
 }
 return 0;
}}
