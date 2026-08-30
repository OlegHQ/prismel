type t
type render_mode=Solid of Color.t|Shaded of Color.t*Color.t|Blended of Color.t
type style=Normal|Bold|Italic|Underline|Strikethrough
type hinting=Normal_hinting|Light_hinting|Mono_hinting|None_hinting
type alignment=Left|Center|Right
val load:string->int->(t,[`Msg of string])result
val system_path : unit -> string option
val system : ?size:int -> unit -> (t,[`Msg of string]) result
val load_dpi : string -> int -> int -> int -> (t,[`Msg of string]) result
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
end
val cache_count:t->int
val clear_cache:t->unit
val release_renderer : Image.Private.renderer -> unit
val shutdown : unit -> unit
val render_wrapped : t -> string -> render_mode -> int -> (Image.t list,[`Msg of string]) result
val render_multiline : t -> string -> render_mode -> alignment -> (Image.t,[`Msg of string]) result
val text_size : t -> string -> (int*int,[`Msg of string]) result
val text_width : t -> string -> (int,[`Msg of string]) result
val text_height : t -> string -> (int,[`Msg of string]) result
val get_height : t -> int
val get_ascent : t -> int
val get_descent : t -> int
val get_line_skip : t -> int
val set_style:t->style list->unit
val get_style:t->style list
val set_hinting:t->hinting->unit
val get_hinting:t->hinting
val set_kerning:t->bool->unit
val get_kerning:t->bool
val get_size:t->int
val get_family_name : t -> string option
val get_style_name : t -> string option
val is_fixed_width : t -> bool
val glyph_provided : t -> int -> bool
val glyph_metrics : t -> int -> (int*int*int*int*int,[`Msg of string]) result
val destroy:t->unit
