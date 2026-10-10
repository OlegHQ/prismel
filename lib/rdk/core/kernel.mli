(** Packed point kernels. Built-in kernels allocate only their exact output
    planes. User callbacks may allocate according to ordinary OCaml closure and
    floating-point boxing rules. [Writer.set] may only target the current stable
    point index passed to the callback. *)

val generate_point_ranges :
  int ->
  (first:int -> last:int ->
   x:float array -> y:float array -> z:float array -> unit) ->
  Geometry.t
(** High-throughput O(n) generator. The callback is invoked once per stable
    disjoint half-open range, not once per point. It may mutate only
    indices from [first] inclusive to [last] exclusive in the supplied owned
    output planes and must not retain the
    arrays. This makes tight user loops allocation-free beyond exact output. *)

val edit_point_ranges :
  ?grain:int ->
  (first:int -> last:int ->
   x:float array -> y:float array -> z:float array -> unit) ->
  Geometry.t ->
  Geometry.t
(** Copy-on-write range kernel. Position planes are copied exactly once, then
    disjoint stable ranges mutate the owned copy before it is frozen. O(n) time
    and O(n) auxiliary/output memory. *)

val transform : ?grain:int -> Rays_math.Mat4.t -> Geometry.t -> Geometry.t
(** Packed affine/projective transform with no per-point OCaml allocation. *)
