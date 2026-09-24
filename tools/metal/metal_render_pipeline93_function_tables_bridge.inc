/* RenderPipeline93 function-table allocation closure (exact 2 IDs).
   The public safe API supplies a checked positive capacity and exact stage;
   this native layer constructs the SDK descriptor locally, avoiding exposure
   of a mutable descriptor handle, then returns one owned table handle. */

static bool prismel_render93_table_stage(int64_t stage) {
  return stage == (int64_t)MTLRenderStageVertex ||
         stage == (int64_t)MTLRenderStageFragment ||
         stage == (int64_t)MTLRenderStageTile ||
         stage == (int64_t)MTLRenderStageObject ||
         stage == (int64_t)MTLRenderStageMesh;
}

extern "C" CAMLprim value
caml_prismel_metal_render93_function_table(value pipeline_raw,
                                            value table_kind_raw,
                                            value stage_raw,
                                            value capacity_raw) {
  CAMLparam4(pipeline_raw,table_kind_raw,stage_raw,capacity_raw);
  CAMLlocal2(handle,result);
  int64_t stage = Int64_val(stage_raw);
  int64_t capacity = Int64_val(capacity_raw);
  if (!prismel_render93_table_stage(stage))
    CAMLreturn(result_error_text("render function-table stage must contain one exact stage"));
  if (capacity <= 0 || (uint64_t)capacity > (uint64_t)NSUIntegerMax)
    CAMLreturn(result_error_text("render function-table capacity is out of range"));
  @try {
    id<MTLRenderPipelineState> pipeline =
        object_of_handle(pipeline_raw,Handle_kind::Render_pipeline);
    switch (Long_val(table_kind_raw)) {
      case 0: {
        MTLVisibleFunctionTableDescriptor *descriptor =
            [MTLVisibleFunctionTableDescriptor visibleFunctionTableDescriptor];
        descriptor.functionCount = (NSUInteger)capacity;
        id<MTLVisibleFunctionTable> table =
            [pipeline newVisibleFunctionTableWithDescriptor:descriptor
                                                      stage:(MTLRenderStages)stage];
        if (table == nil)
          CAMLreturn(result_error_text("Metal failed to allocate render visible function table"));
        handle = allocate_handle(table,Handle_kind::Visible_function_table);
        break;
      }
      case 1: {
        MTLIntersectionFunctionTableDescriptor *descriptor =
            [MTLIntersectionFunctionTableDescriptor intersectionFunctionTableDescriptor];
        descriptor.functionCount = (NSUInteger)capacity;
        id<MTLIntersectionFunctionTable> table =
            [pipeline newIntersectionFunctionTableWithDescriptor:descriptor
                                                           stage:(MTLRenderStages)stage];
        if (table == nil)
          CAMLreturn(result_error_text("Metal failed to allocate render intersection function table"));
        handle = allocate_handle(table,Handle_kind::Intersection_function_table);
        break;
      }
      default:
        CAMLreturn(result_error_text("unknown render function-table kind"));
    }
    result = result_ok(handle);
    CAMLreturn(result);
  } @catch(NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}
