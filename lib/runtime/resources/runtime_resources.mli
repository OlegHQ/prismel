(** Target-neutral owned resource snapshots for the SDL3 migration. *)

type error_kind = Wrong_domain | Destroyed | Invalid_argument | Decode | Io
type error = private { operation:string; kind:error_kind; message:string }
val pp_error : Format.formatter -> error -> unit

module Image : sig
  type t
  val create : width:int -> height:int -> rgba:bytes -> (t,error) result
  val load_file : string -> (t,error) result
  val identity : t -> int
  val generation : t -> int
  val destroyed : t -> bool
  val size : t -> ((int*int),error) result
  val pixels : t -> (bytes,error) result
  module Private : sig
    val replace_gpu : t -> Ogpu.Backend.texture -> (unit,error) result
    val gpu_snapshot : t -> (int * int * int * Ogpu.Backend.texture) option
    type lease
    (* The bytes remain stable until the lease is released, including across
       image destruction. Mutations use a second bounded buffer rather than
       changing leased storage; release is idempotent. *)
    val borrow_snapshot : t ->
      ((int * int * int * bytes * lease),error) result
    val release_snapshot : lease -> unit
  end
  val replace : t -> width:int -> height:int -> rgba:bytes -> (unit,error) result
  (* Atomically transfer the source's owned pixel storage. On success the
     source is destroyed and the target retains its identity. A source with an
     active private snapshot lease is rejected without mutation. *)
  val replace_owned : t -> t -> (unit,error) result
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
  val snapshot : t -> ((int * int * int * bytes),error) result
  val draw_image : t -> Image.t -> x:int -> y:int -> (unit,error) result
  val resize : t -> width:int -> height:int -> (unit,error) result
  val capture : t -> (Image.t,error) result
  val save_png : t -> string -> (unit,error) result
  module Private : sig
    (** [publish_gpu] adopts the canvas execution's completed frame texture
        (borrowed; the execution owns it) as the authoritative pixels and
        bumps the generation. CPU readers read it back lazily; CPU writers
        forget it. *)
    val publish_gpu : t -> Ogpu.Backend.texture -> (unit,error) result
    val gpu_snapshot : t -> (int * int * int * Ogpu.Backend.texture) option

    (** Reads back any stale CPU pixels, then drops the GPU reference. *)
    val forget_gpu : t -> (unit,error) result
    val identity : t -> int
  end
  val destroy : t -> (unit,error) result
end

module Text : sig
  type t
  val generation : t -> int
  val destroyed : t -> bool
  val size : t -> ((int*int),error) result
  val pixels : t -> (bytes,error) result
  val destroy : t -> (unit,error) result
  module Private : sig
    val identity : t -> int
    (* The owned RGBA storage, borrowed without a copy. Do not mutate or retain
       it: [into_image] may later hand it to an image. *)
    val borrow_pixels : t -> (bytes,error) result
    (* Consume the text and transfer its owned RGBA storage to an image. *)
    val into_image : t -> (Image.t,error) result
  end
end

module Font : sig
  type t
  type style = Normal | Bold | Italic | Underline | Strikethrough
  type hinting = Normal_hinting | Light_hinting | Mono_hinting
    | None_hinting | Light_subpixel_hinting
  type glyph_metrics = { min_x:int; max_x:int; min_y:int; max_y:int; advance:int }
  type alignment = Left | Center | Right
  type metrics = { height:int; ascent:int; descent:int; line_skip:int }
  val open_file : path:string -> size:float -> (t,error) result
  val open_system : size:float -> (t,error) result
  val set_style : t -> style list -> (unit,error) result
  val set_outline : t -> int -> (unit,error) result
  val set_hinting : t -> hinting -> (unit,error) result
  val set_kerning : t -> bool -> (unit,error) result
  val glyph_metrics : t -> int -> (glyph_metrics,error) result
  val metrics : t -> (metrics,error) result
  val size_text : t -> ?wrap_width:int -> string -> (int*int,error) result
  val family_name : t -> (string option,error) result
  val style_name : t -> (string option,error) result
  val glyph_metrics_at : t -> density:int -> int -> (glyph_metrics,error) result
  val render : t -> ?wrap_width:int -> ?align:alignment -> density:int ->
    color:int*int*int*int -> string -> (Text.t option,error) result
  val cached_text : t -> ?wrap_width:int -> density:int ->
    color:int*int*int*int -> string -> (Text.t option,error) result
  val destroy : t -> (unit,error) result
end

module Audio : sig
  type t
  type sample
  type generated = { mixed_bytes:int; pcm_f32:bytes }
  val create_memory : sample_rate:int -> channels:int -> max_channels:int -> (t,error) result
  (* Mixes into memory only; drive it with [generate]. *)
  val create_device : max_channels:int -> (t,error) result
  (* Mixes to the default playback device. *)
  val channel_count : t -> int
  val channel_playing : t -> int -> (bool,error) result
  val load_sample_bytes : t -> bytes -> (sample,error) result
  val reload_sample_bytes : sample -> bytes -> (unit,error) result
  val sample_generation : sample -> int
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
  val generate : t -> frames:int -> (generated,error) result
  val destroy_sample : sample -> (unit,error) result
  val destroy : t -> (unit,error) result
end

module Assets : sig
  type t
  val create : unit -> t
  (* Register an owner hook and return the same borrowed value. *)
  val borrow : t -> destroy:(unit -> (unit,error) result) -> 'a -> ('a,error) result
  val destroy : t -> (unit,error) result
end
