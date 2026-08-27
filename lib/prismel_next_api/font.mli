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
val render_text:t->string->render_mode->(Image.t,[`Msg of string])result
val cached_text : ?wrap:int -> ?align:alignment -> t -> string -> render_mode -> (Image.t,[`Msg of string]) result
module Private : sig val cached_text : ?wrap:int -> ?align:alignment -> t -> string -> render_mode -> (Image.t,[`Msg of string]) result end
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
