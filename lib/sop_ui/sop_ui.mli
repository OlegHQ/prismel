(** PXUI adapter for node-owned procedural parameter metadata.

    This is the sole SOP inspector path: Procedural nodes own schemas and
    immutable values, this leaf library builds kit widgets from them every
    frame, and edits go back through [Procedural.Node.apply_parameters] or
    [Procedural.Graph.apply_parameters]. Widgets read the node's current
    values each frame, so nothing is synchronized back. *)

module Node_inspector : sig
  type t

  val create : ?prefix:string -> Procedural.Node.t -> t
  val node_id : t -> int

  val widgets :
    ?expanded:string list -> t -> Pxui.Ui.t -> node:Procedural.Node.t ->
    (Procedural.Node.t * Procedural.Parameter.effects, string) result
  (** Build the node's label and parameter rows inside the current panel.
      Folders become accordions, initially open when their path (joined with
      ["/"]) is in [expanded]. Edits made this frame are applied and
      normalized; without edits the node is returned unchanged with no
      effects. A node with another id renders an explanatory label. *)

  val graph_widgets :
    ?expanded:string list -> t -> Pxui.Ui.t -> graph:Procedural.Graph.t ->
    (Procedural.Graph.t * Procedural.Parameter.effects, string) result
  (** [widgets] for the node with this inspector's id inside [graph]. *)

  val reset :
    t -> graph:Procedural.Graph.t ->
    (Procedural.Graph.t * Procedural.Parameter.effects, string) result
  (** Restore every exposed parameter to its default. *)
end
