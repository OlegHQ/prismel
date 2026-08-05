(** Functional capture of [Shader3] vertex/geometry stage outputs. *)

type t

val capture :
  ?model:Mat4.t ->
  viewport:int * int * int * int ->
  camera:Camera.t ->
  shader:Shader3.t ->
  Mesh.t ->
  t
(** Execute vertex processing and an optional geometry stage without
    rasterization or fragment execution. *)

val primitives : t -> Shader3.primitive list
val vertices : t -> Shader3.vertex_output list
val varyings : t -> float list list
val primitive_count : t -> int
val vertex_count : t -> int
val meshes : t -> Mesh.t list
(** Convert each captured point, line, or triangle to a world-space mesh with
    its output normals, colors, and texture coordinates. *)
