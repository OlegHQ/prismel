(** The fixed 8 by 8 SDL2_gfx diagnostic bitmap, rendered without SDL. *)

type error = Text_too_long

val width : int
val height : int
val max_text_length : int

(** [glyph_row character row] returns the most-significant-bit-first bitmap
    row.  This is exposed for provenance and exact compatibility tests. *)
val glyph_row : char -> int -> int

(** Draw a NUL-terminated-compatible byte string. Bytes after the first NUL
    are ignored, exactly as by SDL2_gfx [stringRGBA]. Out-of-bounds pixels are
    clipped. *)
val draw :
  target:Surface.t ->
  blend:Composite.blend ->
  x:int ->
  y:int ->
  color:int32 ->
  string ->
  (unit, error) result
