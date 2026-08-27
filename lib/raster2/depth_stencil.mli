(** Checked packed depth/stencil attachments. Each pixel is eight bytes:
    binary32 depth, one stencil byte, and three reserved bytes. *)
type t
type compare = Never | Less | Equal | Less_equal | Greater | Not_equal | Greater_equal | Always
type stencil_op = Keep | Zero | Replace | Increment_clamp | Decrement_clamp | Invert | Increment_wrap | Decrement_wrap
type stencil = { compare:compare; fail:stencil_op; depth_fail:stencil_op; pass:stencil_op; read_mask:int; write_mask:int; reference:int }
type state = { depth_compare:compare; depth_write:bool; stencil:stencil option }
type error = Invalid_size of {width:int;height:int} | Invalid_pitch of {minimum:int;actual:int} | Storage_too_small of {required:int;actual:int} | Coordinate_out_of_bounds of {x:int;y:int} | Invalid_depth of float | Invalid_stencil_value of int
val create : ?pitch:int -> width:int -> height:int -> unit -> (t,error) result
val of_bytes : width:int -> height:int -> pitch:int -> bytes -> (t,error) result
val width : t -> int
val height : t -> int
val pitch : t -> int
val bytes : t -> bytes
val clear : t -> depth:float -> stencil:int -> (unit,error) result
val get : t -> x:int -> y:int -> (float * int,error) result
(* The successful hot path creates no temporary records or containers. *)
val test_and_update : t -> state -> x:int -> y:int -> depth:float -> (bool,error) result
module Private : sig
  (** Allocation-free depth/stencil testing for audited raster loops. The
      caller must provide in-bounds coordinates and a finite depth in [0,1]. *)
  val test_and_update_unchecked : t -> state -> x:int -> y:int -> depth:float -> bool
end
