type t
type color_space=Linear|Srgb
type address=Clamp|Repeat|Mirror
type filter=Nearest|Bilinear|Trilinear
type error=Invalid_size|Invalid_capacity|Capacity_exceeded|Invalid_lod of float|Invalid_coordinate
val create : color_space:color_space -> hard_capacity:int -> Surface.t -> (t,error) result
val create_levels : color_space:color_space -> hard_capacity:int -> Surface.t array -> (t,error) result
val width : t -> int
val height : t -> int
val levels : t -> int
val storage_bytes : t -> int
val level : t -> int -> (Surface.t,error) result
val sample : t -> address_u:address -> address_v:address -> filter:filter -> u:float -> v:float -> lod:float -> (int32,error) result
module Private : sig
  (** Borrow already validated immutable mip surfaces for synchronous raster
      sampling. The caller retains every surface through the sampling call. *)
  val create_levels_borrowed : color_space:color_space -> Surface.t array ->
    (t,error) result
  (** Allocation-free sampling for audited raster hot paths. [coordinates]
      is caller-owned reusable storage of at least six floats, containing
      finite [u], [v], and [lod] at indices 0, 1, and 2; indices 3 through 5
      are scratch and may be overwritten. [lod] must be non-negative. *)
  val sample_int_unchecked : t -> address_u:address -> address_v:address ->
    filter:filter -> Float.Array.t -> int
  (* Integer texel lookup with address-mode application. The caller must prove
     that [level] names an existing mip level. *)
  val texel_int_unchecked : t -> level:int -> address_u:address ->
    address_v:address -> x:int -> y:int -> int
end
