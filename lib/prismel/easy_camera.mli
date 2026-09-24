(** Functional pointer-controlled orbit camera inspired by openFrameworks'
    [ofEasyCam]. All positions and control areas use logical points. *)

type interaction = Orbit | Pan | Dolly
type binding = {
  button : Input.mouse_button;
  key : Input.key option;
  interaction : interaction;
}
type t

val create :
  ?target:Vec3.t ->
  ?distance:float ->
  ?azimuth:float ->
  ?elevation:float ->
  ?fov_y:float ->
  ?near:float ->
  ?far:float ->
  ?enabled:bool ->
  ?control_area:(int * int * int * int) ->
  ?inertia:bool ->
  ?drag_coefficient:float ->
  ?rotation_sensitivity:Vec2.t ->
  ?translation_sensitivity:Vec2.t ->
  ?dolly_sensitivity:float ->
  ?up_axis:Vec3.t ->
  ?relative_y_axis:bool ->
  ?middle_button_enabled:bool ->
  ?translation_key:Input.key ->
  ?auto_distance:bool ->
  unit ->
  t

val update : t -> Frame.t -> t
(** Consume the ordered pointer facts in one frame. Captured drags continue
    outside the control area. Double-clicking a configured button resets the
    original target, distance, and orientation. Vertical wheel/trackpad motion
    dollies and horizontal wheel/trackpad motion is ignored. The default drag
    bindings are left orbit and middle/right pan; [translation_key] plus a left
    drag also pans. *)

val camera : t -> Camera.t
val target : t -> Vec3.t
val distance : t -> float
val fov_y : t -> float
val near : t -> float
val far : t -> float
val enabled : t -> bool
val control_area : t -> (int * int * int * int) option
val inertia : t -> bool
val drag_coefficient : t -> float
val rotation_sensitivity : t -> Vec2.t
val translation_sensitivity : t -> Vec2.t
val dolly_sensitivity : t -> float
val up_axis : t -> Vec3.t
val relative_y_axis : t -> bool
val middle_button_enabled : t -> bool
val auto_distance : t -> bool
val interactions : t -> binding list

val with_target : Vec3.t -> t -> t
val of_view : eye:Vec3.t -> target:Vec3.t -> t -> t
(** Orbit to look from [eye] at [target] about the current up axis (elevation
    clamps just short of the poles). Lens, clipping, and input settings are
    kept; inertia stops. *)

val frame_bounds : min:Vec3.t -> max:Vec3.t -> t -> t
(** Target the box center at [radius / tan (fov_y / 2) * 1.2] (radius: half
    the box diagonal), keeping the viewing direction. *)

val with_distance : float -> t -> t
val with_fov_y : float -> t -> t
val with_clip : near:float -> far:float -> t -> t
val set_enabled : bool -> t -> t
val with_control_area : (int * int * int * int) option -> t -> t
val with_inertia : bool -> t -> t
val with_drag_coefficient : float -> t -> t
val with_rotation_sensitivity : Vec2.t -> t -> t
val with_translation_sensitivity : Vec2.t -> t -> t
val with_dolly_sensitivity : float -> t -> t
val with_up_axis : Vec3.t -> t -> t
val with_relative_y_axis : bool -> t -> t
val with_middle_button_enabled : bool -> t -> t
val with_translation_key : Input.key option -> t -> t
val with_auto_distance : bool -> t -> t

val add_interaction :
  ?key:Input.key -> button:Input.mouse_button -> interaction -> t -> t
val remove_interaction :
  ?key:Input.key -> button:Input.mouse_button -> t -> t
val clear_interactions : t -> t
val has_interaction :
  ?key:Input.key -> button:Input.mouse_button -> interaction -> t -> bool

val reset : t -> t

val fly : speed:float -> t -> Frame.t -> t * float
(** One frame of WASD fly navigation: held W/S, D/A, and Q/E move forward,
    right, and up at [speed] units per second (Shift four times faster);
    [Frame.mouse_delta] yaws about the up axis and pitches within 89 degrees;
    each wheel step scales the returned speed by 1.2. The result is an
    ordinary orbit camera, so orbiting resumes seamlessly. *)
