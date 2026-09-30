(** Environment-owned cache. It retains one network plan and one resolution,
    bounded by that network's live drives. Call outside
    [Ui.frame], before submitting a cook; document literals remain untouched. *)
type t
type resolved = private {
  geometry : Procedural.Edit_graph.t;
  applied : Flow.Port_type.value Port.Map.t;
  applied_text : string Port.Map.t;
      (** live text and list parameters as applied (a list of vec3 is
          {!Curve.encode}d), so an unchanged one is not applied again *)
  time_dependent : bool;
}

val create : unit -> t
val resolve : t -> time:float -> Network.t -> (resolved, Flow.Diagnostic.t) result
(** Evaluate the live drives at [time]; only changed SOP
    ports are applied while the literal graph is unchanged. Static networks
    reuse their successful or failed result without recomputation. *)
