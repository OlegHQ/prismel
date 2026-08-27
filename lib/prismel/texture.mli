(** Immutable CPU-readable textures for 3D mesh sampling. *)

type t
type filter = Nearest | Bilinear | Trilinear
type wrap = Clamp | Repeat | Mirror

val create : width:int -> height:int -> Color.t list -> (t, string) result
val create_exn : width:int -> height:int -> Color.t list -> t
val init : width:int -> height:int -> (x:int -> y:int -> Color.t) -> t
val load : string -> (t, string) result
val load_exn : string -> t

val width : t -> int
val height : t -> int
val size : t -> int * int
val pixels : t -> Color.t list
val pixel : t -> x:int -> y:int -> Color.t option
val generate_mipmaps : t -> t
val has_mipmaps : t -> bool
val mipmap_count : t -> int
val subsection :
  x:int ->
  y:int ->
  width:int ->
  height:int ->
  t ->
  (t, string) result
val subsection_exn :
  x:int -> y:int -> width:int -> height:int -> t -> t
(** Copy a rectangular pixel subsection into a new immutable texture. *)

val sample :
  ?filter:filter ->
  ?wrap_u:wrap ->
  ?wrap_v:wrap ->
  t ->
  u:float ->
  v:float ->
  Color.t
(** Sample normalized texture coordinates. [(0, 0)] is the upper-left texel. *)

val sample_lod :
  ?filter:filter ->
  ?wrap_u:wrap ->
  ?wrap_v:wrap ->
  t ->
  lod:float ->
  u:float ->
  v:float ->
  Color.t
(** Sample an explicit finite level of detail. [Trilinear] blends adjacent
    mip levels; other filters select the nearest level. *)

module Private : sig
  (* Zero-copy construction for fresh immutable pixel arrays. The supplied
      array becomes backing storage and must not be mutated afterward. *)
  val create_owned :
    width:int -> height:int -> Color.t array -> (t, string) result
  (* Allocation-free packed RGBA sampling for the software rasterizer. *)
  val sample_lod_packed :
    ?filter:filter ->
    ?wrap_u:wrap ->
    ?wrap_v:wrap ->
    t -> lod:float -> u:float -> v:float -> int
  val levels : t -> (int * int * Color.t array) array
end
