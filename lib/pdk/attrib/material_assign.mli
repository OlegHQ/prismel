(** Assign a surface to a primitive group, preserving unselected surfaces.
    One sequential packed pass; O(primitives) time and storage. Deterministic
    across domain counts. Cancellation is checked every 4096 primitives. *)
val run :
  ?cancel:Pdk_core.Cancel.t -> ?group:string ->
  name:string -> color:(float * float * float) -> roughness:float ->
  emission:(float * float * float) -> Pdk_core.Geometry.t ->
  (Pdk_core.Geometry.t, Pdk_core.Error.t) result
