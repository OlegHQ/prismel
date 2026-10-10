(** Inspectable SOP catalog nodes. Every catalog SOP is declared once in
    [Sop] with its parameter metadata; this library registers the
    declarations and generates the one deterministic manifest of editor
    factories. Graphs are built from Rays Lisp or through these factories
    ([Sop.Edit_graph.instantiate]). *)

(** Deterministic PPX-generated manifest for the interactive SOP network
    editor. A module marked [[@@sop.register]] contributes its local [factory]
    in source order; there is no second hand-maintained registry. Factories
    declare exact input arity and build ordinary immutable nodes, while the
    editor document remains the topology authority. *)
module Editor : sig
  val factories : Sop.Edit_graph.factory list
end
