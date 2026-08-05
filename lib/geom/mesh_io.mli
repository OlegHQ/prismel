(** Additional mesh file formats beyond Prismel's built-in OBJ and PLY. *)

open Prismel

type stl_format = Ascii | Binary

val load_stl : string -> (Mesh.t, string) result
val load_stl_exn : string -> Mesh.t
val save_stl : ?format:stl_format -> Mesh.t -> string -> (unit, string) result
(** STL stores triangle positions only. Loaded normals are regenerated. *)

val load_off : string -> (Mesh.t, string) result
val load_off_exn : string -> Mesh.t
val save_off : Mesh.t -> string -> (unit, string) result
(** OFF polygon faces are fan-triangulated on load. *)
