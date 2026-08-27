#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/threads.h>

#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

#include <SDL3/SDL.h>
#include <SDL3/SDL_metal.h>

#include "generated_abi.h"
#include "../native_layer_token/native_layer_token.h"

static SDL_Window *window_of_value(value raw)
{
  return (SDL_Window *)(intnat)Nativeint_val(raw);
}

static SDL_Surface *surface_of_value(value raw)
{
  return (SDL_Surface *)(intnat)Nativeint_val(raw);
}

typedef struct {
  SDL_Renderer *renderer;
  SDL_Texture *texture;
  int width;
  int height;
  uint8_t *snapshot;
  size_t snapshot_size;
} prismel_rgba_presenter;

static prismel_rgba_presenter *presenter_of_value(value raw)
{
  return (prismel_rgba_presenter *)(intnat)Nativeint_val(raw);
}

CAMLprim value caml_sdl3_create_rgba_presenter(value raw_window)
{
  prismel_rgba_presenter *presenter = calloc(1, sizeof(*presenter));
  if (presenter == NULL) return caml_copy_nativeint(0);
  presenter->renderer = SDL_CreateRenderer(window_of_value(raw_window), NULL);
  if (presenter->renderer == NULL) {
    free(presenter);
    return caml_copy_nativeint(0);
  }
  if (!SDL_SetRenderVSync(presenter->renderer, 0)) {
    SDL_DestroyRenderer(presenter->renderer);
    free(presenter->snapshot);
    free(presenter);
    return caml_copy_nativeint(0);
  }
  return caml_copy_nativeint((intnat)presenter);
}

CAMLprim value caml_sdl3_destroy_rgba_presenter(value raw)
{
  prismel_rgba_presenter *presenter = presenter_of_value(raw);
  if (presenter != NULL) {
    SDL_DestroyTexture(presenter->texture);
    SDL_DestroyRenderer(presenter->renderer);
    free(presenter);
  }
  return Val_unit;
}

CAMLprim value caml_sdl3_present_rgba(
    value raw, value pixels, value pitch, value width, value height)
{
  prismel_rgba_presenter *presenter = presenter_of_value(raw);
  int w = Int_val(width), h = Int_val(height);
  if (presenter->texture == NULL || presenter->width != w || presenter->height != h) {
    SDL_Texture *replacement = SDL_CreateTexture(
        presenter->renderer, SDL_PIXELFORMAT_RGBA32,
        SDL_TEXTUREACCESS_STREAMING, w, h);
    if (replacement == NULL) return Val_false;
    SDL_DestroyTexture(presenter->texture);
    presenter->texture = replacement;
    presenter->width = w;
    presenter->height = h;
  }
  if (!SDL_UpdateTexture(presenter->texture, NULL, Bytes_val(pixels), Int_val(pitch)) ||
      !SDL_RenderClear(presenter->renderer) ||
      !SDL_RenderTexture(presenter->renderer, presenter->texture, NULL, NULL))
    return Val_false;
  {
    size_t row_bytes = (size_t)w * 4;
    size_t needed = row_bytes * (size_t)h;
    uint8_t *replacement = realloc(presenter->snapshot, needed);
    int y;
    if (replacement == NULL) return Val_false;
    presenter->snapshot = replacement;
    presenter->snapshot_size = needed;
    for (y = 0; y < h; ++y)
      memcpy(replacement + ((size_t)y * row_bytes),
             Bytes_val(pixels) + ((size_t)y * (size_t)Int_val(pitch)), row_bytes);
  }
  SDL_RenderPresent(presenter->renderer);
  return Val_true;
}

CAMLprim value caml_sdl3_presenter_copy_rgba(value raw)
{
  CAMLparam1(raw);
  CAMLlocal2(result, some);
  prismel_rgba_presenter *presenter = presenter_of_value(raw);
  if (presenter->snapshot == NULL) CAMLreturn(Val_none);
  result = caml_alloc_string(presenter->snapshot_size);
  memcpy(Bytes_val(result), presenter->snapshot, presenter->snapshot_size);
  some = caml_alloc(1, 0);
  Store_field(some, 0, result);
  CAMLreturn(some);
}

CAMLprim value caml_sdl3_presenter_texture_size(value raw)
{
  CAMLparam1(raw);
  CAMLlocal1(pair);
  prismel_rgba_presenter *presenter = presenter_of_value(raw);
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, Val_int(presenter->width));
  Store_field(pair, 1, Val_int(presenter->height));
  CAMLreturn(pair);
}

CAMLprim value caml_sdl3_linked_version(value unit)
{
  (void)unit;
  return Val_int(SDL_GetVersion());
}

CAMLprim value caml_sdl3_performance_counter(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(caml_copy_int64((int64_t)SDL_GetPerformanceCounter()));
}

