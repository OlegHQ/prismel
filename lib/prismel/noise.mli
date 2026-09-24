(** Seeded coherent gradient noise, safe to share between domains. *)

type t

val create : int -> t
val sample1 : t -> float -> float
val sample2 : t -> x:float -> y:float -> float
val sample3 : t -> x:float -> y:float -> z:float -> float
(** Samples are approximately in the range 0..1. *)

val fbm1 :
  ?octaves:int -> ?lacunarity:float -> ?gain:float -> t -> float -> float
val fbm2 :
  ?octaves:int ->
  ?lacunarity:float ->
  ?gain:float ->
  t -> x:float -> y:float -> float
val fbm3 :
  ?octaves:int ->
  ?lacunarity:float ->
  ?gain:float ->
  t -> x:float -> y:float -> z:float -> float
(** Fractal Brownian motion composed from multiple noise frequencies. *)

module Private : sig
  type fbm3_scratch
  val create_fbm3_scratch : unit -> fbm3_scratch
  val fbm3_with_scratch :
    fbm3_scratch -> t -> octaves:int -> lacunarity:float -> gain:float ->
    x:float -> y:float -> z:float -> float
  (** Allocation-free fractal sample for an already validated octave profile.
      Scratch is caller-owned and must not be shared concurrently. Non-finite
      intermediate coordinates return [nan]. *)

  val sample2_into :
    t -> first:int -> last:int -> frequency:float ->
    x:float array -> y:float array -> output:float array -> unit
  (** Fill the half-open range in [output] from packed coordinate planes.
      Arrays are borrowed, ranges must be in bounds, and disjoint ranges may
      be called concurrently with the same immutable noise value. *)
end
