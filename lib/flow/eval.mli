(** The evaluator of the workspace language (port of the run pass of the
    study's [compile]): everything that is not geometry.

    Numbers, vec3, text, lists, records, functions, loops, [if]/[cond]/[case],
    higher-order forms, [str], list operations, [ref] with overrides and
    graph inputs run here, sequentially, on IEEE doubles, with a step budget.
    Geometry is not built: a catalog call (and the workspace operator
    [sop/curve]) becomes a {e plan node}, and W2's lowering turns the plan
    into one network per graph instance.

    {2 The geometry plan}

    A node is keyed by [(site, iter)]:
    - [site] is the lexical path of the call: the enclosing binding, result,
      zone or [fn] path (as in {!Workspace.path}) extended by the route down
      through argument names ([#n] when a name repeats, as in [sop/merge]),
      list/record/[if]/[cond] positions.  A [defn] body is prefixed by the
      site of its call, so every call site of a [defn] is a distinct subtree;
    - [iter] is the iteration tuple: the running index of each enclosing zone
      (outermost first, counted over the whole product, as in the study) and
      of each enclosing [fn] call (a closure counts its own calls; a [defn] or
      operator passed to [map] counts one per element).
    Two nodes of one graph instance never share a key.

    [args] holds the fully evaluated arguments in written order.  A geometry
    input is [Geo id] (an earlier node, possibly in another instance) or
    [No_geo] (for [nil]); the inputs of [sop/merge] are spliced (lists
    flattened, [No_geo] dropped) and all named [input].  Numbers keep their
    dynamic [Int]/[Float] kind: lowering coerces them to the catalog
    parameter type.  A catalog kind used as a function value ([(map
    sop/box xs)]) has positional arguments named [$0], [$1], ...; kinds are
    named as written.  Scene, world, settings and panel values ([scene/object],
    [ui/split], ...) are [Struct] values, not nodes: their arguments are
    checked here ([ui/tile] holds 1-16 panels, split axis and ratio, settings
    ranges) and geometry inside them is a [Geo] reference.

    {2 Split evaluation (W2b)}

    {!static} evaluates every term that does not depend on [t].  A term that
    does becomes a {!residual}: the term with the environment it was
    evaluated in, so every static capture is folded in.  A plan node whose
    argument depends on [t] carries a [Residual] there (a [Vec3] with a live
    component is one residual for the whole vector); {!residual_eval} and
    {!force} evaluate it for a time without touching the plan, and never
    create geometry.  Structure cannot depend on [t] (the checker rejects
    it), so one static pass serves every frame.  {!run} is the convenience
    that does both for a given time.

    [residual] environments hold the whole scope of the term, not only its free
    variables (ponytail: no free-variable pruning yet; measure in W2b). *)

type value =
  | Int of int
  | Float of float
  | Bool of bool
  | Text of string
  | Vec3 of float * float * float
  | List of value array
  | Record of (string * value) list  (** fields in written order *)
  | Geo of int  (** a plan node *)
  | No_geo  (** [nil] *)
  | Struct of string * (string * value) list
      (** a scene, world, settings or panel value: the operator and its
          arguments; [scene/merge] and [ui/tile] splice their lists *)
  | Fn of fn
  | Residual of residual

and fn
and residual
and node = {
  id : int;  (** index in [plan.nodes] *)
  inst : int;  (** index in [plan.instances] *)
  site : Workspace.path;
  iter : int list;
  kind : string;  (** catalog kind, or [sop/curve] *)
  args : (string * value) list;
}

type live = { t : float }

type instance = {
  graph : string;
  default : bool;  (** the graph evaluated with its own defaults: the one an editor shows, and the one that records *)
  inputs : (string * value) list;  (** every input, defaults filled in *)
  result : value;
}
(** One evaluation of a graph: the top-level graphs with their inputs, and one
    per distinct [(ref g :k v)] override tuple (cached by value, L14). *)

type plan = { instances : instance array; nodes : node array }

type t = {
  plan : plan;
  results : (string * value) list;  (** each graph, evaluated with its default (or given) inputs *)
  records : (Workspace.path * (int list * value) list) list;
      (** with [~record:true]: the values seen at each path, per iteration tuple,
          in evaluation order, at most 4,096 per path (bindings, results,
          zone variables [":x"], [fn] parameters, graph inputs).  Geometry is a
          [Geo] reference (its counts come from the cook, {!Flow_sop.Probe}); a
          live value is a [Residual] until forced ({!run}, {!Flow_sop.Probe}). *)
}

val max_steps : int
(** Evaluation budget: 600,000 evaluation steps ([E_EVAL_BUDGET]). *)

val max_concat : int
(** Elements one [concat] may produce: 4,096. *)

val static :
  ?record:bool -> ?inputs:(string * (string * value) list) list -> Workspace.t ->
  (t, Diagnostic.t) result
(** Evaluate every graph once.  [inputs] overrides graph inputs by graph name
    (the OCaml-visible interface, register O2).  The first error stops the
    run; its code is one of [E_ITER_BOUND] (a driven [range], [linspace],
    [concat] or zone over 4,096), [E_EVAL_BUDGET], [E_LIST_RANGE]
    ([first]/[last]/[nth]), [E_PATTERN] (a destructuring pattern longer than a
    driven list), [E_NONFINITE], [E_RANGE] ([ui/tile], [ui/split],
    [settings/config] with computed arguments), [E_DEPTH], [E_LIVE_GEOMETRY]. *)

val residual_eval : residual -> live:live -> (value, Diagnostic.t) result
(** A live term's value at a time (never a [Residual] at the top). *)

val force : value -> live:live -> (value, Diagnostic.t) result
(** Every residual inside a value replaced by its value at the time. *)

val is_live : value -> bool
(** A residual anywhere inside. *)

val run :
  ?record:bool -> ?inputs:(string * (string * value) list) list -> time:float -> Workspace.t ->
  (t, Diagnostic.t) result
(** {!static} then {!force} of every argument, input, result and record at
    [time]: no [Residual] is left. *)

val hash : float list -> float
(** [value/rand]: the study's pure hash.  Each key [x] becomes
    [k = int32(floor(x * 1000003))]; from [h = 0x9e3779b9] each key does
    [h = imul(h xor k, 0x85ebca6b); h = h xor (h >>> 13); h = imul(h, 0xc2b2ae35);
    h = h xor (h >>> 16)] (32-bit unsigned), and the result is
    [(h mod 1000000) / 1000000] in [[0, 1)]. *)

val show : value -> string
(** [str] formatting (register C2); a residual shows as [?]. *)
