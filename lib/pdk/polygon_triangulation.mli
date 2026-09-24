(** Shared deterministic simple-polygon ear clipping. *)

type scratch

val create_scratch : unit -> scratch
(** Reusable single-caller workspace. *)

val primitive :
  ?cancel:Cancel.t ->
  positions:Packed.Float3.Private.view ->
  topology:Topology.Private.view ->
  ?scratch:scratch ->
  int ->
  emit:(int -> int -> int -> int -> unit) ->
  (unit, string) result
(** Emit source vertex indices for one polygon in stable ear-clipping order.
    Curves, non-finite positions, degenerate projections, and non-simple
    polygons return an error. The first callback argument is the zero-based
    triangle ordinal within the primitive. Time is O(c²) and scratch is O(c),
    where [c] is the polygon corner count. *)
