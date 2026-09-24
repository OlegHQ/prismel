(** Immutable 2D pan/zoom camera for sketch viewports.

    World coordinates use the same axes as [Scene]. Middle/right drag pans;
    [translation_key] plus left drag also pans. Vertical wheel/trackpad motion
    zooms around the pointer, while horizontal scrolling is ignored. *)

type t

val create :
  ?center:Vec2.t ->
  ?zoom:float ->
  ?rotation:float ->
  ?enabled:bool ->
  ?viewport:(int * int * int * int) ->
  ?control_area:(int * int * int * int) ->
  ?inertia:bool ->
  ?drag_coefficient:float ->
  ?pan_sensitivity:float ->
  ?zoom_sensitivity:float ->
  ?translation_key:Input.key ->
  unit ->
  t

val update : t -> Frame.t -> t
(** Captured drags continue outside the control area. Double-clicking a pan
    button resets the initial center, zoom, and rotation. Focus loss or pointer
    cancellation safely releases capture. *)

val center : t -> Vec2.t
val zoom : t -> float
val rotation : t -> float
val enabled : t -> bool
val viewport : t -> (int * int * int * int) option
val control_area : t -> (int * int * int * int) option
val inertia : t -> bool
val drag_coefficient : t -> float
val pan_sensitivity : t -> float
val zoom_sensitivity : t -> float
val translation_key : t -> Input.key option

val with_center : Vec2.t -> t -> t
val with_zoom : float -> t -> t
val with_rotation : float -> t -> t
val set_enabled : bool -> t -> t
val with_viewport : (int * int * int * int) option -> t -> t
val with_control_area : (int * int * int * int) option -> t -> t
val with_inertia : bool -> t -> t
val with_drag_coefficient : float -> t -> t
val with_pan_sensitivity : float -> t -> t
val with_zoom_sensitivity : float -> t -> t
val with_translation_key : Input.key option -> t -> t
val reset : t -> t

val world_to_screen :
  viewport:(int * int * int * int) -> t -> Vec2.t -> Vec2.t
val screen_to_world :
  viewport:(int * int * int * int) -> t -> Vec2.t -> Vec2.t

val scene :
  ?viewport:(int * int * int * int) ->
  ?pixel_scale:float ->
  t ->
  Scene.t ->
  Scene.t
(** Apply clipping and the camera transform to a world scene. [pixel_scale]
    preserves framing when rendering the same logical viewport at a larger
    physical output size. *)
