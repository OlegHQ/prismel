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
