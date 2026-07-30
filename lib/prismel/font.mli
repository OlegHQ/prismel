(** Font loading and text rendering module.
    
    This module provides text rendering capabilities using SDL2_ttf under the hood.
    Fonts are loaded from files and can render text in various modes with different
    colors and styles. *)

(** The abstract font type. Wraps SDL_ttf font resources. *)
type t

(** Text rendering modes corresponding to SDL_ttf rendering functions. *)
type render_mode = 
  | Solid of Color.t  (** Fast rendering with solid color, transparent background *)
  | Shaded of Color.t * Color.t  (** Antialiased rendering with foreground and background colors *)
  | Blended of Color.t  (** High quality antialiased rendering with alpha blending *)

(** Font style flags that can be combined. *)
type style = 
  | Normal
  | Bold 
  | Italic
  | Underline
  | Strikethrough

(** Font hinting modes for glyph rendering. *)
type hinting = 
  | Normal_hinting
  | Light_hinting  
  | Mono_hinting
  | None_hinting

(** Text alignment for multi-line text rendering. *)
type alignment = 
  | Left
  | Center
  | Right

(** Load a font from a file with the specified point size.
    Returns Error if the file cannot be read or is not a valid font. *)
val load : string -> int -> (t, [`Msg of string]) result

val system_path : unit -> string option
(** Resolve Prismel's installed system UI font. [PRISMEL_UI_FONT] overrides the
    platform candidates. *)

val system : ?size:int -> unit -> (t, [`Msg of string]) result
(** Return a process-shared system UI font at a logical point size. Prismel
    releases shared system fonts during application shutdown. *)

(** Load a font at an explicit uniform raster DPI while retaining logical point
    dimensions. This SDL_ttf binding returns [Error] when [hdpi <> vdpi]. *)
val load_dpi : string -> int -> int -> int -> (t, [`Msg of string]) result

(** Create a new font instance with a different point size from an existing font.
    More efficient than loading the same font file multiple times. *)
val resize : t -> int -> (t, [`Msg of string]) result

(** Render a single line to an image whose public dimensions are logical.
    Its private texture is rasterized at the active renderer's backing density.
    Returns Error if text cannot be rendered (e.g., missing glyphs). *)
val render_text : t -> string -> render_mode -> (Image.t, [`Msg of string]) result

val cached_text :
  ?wrap:int ->
  ?align:alignment ->
  t ->
  string ->
  render_mode ->
  (Image.t, [`Msg of string]) result
(** Render or reuse a renderer-local text texture. The returned image is
    borrowed from the font and remains valid until [clear_cache] or [destroy].
    Explicit newlines honor [align]; [wrap] enables word wrapping. *)

module Private : sig
  val cached_text :
    ?wrap:int ->
    ?align:alignment ->
    t ->
    string ->
    render_mode ->
    (Image.t, [`Msg of string]) result
  (** Bounded renderer draw cache. The image is transient and must be consumed
      immediately by the renderer rather than retained by application code. *)
end

val cache_count : t -> int
val clear_cache : t -> unit

val release_renderer : Tsdl.Sdl.renderer -> unit
(** Backend lifecycle hook. Releases cached textures owned by a renderer before
    that renderer is destroyed. Sketch authors do not need to call this. *)

val shutdown : unit -> unit
(** Backend lifecycle hook. Releases all remaining font textures and handles
    before SDL_ttf shuts down. *)

(** Render text with automatic word wrapping at the specified logical width.
    Returns a list of rendered line images. *)
val render_wrapped : t -> string -> render_mode -> int -> (Image.t list, [`Msg of string]) result

(** Render multi-line text with specified alignment.
    Lines are separated by '\n' characters. *)
val render_multiline : t -> string -> render_mode -> alignment -> (Image.t, [`Msg of string]) result

(** Get the logical dimensions that would be occupied by the given text.
    Useful for layout calculations without actually rendering. *)
val text_size : t -> string -> (int * int, [`Msg of string]) result

(** Get the logical width that would be occupied by rendering the given text. *)
val text_width : t -> string -> (int, [`Msg of string]) result

(** Get the logical height that would be occupied by rendering the given text. *)
val text_height : t -> string -> (int, [`Msg of string]) result

(** Get font metrics information. *)
val get_height : t -> int
val get_ascent : t -> int  
val get_descent : t -> int
val get_line_skip : t -> int

(** Get the current point size of the font. *)
val get_size : t -> int

(** Set the font style (can combine multiple styles). *)
val set_style : t -> style list -> unit

(** Get the current font style. *)
val get_style : t -> style list

(** Set the font hinting mode. *)
val set_hinting : t -> hinting -> unit

(** Get the current font hinting mode. *)
val get_hinting : t -> hinting

(** Enable or disable kerning (character spacing adjustments). *)
val set_kerning : t -> bool -> unit

(** Check if kerning is enabled. *)
val get_kerning : t -> bool

(** Get font family name if available. *)
val get_family_name : t -> string option

(** Get font style name if available. *)
val get_style_name : t -> string option

(** Check if the font is fixed-width (monospace). *)
val is_fixed_width : t -> bool

(** Check if a specific Unicode character is available in the font. *)
val glyph_provided : t -> int -> bool

(** Get glyph metrics for a specific Unicode character.
    Returns (min_x, max_x, min_y, max_y, advance) or Error if glyph not found. *)
val glyph_metrics : t -> int -> (int * int * int * int * int, [`Msg of string]) result

(** Free font resources. Should be called when font is no longer needed.
    The font becomes invalid after this call. *)
val destroy : t -> unit
