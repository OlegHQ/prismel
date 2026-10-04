type t
type render_mode=Blended of Color.t
type style=Normal|Bold|Italic|Underline|Strikethrough
type hinting=Normal_hinting|Light_hinting|Mono_hinting|None_hinting
type alignment=Left|Center|Right
val load:string->int->(t,[`Msg of string])result
val system_path : unit -> string option
val system : ?size:int -> unit -> (t,[`Msg of string]) result
val resize : t -> int -> (t,[`Msg of string]) result
val render_text:?density:int->t->string->render_mode->(Image.t,[`Msg of string])result
val cached_text : ?wrap:int -> ?align:alignment -> ?density:int -> t -> string -> render_mode -> (Image.t,[`Msg of string]) result
module Private : sig
  type automatic
  type retained_text
  val cached_text : ?wrap:int -> ?align:alignment -> ?density:int -> t -> string -> render_mode -> (Image.t,[`Msg of string]) result
  val borrow_automatic : ?wrap:int -> ?align:alignment -> ?density:int -> size:int -> string -> render_mode -> (automatic,[`Msg of string]) result
  val automatic_image : automatic -> Image.t
  val release_automatic : automatic -> unit
  val automatic_counts : unit -> int * int * int
  val retain_text : ?font:t -> ?density:int -> size:int -> string ->
    render_mode -> (retained_text,[`Msg of string]) result
  val retained_image : retained_text -> Image.t
  val release_retained : retained_text -> unit
  val generation : t -> int
  type glyph = { glyph_width:int; glyph_height:int; glyph_advance:int;
    glyph_alpha:bytes }
  val glyph : ?density:int -> t -> int -> (glyph,[`Msg of string]) result
  (** Rasterize one code point at [density] exactly as it appears inside a
      rendered string; [glyph_advance] is the pen advance in backing pixels
      and [glyph_alpha] holds one coverage byte per pixel. *)

end
val clear_cache:t->unit
val shutdown : unit -> unit
(* Measurements are logical points and allocate no image; [wrap] measures
   wrapped text. Invalid UTF-8 is measured and drawn as U+FFFD. *)
val text_size : ?wrap:int -> t -> string -> (int*int,[`Msg of string]) result
val text_width : t -> string -> (int,[`Msg of string]) result
val text_height : t -> string -> (int,[`Msg of string]) result
(* Vertical metrics in logical points. Raise [Invalid_argument] on a
   destroyed font. *)
val get_height : t -> int
val get_ascent : t -> int
val get_descent : t -> int
val get_line_skip : t -> int
val set_style:t->style list->(unit,[`Msg of string])result
val get_style:t->style list
val set_hinting:t->hinting->(unit,[`Msg of string])result
val get_hinting:t->hinting
val set_kerning:t->bool->(unit,[`Msg of string])result
val get_kerning:t->bool
val get_size:t->int
val get_family_name : t -> string option
val get_style_name : t -> string option
val glyph_metrics : t -> int -> (int*int*int*int*int,[`Msg of string]) result
val destroy:t->unit
