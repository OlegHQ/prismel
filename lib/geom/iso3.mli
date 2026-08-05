(** Scalar fields and deterministic isosurface extraction. *)

open Prismel

type metaball = private {
  center : Vec3.t;
  radius : float;
  strength : float;
}

type sample = float array
(** Borrowed packed XYZ sample used by {!Field.custom}. The array always has
    length three and is reused on its current domain; callbacks must not retain
    or mutate it. Read X/Y/Z at indices 0/1/2. *)

module Field : sig
  type t

  val constant : float -> t
  val sphere : center:Vec3.t -> radius:float -> t
  val gyroid : ?scale:float -> unit -> t
  val metaballs : metaball list -> t
  val custom : (sample -> float) -> t
end
(** Dense scalar-field descriptions. Built-in fields are evaluated directly
    without allocating a point or boxing callback coordinates per sample.
    [custom] is the allocation-lean escape hatch for arbitrary fields. *)

val metaball :
  ?strength:float -> center:Vec3.t -> radius:float -> unit -> metaball

val metaballs : metaball list -> Vec3.t -> float
(** Inverse-square metaball field. An isovalue of one is a useful default. *)

val sphere : center:Vec3.t -> radius:float -> Vec3.t -> float
(** Signed sphere field, positive inside. *)

val gyroid : ?scale:float -> Vec3.t -> float
(** Triply-periodic gyroid field. Zero is the canonical isovalue. *)

val extract :
  ?smooth:bool ->
  resolution:int * int * int ->
  min:Vec3.t ->
  max:Vec3.t ->
  iso:float ->
  field:(Vec3.t -> float) ->
  unit ->
  (Mesh.t, string) result
(** Extract an isosurface with a six-tetrahedra decomposition per grid cell.
    Values greater than or equal to [iso] are inside. Triangle normals point
    toward decreasing field values. [resolution] specifies cell counts.
    Sampling and gradient evaluation stream through XY planes, so auxiliary
    field memory is O(x-resolution * y-resolution), independent of Z. The
    field must be pure: it is sampled twice to allocate the exact output once. *)

val extract_dense :
  ?smooth:bool ->
  resolution:int * int * int ->
  min:Vec3.t ->
  max:Vec3.t ->
  iso:float ->
  field:Field.t ->
  unit ->
  (Mesh.t, string) result
(** High-density variant of {!extract}. Built-in {!Field} values avoid a
    callback allocation at every sample; custom fields reuse one packed XYZ
    sample per domain. The field has the same purity requirement. *)
