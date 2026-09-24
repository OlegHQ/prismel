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

val linked_version : unit -> Sdl3.Version.t
val check_version : ?release:bool -> unit -> (unit, error) result

val load_file : string -> (Sdl3.Surface.t, error) result

(** Decode an owned byte buffer. [kind] is an optional decoder hint such as
    ["PNG"] or ["JPG"]; the buffer remains owned by the caller. *)
val load_bytes : ?kind:string -> bytes -> (Sdl3.Surface.t, error) result
