(** Reusable camera and render widgets for 3D and 2D sketches.

    Hosts use {!Camera_control.ui_visible} to decide whether to build widgets;
    {!Camera_control.toggle_ui} and {!Camera_control.open_camera} update that
    visibility. Sliders read the camera every frame, so widgets never write
    values back. *)

module Camera_control : sig
  type t
  type render_request = { filename : string }

  val create : ?prefix:string -> unit -> t

  val toggle_ui : t -> t
  val open_camera : t -> t

  val widgets :
    t -> Ui.t -> camera:Prismel.Easy_camera.t ->
    t * Prismel.Easy_camera.t * render_request list
  (** Camera (FOV, distance, clipping, inertia, reset) and Render (output
      name, save) sections, inside the current panel. *)

  val navigate :
    ?control_area:int * int * int * int -> t -> Prismel.Easy_camera.t ->
    Prismel.Frame.t -> Prismel.Easy_camera.t
  (** Orbit, pan (middle/right drag), and zoom inside [control_area]. *)

  val ui_visible : t -> bool
  val save : render_request -> (unit, string) result
  (** Save the full native framebuffer to [request.filename]. *)

end

module Camera2_control : sig
  type t
  type render_request = { filename : string }

  val create : ?prefix:string -> unit -> t
  val toggle_ui : t -> t
  val open_camera : t -> t
  val widgets :
    t -> Ui.t -> camera:Prismel.Easy_camera2.t ->
    t * Prismel.Easy_camera2.t * render_request list
  (** Center, zoom, rotation, inertia, and reset, plus the Render section. *)

  val navigate :
    ?control_area:int * int * int * int -> ?viewport:int * int * int * int ->
    t -> Prismel.Easy_camera2.t -> Prismel.Frame.t -> Prismel.Easy_camera2.t

  val ui_visible : t -> bool
  val save : render_request -> (unit, string) result
end
