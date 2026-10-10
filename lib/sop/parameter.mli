(** Typed node parameters; the schema lives in the dependency-free [Param]
    library so editors and inspectors use it without the geometry stack. *)

include module type of struct include Param end
