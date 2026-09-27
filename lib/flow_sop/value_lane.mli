(** Environment-owned cache. It retains one network plan and one resolution,
    bounded by that network's reachable value nodes and drives. Call outside
    [Ui.frame], before submitting a cook; document literals remain untouched. *)
type t
type resolved = private {
  geometry : Procedural.Edit_graph.t;
  applied : Flow.Port_type.value Port.Map.t;
  outputs : Flow.Port_type.value Port.Map.t;
  time_dependent : bool;
}

val create : unit -> t
val reset : t -> unit
val resolve : t -> time:float -> Network.t -> (resolved, Flow.Diagnostic.t) result
(** Memoize reachable value outputs for this resolution; only changed SOP
    ports are applied while the literal graph is unchanged. Static networks
    reuse their successful or failed result without recomputation. *)
