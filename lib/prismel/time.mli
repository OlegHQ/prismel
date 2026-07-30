(** Time and Animation Management Module *)

(** {1 Basic Time Functions} *)

(** Initialize the timing system. Called automatically when the module is loaded. *)
val init : unit -> unit

(** Get current time in seconds since program start *)
val now : unit -> float

(** Get elapsed time since program start (alias for [now]) *)
val elapsed : unit -> float

(** Get the delta time from the last frame in seconds *)
val get_delta_time : unit -> float

(** Update timing - should be called each frame by the main loop *)
val update : unit -> unit

(** {1 Frame Rate Control} *)

(** Get current frame rate (FPS) *)
val get_frame_rate : unit -> float

(** Set target frame rate. Pass a positive integer to cap FPS, or 0/negative to disable capping *)
val set_frame_rate : int -> unit

(** Enable or disable vertical sync with the monitor *)
val set_vsync : bool -> unit

(** Frame rate limiting - call after rendering to enforce the target FPS *)
val limit_frame_rate : unit -> unit

(** {1 Time Scaling} *)

(** Set time scale for slow motion or fast forward. 
    - 1.0 = normal speed
    - 0.5 = half speed (slow motion)
    - 2.0 = double speed (fast forward)
    - 0.0 = paused *)
val set_time_scale : float -> unit

(** Get current time scale *)
val get_time_scale : unit -> float

(** {1 Animation Helpers} *)

(** Calculate elapsed fraction between start_time and duration.
    Returns a value between 0.0 and 1.0 representing progress.
    [elapsed_fraction start_time duration] *)
val elapsed_fraction : float -> float -> float

(** Smoothstep function for smooth ease in-out interpolation *)
val smoothstep : float -> float

(** {1 Easing Functions} *)

(** Convenience functions for common easing *)
val ease_in : float -> float
val ease_out : float -> float  
val ease_in_out : float -> float

(** Comprehensive easing functions module *)
module Easing : sig
  (** Linear interpolation (no easing) *)
  val linear : float -> float
  
  (** Quadratic easing *)
  val ease_in_quad : float -> float
  val ease_out_quad : float -> float
  val ease_in_out_quad : float -> float
  
  (** Cubic easing *)
  val ease_in_cubic : float -> float
  val ease_out_cubic : float -> float
  val ease_in_out_cubic : float -> float
  
  (** Quartic easing *)
  val ease_in_quart : float -> float
  val ease_out_quart : float -> float
  val ease_in_out_quart : float -> float
  
  (** Quintic easing *)
  val ease_in_quint : float -> float
  val ease_out_quint : float -> float
  val ease_in_out_quint : float -> float
  
  (** Sinusoidal easing *)
  val ease_in_sine : float -> float
  val ease_out_sine : float -> float
  val ease_in_out_sine : float -> float
  
  (** Exponential easing *)
  val ease_in_expo : float -> float
  val ease_out_expo : float -> float
  val ease_in_out_expo : float -> float
  
  (** Circular easing *)
  val ease_in_circ : float -> float
  val ease_out_circ : float -> float
  val ease_in_out_circ : float -> float
  
  (** Back easing (overshoots) *)
  val ease_in_back : float -> float
  val ease_out_back : float -> float
  val ease_in_out_back : float -> float
  
  (** Elastic easing (bouncy) *)
  val ease_in_elastic : float -> float
  val ease_out_elastic : float -> float
  val ease_in_out_elastic : float -> float
  
  (** Bounce easing *)
  val ease_in_bounce : float -> float
  val ease_out_bounce : float -> float
  val ease_in_out_bounce : float -> float
end

(** {1 Animation Scheduler} *)

(** Simple event scheduling for animations and timed callbacks *)
module Scheduler : sig
  (** Schedule a function to be called after a delay in seconds *)
  val delay_call : float -> (unit -> unit) -> unit
  
  (** Schedule a function to be called repeatedly at regular intervals *)
  val every : float -> (unit -> unit) -> unit
  
  (** Update the scheduler - should be called each frame to execute ready events *)
  val update : unit -> unit
end 
