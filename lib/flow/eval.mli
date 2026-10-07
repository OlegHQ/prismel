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
      zone or [fn] path (as in [Workspace.path]) extended by the route down
      through argument names ([#n] when a name repeats, as in [sop/merge]),
      list/record/[if]/[cond] positions.  A [defn] body is prefixed by the
      site of its call, so every call site of a [defn] is a distinct subtree;
    - [iter] is the iteration tuple: the running index of each enclosing zone
      (outermost first, counted over the whole product, as in the study) and
      of each enclosing [fn] call (a closure counts its own calls; a [defn] or
      operator passed to [map] counts one per element).
    Two nodes of one graph instance never share a key.

    [args] holds the fully evaluated arguments in written order.  A geometry
    input is [Deferred (Ty.Geometry, id)] (an earlier node, possibly in another instance) or
    [No_geo] (for [nil]); the inputs of [sop/merge] are spliced (lists
    flattened, [No_geo] dropped) and all named [input].  Numbers keep their
    dynamic [Int]/[Float] kind: lowering coerces them to the catalog
    parameter type.  A catalog kind used as a function value ([(map
    sop/box xs)]) has positional arguments named [$0], [$1], ...; kinds are
    named as written.  Scene, world, settings and panel values ([scene/object],
    [ui/split], ...) are [Struct] values, not nodes: their arguments are
    checked here ([ui/tile] holds 1-16 panels, split axis and ratio, settings
    ranges) and geometry inside them is a [Deferred (Geometry, id)] reference.

    {2 Split evaluation (W2b)}

    {!static} evaluates every term that does not depend on frame facts or a fold. A term that
    does becomes a {!residual}: the term with the environment it was
    evaluated in, so every static capture is folded in.  A plan node whose
    argument depends on the frame carries a [Residual] there (a [Vec3] with a live
    component is one residual for the whole vector); {!residual_eval} and
    {!force} evaluate it for a complete frame without touching the plan, and never
    create geometry.  Structure cannot depend on [t] (the checker rejects
    it), so one static pass serves every frame.  {!run} is the convenience
    that does both for a given time.

    [residual] environments hold the whole scope of the term, not only its free
    variables (ponytail: no free-variable pruning yet; measure in W2b). *)

type ('f, 'r) payload = ('f, 'r) Value.t =
  | Int of int
  | Float of float
  | Bool of bool
  | Text of string
  | Vec3 of float * float * float
  | List of ('f, 'r) payload array
  | Float_array of float array
  | Vec3_array of float array
  | Record of (string * ('f, 'r) payload) list  (** fields in written order *)
  | Deferred of Ty.t * int  (** a plan node *)
  | No_geo  (** [nil] *)
  | Struct of string * Ty.t * (string * ('f, 'r) payload) list
      (** a scene, world, settings or panel value: the head, its resolved type and its
          arguments; [scene/merge] and [ui/tile] splice their lists *)
  | Fn of 'f
  | Residual of 'r

type value = (fn, residual) payload

and fn
and residual
and state
and node = {
  id : int;  (** index in [plan.nodes] *)
  inst : int;  (** index in [plan.instances] *)
  site : Workspace.path;
  iter : int list;
  kind : string;  (** catalog kind or deferred operator, including [sop/curve] and [draw/*] *)
  ty : Ty.t;  (** the declared result type of the deferred node *)
  args : (string * value) list;
}

type live = Frame_input.t

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
  states : value list;  (** frame folds to advance, including unused bindings *)
  records : (Workspace.path * (int list * value) list) list;
      (** with [~record:true]: the values seen at each path, per iteration tuple,
          in evaluation order, at most 4,096 per path (bindings, results,
          zone variables [":x"], [fn] parameters, graph inputs).  Geometry is a
          [Deferred (Geometry, id)] reference (its counts come from the cook, {!Flow_graph.Probe}); a
          live value is a [Residual] until forced ({!run}, {!Flow_graph.Probe}). *)
}

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

val create_state : unit -> state
val reset_state : state -> unit
(** An environment owns this fold state. Reset on reload or a new export. *)

val fork_state : state -> state
(** Copy the fold snapshot for pure worker reads; data is shared immutably. *)

val state_stamp : state -> string
(** Exact content fingerprint for a prepared frame's captured fold snapshot. *)

val transaction : state -> (unit -> ('a, Diagnostic.t) result) -> ('a, Diagnostic.t) result
(** Keep the previous fold snapshot when a group of evaluations fails. *)

val residual_eval : ?state:state -> ?elems:(string * value) list -> residual -> live:live -> (value, Diagnostic.t) result
(** A live term's value at a time (never a [Residual] at the top). *)

val force : ?state:state -> ?elems:(string * value) list -> value -> live:live -> (value, Diagnostic.t) result
(** Every residual inside a value replaced by its value at the time.  [elems] binds
    the element of each geometry zone ({!element_key}) to its value (a point
    is a [Vec3]); a residual that reads an unbound element is an error. *)

val element_key : Workspace.path -> string
(** The name under which {!force} binds the element of the zone at this path. *)

val is_live : value -> bool
(** A residual anywhere inside. *)

val frame_dependent : value -> bool
(** Reads a frame fact; element-only residuals return false. *)

val state_dependent : value -> bool
(** Reads an environment-owned frame fold. *)

val run :
  ?record:bool -> ?inputs:(string * (string * value) list) list -> ?state:state -> ?live:live -> time:float -> Workspace.t ->
  (t, Diagnostic.t) result
(** {!static} then {!force} of every argument, input, result and record at
    [time]: no [Residual] is left. *)

val hash : float list -> float
(** [value/rand]: the study's pure hash.  Each key [x] becomes
    [k = int32(floor(x * 1000003))]; from [h = 0x9e3779b9] each key does
    [h = imul(h xor k, 0x85ebca6b); h = h xor (h >>> 13); h = imul(h, 0xc2b2ae35);
    h = h xor (h >>> 16)] (32-bit unsigned), and the result is
    [(h mod 1000000) / 1000000], greater than or equal to zero and less than one. *)

val show : value -> string
(** [str] formatting (register C2); a residual shows as [?]. *)

module Private : sig
  val compile_residuals : bool ref
  (** [true] (the default): a residual is forced through its compiled closure
      when its term is in the compilable subset.  Tests switch it off to compare the
      closure against the interpreter bit for bit. *)

  val compiled : value -> int
  (** How many residuals inside the value have a compiled closure (after a {!force}). *)
end
