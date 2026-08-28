type t = {
  software_draws : Scene_execution.draw list;
  software_batched_draws : Scene_execution.draw list;
  native_draws : Scene_execution.draw list;
  native_batched_draws : Scene_execution.draw list;
  instances : int;
  vertices_per_instance : int;
  indices_per_instance : int;
  triangles : int;
  samples : int;
  diffuse_rgb : int * int * int;
  ambient_rgb : int * int * int;
  light_direction : float * float * float;
  signature : string;
}

val create : width:int -> height:int -> t
(** Reproduce the topology, camera, and twelve transforms from
    [tools/bench_renderer.ml]'s legacy Scene3 workload. [software_draws] store
    projected pixel coordinates in the legacy 16-byte layout;
    [software_batched_draws] is their exact concatenated/rebased form;
    [native_draws] store clip-space positions and the legacy diffuse color in
    the 68-byte native benchmark layout. [native_batched_draws] is the exact
    concatenation of those compatible draws with rebased indices, avoiding
    per-frame traversal of twelve otherwise identical native pipeline states.
    The remaining fields pin the legacy
    sample, material, ambient, and directional-light facts so protocol
    validation cannot silently compare a simpler scene. *)
