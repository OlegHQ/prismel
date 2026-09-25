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
  val constant : float -> t
  val sphere : center:Prismel_math.Vec3.t -> radius:float -> t
  val gyroid : ?scale:float -> unit -> t
  val metaballs : metaball list -> t
  val custom : (sample -> float) -> t
end

val metaball : ?strength:float -> center:Prismel_math.Vec3.t -> radius:float ->
  unit -> metaball
val metaballs : metaball list -> Prismel_math.Vec3.t -> float
val sphere : center:Prismel_math.Vec3.t -> radius:float ->
  Prismel_math.Vec3.t -> float
val gyroid : ?scale:float -> Prismel_math.Vec3.t -> float

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
  (** The same extractor's owned triangle-soup planes, for renderer adapters
      that do not need to allocate an intermediate PDK topology. Positions
      and normals have equal lengths divisible by three. *)
  val extract_packed : ?cancel:Cancel.t -> ?smooth:bool ->
    resolution:int * int * int -> min:Prismel_math.Vec3.t ->
    max:Prismel_math.Vec3.t -> iso:float ->
    field:(Prismel_math.Vec3.t -> float) -> unit ->
    (Packed.Float3.t * Packed.Float3.t, Error.t) result
  val extract_dense_packed : ?cancel:Cancel.t -> ?smooth:bool ->
    resolution:int * int * int -> min:Prismel_math.Vec3.t ->
    max:Prismel_math.Vec3.t -> iso:float -> field:Field.t -> unit ->
    (Packed.Float3.t * Packed.Float3.t, Error.t) result
end
