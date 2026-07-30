(** Backend-oriented escape hatch.

    Normal sketches should use [Sketch], [Frame], [Scene], [Canvas], [Assets],
    and [Audio]. These modules expose mutable renderer/window lifecycle state
    and must remain on the initial domain. *)

module App = App
module Backend = Backend
module Graphics = Graphics
module Window = Window
