/* RenderPipeline93 linked-function graph closure (exact 12 SDK IDs).

   MTLLinkedFunctions properties are copied by the descriptor.  Setters accept
   an exact-kind handle, while getters return a fresh owned snapshot handle.
   The handwritten safe layer must retain its source graph until replacement
   and must validate every referenced function against the pipeline device.

   Mesh lanes: 0 object, 1 mesh, 2 fragment.  Tile has one linked-functions
   lane.  A missing OCaml option maps to nil and remains a valid graph reset. */

static value prismel_render93_linked_snapshot(MTLLinkedFunctions *linked) {
  CAMLparam0();
  CAMLlocal2(handle,option);
  if (linked == nil) CAMLreturn(Val_none);
  handle = allocate_handle(linked,Handle_kind::Linked_functions);
  option = caml_alloc(1,0);
  Store_field(option,0,handle);
  CAMLreturn(option);
}

extern "C" CAMLprim value
caml_prismel_metal_render93_mesh_linked(value descriptor_raw,
                                        value lane_raw,
                                        value set_raw,
                                        value replacement) {
  CAMLparam4(descriptor_raw,lane_raw,set_raw,replacement);
  CAMLlocal2(snapshot,result);
  @try {
    MTLMeshRenderPipelineDescriptor *descriptor =
        object_of_handle(descriptor_raw,Handle_kind::Mesh_pipeline_descriptor);
    MTLLinkedFunctions *next = Is_none(replacement)
        ? nil
        : object_of_handle(Field(replacement,0),Handle_kind::Linked_functions);
    switch (Long_val(lane_raw)) {
      case 0:
        if (Bool_val(set_raw)) descriptor.objectLinkedFunctions = next;
        snapshot = prismel_render93_linked_snapshot(
            descriptor.objectLinkedFunctions);
        break;
      case 1:
        if (Bool_val(set_raw)) descriptor.meshLinkedFunctions = next;
        snapshot = prismel_render93_linked_snapshot(
            descriptor.meshLinkedFunctions);
        break;
      case 2:
        if (Bool_val(set_raw)) descriptor.fragmentLinkedFunctions = next;
        snapshot = prismel_render93_linked_snapshot(
            descriptor.fragmentLinkedFunctions);
        break;
      default:
        CAMLreturn(result_error_text("unknown mesh linked-functions lane"));
    }
    result = result_ok(snapshot);
    CAMLreturn(result);
  } @catch(NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}

extern "C" CAMLprim value
caml_prismel_metal_render93_tile_linked(value descriptor_raw,
                                        value set_raw,
                                        value replacement) {
  CAMLparam3(descriptor_raw,set_raw,replacement);
  CAMLlocal2(snapshot,result);
  @try {
    MTLTileRenderPipelineDescriptor *descriptor =
        object_of_handle(descriptor_raw,Handle_kind::Tile_pipeline_descriptor);
    MTLLinkedFunctions *next = Is_none(replacement)
        ? nil
        : object_of_handle(Field(replacement,0),Handle_kind::Linked_functions);
    if (Bool_val(set_raw)) descriptor.linkedFunctions = next;
    snapshot = prismel_render93_linked_snapshot(descriptor.linkedFunctions);
    result = result_ok(snapshot);
    CAMLreturn(result);
  } @catch(NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}
