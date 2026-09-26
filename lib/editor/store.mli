(** Versioned, atomic JSON persistence shared by editor panes. *)

type kind = Preset | Settings

val save : filename:string -> kind:kind -> sketch:string ->
  sections:(string * Yojson.Safe.t) list -> (unit, string) result
val load : filename:string -> kind:kind ->
  (string * (string * Yojson.Safe.t) list, string) result

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
