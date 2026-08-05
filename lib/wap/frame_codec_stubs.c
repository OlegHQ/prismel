#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  uint8_t r, g, b, a;
} prismel_qoi_pixel;

static int prismel_qoi_same(prismel_qoi_pixel left, prismel_qoi_pixel right) {
  return left.r == right.r && left.g == right.g &&
         left.b == right.b && left.a == right.a;
}

static unsigned prismel_qoi_hash(prismel_qoi_pixel pixel) {
  return (pixel.r * 3u + pixel.g * 5u + pixel.b * 7u + pixel.a * 11u) & 63u;
}

static int prismel_qoi_emit(uint8_t *output, size_t capacity, size_t *length,
                            const uint8_t *bytes, size_t count) {
  if (count > capacity - *length) return 0;
  memcpy(output + *length, bytes, count);
  *length += count;
  return 1;
}

CAMLprim value prismel_wap_encode_qoi(value input_value) {
  CAMLparam1(input_value);
  CAMLlocal2(result, output_value);
  struct caml_ba_array *input_array = Caml_ba_array_val(input_value);
  size_t input_length = (size_t)input_array->dim[0];
  const uint8_t *input = (const uint8_t *)input_array->data;
  uint8_t *output;
  size_t output_length = 0;
  prismel_qoi_pixel previous = {0, 0, 0, 255};
  prismel_qoi_pixel index[64] = {{0, 0, 0, 0}};
  unsigned run = 0;

  if (input_length == 0 || (input_length & 3u) != 0) CAMLreturn(Val_none);
  output = malloc(input_length);
  if (output == NULL) caml_raise_out_of_memory();

#define PRISMEL_QOI_EMIT(bytes, count)                                      \
  do {                                                                      \
    if (!prismel_qoi_emit(output, input_length, &output_length, bytes, count)) { \
      free(output);                                                         \
      CAMLreturn(Val_none);                                                  \
    }                                                                       \
  } while (0)

  for (size_t offset = 0; offset < input_length; offset += 4) {
    prismel_qoi_pixel pixel = {
      input[offset], input[offset + 1], input[offset + 2], input[offset + 3]
    };
    int last = offset + 4 == input_length;

    if (prismel_qoi_same(pixel, previous)) {
      run++;
      if (run == 62 || last) {
        uint8_t opcode = (uint8_t)(0xc0u | (run - 1u));
        PRISMEL_QOI_EMIT(&opcode, 1);
        run = 0;
      }
      continue;
    }

    if (run > 0) {
      uint8_t opcode = (uint8_t)(0xc0u | (run - 1u));
      PRISMEL_QOI_EMIT(&opcode, 1);
      run = 0;
    }

    unsigned hash = prismel_qoi_hash(pixel);
    if (prismel_qoi_same(index[hash], pixel)) {
      uint8_t opcode = (uint8_t)hash;
      PRISMEL_QOI_EMIT(&opcode, 1);
    } else {
      int red = (int)pixel.r - (int)previous.r;
      int green = (int)pixel.g - (int)previous.g;
      int blue = (int)pixel.b - (int)previous.b;
      index[hash] = pixel;
      if (pixel.a != previous.a) {
        uint8_t bytes[5] = {0xff, pixel.r, pixel.g, pixel.b, pixel.a};
        PRISMEL_QOI_EMIT(bytes, 5);
      } else if (red >= -2 && red <= 1 && green >= -2 && green <= 1 &&
                 blue >= -2 && blue <= 1) {
        uint8_t opcode = (uint8_t)(0x40u | ((red + 2) << 4) |
                                   ((green + 2) << 2) | (blue + 2));
        PRISMEL_QOI_EMIT(&opcode, 1);
      } else {
        int red_green = red - green;
        int blue_green = blue - green;
        if (green >= -32 && green <= 31 &&
            red_green >= -8 && red_green <= 7 &&
            blue_green >= -8 && blue_green <= 7) {
          uint8_t bytes[2] = {
            (uint8_t)(0x80u | (green + 32)),
            (uint8_t)(((red_green + 8) << 4) | (blue_green + 8))
          };
          PRISMEL_QOI_EMIT(bytes, 2);
        } else {
          uint8_t bytes[4] = {0xfe, pixel.r, pixel.g, pixel.b};
          PRISMEL_QOI_EMIT(bytes, 4);
        }
      }
    }
    previous = pixel;
  }

#undef PRISMEL_QOI_EMIT

  /* Decode work is not worthwhile for nearly-incompressible imagery. */
  if (output_length + 32 >= input_length ||
      output_length >= input_length - (input_length / 20)) {
    free(output);
    CAMLreturn(Val_none);
  }
  {
    uint8_t *resized = realloc(output, output_length);
    if (resized != NULL) output = resized;
  }
  output_value = caml_ba_alloc_dims(
      CAML_BA_UINT8 | CAML_BA_C_LAYOUT | CAML_BA_MANAGED,
      1, output, (intnat)output_length);
  result = caml_alloc(1, 0);
  Store_field(result, 0, output_value);
  CAMLreturn(result);
}

