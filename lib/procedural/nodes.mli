(** Editor factories of the SOP nodes declared once in this library: each
    [parameters] record derives its schema, this factory and the typed [Sop]
    constructor of the same operation, so the three never drift. *)
module Group_non_planar : sig val factory : Edit_graph.factory end
module Group_backface : sig val factory : Edit_graph.factory end
module Group_unshared : sig val factory : Edit_graph.factory end
