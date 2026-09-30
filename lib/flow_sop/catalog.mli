(** Adapt the one generated SOP factory registry to the context-generic
    Flow checker/printer descriptor. *)

type descriptor = {
  qualified : string;
  key : string;
  operation : string;
  label : string;
  category : string list;
  slots : (string * Procedural.Edit_graph.input_requirement) list;
  fields : Param.field_view list;
}
(** One catalog kind: a SOP factory, or a scene, world or settings kind that
    the editor document generates from its own schemas
    ([Editor_document.Contexts]).  The namespace of [qualified] gives the
    context. *)

val descriptor : Procedural.Edit_graph.factory -> descriptor
(** The [sop/] kind of a factory. *)

val of_factories :
  version:int -> ?extra:descriptor list -> Procedural.Edit_graph.factory list ->
  (Flow.Check.catalog, Flow.Diagnostic.t) result
