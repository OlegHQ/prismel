val run :
  ?cancel:Cancel.t ->
  grain:int ->
  ?source_primitives:Group.t ->
  ?collision_primitives:Group.t ->
  tolerance:float ->
  include_coplanar:bool ->
  intersecting_group:string option ->
  intersections_attribute:string option ->
  count_attribute:string option ->
  self_intersecting_group:string option ->
  self_intersections_attribute:string option ->
  self_count_attribute:string option ->
  collision:Geometry.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Detect source/collision and optional same-surface polygon intersections after deterministic
    triangulation, packed BVH broad-phase traversal, and a scale-filtered
    floating-point narrow phase with explicit tolerance. The source topology
    is retained; outputs own source primitives. Self-pair output is symmetric
    and suppresses ordinary contacts through shared topology. *)
