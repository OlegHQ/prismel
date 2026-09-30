(** Atomic file writes, and the JSON persistence of user preferences and
    viewport state.  Documents (presets) are s-expressions, see
    [Editor_document.Preset]. *)

type kind = Settings

val write_text : filename:string -> string -> (unit, string) result
(** Write through a temporary file and a rename; creates the directory. *)

val read_text : filename:string -> (string, string) result

module Viewport : sig
  val encode3 : Prismel.Easy_camera.t -> look_through:bool -> Yojson.Safe.t
  val decode3 : Prismel.Easy_camera.t -> Yojson.Safe.t ->
    Prismel.Easy_camera.t * bool
  val encode2 : Prismel.Easy_camera2.t -> Yojson.Safe.t
  val decode2 : Prismel.Easy_camera2.t -> Yojson.Safe.t -> Prismel.Easy_camera2.t
end

module Settings : sig
  type value =
    | Bool of bool | Float of float | Int of int
    | Text of string | Choice of string | Pair of float * float
  type t = (string * value) list

  val save : sketch:string -> string -> t -> (unit, string) result
  val load : sketch:string -> string -> (t, string) result

  val bool : t -> string -> bool option
  val float : t -> string -> float option
  val int : t -> string -> int option
end
