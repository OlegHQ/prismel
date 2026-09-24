(** Reusable camera and render panels for 3D and 2D sketches.

    [H] hides every PXUI element and overlay; [C] shows the UI and toggles the
    Camera section. Sliders read the camera every frame, so the panel never
    writes values back. *)

module Camera_control : sig
  type t
  type render_request = { filename : string; factor : int }

  val create : ?prefix:string -> unit -> t

  val shortcuts : ?text_focus:bool -> t -> Prismel.Frame.t -> t
  (** Apply [H]/[C] unless [text_focus]. *)

  val widgets :
    t -> Ui.t -> camera:Prismel.Easy_camera.t ->
    t * Prismel.Easy_camera.t * render_request list
  (** Camera (FOV, distance, clipping, inertia, reset) and Render (output
      name, save) sections, inside the current panel. *)

  val navigate :
    ?control_area:int * int * int * int -> t -> Prismel.Easy_camera.t ->
    Prismel.Frame.t -> Prismel.Easy_camera.t
  (** Orbit, pan (middle/right drag), zoom, and Space translation inside
      [control_area]. *)

  val panel :
    ?x:float -> ?y:float -> ?width:float -> t -> Ui.t ->
    camera:Prismel.Easy_camera.t -> Prismel.Frame.t ->
    t * Prismel.Easy_camera.t * render_request list
  (** Shortcuts, a panel fitted to the frame height, and navigation in the
      larger area beside it. Call inside [Ui.frame]. *)

  val ui_visible : t -> bool
  val overlay : t -> Prismel.Scene.t -> Prismel.Scene.t
  val save :
    ?background:Prismel.Color.t -> render_request -> frame:Prismel.Frame.t ->
    camera:Prismel.Easy_camera.t -> Prismel.Scene3.t -> (unit, string) result
end

module Camera2_control : sig
  type t
  type render_request = { filename : string; factor : int }

  val create : ?prefix:string -> unit -> t
  val shortcuts : ?text_focus:bool -> t -> Prismel.Frame.t -> t
  val widgets :
    t -> Ui.t -> camera:Prismel.Easy_camera2.t ->
    t * Prismel.Easy_camera2.t * render_request list
  (** Center, zoom, rotation, inertia, and reset, plus the Render section. *)

  val navigate :
    ?control_area:int * int * int * int -> ?viewport:int * int * int * int ->
    t -> Prismel.Easy_camera2.t -> Prismel.Frame.t -> Prismel.Easy_camera2.t

  val panel :
    ?x:float -> ?y:float -> ?width:float -> ?viewport:int * int * int * int ->
    t -> Ui.t -> camera:Prismel.Easy_camera2.t -> Prismel.Frame.t ->
    t * Prismel.Easy_camera2.t * render_request list

  val ui_visible : t -> bool
  val overlay : t -> Prismel.Scene.t -> Prismel.Scene.t
  val save :
    ?background:Prismel.Color.t -> render_request -> frame:Prismel.Frame.t ->
    camera:Prismel.Easy_camera2.t -> Prismel.Scene.t -> (unit, string) result
end
