#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdint.h>
#include <string.h>

#include <SDL3/SDL.h>
#include <SDL3_image/SDL_image.h>

#include "generated_abi.h"

static value decoder_error(void)
{
  const char *message = SDL_GetError();
  CAMLparam0();
  CAMLlocal2(copy, result);
  copy = caml_copy_string(
      message != NULL && message[0] != '\0' ? message : "image decode failed");
  result = caml_alloc(1, 1);
  Store_field(result, 0, copy);
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
    CAMLreturn(decoder_error());
  }
  if (source->format == SDL_PIXELFORMAT_RGBA32) {
    surface = source;
  } else {
    surface = SDL_ConvertSurface(source, SDL_PIXELFORMAT_RGBA32);
    if (surface == NULL) {
      failure = decoder_error();
      SDL_DestroySurface(source);
      CAMLreturn(failure);
    }
    SDL_DestroySurface(source);
  }
  if (surface->w <= 0 || surface->h <= 0 || surface->pixels == NULL ||
      (size_t)surface->w > SIZE_MAX / 4) {
    SDL_SetError("decoded image has invalid dimensions or no CPU pixels");
    failure = decoder_error();
    SDL_DestroySurface(surface);
    CAMLreturn(failure);
  }
  row_bytes = (size_t)surface->w * 4;
  if ((size_t)surface->h > SIZE_MAX / row_bytes ||
      surface->pitch < 0 || (size_t)surface->pitch < row_bytes) {
    SDL_SetError("decoded image byte count or pitch is invalid");
    failure = decoder_error();
    SDL_DestroySurface(surface);
    CAMLreturn(failure);
  }
  total_bytes = row_bytes * (size_t)surface->h;
  if (total_bytes > Max_long) {
    SDL_SetError("decoded image is too large for an OCaml byte string");
    failure = decoder_error();
    SDL_DestroySurface(surface);
    CAMLreturn(failure);
  }
  pixels = caml_alloc_string(total_bytes);
  if (!SDL_LockSurface(surface)) {
    failure = decoder_error();
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

CAMLprim value caml_sdl3_image_version(value unit)
{
  (void)unit;
  return Val_int(IMG_Version());
}

CAMLprim value caml_sdl3_image_decode_bytes(value bytes, value kind)
{
  SDL_IOStream *stream;
  SDL_Surface *surface;
  CAMLparam2(bytes, kind);
  stream = SDL_IOFromConstMem(Bytes_val(bytes), caml_string_length(bytes));
  if (stream == NULL) {
    CAMLreturn(decoder_error());
  }
  if (Is_block(kind)) {
    surface = IMG_LoadTyped_IO(stream, true, String_val(Field(kind, 0)));
  } else {
    surface = IMG_Load_IO(stream, true);
  }
  CAMLreturn(decoded_surface(surface));
}
