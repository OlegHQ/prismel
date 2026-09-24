(** CPU-only image decoding through the pinned stable SDL3_image library. *)

type error_kind =
  | Decoder_error
  | Wrong_domain
  | Invalid_argument
  | Incompatible_version
  | Surface_error of Sdl3.error

type error = private {
  operation : string;
  kind : error_kind;
  message : string;
}

val pp_error : Format.formatter -> error -> unit

module Version : sig
  type t = { major : int; minor : int; patch : int }

  val compiled : t
  val linked : unit -> t
  val stable_headers : bool
  val generator_version : string
  val header_sha256 : string
  val function_count : int
  val safe_function_count : int
  val check : ?release:bool -> unit -> (unit, error) result
end

val load_file : string -> (Sdl3.Surface.t, error) result

(** Decode an owned byte buffer. [kind] is an optional decoder hint such as
    ["PNG"] or ["JPG"]; the buffer remains owned by the caller. *)
val load_bytes : ?kind:string -> bytes -> (Sdl3.Surface.t, error) result

type format = Png | Jpeg | Bmp | Gif | Webp | Tiff | Svg | Other of string
type orientation =
  | Normal | Mirror_horizontal | Rotate_180 | Mirror_vertical
  | Transpose | Rotate_90 | Transverse | Rotate_270
type facts = {
  format : format;
  source_orientation : orientation;
  width : int;
  height : int;
  has_alpha : bool;
  has_transparency : bool;
  color_key : int32 option;
}
type snapshot = { surface : Sdl3.Surface.t; facts : facts }

(** Decode to a newly owned tightly-packed RGBA surface and copied facts.
    [has_alpha] describes the normalized RGBA output, [has_transparency]
    reports whether any copied alpha sample is non-opaque, and [color_key] is
    [None] because source color keys are resolved into alpha during decoding. *)
val decode_file : string -> (snapshot, error) result
val decode_bytes : ?kind:string -> bytes -> (snapshot, error) result

module Retained : sig
  type t
  val create : snapshot -> t
  val generation : t -> int
  val snapshot : t -> snapshot option
  (* Failure preserves the previous snapshot and generation. *)
  val reload_file : t -> string -> (unit, error) result
  val destroy : t -> (unit, error) result
end
