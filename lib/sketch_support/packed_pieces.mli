(** Terminal render representation for disconnected SOP pieces.

    The source remains one immutable cooked PDK geometry. Piece membership and
    centers are compiled once into compact arrays, after which explosion
    controls only rebuild render positions; they never recook topology. This
    is the Prismel counterpart of Connectivity -> Pack by Name -> Transform
    Pieces/Exploded View, without inventing editable packed primitives inside
    [Pdk.Geometry.t]. *)

type t

val of_geometry :
  ?cancel:Pdk.Cancel.t ->
  ?center:Prismel.Vec3.t ->
  piece_attribute:string ->
  Pdk.Geometry.t ->
  (t, string) result

val piece_count : t -> int
val vertex_count : t -> int
val payload_bytes : t -> int

val mesh :
  ?noise_amount:float ->
  ?noise_frequency:float ->
  ?noise_seed:int ->
  amount:float ->
  t ->
  Prismel.Mesh.t
(** Translate every piece away from [center] by [amount]. Optional deterministic
    fBm multiplies each piece translation without changing its rigid shape. *)

type explosion = {
  amount : float;
  scale : Prismel.Vec3.t;
  piece_attribute : string;
  noise_amount : float;
  noise_frequency : float;
  noise_seed : int;
}

val explosion : Procedural.Node.t -> explosion option
val mesh_for_node : Procedural.Node.t -> t -> Prismel.Mesh.t
