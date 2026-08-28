#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/bigarray.h>
#include <string.h>

CAMLprim value caml_wap_raster2_blit_bytes_to_pixels(
    value source, value source_offset, value destination,
    value destination_offset, value length)
{
  CAMLparam5(source, source_offset, destination, destination_offset, length);
  intnat src = Long_val(source_offset);
  intnat dst = Long_val(destination_offset);
  intnat count = Long_val(length);
  intnat source_length = caml_string_length(source);
  intnat destination_length = Caml_ba_array_val(destination)->dim[0];
  if (src < 0 || dst < 0 || count < 0 || src > source_length - count
      || dst > destination_length - count)
    caml_invalid_argument("Wap_raster2_presenter.blit_bytes_to_pixels");
  memcpy((unsigned char *)Caml_ba_data_val(destination) + dst,
         (const unsigned char *)Bytes_val(source) + src, (size_t)count);
  CAMLreturn(Val_unit);
}
