type buffer =
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

external encode_qoi : buffer -> buffer option = "prismel_wap_encode_qoi"
external diff_rectangle :
  buffer -> buffer -> int -> (int * int * int * int * buffer) option
  = "prismel_wap_diff_rectangle"
