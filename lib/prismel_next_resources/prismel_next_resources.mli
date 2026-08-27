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
  val replace_pixels : t -> bytes -> (unit,error) result
  (* Atomically replace [image] with the current canvas pixels while retaining
     the image identity. Equal extents reuse the image's owned storage. *)
  val copy_to_image : t -> Image.t -> (unit,error) result
  (* Execute directly against the canvas's authoritative surface. Consumer
     execution is transactional, so rejection leaves pixels/generation unchanged. *)
  val render_ir : t -> lookup:(int -> Raster2.Consumer.resource option) ->
    Raster2.Render_ir.t -> (unit,error) result
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

module Audio : sig
  type t
  type sample
  type intent =
    | Master_volume of float | Stop_all
    | Sample_play of { asset:string; channel:int; loops:int; volume:float }
    | Sample_stop of int | Sample_pause of int | Sample_resume of int
    | Music_play of { asset:string; loops:int; fade_ms:int }
    | Music_volume of float | Music_pause | Music_resume | Music_stop of int
    | Asset_remove of string
  type generated = { mixed_bytes:int; pcm_f32:bytes }
  val create_memory : sample_rate:int -> channels:int -> max_channels:int -> (t,error) result
  val load_sample_bytes : t -> bytes -> (sample,error) result
  val reload_sample_bytes : sample -> bytes -> (unit,error) result
  val sample_identity : sample -> string
  val sample_generation : sample -> int
  val sample_destroyed : sample -> bool
  val sample_encoded : sample -> (bytes,error) result
  val play_sample : t -> ?channel:int -> ?loops:int -> ?fade_in_ms:int ->
    ?volume:float -> sample -> (int,error) result
  val stop_channel : t -> int -> ?fade_out_ms:int -> unit -> (unit,error) result
  val pause_channel : t -> int -> (unit,error) result
  val resume_channel : t -> int -> (unit,error) result
  val play_music : t -> ?loops:int -> ?fade_in_ms:int -> sample -> (unit,error) result
  val pause_music : t -> (unit,error) result
  val resume_music : t -> (unit,error) result
  val stop_music : t -> ?fade_out_ms:int -> unit -> (unit,error) result
  val set_master_volume : t -> float -> (unit,error) result
  val set_music_volume : t -> float -> (unit,error) result
  val master_volume : t -> (float,error) result
  val music_volume : t -> (float,error) result
  val generate : t -> frames:int -> (generated,error) result
  val drain_web_intents : t -> intent list
  val dropped_web_intents : t -> int
  val destroy_sample : sample -> (unit,error) result
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