CAMLprim value caml_sdl3_performance_frequency(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(caml_copy_int64((int64_t)SDL_GetPerformanceFrequency()));
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

CAMLprim value caml_sdl3_window_id(value raw)
{
  CAMLparam1(raw);
  CAMLreturn(caml_copy_int64(SDL_GetWindowID(window_of_value(raw))));
}

CAMLprim value caml_sdl3_window_display(value raw)
{
  CAMLparam1(raw);
  CAMLreturn(caml_copy_int64(SDL_GetDisplayForWindow(window_of_value(raw))));
}

CAMLprim value caml_sdl3_window_pixel_density(value raw)
{
  CAMLparam1(raw);
  CAMLreturn(caml_copy_double(SDL_GetWindowPixelDensity(window_of_value(raw))));
}

CAMLprim value caml_sdl3_window_display_scale(value raw)
{
  CAMLparam1(raw);
  CAMLreturn(caml_copy_double(SDL_GetWindowDisplayScale(window_of_value(raw))));
}

CAMLprim value caml_sdl3_window_position(value raw)
{
  int x = 0;
  int y = 0;
  bool success = SDL_GetWindowPosition(window_of_value(raw), &x, &y);
  return copy_size_result(success, x, y);
}

CAMLprim value caml_sdl3_window_title(value raw)
{
  const char *title;
  CAMLparam1(raw);
  title = SDL_GetWindowTitle(window_of_value(raw));
  CAMLreturn(caml_copy_string(title != NULL ? title : ""));
}

CAMLprim value caml_sdl3_set_window_title(value raw, value title)
{
  return Val_bool(SDL_SetWindowTitle(window_of_value(raw), String_val(title)));
}

CAMLprim value caml_sdl3_center_window(value raw)
{
  return Val_bool(SDL_SetWindowPosition(window_of_value(raw),
      SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED));
}

CAMLprim value caml_sdl3_set_window_bordered(value raw, value enabled)
{
  return Val_bool(SDL_SetWindowBordered(window_of_value(raw), Bool_val(enabled)));
}

CAMLprim value caml_sdl3_set_window_resizable(value raw, value enabled)
{
  return Val_bool(SDL_SetWindowResizable(window_of_value(raw), Bool_val(enabled)));
}

CAMLprim value caml_sdl3_set_window_always_on_top(value raw, value enabled)
{
  return Val_bool(SDL_SetWindowAlwaysOnTop(window_of_value(raw), Bool_val(enabled)));
}

CAMLprim value caml_sdl3_set_window_relative_mouse(value raw, value enabled)
{
  return Val_bool(SDL_SetWindowRelativeMouseMode(
      window_of_value(raw), Bool_val(enabled)));
}

CAMLprim value caml_sdl3_window_relative_mouse(value raw)
{
  return Val_bool(SDL_GetWindowRelativeMouseMode(window_of_value(raw)));
}

CAMLprim value caml_sdl3_capture_mouse(value enabled)
{
  return Val_bool(SDL_CaptureMouse(Bool_val(enabled)));
}

CAMLprim value caml_sdl3_display_refresh_rate(value raw_id)
{
  const SDL_DisplayMode *mode;
  CAMLparam1(raw_id);
  CAMLlocal2(rate, some);
  mode = SDL_GetCurrentDisplayMode((SDL_DisplayID)Int64_val(raw_id));
  if (mode == NULL || !isfinite(mode->refresh_rate) ||
      mode->refresh_rate <= 0.0f) {
    CAMLreturn(Val_none);
  }
  rate = caml_copy_double(mode->refresh_rate);
  some = caml_alloc(1, 0);
  Store_field(some, 0, rate);
  CAMLreturn(some);
}

CAMLprim value caml_sdl3_create_system_cursor(value shape)
{
  CAMLparam1(shape);
  CAMLreturn(caml_copy_nativeint((intnat)SDL_CreateSystemCursor(
      (SDL_SystemCursor)Int_val(shape))));
}

CAMLprim value caml_sdl3_set_cursor(value raw)
{
  return Val_bool(SDL_SetCursor((SDL_Cursor *)(intnat)Nativeint_val(raw)));
}

CAMLprim value caml_sdl3_destroy_cursor(value raw)
{
  SDL_DestroyCursor((SDL_Cursor *)(intnat)Nativeint_val(raw));
  return Val_unit;
}

CAMLprim value caml_sdl3_show_cursor(value unit)
{
  (void)unit;
  return Val_bool(SDL_ShowCursor());
}

CAMLprim value caml_sdl3_hide_cursor(value unit)
{
  (void)unit;
  return Val_bool(SDL_HideCursor());
}

CAMLprim value caml_sdl3_cursor_visible(value unit)
{
  (void)unit;
  return Val_bool(SDL_CursorVisible());
}

CAMLprim value caml_sdl3_set_window_position(value raw, value x, value y)
{
  return Val_bool(SDL_SetWindowPosition(
      window_of_value(raw), Int_val(x), Int_val(y)));
}

CAMLprim value caml_sdl3_set_window_size(value raw, value width, value height)
{
  return Val_bool(SDL_SetWindowSize(
      window_of_value(raw), Int_val(width), Int_val(height)));
}

CAMLprim value caml_sdl3_maximize_window(value raw)
{
  return Val_bool(SDL_MaximizeWindow(window_of_value(raw)));
}

CAMLprim value caml_sdl3_minimize_window(value raw)
{
  return Val_bool(SDL_MinimizeWindow(window_of_value(raw)));
}

CAMLprim value caml_sdl3_restore_window(value raw)
{
  return Val_bool(SDL_RestoreWindow(window_of_value(raw)));
}

CAMLprim value caml_sdl3_sync_window(value raw)
{
  SDL_Window *window;
  bool success;
  CAMLparam1(raw);
  window = window_of_value(raw);
  caml_release_runtime_system();
  success = SDL_SyncWindow(window);
  caml_acquire_runtime_system();
  CAMLreturn(Val_bool(success));
}

CAMLprim value caml_sdl3_displays(value unit)
{
  SDL_DisplayID *displays;
  int count = 0;
  int index;
  CAMLparam1(unit);
  CAMLlocal3(array, item, some);
  displays = SDL_GetDisplays(&count);
  if (displays == NULL) {
    CAMLreturn(Val_none);
  }
  if (count < 0 || count > 1048576) {
    SDL_free(displays);
    SDL_SetError("display count is invalid or unreasonably large");
    CAMLreturn(Val_none);
  }
  array = count == 0 ? Atom(0) : caml_alloc(count, 0);
  for (index = 0; index < count; index++) {
    item = caml_copy_int64(displays[index]);
    Store_field(array, index, item);
  }
  SDL_free(displays);
  some = caml_alloc(1, 0);
  Store_field(some, 0, array);
  CAMLreturn(some);
}

CAMLprim value caml_sdl3_primary_display(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(caml_copy_int64(SDL_GetPrimaryDisplay()));
}

CAMLprim value caml_sdl3_display_name(value raw_id)
{
  const char *name;
  CAMLparam1(raw_id);
  CAMLlocal2(copy, some);
  name = SDL_GetDisplayName((SDL_DisplayID)Int64_val(raw_id));
  if (name == NULL) {
    CAMLreturn(Val_none);
  }
  copy = caml_copy_string(name);
  some = caml_alloc(1, 0);
  Store_field(some, 0, copy);
  CAMLreturn(some);
}

CAMLprim value caml_sdl3_display_bounds(value raw_id, value usable)
{
  SDL_Rect rect;
  bool success;
  CAMLparam2(raw_id, usable);
  CAMLlocal2(result, some);
  if (Bool_val(usable)) {
    success = SDL_GetDisplayUsableBounds(
        (SDL_DisplayID)Int64_val(raw_id), &rect);
  } else {
    success = SDL_GetDisplayBounds((SDL_DisplayID)Int64_val(raw_id), &rect);
  }
  if (!success) {
    CAMLreturn(Val_none);
  }
  result = caml_alloc_tuple(4);
  Store_field(result, 0, Val_int(rect.x));
  Store_field(result, 1, Val_int(rect.y));
  Store_field(result, 2, Val_int(rect.w));
  Store_field(result, 3, Val_int(rect.h));
  some = caml_alloc(1, 0);
  Store_field(some, 0, result);
  CAMLreturn(some);
}

CAMLprim value caml_sdl3_display_content_scale(value raw_id)
{
  CAMLparam1(raw_id);
  CAMLreturn(caml_copy_double(
      SDL_GetDisplayContentScale((SDL_DisplayID)Int64_val(raw_id))));
}

CAMLprim value caml_sdl3_clipboard_set_text(value text)
{
  return Val_bool(SDL_SetClipboardText(String_val(text)));
}

CAMLprim value caml_sdl3_clipboard_get_text(value unit)
{
  char *text;
  CAMLparam1(unit);
  CAMLlocal2(copy, some);
  text = SDL_GetClipboardText();
  if (text == NULL) {
    CAMLreturn(Val_none);
  }
  copy = caml_copy_string(text);
  SDL_free(text);
  some = caml_alloc(1, 0);
  Store_field(some, 0, copy);
  CAMLreturn(some);
}

CAMLprim value caml_sdl3_clipboard_has_text(value unit)
{
  (void)unit;
  return Val_bool(SDL_HasClipboardText());
}

CAMLprim value caml_sdl3_start_text_input(value raw)
{
  return Val_bool(SDL_StartTextInput(window_of_value(raw)));
}

CAMLprim value caml_sdl3_stop_text_input(value raw)
{
  return Val_bool(SDL_StopTextInput(window_of_value(raw)));
}

CAMLprim value caml_sdl3_text_input_active(value raw)
{
  return Val_bool(SDL_TextInputActive(window_of_value(raw)));
}

CAMLprim value caml_sdl3_set_text_input_area(
    value raw, value rectangle, value cursor)
{
  SDL_Rect native_rectangle;
  SDL_Rect *pointer = NULL;
  if (Is_block(rectangle)) {
    value fields = Field(rectangle, 0);
    native_rectangle.x = Int_val(Field(fields, 0));
    native_rectangle.y = Int_val(Field(fields, 1));
    native_rectangle.w = Int_val(Field(fields, 2));
    native_rectangle.h = Int_val(Field(fields, 3));
    pointer = &native_rectangle;
  }
  return Val_bool(SDL_SetTextInputArea(
      window_of_value(raw), pointer, Int_val(cursor)));
}

CAMLprim value caml_sdl3_text_input_area(value raw)
{
  SDL_Rect rectangle;
  int cursor = 0;
  CAMLparam1(raw);
  CAMLlocal3(fields, pair, some);
  if (!SDL_GetTextInputArea(window_of_value(raw), &rectangle, &cursor)) {
    CAMLreturn(Val_none);
  }
  fields = caml_alloc_tuple(4);
  Store_field(fields, 0, Val_int(rectangle.x));
  Store_field(fields, 1, Val_int(rectangle.y));
  Store_field(fields, 2, Val_int(rectangle.w));
  Store_field(fields, 3, Val_int(rectangle.h));
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, fields);
  Store_field(pair, 1, Val_int(cursor));
  some = caml_alloc(1, 0);
  Store_field(some, 0, pair);
  CAMLreturn(some);
}

