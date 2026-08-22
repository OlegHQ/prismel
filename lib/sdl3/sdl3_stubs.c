#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <SDL3/SDL.h>
#include <SDL3/SDL_metal.h>

#include "generated_abi.h"

static SDL_Window *window_of_value(value raw)
{
  return (SDL_Window *)(intnat)Nativeint_val(raw);
}

CAMLprim value caml_sdl3_linked_version(value unit)
{
  (void)unit;
  return Val_int(SDL_GetVersion());
}

CAMLprim value caml_sdl3_revision(value unit)
{
  const char *revision;
  CAMLparam1(unit);
  revision = SDL_GetRevision();
  CAMLreturn(caml_copy_string(revision != NULL ? revision : ""));
}

CAMLprim value caml_sdl3_get_error(value unit)
{
  const char *message;
  CAMLparam1(unit);
  message = SDL_GetError();
  CAMLreturn(caml_copy_string(message != NULL ? message : ""));
}

CAMLprim value caml_sdl3_clear_error(value unit)
{
  (void)unit;
  SDL_ClearError();
  return Val_unit;
}

CAMLprim value caml_sdl3_is_main_thread(value unit)
{
  (void)unit;
  return Val_bool(SDL_IsMainThread());
}

CAMLprim value caml_sdl3_init_subsystem(value flags)
{
  return Val_bool(SDL_InitSubSystem((SDL_InitFlags)Int_val(flags)));
}

CAMLprim value caml_sdl3_quit_subsystem(value flags)
{
  SDL_QuitSubSystem((SDL_InitFlags)Int_val(flags));
  return Val_unit;
}

CAMLprim value caml_sdl3_quit(value unit)
{
  (void)unit;
  SDL_Quit();
  return Val_unit;
}

CAMLprim value caml_sdl3_was_init(value flags)
{
  return Val_int(SDL_WasInit((SDL_InitFlags)Int_val(flags)));
}

CAMLprim value caml_sdl3_create_window(
    value title, value width, value height, value flags)
{
  SDL_Window *window;
  CAMLparam4(title, width, height, flags);
  window = SDL_CreateWindow(
      String_val(title), Int_val(width), Int_val(height),
      (SDL_WindowFlags)Int64_val(flags));
  CAMLreturn(caml_copy_nativeint((intnat)window));
}

CAMLprim value caml_sdl3_destroy_window(value raw)
{
  SDL_DestroyWindow(window_of_value(raw));
  return Val_unit;
}

static value copy_size_result(bool success, int width, int height)
{
  CAMLparam0();
  CAMLlocal2(pair, some);
  if (!success) {
    CAMLreturn(Val_none);
  }
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, Val_int(width));
  Store_field(pair, 1, Val_int(height));
  some = caml_alloc(1, 0);
  Store_field(some, 0, pair);
  CAMLreturn(some);
}

CAMLprim value caml_sdl3_window_size(value raw)
{
  int width = 0;
  int height = 0;
  bool success = SDL_GetWindowSize(window_of_value(raw), &width, &height);
  return copy_size_result(success, width, height);
}

CAMLprim value caml_sdl3_window_size_in_pixels(value raw)
{
  int width = 0;
  int height = 0;
  bool success = SDL_GetWindowSizeInPixels(
      window_of_value(raw), &width, &height);
  return copy_size_result(success, width, height);
}

CAMLprim value caml_sdl3_window_flags(value raw)
{
  CAMLparam1(raw);
  CAMLreturn(caml_copy_int64((int64_t)SDL_GetWindowFlags(window_of_value(raw))));
}

CAMLprim value caml_sdl3_show_window(value raw)
{
  return Val_bool(SDL_ShowWindow(window_of_value(raw)));
}

CAMLprim value caml_sdl3_hide_window(value raw)
{
  return Val_bool(SDL_HideWindow(window_of_value(raw)));
}

CAMLprim value caml_sdl3_set_window_fullscreen(value raw, value enabled)
{
  return Val_bool(SDL_SetWindowFullscreen(window_of_value(raw), Bool_val(enabled)));
}

CAMLprim value caml_sdl3_create_metal_view(value raw_window)
{
  SDL_MetalView view;
  CAMLparam1(raw_window);
  view = SDL_Metal_CreateView(window_of_value(raw_window));
  CAMLreturn(caml_copy_nativeint((intnat)view));
}

CAMLprim value caml_sdl3_destroy_metal_view(value raw_view)
{
  SDL_Metal_DestroyView((SDL_MetalView)(intnat)Nativeint_val(raw_view));
  return Val_unit;
}

CAMLprim value caml_sdl3_metal_layer_is_nonnull(value raw_view)
{
  void *layer = SDL_Metal_GetLayer(
      (SDL_MetalView)(intnat)Nativeint_val(raw_view));
  return Val_bool(layer != NULL);
}