CAMLprim value prismel_wap_diff_rectangle(value previous_value,
                                           value current_value,
                                           value width_value) {
  CAMLparam3(previous_value, current_value, width_value);
  CAMLlocal3(result, tuple, patch_value);
  struct caml_ba_array *previous_array = Caml_ba_array_val(previous_value);
  struct caml_ba_array *current_array = Caml_ba_array_val(current_value);
  size_t length = (size_t)current_array->dim[0];
  const uint8_t *previous = previous_array->data;
  const uint8_t *current = current_array->data;
  int width = Int_val(width_value);
  int height;
  int left, top, right = -1, bottom = -1;

  if (width <= 0 || length == 0 || (length & 3u) != 0 ||
      (size_t)previous_array->dim[0] != length ||
      length % ((size_t)width * 4u) != 0)
    caml_invalid_argument("Wap frame diff dimensions are inconsistent");
  height = (int)(length / ((size_t)width * 4u));
  left = width;
  top = height;
  for (int y = 0; y < height; y++) {
    const uint8_t *previous_row = previous + (size_t)y * (size_t)width * 4u;
    const uint8_t *current_row = current + (size_t)y * (size_t)width * 4u;
    if (memcmp(previous_row, current_row, (size_t)width * 4u) == 0) continue;
    if (y < top) top = y;
    bottom = y;
    const uint32_t *previous_pixels = (const uint32_t *)previous_row;
    const uint32_t *current_pixels = (const uint32_t *)current_row;
    for (int x = 0; x < width; x++) {
      if (previous_pixels[x] != current_pixels[x]) {
        if (x < left) left = x;
        if (x > right) right = x;
      }
    }
  }
  if (right < left || bottom < top) CAMLreturn(Val_none);
  {
    int patch_width = right - left + 1;
    int patch_height = bottom - top + 1;
    size_t row_bytes = (size_t)patch_width * 4u;
    size_t patch_length = row_bytes * (size_t)patch_height;
    if (left == 0 && top == 0 && patch_width == width && patch_height == height) {
      patch_value = current_value;
    } else {
      uint8_t *patch = malloc(patch_length);
      if (patch == NULL) caml_raise_out_of_memory();
      for (int row = 0; row < patch_height; row++) {
        const uint8_t *source = current +
          ((size_t)(top + row) * (size_t)width + (size_t)left) * 4u;
        memcpy(patch + (size_t)row * row_bytes, source, row_bytes);
      }
      patch_value = caml_ba_alloc_dims(
        CAML_BA_UINT8 | CAML_BA_C_LAYOUT | CAML_BA_MANAGED,
        1, patch, (intnat)patch_length);
    }
    tuple = caml_alloc_tuple(5);
    Store_field(tuple, 0, Val_int(left));
    Store_field(tuple, 1, Val_int(top));
    Store_field(tuple, 2, Val_int(patch_width));
    Store_field(tuple, 3, Val_int(patch_height));
    Store_field(tuple, 4, patch_value);
    result = caml_alloc(1, 0);
    Store_field(result, 0, tuple);
    CAMLreturn(result);
  }
}
