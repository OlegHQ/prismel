type t = {
  software_draws : Scene_execution.draw list;
  native_draws : Scene_execution.draw list;
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
    projected pixel coordinates in the 16-byte Raster2 layout;
    [native_draws] store clip-space positions and the legacy diffuse color in
    the 68-byte native benchmark layout. The remaining fields pin the legacy
    sample, material, ambient, and directional-light facts so protocol
    validation cannot silently compare a simpler scene. *)
