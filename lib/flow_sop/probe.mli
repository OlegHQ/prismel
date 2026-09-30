(** Probes and footers (plan W5): what a recording evaluation
    ({!Flow.Eval.static} [~record:true]) saw at each path, per iteration tuple,
    and the text and numbers a node footer, the iteration counts and the
    inspector's per-iteration list show.  No drawing here.

    A record is keyed by [(path, iteration tuple)]; a node inside [c] zones
    ([for], [fold], [scan], [sum], [fn]; not [let*]) has a tuple of length
    [c].  [probes] below is the probed index of each enclosing zone, outermost
    first, so the value at the probe is the record with exactly that tuple.
    Geometry is never stored: a [Geo] value shows the counts the cook reported
    for its plan node ({!make} [~geometry]). *)

type path = Flow.Workspace.path

type geometry = { prims : int; groups : string list; data_id : int }

type summary = Value of Flow.Eval.value | Geometry of geometry

type t

val make :
  ?time:float -> ?geometry:(int -> geometry option) -> ?dynamic:(path -> int option) ->
  Flow.Eval.t -> t
(** [time] forces live (residual) values on lookup; [geometry] maps a plan
    node id to its cooked counts; [dynamic] gives the element count a loop over
    geometry ran over in the last cook (plan W8): {!counts} reports it, and a
    node inside such a loop reads its one template record at every element. *)

val same_eval : t -> t -> bool
(** Both come from one evaluation (only the time or the geometry counts may
    differ), so their iteration counts are equal. *)

val plan_node : t -> path -> probes:int list -> int option
(** The plan node ({!Flow.Eval.node} id) of a geometry value at the probe. *)

val records : t -> path -> (int list * summary) array
(** Every record of a path in evaluation order (at most 4,096). *)

val chains : Projection.scope -> (path, path list) Hashtbl.t
(** The enclosing iterating zones of every node below the scope, outermost
    first ([let*] zones do not iterate and are left out). *)

val counts : t -> Projection.scope -> probe:(path -> int) -> (path * int) list
(** Iterations (or calls) each zone ran under the probes of the zones around
    it: the records of its first loop name or parameter with the outer
    tuple.  A zone with no record is missing. *)

type footer = {
  value : string;  (** at the probe; its type when never recorded, [not run here] in a zone it skipped *)
  spark : (float array * int) option;  (** numbers or flags across the innermost zone, and the probed index *)
  branch : string option;  (** [then a · else b] for an [if] on a name *)
  kept : string option;  (** [kept a of b] for a [filter] *)
  runs : int option;  (** [×n], in a zone, when the value changes *)
  invariant : bool;  (** [↥ same each time]: the checker says it can leave the loop *)
  live : bool;  (** depends on [t] *)
}

val footer : t -> Projection.node -> probes:int list -> footer

val text : footer -> string
(** The footer as one line, parts joined by [ · ] ([↥], [◷ t] spelled as
    drawn: [↑ same each time], [t]). *)

val readouts : t -> Projection.node -> probes:int list -> (string * string) list
(** The inspector's rows: [value] (or [value at probe] inside a zone) and
    [cook] ([live, recooks every frame] or [cached]). *)

val iterations : t -> Projection.node -> probes:int list -> string array
(** {!describe} of {!series}: the inspector's list of every iteration. *)

val geometry_targets : t -> Projection.scope -> probe:(path -> int) -> int list
(** The plan nodes of every geometry node of the scope at its probes: what a
    footer wants the cook to count. *)