CAMLprim value caml_sdl3_create_surface_rgba(value width, value height)
{
  SDL_Surface *surface;
  CAMLparam2(width, height);
  surface = SDL_CreateSurface(Int_val(width), Int_val(height),
      SDL_PIXELFORMAT_RGBA32);
  CAMLreturn(caml_copy_nativeint((intnat)surface));
}

CAMLprim value caml_sdl3_destroy_surface(value raw)
{
  SDL_DestroySurface(surface_of_value(raw));
  return Val_unit;
}

CAMLprim value caml_sdl3_surface_info(value raw)
{
  SDL_Surface *surface = surface_of_value(raw);
  CAMLparam1(raw);
  CAMLlocal2(info, some);
  if (surface == NULL) {
    SDL_SetError("surface pointer is NULL");
    CAMLreturn(Val_none);
  }
  info = caml_alloc_tuple(3);
  Store_field(info, 0, Val_int(surface->w));
  Store_field(info, 1, Val_int(surface->h));
  Store_field(info, 2, Val_int(surface->pitch));
  some = caml_alloc(1, 0);
  Store_field(some, 0, info);
  CAMLreturn(some);
}

static bool valid_rgba_surface(SDL_Surface *surface, size_t *row_bytes,
    size_t *total_bytes)
{
  size_t row;
  if (surface == NULL || surface->format != SDL_PIXELFORMAT_RGBA32 ||
      surface->w <= 0 || surface->h <= 0 || surface->pixels == NULL) {
    SDL_SetError("surface is not a non-empty RGBA32 CPU surface");
    return false;
  }
  if ((size_t)surface->w > SIZE_MAX / 4) {
    SDL_SetError("surface row byte count overflows");
    return false;
  }
  row = (size_t)surface->w * 4;
  if ((size_t)surface->h > SIZE_MAX / row) {
    SDL_SetError("surface byte count overflows");
    return false;
  }
  *row_bytes = row;
  *total_bytes = row * (size_t)surface->h;
  return true;
}

