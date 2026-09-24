/* Largest exact synchronous ownership closure from Pipeline113. Descriptor
   records cover functions, archives, dynamic libraries, linked functions and
   compute stage input. Classic vertex-descriptor handles remain blocked. */

static bool prismel_pipeline_linked_same_device(MTLLinkedFunctions *linked,
                                                 id<MTLDevice> device) {
  for (id<MTLFunction> function in linked.functions)
    if (function.device.registryID != device.registryID) return false;
  return true;
}

extern "C" CAMLprim value caml_prismel_metal_pipeline_render_descriptor(
    value raw_device, value raw) {
  CAMLparam2(raw_device, raw); CAMLlocal2(handle, result); @autoreleasepool { @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    PrismelRenderPipelineObjects objects = {};
    objects.device = device;
    objects.vertexFunction = object_of_handle(Field(raw, 0), Handle_kind::Function);
    objects.fragmentFunction = prismel_optional_typed_handle(Field(raw, 1), Handle_kind::Function);
    objects.binaryArchives = prismel_mesh_archives(Field(raw, 2));
    objects.vertexLibraries = prismel_mesh_libraries(Field(raw, 3));
    objects.fragmentLibraries = prismel_mesh_libraries(Field(raw, 4));
    objects.vertexLinked = static_cast<MTLLinkedFunctions *>(
        prismel_optional_typed_handle(Field(raw, 5), Handle_kind::Linked_functions));
    objects.fragmentLinked = static_cast<MTLLinkedFunctions *>(
        prismel_optional_typed_handle(Field(raw, 6), Handle_kind::Linked_functions));
    if (objects.vertexFunction.device.registryID != device.registryID ||
        (objects.fragmentFunction != nil && objects.fragmentFunction.device.registryID != device.registryID))
      CAMLreturn(result_error_text("render descriptor function belongs to another device"));
    for (id object in objects.binaryArchives)
      if (!prismel_mesh_tile_same_device(device, object)) CAMLreturn(result_error_text("render archive belongs to another device"));
    for (id object in objects.vertexLibraries)
      if (!prismel_mesh_tile_same_device(device, object)) CAMLreturn(result_error_text("vertex library belongs to another device"));
    for (id object in objects.fragmentLibraries)
      if (!prismel_mesh_tile_same_device(device, object)) CAMLreturn(result_error_text("fragment library belongs to another device"));
    if (!prismel_pipeline_linked_same_device(objects.vertexLinked, device) ||
        !prismel_pipeline_linked_same_device(objects.fragmentLinked, device))
      CAMLreturn(result_error_text("linked function belongs to another device"));
    NSString *failure = nil;
    MTLRenderPipelineDescriptor *descriptor = prismel_materialize_render_pipeline(objects, &failure);
    if (descriptor == nil) CAMLreturn(result_error(failure));
    handle = allocate_handle(descriptor, Handle_kind::Render_pipeline_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
}

extern "C" CAMLprim value caml_prismel_metal_pipeline_compute_descriptor(
    value raw_device, value raw) {
  CAMLparam2(raw_device, raw); CAMLlocal2(handle, result); @autoreleasepool { @try {
    id<MTLDevice> device = object_of_handle(raw_device, Handle_kind::Device);
    PrismelComputePipelineObjects objects = {};
    objects.device = device;
    objects.computeFunction = object_of_handle(Field(raw, 0), Handle_kind::Function);
    objects.libraries = prismel_mesh_libraries(Field(raw, 1));
    objects.stageInput = static_cast<MTLStageInputOutputDescriptor *>(
        prismel_optional_typed_handle(Field(raw, 2), Handle_kind::Shader_stage_descriptor));
    if (objects.computeFunction.device.registryID != device.registryID)
      CAMLreturn(result_error_text("compute function belongs to another device"));
    for (id object in objects.libraries)
      if (!prismel_mesh_tile_same_device(device, object)) CAMLreturn(result_error_text("compute library belongs to another device"));
    NSString *failure = nil;
    MTLComputePipelineDescriptor *descriptor = prismel_materialize_compute_pipeline(objects, &failure);
    if (descriptor == nil) CAMLreturn(result_error(failure));
    handle = allocate_handle(descriptor, Handle_kind::Compute_pipeline_descriptor);
    result = result_ok(handle); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } }
}

extern "C" CAMLprim value caml_prismel_metal_pipeline_render_compile(value raw_device,value raw_descriptor,value raw_options){CAMLparam3(raw_device,raw_descriptor,raw_options);@autoreleasepool{@try{id<MTLDevice>device=object_of_handle(raw_device,Handle_kind::Device);MTLRenderPipelineDescriptor*d=object_of_handle(raw_descriptor,Handle_kind::Render_pipeline_descriptor);MTLRenderPipelineReflection*r=nil;NSError*e=nil;id<MTLRenderPipelineState>p=[device newRenderPipelineStateWithDescriptor:d options:(MTLPipelineOption)Int64_val(raw_options) reflection:&r error:&e];if(!p)CAMLreturn(result_error(error_description(e,@"render pipeline compilation failed")));CAMLreturn(prismel_mesh_tile_pipeline_result(p,r));}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}}
extern "C" CAMLprim value caml_prismel_metal_pipeline_compute_compile(value raw_device,value raw_descriptor,value raw_options){CAMLparam3(raw_device,raw_descriptor,raw_options);CAMLlocal4(handle,bindings,pair,result);@autoreleasepool{@try{id<MTLDevice>device=object_of_handle(raw_device,Handle_kind::Device);MTLComputePipelineDescriptor*d=object_of_handle(raw_descriptor,Handle_kind::Compute_pipeline_descriptor);MTLComputePipelineReflection*r=nil;NSError*e=nil;id<MTLComputePipelineState>p=[device newComputePipelineStateWithDescriptor:d options:(MTLPipelineOption)Int64_val(raw_options) reflection:&r error:&e];if(!p)CAMLreturn(result_error(error_description(e,@"compute pipeline compilation failed")));handle=allocate_handle(p,Handle_kind::Compute_pipeline);bindings=copy_bindings(r.bindings);pair=caml_alloc_tuple(2);Store_field(pair,0,handle);Store_field(pair,1,bindings);result=result_ok(pair);CAMLreturn(result);}@catch(NSException*x){CAMLreturn(result_error(x.reason));}}}
