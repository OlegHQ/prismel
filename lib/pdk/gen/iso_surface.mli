(** Streaming deterministic isosurface extraction into packed PDK geometry. *)

type metaball = private {
  center : Prismel_math.Vec3.t;
  radius : float;
  strength : float;
}

type sample = float array
(** Borrowed XYZ sample. Custom callbacks must not retain or mutate it. *)

module Field : sig
  type t
  val gyroid : ?scale:float -> unit -> t
  val custom : (sample -> float) -> t
end

val extract : ?cancel:Cancel.t -> ?smooth:bool ->
  resolution:int * int * int -> min:Prismel_math.Vec3.t ->
  max:Prismel_math.Vec3.t -> iso:float ->
  field:(Prismel_math.Vec3.t -> float) -> unit ->
  (Geometry.t, Error.t) result
val extract_dense : ?cancel:Cancel.t -> ?smooth:bool ->
  resolution:int * int * int -> min:Prismel_math.Vec3.t ->
  max:Prismel_math.Vec3.t -> iso:float -> field:Field.t -> unit ->
  (Geometry.t, Error.t) result

module Private : sig
end
