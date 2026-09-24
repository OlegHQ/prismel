/* Ownership graph half of shader157; the 54 value/scalar IDs remain generated. */
enum class PrismelShaderKind { Function, Library, BinaryArchive, FunctionNode,
  InputNode, StitchingGraph, StitchedLibraryDescriptor, FunctionReflection,
  ArgumentEncoder, StageDescriptor };
struct PrismelShaderNode { NSString *name; NSArray<id<MTLFunctionStitchingNode>> *arguments;
  NSArray<MTLFunctionStitchingFunctionNode*> *dependencies; };
struct PrismelShaderGraph { NSString *name; NSArray<MTLFunctionStitchingFunctionNode*> *nodes;
  MTLFunctionStitchingFunctionNode *output; NSArray<id<MTLFunctionStitchingAttribute>> *attributes; };
static NSString *prismel_shader_no_nil(NSArray *xs,NSString *what){for(id x in xs)if(x==nil)return[NSString stringWithFormat:@"nil %@",what];return nil;}
static MTLFunctionStitchingFunctionNode *prismel_shader_node(PrismelShaderNode v,NSString **failure){
 if(v.name==nil){*failure=@"function node name is required";return nil;}NSString*bad=prismel_shader_no_nil(v.arguments,@"argument");if(!bad)bad=prismel_shader_no_nil(v.dependencies,@"dependency");if(bad){*failure=bad;return nil;}
 @try{return[[MTLFunctionStitchingFunctionNode alloc]initWithName:v.name arguments:v.arguments controlDependencies:v.dependencies];}@catch(NSException*x){*failure=x.reason;return nil;}}
static MTLFunctionStitchingGraph *prismel_shader_graph(PrismelShaderGraph v,NSString **failure){
 if(v.name==nil||v.output==nil){*failure=@"graph name and output are required";return nil;}NSString*bad=prismel_shader_no_nil(v.nodes,@"node");if(!bad)bad=prismel_shader_no_nil(v.attributes,@"attribute");if(bad){*failure=bad;return nil;}
 @try{return[[MTLFunctionStitchingGraph alloc]initWithFunctionName:v.name nodes:v.nodes outputNode:v.output attributes:v.attributes];}@catch(NSException*x){*failure=x.reason;return nil;}}
static MTLStitchedLibraryDescriptor *prismel_stitched_library(NSArray<id<MTLFunction>>*functions,NSArray<MTLFunctionStitchingGraph*>*graphs,NSArray<id<MTLBinaryArchive>>*archives,NSString **failure){
 NSString*bad=prismel_shader_no_nil(functions,@"function");if(!bad)bad=prismel_shader_no_nil(graphs,@"graph");if(!bad)bad=prismel_shader_no_nil(archives,@"archive");if(bad){*failure=bad;return nil;}
 @try{MTLStitchedLibraryDescriptor*d=[MTLStitchedLibraryDescriptor new];d.functions=functions;d.functionGraphs=graphs;d.binaryArchives=archives;return d;}@catch(NSException*x){*failure=x.reason;return nil;}}
#ifdef PRISMEL_SHADER_CAML_BRIDGE
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
extern bool prismel_shader_node_value(value,PrismelShaderNode*,NSString**);
extern bool prismel_shader_graph_value(value,PrismelShaderGraph*,NSString**);
extern value prismel_shader_owned_handle(id,PrismelShaderKind);extern value prismel_shader_error(NSString*);
extern "C" CAMLprim value caml_prismel_shader_node(value raw){CAMLparam1(raw);CAMLlocal1(r);@autoreleasepool{PrismelShaderNode v={};NSString*f=nil;if(!prismel_shader_node_value(raw,&v,&f))CAMLreturn(prismel_shader_error(f));id x=prismel_shader_node(v,&f);if(!x)CAMLreturn(prismel_shader_error(f));r=prismel_shader_owned_handle(x,PrismelShaderKind::FunctionNode);CAMLreturn(r);}}
extern "C" CAMLprim value caml_prismel_shader_graph(value raw){CAMLparam1(raw);CAMLlocal1(r);@autoreleasepool{PrismelShaderGraph v={};NSString*f=nil;if(!prismel_shader_graph_value(raw,&v,&f))CAMLreturn(prismel_shader_error(f));id x=prismel_shader_graph(v,&f);if(!x)CAMLreturn(prismel_shader_error(f));r=prismel_shader_owned_handle(x,PrismelShaderKind::StitchingGraph);CAMLreturn(r);}}
#endif
