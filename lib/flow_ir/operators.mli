(** Immutable value declarations that need the math layer. Hosts pass [all]
    in their workspace-owned operator list; [flow] retains no upward dependency. *)
val noise3 : Flow.Op.t
val noise_table : int -> Rays_math.Noise.t
val drawing_color : ('f, 'r) Flow.Value.t -> Rays_math.Color.t
val all : Flow.Op.t list
