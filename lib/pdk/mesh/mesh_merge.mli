(** Concatenate geometries with matching attribute schemas. Group schemas are
    unioned in first-seen order by default; a missing group contributes no
    members. Pass [~pad_groups:false] to require exact group schemas. Detail
    attributes still require an explicit merge policy. *)
val merge : ?cancel:Cancel.t -> ?grain:int -> ?pad_groups:bool -> Geometry.t list ->
  (Geometry.t, string) result
val run : ?cancel:Cancel.t -> ?grain:int -> Geometry.t list ->
  (Geometry.t, Error.t) result
