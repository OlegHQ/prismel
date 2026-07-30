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
