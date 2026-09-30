(** Concatenate geometries with matching attribute schemas. Group schemas are
    unioned in first-seen order by default; a missing group contributes no
    members. Pass [~pad_groups:false] to require exact group schemas. Detail
    attributes still require an explicit merge policy.

    [~source_attribute:name] also writes a primitive int attribute [name]
    holding, per primitive, the index of the input it came from (an input
    that already has [name] loses it first). *)
val merge : ?cancel:Cancel.t -> ?grain:int -> ?pad_groups:bool ->
  ?source_attribute:string -> Geometry.t list -> (Geometry.t, string) result
val run : ?cancel:Cancel.t -> ?grain:int -> ?source_attribute:string ->
  Geometry.t list ->
  (Geometry.t, Error.t) result
