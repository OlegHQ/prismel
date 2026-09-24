(** Reusable camera and render panels for 3D and 2D sketches.

    {!Camera_control.toggle_ui} hides every PXUI element and overlay;
    {!Camera_control.open_camera} shows the UI and toggles the Camera section.
    Hosts bind them to keys (Sketch_ui uses its leader). Sliders read the camera every frame, so the panel never
    writes values back. *)

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

  val panel :
    ?x:float -> ?y:float -> ?width:float -> t -> Ui.t ->
    camera:Prismel.Easy_camera.t -> Prismel.Frame.t ->
    t * Prismel.Easy_camera.t * render_request list
  (** A panel fitted to the frame height, and navigation in the
      larger area beside it. Call inside [Ui.frame]. *)

  val ui_visible : t -> bool
  val overlay : t -> Prismel.Scene.t -> Prismel.Scene.t
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

  val panel :
    ?x:float -> ?y:float -> ?width:float -> ?viewport:int * int * int * int ->
    t -> Ui.t -> camera:Prismel.Easy_camera2.t -> Prismel.Frame.t ->
    t * Prismel.Easy_camera2.t * render_request list

  val ui_visible : t -> bool
  val overlay : t -> Prismel.Scene.t -> Prismel.Scene.t
  val save : render_request -> (unit, string) result
end
