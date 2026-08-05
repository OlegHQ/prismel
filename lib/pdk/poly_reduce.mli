type plan = {
  edges : Edge_group.t;
  removed_primitives : int;
}

type scratch

val create_scratch : points:int -> primitives:int -> edges:int -> scratch

val plan_round :
  ?cancel:Cancel.t ->
  scratch:scratch ->
  grain:int ->
  primitive_selection:Group.t option ->
  hard_points:Group.t option ->
  hard_edges:Edge_group.t option ->
  preserve_boundary:bool ->
  only_original_positions:bool ->
  equalize_lengths:float ->
  max_normal_deviation:float option ->
  primitive_budget:int ->
  Geometry.t ->
  (plan, string) result
(** Plan one deterministic, one-ring-independent batch of QEM edge
    contractions. The input must contain triangles only. *)
