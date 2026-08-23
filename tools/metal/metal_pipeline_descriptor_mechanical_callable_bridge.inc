/* Callable adapters for the 14 descriptor methods (and their six property
   companions) in metal_pipeline_header_mechanical_generated.mm.  The OCaml
   size schema is (width, height, depth), all int64. */

static bool prismel_pipeline_descriptor_size(value raw, MTLSize *out) {
  int64_t width = Int64_val(Field(raw, 0));
  int64_t height = Int64_val(Field(raw, 1));
  int64_t depth = Int64_val(Field(raw, 2));
  if (width < 1 || height < 1 || depth < 1) return false;
  *out = MTLSizeMake((NSUInteger)width, (NSUInteger)height, (NSUInteger)depth);
  return true;
}

#define PRISMEL_PIPELINE_DESCRIPTOR_GET_INT(NAME, KIND, TYPE, CALL) \
extern "C" CAMLprim value NAME(value raw) { \
  CAMLparam1(raw); CAMLlocal2(v, result); @try { \
    TYPE descriptor = object_of_handle(raw, KIND); \
    v = caml_copy_int64((int64_t)(CALL)); result = result_ok(v); \
    CAMLreturn(result); \
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
}

#define PRISMEL_PIPELINE_DESCRIPTOR_SET_INT(NAME, KIND, TYPE, CALL) \
extern "C" CAMLprim value NAME(value raw, value raw_value) { \
  CAMLparam2(raw, raw_value); @try { \
    TYPE descriptor = object_of_handle(raw, KIND); \
    int64_t integer = Int64_val(raw_value); \
    if (integer < 0) CAMLreturn(result_error_text("pipeline descriptor value must be non-negative")); \
    CALL; CAMLreturn(result_ok(Val_unit)); \
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
}

#define PRISMEL_PIPELINE_DESCRIPTOR_RESET(NAME, KIND, TYPE, CALL) \
extern "C" CAMLprim value NAME(value raw) { \
  CAMLparam1(raw); @try { TYPE descriptor = object_of_handle(raw, KIND); CALL; \
    CAMLreturn(result_ok(Val_unit)); \
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); } \
}

extern "C" CAMLprim value caml_prismel_metal_pipeline_compute_descriptor_required_threads(value raw) {
  CAMLparam1(raw); CAMLlocal2(v, result); @try {
    MTLComputePipelineDescriptor *descriptor = object_of_handle(raw, Handle_kind::Compute_pipeline_descriptor);
    if (![descriptor respondsToSelector:@selector(requiredThreadsPerThreadgroup)])
      CAMLreturn(result_error_text("requiredThreadsPerThreadgroup is unavailable"));
    v = prismel_pipeline_size_value(prismel_pipeline_mtlcomputepipelinedescriptor_requiredthreadsperthreadgroup(descriptor));
    result = result_ok(v); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_pipeline_compute_descriptor_set_required_threads(value raw, value raw_size) {
  CAMLparam2(raw, raw_size); @try {
    MTLComputePipelineDescriptor *descriptor = object_of_handle(raw, Handle_kind::Compute_pipeline_descriptor);
    if (![descriptor respondsToSelector:@selector(setRequiredThreadsPerThreadgroup:)])
      CAMLreturn(result_error_text("requiredThreadsPerThreadgroup is unavailable"));
    MTLSize size; if (!prismel_pipeline_descriptor_size(raw_size, &size))
      CAMLreturn(result_error_text("pipeline thread dimensions must be positive"));
    prismel_pipeline_mtlcomputepipelinedescriptor_setrequiredthreadsperthreadgroup_(descriptor, size);
    CAMLreturn(result_ok(Val_unit));
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

PRISMEL_PIPELINE_DESCRIPTOR_RESET(caml_prismel_metal_pipeline_compute_descriptor_reset,
  Handle_kind::Compute_pipeline_descriptor, MTLComputePipelineDescriptor *,
  prismel_pipeline_mtlcomputepipelinedescriptor_reset(descriptor))

PRISMEL_PIPELINE_DESCRIPTOR_GET_INT(caml_prismel_metal_pipeline_render_descriptor_depth_format,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_depthattachmentpixelformat(descriptor))
PRISMEL_PIPELINE_DESCRIPTOR_GET_INT(caml_prismel_metal_pipeline_render_descriptor_input_topology,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_inputprimitivetopology(descriptor))
PRISMEL_PIPELINE_DESCRIPTOR_GET_INT(caml_prismel_metal_pipeline_render_descriptor_sample_count,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_samplecount(descriptor))
PRISMEL_PIPELINE_DESCRIPTOR_GET_INT(caml_prismel_metal_pipeline_render_descriptor_stencil_format,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_stencilattachmentpixelformat(descriptor))
PRISMEL_PIPELINE_DESCRIPTOR_GET_INT(caml_prismel_metal_pipeline_render_descriptor_tessellation_winding,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_tessellationoutputwindingorder(descriptor))

PRISMEL_PIPELINE_DESCRIPTOR_SET_INT(caml_prismel_metal_pipeline_render_descriptor_set_depth_format,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_setdepthattachmentpixelformat_(descriptor, (MTLPixelFormat)integer))
PRISMEL_PIPELINE_DESCRIPTOR_SET_INT(caml_prismel_metal_pipeline_render_descriptor_set_input_topology,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_setinputprimitivetopology_(descriptor, (MTLPrimitiveTopologyClass)integer))
PRISMEL_PIPELINE_DESCRIPTOR_SET_INT(caml_prismel_metal_pipeline_render_descriptor_set_sample_count,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_setsamplecount_(descriptor, (NSUInteger)integer))
PRISMEL_PIPELINE_DESCRIPTOR_SET_INT(caml_prismel_metal_pipeline_render_descriptor_set_stencil_format,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_setstencilattachmentpixelformat_(descriptor, (MTLPixelFormat)integer))
PRISMEL_PIPELINE_DESCRIPTOR_SET_INT(caml_prismel_metal_pipeline_render_descriptor_set_tessellation_winding,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_settessellationoutputwindingorder_(descriptor, (MTLWinding)integer))
PRISMEL_PIPELINE_DESCRIPTOR_RESET(caml_prismel_metal_pipeline_render_descriptor_reset,
  Handle_kind::Render_pipeline_descriptor, MTLRenderPipelineDescriptor *,
  prismel_pipeline_mtlrenderpipelinedescriptor_reset(descriptor))

#undef PRISMEL_PIPELINE_DESCRIPTOR_GET_INT
#undef PRISMEL_PIPELINE_DESCRIPTOR_SET_INT
#undef PRISMEL_PIPELINE_DESCRIPTOR_RESET