CAMLprim value caml_sdl3_surface_write_rgba(
    value raw, value pixels, value source_pitch_value)
{
  SDL_Surface *surface = surface_of_value(raw);
  size_t row_bytes = 0;
  size_t total_bytes = 0;
  size_t source_pitch;
  size_t required;
  int row;
  CAMLparam3(raw, pixels, source_pitch_value);
  if (!valid_rgba_surface(surface, &row_bytes, &total_bytes)) {
    CAMLreturn(Val_false);
  }
  (void)total_bytes;
  if (Int_val(source_pitch_value) < 0) {
    SDL_SetError("negative RGBA source pitch");
    CAMLreturn(Val_false);
  }
  source_pitch = (size_t)Int_val(source_pitch_value);
  if (source_pitch < row_bytes ||
      (size_t)surface->h > SIZE_MAX / source_pitch) {
    SDL_SetError("invalid or overflowing RGBA source pitch");
    CAMLreturn(Val_false);
  }
  required = source_pitch * (size_t)surface->h;
  if (required > caml_string_length(pixels)) {
    SDL_SetError("RGBA source buffer is too short");
    CAMLreturn(Val_false);
  }
  if (!SDL_LockSurface(surface)) {
    CAMLreturn(Val_false);
  }
  for (row = 0; row < surface->h; row++) {
    memcpy((uint8_t *)surface->pixels + ((size_t)row * (size_t)surface->pitch),
        (const uint8_t *)Bytes_val(pixels) + ((size_t)row * source_pitch),
        row_bytes);
  }
  SDL_UnlockSurface(surface);
  CAMLreturn(Val_true);
}

