(** Packed profile revolution behind the typed [Ops.revolve] boundary. *)

type revolve_type = Revolve_closed | Revolve_open_arc

val run :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?revolve_type:revolve_type ->
  ?connectivity:Plane_generators.grid_connectivity ->
  ?start_angle:float -> ?end_angle:float ->
  ?reverse_cross_sections:bool -> ?caps:bool -> ?cap_group:string ->
  ?uv_attribute:string option -> divisions:int ->
  origin:Prismel_math.Vec3.t -> axis:Prismel_math.Vec3.t ->
  Geometry.t -> (Geometry.t, string) result
