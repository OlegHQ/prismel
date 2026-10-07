(** Probes and footers: what a recording evaluation
    ({!Flow.Eval.static} [~record:true]) saw at each path, per iteration tuple,
    and the text and numbers a node footer, the iteration counts and the
    inspector's per-iteration list show.  No drawing here.

    A record is keyed by [(path, iteration tuple)]; a node inside [c] zones
    ([for], [fold], [scan], [sum], [fn]; not [let*]) has a tuple of length
    [c].  [probes] below is the probed index of each enclosing zone, outermost
    first, so the value at the probe is the record with exactly that tuple.
    Geometry is never stored: a [Deferred (Geometry, id)] value shows the counts the cook reported
    for its plan node ({!make} [~geometry]). *)

type path = Flow.Workspace.path

type geometry = {
  points : int; prims : int; groups : string list; data_id : int;
  extent : (float * float * float) option;  (** the size of the bounding box, when there are points *)
  seconds : float option;  (** what the node itself took the last time it was really cooked (a cache hit keeps it) *)
}

type summary = Value of Flow.Eval.value | Geometry of geometry

type execution = {tier : string; group : path; seconds : float option}
(** Renderer-neutral host report. Only the owning card has a group duration;
    other fused cards name the same group and tier. *)

type t

val make :
  ?state:Flow.Eval.state -> ?live:Frame_input.t -> ?time:float ->
  ?resolve:(Flow.Eval.value -> (Flow.Eval.value, Flow.Diagnostic.t) result) ->
  ?execution:(path -> probes:int list -> execution option) ->
  ?geometry:(int -> geometry option) -> ?dynamic:(path -> int option) ->
  ?element:(path -> int -> (string * Flow.Eval.value) list option) -> Flow.Eval.t -> t
(** [live] forces residual values using the complete frame; [time] supplies a
    time-only frame when [live] is absent. [state] is copied when the probe is
    created, so inspecting a fold never advances the environment's state.
    [geometry] maps a plan
    node id to its cooked counts; [dynamic] gives the element count a loop over
    geometry ran over in the last cook: {!counts} reports it, and a
    node inside such a loop reads its one template record at every element.  [element zone k]
    names element [k] of that loop and gives its value (a point's position): the template's
    element-dependent values are then forced for it (without it they read [?]).
    [resolve] supplies cooked packed sources. Map selectors materialize their
    inputs once and reference-evaluate just the selected call, beyond the 4,096
    recording cap. The selected call and all its body records share one bounded memo.
    Packed function sparklines sample at most 64 calls across the complete input. *)

val same_eval : t -> t -> bool
(** Both come from one evaluation (only the time or the geometry counts may
    differ), so their iteration counts are equal. *)

val execution : t -> path -> probes:int list -> execution option
(** Host execution metadata without forcing a probe value. *)

val plan_node : t -> path -> probes:int list -> int option
(** The plan node ({!Flow.Eval.node} id) of a geometry value at the probe.
    A loop over geometry shares its template id across element indices; static
    loop indices retain their exact match, including skipped iterations. *)

val records : t -> path -> (int list * summary) array
(** Every recorded value of a path in evaluation order, capped at 4,096
    previews even when a packed array evaluates more elements. *)

val at : t -> path -> probes:int list -> summary option
(** Reference value at the selected iteration tuple, including packed function
    calls outside the recording cap. Cooked inputs and call records are memoized. *)

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
  live : bool;  (** depends on frame facts or a frame fold *)
  execution : execution option;
}

val footer : t -> Projection.node -> probes:int list -> footer

val text : footer -> string
(** The footer as one line, parts joined by [ · ] ([↥], [◷ t] spelled as
    drawn: [↑ same each time], [t]). *)

val readouts : t -> Projection.node -> probes:int list -> (string * string) list
(** The inspector's rows: [value] (or [value at probe] inside a zone) and
    [cook] ([live, recooks every frame] or [cached]). *)

val iterations : t -> Projection.node -> probes:int list -> string array
(** The inspector's textual summary of each recorded iteration. *)

val geometry_targets : t -> Projection.scope -> probe:(path -> int) -> int list
(** The plan nodes of every geometry node of the scope at its probes: what a
    footer wants the cook to count. *)