CAMLprim value caml_sdl3_surface_copy_rgba(value raw)
{
  SDL_Surface *surface = surface_of_value(raw);
  size_t row_bytes = 0;
  size_t total_bytes = 0;
  int row;
  CAMLparam1(raw);
  CAMLlocal2(pixels, some);
  if (!valid_rgba_surface(surface, &row_bytes, &total_bytes)) {
    CAMLreturn(Val_none);
  }
  if (total_bytes > Max_long) {
    SDL_SetError("surface is too large for an OCaml byte string");
    CAMLreturn(Val_none);
  }
  pixels = caml_alloc_string(total_bytes);
  if (!SDL_LockSurface(surface)) {
    CAMLreturn(Val_none);
  }
  for (row = 0; row < surface->h; row++) {
    memcpy((uint8_t *)Bytes_val(pixels) + ((size_t)row * row_bytes),
        (const uint8_t *)surface->pixels + ((size_t)row * (size_t)surface->pitch),
        row_bytes);
  }
  SDL_UnlockSurface(surface);
  some = caml_alloc(1, 0);
  Store_field(some, 0, pixels);
  CAMLreturn(some);
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

CAMLprim value caml_sdl3_metal_layer_token(value raw_view,value owner,value generation)
{ CAMLparam3(raw_view,owner,generation);void*layer=SDL_Metal_GetLayer((SDL_MetalView)(intnat)Nativeint_val(raw_view));CAMLreturn(prismel_native_layer_token_create(layer,Int64_val(owner),Int64_val(generation))); }
CAMLprim value caml_sdl3_invalidate_metal_layer_token(value token)
{ prismel_native_layer_token_invalidate(token);return Val_unit; }

/* Keep this order synchronized with Private_raw.raw_event.  The union remains
   private and is immediately converted while pointer payloads are valid. */
enum prismel_raw_event_tag {
  RAW_APPLICATION = 0,
  RAW_DISPLAY,
  RAW_WINDOW,
  RAW_KEYBOARD_DEVICE,
  RAW_KEY,
  RAW_TEXT_EDITING,
  RAW_TEXT_EDITING_CANDIDATES,
  RAW_TEXT_INPUT,
  RAW_MOUSE_DEVICE,
  RAW_MOUSE_MOTION,
  RAW_MOUSE_BUTTON,
  RAW_MOUSE_WHEEL,
  RAW_GAMEPAD_AXIS,
  RAW_GAMEPAD_BUTTON,
  RAW_GAMEPAD_DEVICE,
  RAW_GAMEPAD_TOUCHPAD,
  RAW_GAMEPAD_SENSOR,
  RAW_TOUCH,
  RAW_PINCH,
  RAW_PEN_PROXIMITY,
  RAW_PEN_MOTION,
  RAW_PEN_TOUCH,
  RAW_PEN_BUTTON,
  RAW_PEN_AXIS,
  RAW_DROP,
  RAW_CLIPBOARD,
  RAW_AUDIO_DEVICE,
  RAW_SENSOR,
  RAW_UNKNOWN
};

static value copy_nullable_string(const char *text)
{
  CAMLparam0();
  CAMLlocal2(copy, some);
  if (text == NULL) {
    CAMLreturn(Val_none);
  }
  copy = caml_copy_string(text);
  some = caml_alloc(1, 0);
  Store_field(some, 0, copy);
  CAMLreturn(some);
}

static value copy_string_array(const char * const *strings, int count)
{
  int index;
  CAMLparam0();
  CAMLlocal2(result, item);
  if (strings == NULL || count <= 0) {
    CAMLreturn(Atom(0));
  }
  if (count > 1048576) {
    caml_invalid_argument("SDL3 event string array is unreasonably large");
  }
  result = caml_alloc(count, 0);
  for (index = 0; index < count; index++) {
    item = caml_copy_string(strings[index] != NULL ? strings[index] : "");
    Store_field(result, index, item);
  }
  CAMLreturn(result);
}

static value copy_float_array(const float *values, int count)
{
  int index;
  CAMLparam0();
  CAMLlocal1(result);
  result = caml_alloc(count * Double_wosize, Double_array_tag);
  for (index = 0; index < count; index++) {
    Store_double_field(result, index, (double)values[index]);
  }
  CAMLreturn(result);
}

static value copy_sdl_event(const SDL_Event *event)
{
  CAMLparam0();
  CAMLlocal3(result, item, payload);

#define ALLOC_EVENT(tag, size) result = caml_alloc((size), (tag))
#define STORE_INT(index, number) Store_field(result, (index), Val_int((number)))
#define STORE_BOOL(index, boolean) Store_field(result, (index), Val_bool((boolean)))
#define STORE_I64(index, number) do { \
    item = caml_copy_int64((int64_t)(number)); \
    Store_field(result, (index), item); \
  } while (0)
#define STORE_FLOAT(index, number) do { \
    item = caml_copy_double((double)(number)); \
    Store_field(result, (index), item); \
  } while (0)
