(** Deterministic Bézier and Catmull–Rom samples for planar and spatial curves. *)

val quadratic2 : ?cancel:Cancel.t -> resolution:int ->
  from_:Prismel_math.Vec2.t -> control:Prismel_math.Vec2.t ->
  to_:Prismel_math.Vec2.t -> unit ->
  (Prismel_math.Vec2.t list, Error.t) result
val cubic2 : ?cancel:Cancel.t -> resolution:int ->
  from_:Prismel_math.Vec2.t -> control1:Prismel_math.Vec2.t ->
  control2:Prismel_math.Vec2.t -> to_:Prismel_math.Vec2.t -> unit ->
  (Prismel_math.Vec2.t list, Error.t) result
val catmull_rom2 : ?cancel:Cancel.t -> ?closed:bool -> ?tension:float ->
  resolution:int -> Prismel_math.Vec2.t list ->
  (Prismel_math.Vec2.t list, Error.t) result

val quadratic3 : ?cancel:Cancel.t -> resolution:int ->
  from_:Prismel_math.Vec3.t -> control:Prismel_math.Vec3.t ->
  to_:Prismel_math.Vec3.t -> unit ->
  (Prismel_math.Vec3.t list, Error.t) result
val cubic3 : ?cancel:Cancel.t -> resolution:int ->
  from_:Prismel_math.Vec3.t -> control1:Prismel_math.Vec3.t ->
  control2:Prismel_math.Vec3.t -> to_:Prismel_math.Vec3.t -> unit ->
  (Prismel_math.Vec3.t list, Error.t) result
val catmull_rom3 : ?cancel:Cancel.t -> ?closed:bool -> ?tension:float ->
  resolution:int -> Prismel_math.Vec3.t list ->
  (Prismel_math.Vec3.t list, Error.t) result
