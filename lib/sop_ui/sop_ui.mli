(** PXUI adapter for node-owned procedural parameter metadata.

    This is the sole SOP inspector path: Procedural nodes own schemas and
    immutable values, this leaf library owns widget adaptation, and edits go
    back through [Procedural.Graph.apply_parameters]. *)

module Node_inspector : sig
  type t

  val create : ?prefix:string -> Procedural.Node.t -> t
  val node_id : t -> int

  val append :
    ?expanded:string list ->
    t ->
    graph:Procedural.Graph.t ->
    Pxui.t ->
    Pxui.t
  val append_node :
    ?expanded:string list -> t -> node:Procedural.Node.t -> Pxui.t -> Pxui.t
(** Append native widgets for the selected node's concrete metadata. Missing
    or unparameterized nodes render a short explanatory label. *)

  val update :
    t ->
    graph:Procedural.Graph.t ->
    ui:Pxui.t ->
    Pxui.change list ->
    (Procedural.Graph.t * Pxui.t * Procedural.Parameter.effects, string) result
  val update_node :
    t ->
    node:Procedural.Node.t ->
    ui:Pxui.t ->
    Pxui.change list ->
    (Procedural.Node.t * Pxui.t * Procedural.Parameter.effects, string) result
(** Apply relevant changes, preserving graph IDs and synchronizing normalized
    values back to their widgets. *)

  val reset :
    t ->
    graph:Procedural.Graph.t ->
    ui:Pxui.t ->
    (Procedural.Graph.t * Pxui.t * Procedural.Parameter.effects, string) result
end