#define STORE_STRING(index, text) do { \
    item = caml_copy_string((text) != NULL ? (text) : ""); \
    Store_field(result, (index), item); \
  } while (0)

  switch (event->type) {
  case SDL_EVENT_QUIT:
  case SDL_EVENT_TERMINATING:
  case SDL_EVENT_LOW_MEMORY:
  case SDL_EVENT_WILL_ENTER_BACKGROUND:
  case SDL_EVENT_DID_ENTER_BACKGROUND:
  case SDL_EVENT_WILL_ENTER_FOREGROUND:
  case SDL_EVENT_DID_ENTER_FOREGROUND:
  case SDL_EVENT_LOCALE_CHANGED:
  case SDL_EVENT_SYSTEM_THEME_CHANGED:
  case SDL_EVENT_KEYMAP_CHANGED:
  case SDL_EVENT_SCREEN_KEYBOARD_SHOWN:
  case SDL_EVENT_SCREEN_KEYBOARD_HIDDEN:
    ALLOC_EVENT(RAW_APPLICATION, 2);
    STORE_INT(0, event->type);
    STORE_I64(1, event->common.timestamp);
    break;

  case SDL_EVENT_DISPLAY_ORIENTATION:
  case SDL_EVENT_DISPLAY_ADDED:
  case SDL_EVENT_DISPLAY_REMOVED:
  case SDL_EVENT_DISPLAY_MOVED:
  case SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED:
  case SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED:
  case SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED:
  case SDL_EVENT_DISPLAY_USABLE_BOUNDS_CHANGED:
    ALLOC_EVENT(RAW_DISPLAY, 5);
    STORE_INT(0, event->type);
    STORE_I64(1, event->display.timestamp);
    STORE_I64(2, event->display.displayID);
    STORE_INT(3, event->display.data1);
    STORE_INT(4, event->display.data2);
    break;

  case SDL_EVENT_WINDOW_SHOWN:
  case SDL_EVENT_WINDOW_HIDDEN:
  case SDL_EVENT_WINDOW_EXPOSED:
  case SDL_EVENT_WINDOW_MOVED:
  case SDL_EVENT_WINDOW_RESIZED:
  case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
  case SDL_EVENT_WINDOW_METAL_VIEW_RESIZED:
  case SDL_EVENT_WINDOW_MINIMIZED:
  case SDL_EVENT_WINDOW_MAXIMIZED:
  case SDL_EVENT_WINDOW_RESTORED:
  case SDL_EVENT_WINDOW_MOUSE_ENTER:
  case SDL_EVENT_WINDOW_MOUSE_LEAVE:
  case SDL_EVENT_WINDOW_FOCUS_GAINED:
  case SDL_EVENT_WINDOW_FOCUS_LOST:
  case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
  case SDL_EVENT_WINDOW_HIT_TEST:
  case SDL_EVENT_WINDOW_ICCPROF_CHANGED:
  case SDL_EVENT_WINDOW_DISPLAY_CHANGED:
  case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
  case SDL_EVENT_WINDOW_SAFE_AREA_CHANGED:
  case SDL_EVENT_WINDOW_OCCLUDED:
  case SDL_EVENT_WINDOW_ENTER_FULLSCREEN:
  case SDL_EVENT_WINDOW_LEAVE_FULLSCREEN:
  case SDL_EVENT_WINDOW_DESTROYED:
  case SDL_EVENT_WINDOW_HDR_STATE_CHANGED:
    ALLOC_EVENT(RAW_WINDOW, 5);
    STORE_INT(0, event->type);
    STORE_I64(1, event->window.timestamp);
    STORE_I64(2, event->window.windowID);
    STORE_INT(3, event->window.data1);
    STORE_INT(4, event->window.data2);
    break;

  case SDL_EVENT_KEYBOARD_ADDED:
  case SDL_EVENT_KEYBOARD_REMOVED:
    ALLOC_EVENT(RAW_KEYBOARD_DEVICE, 3);
    STORE_INT(0, event->type);
    STORE_I64(1, event->kdevice.timestamp);
    STORE_I64(2, event->kdevice.which);
    break;

  case SDL_EVENT_KEY_DOWN:
  case SDL_EVENT_KEY_UP:
    ALLOC_EVENT(RAW_KEY, 9);
    STORE_I64(0, event->key.timestamp);
    STORE_I64(1, event->key.windowID);
    STORE_I64(2, event->key.which);
    STORE_INT(3, event->key.scancode);
    STORE_INT(4, event->key.key);
    STORE_INT(5, event->key.mod);
    STORE_INT(6, event->key.raw);
    STORE_BOOL(7, event->key.down);
    STORE_BOOL(8, event->key.repeat);
    break;

  case SDL_EVENT_TEXT_EDITING:
    ALLOC_EVENT(RAW_TEXT_EDITING, 5);
    STORE_I64(0, event->edit.timestamp);
    STORE_I64(1, event->edit.windowID);
    STORE_STRING(2, event->edit.text);
    STORE_INT(3, event->edit.start);
    STORE_INT(4, event->edit.length);
    break;

  case SDL_EVENT_TEXT_EDITING_CANDIDATES:
    ALLOC_EVENT(RAW_TEXT_EDITING_CANDIDATES, 5);
    STORE_I64(0, event->edit_candidates.timestamp);
    STORE_I64(1, event->edit_candidates.windowID);
    payload = copy_string_array(event->edit_candidates.candidates,
        event->edit_candidates.num_candidates);
    Store_field(result, 2, payload);
    STORE_INT(3, event->edit_candidates.selected_candidate);
    STORE_BOOL(4, event->edit_candidates.horizontal);
    break;

  case SDL_EVENT_TEXT_INPUT:
    ALLOC_EVENT(RAW_TEXT_INPUT, 3);
    STORE_I64(0, event->text.timestamp);
    STORE_I64(1, event->text.windowID);
    STORE_STRING(2, event->text.text);
    break;

  case SDL_EVENT_MOUSE_ADDED:
  case SDL_EVENT_MOUSE_REMOVED:
    ALLOC_EVENT(RAW_MOUSE_DEVICE, 3);
    STORE_INT(0, event->type);
    STORE_I64(1, event->mdevice.timestamp);
    STORE_I64(2, event->mdevice.which);
    break;

  case SDL_EVENT_MOUSE_MOTION:
    ALLOC_EVENT(RAW_MOUSE_MOTION, 8);
    STORE_I64(0, event->motion.timestamp);
    STORE_I64(1, event->motion.windowID);
    STORE_I64(2, event->motion.which);
    STORE_I64(3, event->motion.state);
    STORE_FLOAT(4, event->motion.x);
    STORE_FLOAT(5, event->motion.y);
    STORE_FLOAT(6, event->motion.xrel);
    STORE_FLOAT(7, event->motion.yrel);
    break;

  case SDL_EVENT_MOUSE_BUTTON_DOWN:
  case SDL_EVENT_MOUSE_BUTTON_UP:
    ALLOC_EVENT(RAW_MOUSE_BUTTON, 8);
    STORE_I64(0, event->button.timestamp);
    STORE_I64(1, event->button.windowID);
    STORE_I64(2, event->button.which);
    STORE_INT(3, event->button.button);
    STORE_BOOL(4, event->button.down);
    STORE_INT(5, event->button.clicks);
    STORE_FLOAT(6, event->button.x);
    STORE_FLOAT(7, event->button.y);
    break;

  case SDL_EVENT_MOUSE_WHEEL:
    ALLOC_EVENT(RAW_MOUSE_WHEEL, 10);
    STORE_I64(0, event->wheel.timestamp);
    STORE_I64(1, event->wheel.windowID);
    STORE_I64(2, event->wheel.which);
    STORE_FLOAT(3, event->wheel.x);
    STORE_FLOAT(4, event->wheel.y);
    STORE_INT(5, event->wheel.direction);
    STORE_FLOAT(6, event->wheel.mouse_x);
    STORE_FLOAT(7, event->wheel.mouse_y);
    STORE_INT(8, event->wheel.integer_x);
    STORE_INT(9, event->wheel.integer_y);
    break;

  case SDL_EVENT_GAMEPAD_AXIS_MOTION:
    ALLOC_EVENT(RAW_GAMEPAD_AXIS, 4);
    STORE_I64(0, event->gaxis.timestamp);
    STORE_I64(1, event->gaxis.which);
    STORE_INT(2, event->gaxis.axis);
    STORE_INT(3, event->gaxis.value);
    break;

  case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
  case SDL_EVENT_GAMEPAD_BUTTON_UP:
    ALLOC_EVENT(RAW_GAMEPAD_BUTTON, 4);
    STORE_I64(0, event->gbutton.timestamp);
    STORE_I64(1, event->gbutton.which);
    STORE_INT(2, event->gbutton.button);
    STORE_BOOL(3, event->gbutton.down);
    break;

  case SDL_EVENT_GAMEPAD_ADDED:
  case SDL_EVENT_GAMEPAD_REMOVED:
  case SDL_EVENT_GAMEPAD_REMAPPED:
  case SDL_EVENT_GAMEPAD_UPDATE_COMPLETE:
  case SDL_EVENT_GAMEPAD_STEAM_HANDLE_UPDATED:
    ALLOC_EVENT(RAW_GAMEPAD_DEVICE, 3);
    STORE_INT(0, event->type);
    STORE_I64(1, event->gdevice.timestamp);
    STORE_I64(2, event->gdevice.which);
    break;

  case SDL_EVENT_GAMEPAD_TOUCHPAD_DOWN:
  case SDL_EVENT_GAMEPAD_TOUCHPAD_MOTION:
  case SDL_EVENT_GAMEPAD_TOUCHPAD_UP:
    ALLOC_EVENT(RAW_GAMEPAD_TOUCHPAD, 8);
    STORE_INT(0, event->type);
    STORE_I64(1, event->gtouchpad.timestamp);
    STORE_I64(2, event->gtouchpad.which);
    STORE_INT(3, event->gtouchpad.touchpad);
    STORE_INT(4, event->gtouchpad.finger);
    STORE_FLOAT(5, event->gtouchpad.x);
    STORE_FLOAT(6, event->gtouchpad.y);
    STORE_FLOAT(7, event->gtouchpad.pressure);
    break;

  case SDL_EVENT_GAMEPAD_SENSOR_UPDATE:
    ALLOC_EVENT(RAW_GAMEPAD_SENSOR, 5);
    STORE_I64(0, event->gsensor.timestamp);
    STORE_I64(1, event->gsensor.which);
    STORE_INT(2, event->gsensor.sensor);
    payload = copy_float_array(event->gsensor.data, 3);
    Store_field(result, 3, payload);
    STORE_I64(4, event->gsensor.sensor_timestamp);
    break;

  case SDL_EVENT_FINGER_DOWN:
  case SDL_EVENT_FINGER_UP:
  case SDL_EVENT_FINGER_MOTION:
  case SDL_EVENT_FINGER_CANCELED:
    ALLOC_EVENT(RAW_TOUCH, 10);
    STORE_INT(0, event->type);
    STORE_I64(1, event->tfinger.timestamp);
    STORE_I64(2, event->tfinger.touchID);
    STORE_I64(3, event->tfinger.fingerID);
    STORE_FLOAT(4, event->tfinger.x);
    STORE_FLOAT(5, event->tfinger.y);
    STORE_FLOAT(6, event->tfinger.dx);
    STORE_FLOAT(7, event->tfinger.dy);
    STORE_FLOAT(8, event->tfinger.pressure);
    STORE_I64(9, event->tfinger.windowID);
    break;

  case SDL_EVENT_PINCH_BEGIN:
  case SDL_EVENT_PINCH_UPDATE:
  case SDL_EVENT_PINCH_END:
    ALLOC_EVENT(RAW_PINCH, 4);
    STORE_INT(0, event->type);
    STORE_I64(1, event->pinch.timestamp);
    STORE_FLOAT(2, event->pinch.scale);
    STORE_I64(3, event->pinch.windowID);
    break;

  case SDL_EVENT_PEN_PROXIMITY_IN:
  case SDL_EVENT_PEN_PROXIMITY_OUT:
    ALLOC_EVENT(RAW_PEN_PROXIMITY, 4);
    STORE_INT(0, event->type);
    STORE_I64(1, event->pproximity.timestamp);
    STORE_I64(2, event->pproximity.windowID);
    STORE_I64(3, event->pproximity.which);
    break;

  case SDL_EVENT_PEN_MOTION:
    ALLOC_EVENT(RAW_PEN_MOTION, 6);
    STORE_I64(0, event->pmotion.timestamp);
    STORE_I64(1, event->pmotion.windowID);
    STORE_I64(2, event->pmotion.which);
    STORE_I64(3, event->pmotion.pen_state);
    STORE_FLOAT(4, event->pmotion.x);
    STORE_FLOAT(5, event->pmotion.y);
    break;

  case SDL_EVENT_PEN_DOWN:
  case SDL_EVENT_PEN_UP:
    ALLOC_EVENT(RAW_PEN_TOUCH, 8);
    STORE_I64(0, event->ptouch.timestamp);
    STORE_I64(1, event->ptouch.windowID);
    STORE_I64(2, event->ptouch.which);
    STORE_I64(3, event->ptouch.pen_state);
    STORE_FLOAT(4, event->ptouch.x);
    STORE_FLOAT(5, event->ptouch.y);
    STORE_BOOL(6, event->ptouch.eraser);
    STORE_BOOL(7, event->ptouch.down);
    break;

  case SDL_EVENT_PEN_BUTTON_DOWN:
  case SDL_EVENT_PEN_BUTTON_UP:
    ALLOC_EVENT(RAW_PEN_BUTTON, 8);
    STORE_I64(0, event->pbutton.timestamp);
    STORE_I64(1, event->pbutton.windowID);
    STORE_I64(2, event->pbutton.which);
    STORE_I64(3, event->pbutton.pen_state);
    STORE_FLOAT(4, event->pbutton.x);
    STORE_FLOAT(5, event->pbutton.y);
    STORE_INT(6, event->pbutton.button);
    STORE_BOOL(7, event->pbutton.down);
    break;

  case SDL_EVENT_PEN_AXIS:
    ALLOC_EVENT(RAW_PEN_AXIS, 8);
    STORE_I64(0, event->paxis.timestamp);
    STORE_I64(1, event->paxis.windowID);
    STORE_I64(2, event->paxis.which);
    STORE_I64(3, event->paxis.pen_state);
    STORE_FLOAT(4, event->paxis.x);
    STORE_FLOAT(5, event->paxis.y);
    STORE_INT(6, event->paxis.axis);
    STORE_FLOAT(7, event->paxis.value);
    break;

  case SDL_EVENT_DROP_FILE:
  case SDL_EVENT_DROP_TEXT:
  case SDL_EVENT_DROP_BEGIN:
  case SDL_EVENT_DROP_COMPLETE:
  case SDL_EVENT_DROP_POSITION:
    ALLOC_EVENT(RAW_DROP, 7);
    STORE_INT(0, event->type);
    STORE_I64(1, event->drop.timestamp);
    STORE_I64(2, event->drop.windowID);
    STORE_FLOAT(3, event->drop.x);
    STORE_FLOAT(4, event->drop.y);
    payload = copy_nullable_string(event->drop.source);
    Store_field(result, 5, payload);
    payload = copy_nullable_string(event->drop.data);
    Store_field(result, 6, payload);
    break;

  case SDL_EVENT_CLIPBOARD_UPDATE:
    ALLOC_EVENT(RAW_CLIPBOARD, 3);
    STORE_I64(0, event->clipboard.timestamp);
    STORE_BOOL(1, event->clipboard.owner);
    payload = copy_string_array(
        (const char * const *)event->clipboard.mime_types,
        event->clipboard.num_mime_types);
    Store_field(result, 2, payload);
    break;

  case SDL_EVENT_AUDIO_DEVICE_ADDED:
  case SDL_EVENT_AUDIO_DEVICE_REMOVED:
  case SDL_EVENT_AUDIO_DEVICE_FORMAT_CHANGED:
    ALLOC_EVENT(RAW_AUDIO_DEVICE, 4);
    STORE_INT(0, event->type);
    STORE_I64(1, event->adevice.timestamp);
    STORE_I64(2, event->adevice.which);
    STORE_BOOL(3, event->adevice.recording);
    break;

  case SDL_EVENT_SENSOR_UPDATE:
    ALLOC_EVENT(RAW_SENSOR, 4);
    STORE_I64(0, event->sensor.timestamp);
    STORE_I64(1, event->sensor.which);
    payload = copy_float_array(event->sensor.data, 6);
    Store_field(result, 2, payload);
    STORE_I64(3, event->sensor.sensor_timestamp);
    break;

  default:
    ALLOC_EVENT(RAW_UNKNOWN, 2);
    STORE_INT(0, event->type);
    STORE_I64(1, event->common.timestamp);
    break;
  }

