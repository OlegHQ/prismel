(** Deterministic still-image rendering for camera-controlled 2D scenes. *)

val save_png :
  logical_width:int ->
  logical_height:int ->
  factor:int ->
  ?background:Color.t ->
  camera:Easy_camera2.t ->
  Scene.t ->
  string ->
  (unit, string) result
(** Render the logical viewport at [factor] times its width and height while
    preserving camera framing. This explicit offscreen export uses Prismel's
    software canvas on every target; ordinary native sketch presentation
    remains on the configured accelerated SDL renderer. *)
