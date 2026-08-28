(** Explicit still-image rendering for pure 3D scenes. *)

val save_png :
  width:int ->
  height:int ->
  ?background:Color.t ->
  camera:Camera.t ->
  Scene3.t ->
  string ->
  (unit, string) result
(** Renders at the requested pixel dimensions and saves a PNG through the
    native Metal renderer. *)
