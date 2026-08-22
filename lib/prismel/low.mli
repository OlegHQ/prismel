(** Backend-oriented escape hatch.

    Normal sketches should use [Sketch], [Frame], [Scene], [Canvas], [Assets],
    and [Audio]. These modules expose mutable renderer/window lifecycle state
    and must remain on the initial domain. *)

module App : module type of App
module Backend : module type of Backend
module Graphics : module type of Graphics
module Window : module type of Window
