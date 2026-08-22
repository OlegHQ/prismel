#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdint.h>
#include <string.h>

#include <SDL3/SDL.h>
#include <SDL3_ttf/SDL_ttf.h>

#include "generated_abi.h"

static TTF_Font *font_of_value(value raw)
{
  return (TTF_Font *)(intnat)Nativeint_val(raw);
}

static value string_error(void)
{
  const char *message = SDL_GetError();
  CAMLparam0();
  CAMLlocal2(copy, result);
  copy = caml_copy_string(
      message != NULL && message[0] != '\0' ? message : "SDL3_ttf call failed");
  result = caml_alloc(1, 1);
  Store_field(result, 0, copy);
  CAMLreturn(result);
}

static value unit_success(void)
{
  CAMLparam0();
  CAMLlocal1(result);
  result = caml_alloc(1, 0);
  Store_field(result, 0, Val_unit);
  CAMLreturn(result);
}

static value decoded_surface(SDL_Surface *source)
{
  SDL_Surface *surface;
  size_t row_bytes;
  size_t total_bytes;
  int row;
  CAMLparam0();
  CAMLlocal4(failure, pixels, decoded, result);
  if (source == NULL) {
    CAMLreturn(string_error());
  }
  if (source->format == SDL_PIXELFORMAT_RGBA32) {
    surface = source;
  } else {
    surface = SDL_ConvertSurface(source, SDL_PIXELFORMAT_RGBA32);
    if (surface == NULL) {
      failure = string_error();
      SDL_DestroySurface(source);
      CAMLreturn(failure);
    }
    SDL_DestroySurface(source);
  }
  if (surface->w <= 0 || surface->h <= 0 || surface->pixels == NULL ||
      (size_t)surface->w > SIZE_MAX / 4) {
    SDL_SetError("rasterized text has invalid dimensions or no CPU pixels");
    failure = string_error();
    SDL_DestroySurface(surface);
    CAMLreturn(failure);
  }
  row_bytes = (size_t)surface->w * 4;
  if ((size_t)surface->h > SIZE_MAX / row_bytes ||
      surface->pitch < 0 || (size_t)surface->pitch < row_bytes) {
    SDL_SetError("rasterized text byte count or pitch is invalid");
    failure = string_error();
    SDL_DestroySurface(surface);
    CAMLreturn(failure);
  }
  total_bytes = row_bytes * (size_t)surface->h;
  if (total_bytes > Max_long) {
    SDL_SetError("rasterized text is too large for an OCaml byte string");
    failure = string_error();
    SDL_DestroySurface(surface);
    CAMLreturn(failure);
  }
  pixels = caml_alloc_string(total_bytes);
  if (!SDL_LockSurface(surface)) {
    failure = string_error();
    SDL_DestroySurface(surface);
    CAMLreturn(failure);
  }
  for (row = 0; row < surface->h; row++) {
    memcpy((uint8_t *)Bytes_val(pixels) + ((size_t)row * row_bytes),
        (const uint8_t *)surface->pixels +
          ((size_t)row * (size_t)surface->pitch),
        row_bytes);
  }
  SDL_UnlockSurface(surface);
  decoded = caml_alloc_tuple(3);
  Store_field(decoded, 0, Val_int(surface->w));
  Store_field(decoded, 1, Val_int(surface->h));
  Store_field(decoded, 2, pixels);
  SDL_DestroySurface(surface);
  result = caml_alloc(1, 0);
  Store_field(result, 0, decoded);
  CAMLreturn(result);
}

CAMLprim value caml_sdl3_ttf_version(value unit)
{
  (void)unit;
  return Val_int(TTF_Version());
}

CAMLprim value caml_sdl3_ttf_init(value unit)
{
  (void)unit;
  if (!TTF_Init()) {
    return string_error();
  }
  return unit_success();
}

CAMLprim value caml_sdl3_ttf_quit(value unit)
{
  (void)unit;
  TTF_Quit();
  return Val_unit;
}

CAMLprim value caml_sdl3_ttf_was_init(value unit)
{
  (void)unit;
  return Val_int(TTF_WasInit());
}

CAMLprim value caml_sdl3_ttf_open_font(value path, value size)
{
  TTF_Font *font;
  CAMLparam2(path, size);
  CAMLlocal2(raw, result);
  font = TTF_OpenFont(String_val(path), Double_val(size));
  if (font == NULL) {
    CAMLreturn(string_error());
  }
  raw = caml_copy_nativeint((intnat)font);
  result = caml_alloc(1, 0);
  Store_field(result, 0, raw);
  CAMLreturn(result);
}

