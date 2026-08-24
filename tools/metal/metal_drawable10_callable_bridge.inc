/* Drawable10 isolated shard. Safe owners retain the drawable from acquisition
   through schedule and completion. Handler roots are bounded, exactly-once,
   and explicitly cancellable if presentation never occurs. */
struct PrismelDrawableCallbackState {
  std::atomic<int> state{0}; value *root = nullptr;
};
struct PrismelDrawableCallbackToken {
  std::shared_ptr<PrismelDrawableCallbackState> state;
};

static void prismel_drawable_callback_fire(
    const std::shared_ptr<PrismelDrawableCallbackState> &state,
    id<MTLDrawable> drawable) {
  int expected = 0;
  if (!state->state.compare_exchange_strong(expected, 1)) return;
  int registered = caml_c_thread_register(); caml_acquire_runtime_system();
  CAMLparam0(); CAMLlocal3(tuple, identifier, presented);
  identifier = caml_copy_int64((int64_t)drawable.drawableID);
  presented = caml_copy_double(drawable.presentedTime);
  tuple = caml_alloc_tuple(2); Store_field(tuple, 0, identifier);
  Store_field(tuple, 1, presented); (void)caml_callback_exn(*state->root, tuple);
  caml_remove_generational_global_root(state->root); free(state->root);
  state->root = nullptr; CAMLdrop; caml_release_runtime_system();
  if (registered) caml_c_thread_unregister();
}

extern "C" CAMLprim value caml_prismel_metal_drawable10_snapshot(value raw) {
  CAMLparam1(raw); CAMLlocal4(tuple, identifier, presented, result);
  @try { id<MTLDrawable> drawable = object_of_handle(raw, Handle_kind::Metal_drawable);
    identifier = caml_copy_int64((int64_t)drawable.drawableID);
    presented = caml_copy_double(drawable.presentedTime);
    tuple = caml_alloc_tuple(2); Store_field(tuple, 0, identifier);
    Store_field(tuple, 1, presented); result = result_ok(tuple); CAMLreturn(result);
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_drawable10_present(
    value raw, value mode_raw, value time_raw, value unscheduled_raw) {
  CAMLparam4(raw, mode_raw, time_raw, unscheduled_raw);
  if (!Bool_val(unscheduled_raw))
    CAMLreturn(result_error_text("drawable presentation is already scheduled"));
  int mode = Long_val(mode_raw); double time = Double_val(time_raw);
  if (mode < 0 || mode > 2 || (mode != 0 && (!std::isfinite(time) || time < 0.0)))
    CAMLreturn(result_error_text("invalid drawable presentation schedule"));
  @try { id<MTLDrawable> drawable = object_of_handle(raw, Handle_kind::Metal_drawable);
    if (mode == 0) [drawable present];
    else if (mode == 1) [drawable presentAtTime:time];
    else [drawable presentAfterMinimumDuration:time];
    CAMLreturn(result_unit());
  } @catch (NSException *exception) { CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_drawable10_add_handler(
    value raw, value callback) {
  CAMLparam2(raw, callback); CAMLlocal2(token, result);
  auto state = std::make_shared<PrismelDrawableCallbackState>();
  state->root = (value *)malloc(sizeof(value));
  if (state->root == nullptr) CAMLreturn(result_error_text("unable to root drawable handler"));
  *state->root = callback; caml_register_generational_global_root(state->root);
  PrismelDrawableCallbackToken *registration = nullptr;
  try { registration = new PrismelDrawableCallbackToken{state}; }
  catch (...) { caml_remove_generational_global_root(state->root); free(state->root);
    state->root = nullptr; CAMLreturn(result_error_text("unable to allocate drawable handler")); }
  @try { id<MTLDrawable> drawable = object_of_handle(raw, Handle_kind::Metal_drawable);
    [drawable addPresentedHandler:^(id<MTLDrawable> completed) {
      prismel_drawable_callback_fire(state, completed);
    }]; token = caml_copy_nativeint((intnat)registration);
    result = result_ok(token); CAMLreturn(result);
  } @catch (NSException *exception) { int expected = 0;
    if (state->state.compare_exchange_strong(expected, 2)) {
      caml_remove_generational_global_root(state->root); free(state->root);
      state->root = nullptr;
    } delete registration; CAMLreturn(result_error(exception.reason)); }
}

extern "C" CAMLprim value caml_prismel_metal_drawable10_handler_cancel(value raw) {
  CAMLparam1(raw); auto *token =
    (PrismelDrawableCallbackToken *)Nativeint_val(raw);
  if (token != nullptr) { int expected = 0;
    if (token->state->state.compare_exchange_strong(expected, 2)) {
      caml_remove_generational_global_root(token->state->root);
      free(token->state->root); token->state->root = nullptr;
    } delete token;
  } CAMLreturn(Val_unit);
}
