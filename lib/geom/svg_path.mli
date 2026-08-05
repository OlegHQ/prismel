(** SVG path-data parsing and serialization. *)

open Prismel

val parse : string -> (Path.t, string) result
(** Parse absolute or relative M/L/H/V/C/S/Q/T/A/Z path commands. Elliptical
    arcs are converted to cubic Bezier segments. *)

val to_string : ?precision:int -> Path.t -> string
(** Serialize a Prismel path using absolute commands. *)
