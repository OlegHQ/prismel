(** Concatenate geometries with matching attribute schemas. Group schemas are
    unioned in first-seen order by default; a missing group contributes no
    members. Pass [~pad_groups:false] to require exact group schemas. Detail
    attributes still require an explicit merge policy.

    [~source_attribute:name] also writes a primitive int attribute [name]
    holding, per primitive, [source_base] (default 0) plus the index of the
    input it came from.  An input that already has [name] keeps its values, so
    a merge of merges keeps the innermost tag (give every merge its own
    [source_base] range and a tag names one input of one merge). *)
val merge : ?cancel:Cancel.t -> ?grain:int -> ?pad_groups:bool ->
  ?source_attribute:string -> ?source_base:int -> Geometry.t list ->
  (Geometry.t, string) result
val run : ?cancel:Cancel.t -> ?grain:int -> ?source_attribute:string ->
  ?source_base:int -> Geometry.t list ->
  (Geometry.t, Error.t) result
