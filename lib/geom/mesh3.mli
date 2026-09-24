(** Procedural 3D mesh generation from immutable 2D geometry. *)

open Prismel

val extrude :
  ?centered:bool ->
  ?capped:bool ->
  depth:float ->
  Polygon2.t ->
  (Mesh.t, string) result
(** Extrude a simple polygon along the Z axis. Concave caps are tessellated
    with {!Polygon2.triangulate}; side and cap normals remain faceted. *)

val lathe :
  ?segments:int ->
  ?capped:bool ->
  Curve2.t ->
  (Mesh.t, string) result
(** Revolve a radius/height curve about the Y axis. Curve X is radius and Y is
    height. Open profiles are expected to run from their lower end toward their
    upper end when caps are requested. *)

val sweep :
  ?capped:bool ->
  ?smooth_angle:float ->
  profile:Polygon2.t ->
  spine:Vec3.t list ->
  unit ->
  (Mesh.t, string) result
(** Sweep a polygonal profile along a 3D point sequence using
    parallel-transport frames. Profile X/Y coordinates map to each frame's
    normal/binormal axes. *)

val loop_subdivide :
  ?iterations:int -> Mesh.t -> (Mesh.t, string) result
(** Loop subdivision for indexed triangle geometry. Positions, colors, and
    texture coordinates are interpolated by the shared packed PDK kernel;
    normals are regenerated. Existing index connectivity is authoritative, so
    coincident but topologically distinct seam vertices remain distinct. *)

val butterfly_subdivide :
  ?iterations:int -> ?omega:float -> Mesh.t -> (Mesh.t, string) result
(** Interpolating eight-point Butterfly subdivision for triangle meshes.
    Boundary or incomplete stencils use edge midpoints. *)

val catmull_clark :
  ?iterations:int -> Mesh.t -> (Mesh.t, string) result
(** Catmull-Clark subdivision. Prismel triangle inputs produce three quads per
    input face, tessellated into triangles at the [Mesh.t] boundary. *)

val doo_sabin :
  ?iterations:int -> Mesh.t -> (Mesh.t, string) result
(** Doo-Sabin subdivision with face, interior-edge, and closed-vertex faces,
    tessellated into triangle geometry. *)

val saddle : size:float -> (Mesh.t, string) result
(** Four-cube alternating saddle/polycube with internal faces removed by BSP
    union. *)