#undef STORE_STRING
#undef STORE_FLOAT
#undef STORE_I64
#undef STORE_BOOL
#undef STORE_INT
#undef ALLOC_EVENT
  CAMLreturn(result);
}

/* Event operations are safe-module main-domain-only, so one reusable native
   union is sufficient. SDL-owned pointer fields are copied before reuse. */
static SDL_Event prismel_sdl3_event;

CAMLprim value caml_sdl3_poll_event(value unit)
{
  CAMLparam1(unit);
  CAMLlocal2(raw, some);
  if (!SDL_PollEvent(&prismel_sdl3_event)) {
    CAMLreturn(Val_none);
  }
  raw = copy_sdl_event(&prismel_sdl3_event);
  some = caml_alloc(1, 0);
  Store_field(some, 0, raw);
  CAMLreturn(some);
}

CAMLprim value caml_sdl3_wait_event_timeout(value timeout_value)
{
  bool received;
  int timeout;
  CAMLparam1(timeout_value);
  CAMLlocal2(raw, some);
  timeout = Int_val(timeout_value);
  if (timeout == 0) {
    received = SDL_WaitEventTimeout(&prismel_sdl3_event, 0);
  } else {
    caml_release_runtime_system();
    received = SDL_WaitEventTimeout(&prismel_sdl3_event, timeout);
    caml_acquire_runtime_system();
  }
  if (!received) {
    CAMLreturn(Val_none);
  }
  raw = copy_sdl_event(&prismel_sdl3_event);
  some = caml_alloc(1, 0);
  Store_field(some, 0, raw);
  CAMLreturn(some);
}
