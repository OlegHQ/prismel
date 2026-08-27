type t
type session

type error =
  | Invalid_frame of string
  | Sdl of Sdl3.error
  | Destroyed

type frame = {
  rgba : bytes;
  pitch : int;
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
}

type stats = {
  live_presenters : int;
  live_textures : int;
  texture_recreations : int;
  presented_frames : int;
}

val create : Sdl3.Window.t -> (t, error) result
val present : t -> frame -> (unit, error) result
val copy_rgba : t -> (bytes, error) result
val stats : t -> stats
val destroy : t -> (unit, error) result

val create_session : logical_width:int -> logical_height:int ->
  (session, error) result
val resize_session : session -> logical_width:int -> logical_height:int ->
  (unit, error) result
val present_session : session -> frame -> (unit, error) result
val copy_session_rgba : session -> (bytes, error) result
val destroy_session : session -> (unit, error) result
