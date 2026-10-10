(** The [:source_attribute] / [:source_base] of a lowered [sop/merge]. *)

val node : tag:string -> attribute:string -> base:int -> source_base:int ->
  Sop.Node.t list -> Sop.Node.t
(** [node ~tag ~attribute ~base ~source_base inputs] merges [inputs] with the lowering's
    provenance attribute [tag] ([base + input index]) and adds the primitive integer attribute
    [attribute] ([source_base + input index]), as [Rdk.Mesh_merge] tags it. *)
