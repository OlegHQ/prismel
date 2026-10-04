(** Terminal render representation for disconnected SOP pieces.

    The source remains one immutable cooked RDK geometry. Piece membership and
    centers are compiled once into compact arrays, after which explosion
    controls only rebuild render positions; they never recook topology. This
    is the Rays counterpart of Connectivity -> Pack by Name -> Transform
    Pieces/Exploded View, without inventing editable packed primitives inside
    [Rdk.Geometry.t]. *)

type t

val of_geometry :
  ?cancel:Rdk.Cancel.t ->
  ?center:Rays.Vec3.t ->
  piece_attribute:string ->
  Rdk.Geometry.t ->
  (t, string) result

val piece_count : t -> int

val mesh :
  ?noise_amount:float ->
  ?noise_frequency:float ->
  ?noise_seed:int ->
  amount:float ->
  t ->
  Rays.Mesh.t
(** Translate every piece away from [center] by [amount]. Optional deterministic
    fBm multiplies each piece translation without changing its rigid shape. *)

type explosion = {
  amount : float;
  scale : Rays.Vec3.t;
  piece_attribute : string;
  noise_amount : float;
  noise_frequency : float;
  noise_seed : int;
}

val explosion : Procedural.Node.t -> explosion option
val mesh_for_node : Procedural.Node.t -> t -> Rays.Mesh.t
