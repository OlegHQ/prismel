(** Environment-owned cache. It retains one network plan and one resolution,
    bounded by that network's live drives. Call outside
    [Ui.frame], before submitting a cook; document literals remain untouched. *)
type t
type resolved = private {
  geometry : Sop.Edit_graph.t;
  applied : Flow.Port_type.value Port.Map.t;
  applied_text : string Port.Map.t;
      (** live text and list parameters as applied (a list of vec3 is
          {!Curve.encode}d), so an unchanged one is not applied again *)
  time_dependent : bool;
}

val create : ?state:Flow.Eval.state -> unit -> t
val reset : ?host_state:bool -> t -> unit
(** Clear cached resolution and fold values for a fresh playback. *)

val resolve : ?live:Frame_input.t -> t -> time:float -> Network.t -> (resolved, Flow.Diagnostic.t) result
(** Evaluate the live drives at [time] through prepared Flow IR programs; only changed SOP
    ports are applied while the literal graph is unchanged. Static networks
    reuse their successful or failed result without recomputation. *)
