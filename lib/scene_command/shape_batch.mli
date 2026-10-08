(** Immutable packed 2D primitives. Sixteen little-endian words per instance:
    bounds/endpoints (0..3), reserved (4..7), RGBA fill/stroke (8..9),
    kind (10: rect=0, circle=4, line=5), radius (11), stroke width (12),
    anti-alias flag (13), reserved (14..15). Coordinates are logical points. *)
type t
type gpu_token
val instance_bytes : int
val count : t -> int
val instances : t -> bytes
(* Read-only borrowed storage. *)
val gpu : t -> gpu_token option
module Private : sig
  val copy : t -> t
  val valid : t -> bool
  val gpu_token : identity:int -> count:int -> stamp:int64 -> gpu_token
  val gpu_identity : gpu_token -> int
  val gpu_count : gpu_token -> int
  val gpu_stamp : gpu_token -> int64
  val of_gpu : gpu_token -> t
end
module Builder : sig
  type batch = t
  type t
  val create : ?capacity:int -> unit -> t
  val circle : t -> x:float -> y:float -> radius:float ->
    ?fill:int32 -> ?stroke:int32 -> ?stroke_width:float -> unit -> unit
  val rect : t -> x:float -> y:float -> width:float -> height:float ->
    ?fill:int32 -> ?stroke:int32 -> ?stroke_width:float -> unit -> unit
  val line : t -> x0:float -> y0:float -> x1:float -> y1:float ->
    color:int32 -> width:float -> unit
  val publish : t -> batch
end
