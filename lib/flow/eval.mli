(** The evaluator of the workspace language (port of the run pass of the
    study's [compile]): everything that is not geometry.

    Numbers, vectors, text, lists, records, functions, loops, [if]/[cond]/[case],
    higher-order forms, [str], list operations, [ref] with overrides and
    graph inputs run here, sequentially, on IEEE doubles, with a step budget.
    Packed operations budget each 1,024-element block separately; native
    storage bounds limit their counts, while expensive bodies remain bounded.
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
    input is [Deferred (Ty.geometry, id)] (an earlier node, possibly in another instance) or
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

    [residual] environments hold only lexically free bindings, including names
    captured by nested function and zone bodies. The checked-term walk is
    memoized with a bounded weak cache. *)

type ('f, 'r) payload = ('f, 'r) Value.t =
  | Int of int
  | Float of float
  | Bool of bool
  | Text of string
  | Vec2 of float * float
  | Vec3 of float * float * float
  | Vec4 of float * float * float * float
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
  authored : int array;
      (** Originating syntax form ID by plan node ID, shared by copies and
          independent of the evaluation route. IDs belong to this checked
          source and can change on reparse; they are not plan identities.
          Zero denotes a synthetic node or a kind invoked as a function value. *)
  results : (string * value) list;  (** each graph, evaluated with its default (or given) inputs *)
  states : value list;  (** frame folds to advance, including unused bindings *)
  records : (Workspace.path * (int list * value) list) list;
      (** with [~record:true]: the values seen at each path, per iteration tuple,
          in evaluation order, at most 4,096 per path (bindings, results,
          zone variables [":x"], [fn] parameters, graph inputs).  Geometry is a
          [Deferred (Geometry, id)] reference (its counts come from the cook, {!Flow_graph.Probe}); a
          live value is a [Residual] until forced ({!run}, {!Flow_graph.Probe}).
          Packed local maps retain [fn-path/~calls] templates for reference
          inspection beyond the recording cap. *)
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
val reset_state : ?host_state:bool -> state -> unit
(** Reset on reload or a new export. [host_state=false] resets animation
    playback while retaining host interaction state. *)

val fork_state : state -> state
(** Copy the fold snapshot for pure worker reads; data is shared immutably. *)

val state_stamp : state -> string
(** Exact content fingerprint for a prepared frame's captured fold snapshot. *)

val transaction : state -> (unit -> ('a, Diagnostic.t) result) -> ('a, Diagnostic.t) result
(** Keep the previous fold snapshot when a group of evaluations fails. *)

val residual_eval : ?state:state -> ?elems:(string * value) list -> residual -> live:live -> (value, Diagnostic.t) result
(** A live term's value at a time (never a [Residual] at the top). *)

val force : ?state:state -> ?elems:(string * value) list ->
  ?resolve:(value -> (value, Diagnostic.t) result) -> value -> live:live -> (value, Diagnostic.t) result
(** Every residual inside a value replaced by its value at the time.  [elems] binds
    the element of each geometry zone ({!element_key}) to its value (a point
    is a [Vec3]); a residual that reads an unbound element is an error.
    [resolve] materializes host-owned packed [Struct] sources at the cook
    boundary. Without a resolver these report [E_DATA_SOURCE]. *)

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
  val map_function : signature:Ty.fn_signature -> fn -> value list -> (value, Diagnostic.t) result
  (** Bind immutable packed columns to an instantiated function, retaining its
      body and captures as a genuine residual map for downstream compilation. *)

  val free_names : Workspace.term -> string list
  (** Lexically free binding names, including nested function captures. *)

  val free_name_walks : unit -> int
  (** Number of memo misses, for the checked-term reuse regression. *)

  val force_with_executor : ?state:state -> ?elems:(string * value) list ->
    ?resolve:(value -> (value, Diagnostic.t) result) ->
    execute:(residual -> live -> (value, Diagnostic.t) result option) ->
    value -> live:live -> (value, Diagnostic.t) result
  (** Dispatch supported packed subterms inside an evaluator-owned frame fold.
      None retains the interpreter. The callback receives the current immutable
      bindings; the evaluator still owns cell identity and the frame transaction.
      Reference forcing never invokes this callback. *)

  val function_bindings : fn -> (string * value) list
  (** Captured immutable inputs of a function value, for host data dependencies. *)

  val function_id : fn -> int
  (** Immutable hash hint, not equality: specialized closures may share this id. *)

  val state_values : state -> value list
  (** Values retained by a forked snapshot, for host payload accounting. *)

  val function_body : fn -> ((Workspace.pattern * Ty.t option) list * Workspace.term) option
  (** Checked body of a local function; named definitions remain interpreted. *)

  val function_scope : fn -> (Workspace.path * int list) option
  (** Authored zone and enclosing iteration tuple of an instantiated local
      function, for a host supplying selected bulk-call probes. *)

  type residual_view = {
    term : Workspace.term;
    bindings : (string * value) list;
    site : Workspace.path;
    iter : int list;
    instance : int;
    previous : bool;
  }
  val residual_view : residual -> residual_view
  (** Immutable specialized term and captured values for downstream IR construction. *)

  val residual_id : residual -> int
  (** Stable within one specialized evaluation; equality across evaluations is physical. *)

  val residual_ops : residual -> Op.t list
  (** The immutable operator extension list of the captured workspace. *)

  val force_reference : ?state:state -> ?elems:(string * value) list ->
    ?resolve:(value -> (value, Diagnostic.t) result) -> value -> live:live ->
    (value, Diagnostic.t) result
  (** Force through the tree walker, including captured residuals, without changing
      process-wide compilation settings. Suitable for probes and parity checks. *)

  val closure_available : residual -> bool
  (** Prepare the existing scalar closure once; false for unsupported terms. *)

  val eval_term : ?state:state -> ?elems:(string * value) list ->
    ?resolve:(value -> (value, Diagnostic.t) result) -> residual -> Workspace.term ->
    live:live -> (value, Diagnostic.t) result
  (** Evaluate a checked subterm in the residual's captured scope, through the
      reference walker. IR kernels use this once for their packed inputs. *)

  val map_probe : ?state:state -> ?resolve:(value -> (value, Diagnostic.t) result) ->
    ?offset:int -> residual -> live:live ->
    (int * (int -> ((Workspace.path * (int list * value) list) list, Diagnostic.t) result), Diagnostic.t) result
  (** Materialize map inputs once with the reference walker, then record only
      the selected function call. This admits indices beyond the preview cap;
      [offset] preserves call numbering when a function serves several maps. *)

  val compile_residuals : bool ref
  (** [true] (the default): a residual is forced through its compiled closure
      when its term is in the compilable subset.  Tests switch it off to compare the
      closure against the interpreter bit for bit. *)

  val compiled : value -> int
  (** How many residuals inside the value have a compiled closure (after a {!force}). *)
end
