(** Neutral cooked-image generators. Lisp declarations derive their fields
    from these parameter schemas, as geometry SOPs do. *)
val noise_factory : Edit_graph.factory
val noise : ?width:int -> ?height:int -> ?frequency:float -> ?seed:int -> unit -> Node.t
