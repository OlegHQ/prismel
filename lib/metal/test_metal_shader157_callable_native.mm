#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static void require(bool condition, NSString *message) {
  if (!condition) {
    @throw [NSException exceptionWithName:@"Shader157"
                                   reason:message
                                 userInfo:nil];
  }
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;

    NSError *error = nil;
    NSString *source =
        @"#include <metal_stdlib>\n"
         "using namespace metal;\n"
         "struct Args { device uint *values [[id(0)]]; };\n"
         "kernel void argument_kernel(constant Args &args [[buffer(0)]], uint i [[thread_position_in_grid]]) { args.values[i] = i; }\n"
         "struct In { float2 p [[attribute(0)]]; };\n"
         "struct Out { float4 p [[position]]; };\n"
         "vertex Out vertex_main(In in [[stage_in]]) { return {float4(in.p, 0, 1)}; }";
    id<MTLLibrary> library = [device newLibraryWithSource:source
                                                  options:nil
                                                    error:&error];
    require(library != nil, error.localizedDescription ?: @"library creation");

    id<MTLFunction> kernel = [library newFunctionWithName:@"argument_kernel"];
    require(kernel != nil, @"kernel lookup");
    require(kernel.name.length > 0, @"function name");
    (void)kernel.options;
    (void)kernel.patchType;
    (void)kernel.patchControlPointCount;
    id<MTLArgumentEncoder> encoder =
        [kernel newArgumentEncoderWithBufferIndex:0];
    require(encoder != nil && encoder.encodedLength > 0, @"argument encoder");

    id<MTLFunction> vertex = [library newFunctionWithName:@"vertex_main"];
    require(vertex != nil, @"vertex lookup");
    NSArray<MTLVertexAttribute *> *attributes = vertex.vertexAttributes;
    require(attributes.count == 1, @"vertex attribute reflection");
    MTLVertexAttribute *attribute = attributes[0];
    require(attribute.attributeIndex == 0 && attribute.name.length > 0,
            @"vertex attribute fields");
    (void)attribute.attributeType;
    (void)attribute.active;
    (void)attribute.patchData;
    (void)attribute.patchControlPointData;

    MTLStageInputOutputDescriptor *stage =
        [MTLStageInputOutputDescriptor stageInputOutputDescriptor];
    require(stage != nil, @"stage descriptor");
    stage.indexBufferIndex = 3;
    stage.indexType = MTLIndexTypeUInt32;
    require(stage.indexBufferIndex == 3 && stage.indexType == MTLIndexTypeUInt32,
            @"stage scalar roundtrip");
    MTLAttributeDescriptor *descriptor = stage.attributes[0];
    descriptor.bufferIndex = 2;
    descriptor.offset = 16;
    descriptor.format = MTLAttributeFormatFloat2;
    require(stage.attributes[0].bufferIndex == 2 &&
            stage.attributes[0].offset == 16 &&
            stage.attributes[0].format == MTLAttributeFormatFloat2,
            @"attribute descriptor roundtrip");
    require(stage.layouts != nil, @"stage layouts");
    [stage reset];

    if (@available(macOS 11.0, *)) {
      MTLFunctionStitchingInputNode *input =
          [[MTLFunctionStitchingInputNode alloc] initWithArgumentIndex:5];
      require(input.argumentIndex == 5, @"stitch input construction");
      input.argumentIndex = 7;
      require(input.argumentIndex == 7, @"stitch input roundtrip");
    }

    NSLog(@"shader157 callable native: function/argument/attribute/stage/stitch green");
    return 0;
  }
}
