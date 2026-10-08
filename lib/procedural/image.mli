(** Immutable, renderer-independent row-major RGBA samples in [0,1]. *)
type t
val create : width:int -> height:int -> rgba:float array -> (t, Diagnostic.error) result
val width : t -> int
val height : t -> int
val data_id : t -> int
val rgba : t -> float array
(** An owned copy; modifying it does not change the cooked image. *)
val payload_bytes : t -> int
module Private : sig
  val storage : t -> float array
  (** Borrowed immutable storage; consumers must not modify or retain it beyond
      the image's lifetime. *)
  val of_owned_rgba : width:int -> height:int -> float array -> (t, Diagnostic.error) result
  (** Transfers sole ownership after validating dimensions and samples. *)
end
