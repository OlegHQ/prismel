(** Initial-domain conversion of scalar-interleaved float32 xyz positions into
    the existing 64-byte Shape_batch circle instance ABI. *)
type t
val source : string
val create : device:Ogpu.Backend.device -> queue:Ogpu.Backend.queue ->
  (t, Ogpu.Error.t) result
val dispatch : t -> source:Ogpu.Backend.buffer -> count:int -> radius:float ->
  fill:int32 -> stroke:int32 -> stroke_width:float ->
  (Ogpu.Backend.buffer, Ogpu.Error.t) result
(** Counts are bounded to 0..1,000,000. Coordinates must be finite and their
    radius-expanded bounds representable as float32. Source validity and
    generation belong to the caller. The completed output is borrowed until
    the next dispatch or close, uses Vertex/Storage, and grows geometrically.
    A four-byte validation status rejects nonfinite coordinates or expanded
    bounds; instance data stays on the GPU. Fill/stroke are packed RGBA words; use fill=-1l,
    stroke=0l for the usual white fill. A zero stroke disables stroke width. *)

val close : t -> unit
(** Idempotent on the creating initial domain; rejects another domain. *)
