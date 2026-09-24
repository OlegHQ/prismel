(** Private exact-axis shell winding classification for a Weiler complex. *)

type t

val build :
  ?cancel:Cancel.t -> ?axis_fast_path:bool -> ?component_index:bool ->
  ?track_left:bool -> ?track_right:bool ->
  Boolean_complex.t -> Boolean_weiler.t ->
  (t, Error.t) result
(** [axis_fast_path=false] forces the exact positive-infinitesimal classifier.
    It is an internal differential-test/benchmark switch; production keeps the
    six cheaper exact axis attempts.

    [component_index=false] retains an exhaustive component-AABB scan solely as
    a differential-test oracle for the packed component index.

    An operand whose [track_*] flag is false remains part of the arrangement,
    but contributes zero to volumetric winding. This is the exact surface
    treatment used by the Boolean product layer. *)

val shell_count : t -> int
val left_winding : t -> int -> int
val right_winding : t -> int -> int
(** Signed generalized winding values. Non-zero means inside for the default
    solid interpretation; signs preserve source orientation diagnostics. *)

val symbolic_seed_count : t -> int
(** Number of disconnected shell components whose six exact axis rays were
    boundary-degenerate and therefore used the exact positive-infinitesimal
    classifier. Exposed only through the private Boolean kernel for coverage
    and phase diagnostics. *)

module Private : sig
  val weiler : t -> Boolean_weiler.t
end