CAMLprim value caml_sdl3_ttf_close_font(value raw)
{
  TTF_CloseFont(font_of_value(raw));
  return Val_unit;
}

CAMLprim value caml_sdl3_ttf_font_metrics(value raw)
{
  TTF_Font *font = font_of_value(raw);
  CAMLparam1(raw);
  CAMLlocal1(result);
  result = caml_alloc_tuple(4);
  Store_field(result, 0, Val_int(TTF_GetFontHeight(font)));
  Store_field(result, 1, Val_int(TTF_GetFontAscent(font)));
  Store_field(result, 2, Val_int(TTF_GetFontDescent(font)));
  Store_field(result, 3, Val_int(TTF_GetFontLineSkip(font)));
  CAMLreturn(result);
}

static value copy_nullable_name(const char *name)
{
  CAMLparam0();
  CAMLlocal2(copy, some);
  if (name == NULL) {
    CAMLreturn(Val_none);
  }
  copy = caml_copy_string(name);
  some = caml_alloc(1, 0);
  Store_field(some, 0, copy);
  CAMLreturn(some);
}

CAMLprim value caml_sdl3_ttf_font_family_name(value raw)
{
  CAMLparam1(raw);
  CAMLreturn(copy_nullable_name(TTF_GetFontFamilyName(font_of_value(raw))));
}

CAMLprim value caml_sdl3_ttf_font_style_name(value raw)
{
  CAMLparam1(raw);
  CAMLreturn(copy_nullable_name(TTF_GetFontStyleName(font_of_value(raw))));
}

CAMLprim value caml_sdl3_ttf_set_font_size(value raw, value size)
{
  CAMLparam2(raw, size);
  if (!TTF_SetFontSize(font_of_value(raw), Double_val(size))) {
    CAMLreturn(string_error());
  }
  CAMLreturn(unit_success());
}

CAMLprim value caml_sdl3_ttf_set_font_size_dpi(
    value raw, value size, value horizontal, value vertical)
{
  CAMLparam4(raw, size, horizontal, vertical);
  if (!TTF_SetFontSizeDPI(font_of_value(raw), Double_val(size),
      Int_val(horizontal), Int_val(vertical))) {
    CAMLreturn(string_error());
  }
  CAMLreturn(unit_success());
}

CAMLprim value caml_sdl3_ttf_font_dpi(value raw)
{
  int horizontal = 0;
  int vertical = 0;
  CAMLparam1(raw);
  CAMLlocal3(pair, result, failure);
  if (!TTF_GetFontDPI(font_of_value(raw), &horizontal, &vertical)) {
    failure = string_error();
    CAMLreturn(failure);
  }
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, Val_int(horizontal));
  Store_field(pair, 1, Val_int(vertical));
  result = caml_alloc(1, 0);
  Store_field(result, 0, pair);
  CAMLreturn(result);
}

CAMLprim value caml_sdl3_ttf_size_text(value raw, value text)
{
  int width = 0;
  int height = 0;
  CAMLparam2(raw, text);
  CAMLlocal3(pair, result, failure);
  if (!TTF_GetStringSize(font_of_value(raw), String_val(text),
      caml_string_length(text), &width, &height)) {
    failure = string_error();
    CAMLreturn(failure);
  }
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, Val_int(width));
  Store_field(pair, 1, Val_int(height));
  result = caml_alloc(1, 0);
  Store_field(result, 0, pair);
  CAMLreturn(result);
}

CAMLprim value caml_sdl3_ttf_render_blended(
    value raw, value text, value red, value green, value blue, value alpha)
{
  SDL_Color color;
  SDL_Surface *surface;
  CAMLparam5(raw, text, red, green, blue);
  CAMLxparam1(alpha);
  color.r = Int_val(red);
  color.g = Int_val(green);
  color.b = Int_val(blue);
  color.a = Int_val(alpha);
  surface = TTF_RenderText_Blended(font_of_value(raw), String_val(text),
      caml_string_length(text), color);
  CAMLreturn(decoded_surface(surface));
}

CAMLprim value caml_sdl3_ttf_render_blended_bytecode(value *arguments, int count)
{
  (void)count;
  return caml_sdl3_ttf_render_blended(arguments[0], arguments[1], arguments[2],
      arguments[3], arguments[4], arguments[5]);
}
