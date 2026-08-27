type t
type render_mode=Solid of Color.t|Shaded of Color.t*Color.t|Blended of Color.t
type style=Normal|Bold|Italic|Underline|Strikethrough
type hinting=Normal_hinting|Light_hinting|Mono_hinting|None_hinting
type alignment=Left|Center|Right
val load:string->int->(t,[`Msg of string])result
val system : ?size:int -> unit -> (t,[`Msg of string]) result
val render_text:t->string->render_mode->(Image.t,[`Msg of string])result
val cached_text : ?wrap:int -> ?align:alignment -> t -> string -> render_mode -> (Image.t,[`Msg of string]) result
val cache_count:t->int
val clear_cache:t->unit
val set_style:t->style list->unit
val get_style:t->style list
val set_hinting:t->hinting->unit
val get_hinting:t->hinting
val set_kerning:t->bool->unit
val get_kerning:t->bool
val get_size:t->int
val destroy:t->unit
