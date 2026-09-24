/* Handwritten enabling constructor for the LinkedFunctions9 safe graph.
   MTLLinkedFunctions is a descriptor-like retained object with no device
   property.  The safe OCaml owner therefore records the authoritative device
   separately and passes its registry ID to every function-bearing setter. */
extern "C" CAMLprim value
caml_prismel_metal_linked_functions_create(value unit_raw)
{
  CAMLparam1(unit_raw);
  CAMLlocal2(handle, result);
  (void)unit_raw;
  @try {
    MTLLinkedFunctions *linked = [MTLLinkedFunctions new];
    if (linked == nil)
      CAMLreturn(result_error_text("Metal returned no linked-functions object"));
    handle = allocate_handle(linked, Handle_kind::Linked_functions);
    result = result_ok(handle);
    CAMLreturn(result);
  } @catch (NSException *exception) {
    CAMLreturn(result_error(exception.reason));
  }
}
