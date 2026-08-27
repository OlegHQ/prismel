(** Explicit still-image rendering for pure 3D scenes. *)

val save_png :
  width:int ->
  height:int ->
  ?background:Color.t ->
  camera:Camera.t ->
  Scene3.t ->
  string ->
  (unit, string) result
(** Render at the requested pixel dimensions and save a PNG. Native supported
    scenes use the GPU; headless and unsupported native scenes use the
    deterministic software renderer. *)
