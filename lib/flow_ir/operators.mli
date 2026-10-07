(** Immutable value declarations that need the math layer. Hosts pass [all]
    in their workspace-owned operator list; [flow] retains no upward dependency. *)
val noise3 : Flow.Op.t
val all : Flow.Op.t list
