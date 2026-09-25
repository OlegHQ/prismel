(** Deterministic packed mesh import and export. *)

type stl_format = Ascii | Binary

val load_stl : ?cancel:Cancel.t -> string -> (Geometry.t, Error.t) result
val save_stl : ?cancel:Cancel.t -> ?format:stl_format -> Geometry.t -> string ->
  (unit, Error.t) result

val load_off : ?cancel:Cancel.t -> string -> (Geometry.t, Error.t) result
val save_off : ?cancel:Cancel.t -> Geometry.t -> string -> (unit, Error.t) result

val load_obj : ?cancel:Cancel.t -> string -> (Geometry.t, Error.t) result
val save_obj : ?cancel:Cancel.t -> Geometry.t -> string -> (unit, Error.t) result
