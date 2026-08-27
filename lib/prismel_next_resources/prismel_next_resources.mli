(** Target-neutral owned resource snapshots for the SDL3 migration. *)

type error_kind = Wrong_domain | Destroyed | Invalid_argument | Decode | Io
type error = private { operation:string; kind:error_kind; message:string }
val pp_error : Format.formatter -> error -> unit

module Image : sig
  type t
  val create : width:int -> height:int -> rgba:bytes -> (t,error) result
  val load_file : string -> (t,error) result
  val load_bytes : ?kind:string -> bytes -> (t,error) result
  val identity : t -> int
  val generation : t -> int
  val destroyed : t -> bool
  val size : t -> ((int*int),error) result
  val pixels : t -> (bytes,error) result
  val replace : t -> width:int -> height:int -> rgba:bytes -> (unit,error) result
  (* Stable-identity watched replacement. Decode failure retains the previous
      valid generation and pixels. *)
  val reload_file : t -> string -> (unit,error) result
  val destroy : t -> (unit,error) result
end

module Canvas : sig
  type t
  val create : width:int -> height:int -> (t,error) result
  val generation : t -> int
  val destroyed : t -> bool
  val size : t -> ((int*int),error) result
  val clear : t -> int32 -> (unit,error) result
  val set_pixel : t -> x:int -> y:int -> int32 -> (unit,error) result
  val draw_image : t -> Image.t -> x:int -> y:int -> (unit,error) result
  val resize : t -> width:int -> height:int -> (unit,error) result
  val capture : t -> (Image.t,error) result
  val save_png : t -> string -> (unit,error) result
  val destroy : t -> (unit,error) result
end

module Text : sig
  type t
  val generation : t -> int
  val destroyed : t -> bool
  val size : t -> ((int*int),error) result
  val pixels : t -> (bytes,error) result
  val destroy : t -> (unit,error) result
end

module Font : sig
  type t
  type style = Normal | Bold | Italic | Underline | Strikethrough
  type hinting = Normal_hinting | Light_hinting | Mono_hinting
    | None_hinting | Light_subpixel_hinting
  type glyph_metrics = { min_x:int; max_x:int; min_y:int; max_y:int; advance:int }
  val open_file : path:string -> size:float -> (t,error) result
  val open_system : size:float -> (t,error) result
  val generation : t -> int
  val destroyed : t -> bool
  val set_style : t -> style list -> (unit,error) result
  val set_outline : t -> int -> (unit,error) result
  val set_hinting : t -> hinting -> (unit,error) result
  val set_kerning : t -> bool -> (unit,error) result
  val glyph_metrics : t -> int -> (glyph_metrics,error) result
  val render : t -> ?wrap_width:int -> density:int ->
    color:int*int*int*int -> string -> (Text.t option,error) result
  val cached_text : t -> ?wrap_width:int -> density:int ->
    color:int*int*int*int -> string -> (Text.t option,error) result
  val render_cached : t -> renderer:int -> ?wrap_width:int -> density:int ->
    color:int*int*int*int -> string -> (Text.t option,error) result
  val cache_entries : t -> renderer:int -> int
  val release_renderer : t -> renderer:int -> (unit,error) result
  val destroy : t -> (unit,error) result
end

module Assets : sig
  type t
  val create : unit -> t
  (* Register an owner hook and return the same borrowed value. *)
  val borrow : t -> destroy:(unit -> (unit,error) result) -> 'a -> ('a,error) result
  val count : t -> int
  val destroy : t -> (unit,error) result
end
