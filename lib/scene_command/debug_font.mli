(** A fixed 8 by 8 diagnostic bitmap, rendered without a font service. *)

type error = Text_too_long

val width : int
val height : int
val max_text_length : int

(** [glyph_row character row] returns the most-significant-bit-first bitmap
    row for [character]. *)
val glyph_row : char -> int -> int
