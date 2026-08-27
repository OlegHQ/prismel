(** Deterministic packed software-rendering surfaces. *)

type t

type error =
  | Invalid_size of { width : int; height : int }
  | Invalid_pitch of { minimum : int; actual : int }
  | Storage_too_small of { required : int; actual : int }
  | Coordinate_out_of_bounds of { x : int; y : int }

val create : ?pitch:int -> width:int -> height:int -> unit -> (t, error) result
val of_bytes : width:int -> height:int -> pitch:int -> bytes -> (t, error) result
val width : t -> int
val height : t -> int
val pitch : t -> int
val bytes : t -> bytes

(** Colors are encoded as [0xRRGGBBAA]. *)
val clear : t -> int32 -> unit
val get_rgba : t -> x:int -> y:int -> (int32, error) result
val set_rgba : t -> x:int -> y:int -> int32 -> (unit, error) result
