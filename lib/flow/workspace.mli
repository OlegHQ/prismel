(** The workspace language checker: resolves, types and validates a
    [(workspace ...)] and produces the typed IR that lowering and evaluation
    read (port of the static pass of the study's [compile]).

    Static only: no value is evaluated.  A count that is a literal (a literal
    [range], [linspace] or [list]) is bounded here ([E_ITER_BOUND],
    destructuring lengths); a count that comes from an input, [t] or geometry
    is bounded by [Eval] when it runs.  Every body is typed once (both [if]
    branches, zero-iteration loops) and a [fn] or [defn] body is typed again at
    each call site with the argument types, unannotated [fn] parameters
    starting as [Any] (register F2).  A definition called from several sites
    reports each diagnostic once.

    Codes: [E_SHADOW] [E_FN_ESCAPES] [E_ACC_TYPE] [E_ITER_BOUND]
    [E_NO_ELSE] [E_PATTERN] [E_INPUT_DEFAULT] [E_TIME_COUNT] [E_TIME_BRANCH]
    [W_UNKNOWN_GROUP], the [E_MACRO_*] codes of {!Macro}, and the study's other
    diagnostics ([E_TYPE], [E_UNBOUND], [E_ARITY], [E_UNKNOWN_PARAM],
    [E_RECURSION], [E_GRAPH_CYCLE], ...) with the study's wording. *)

type path = string list
(** Lexical identity, stable across edits: [["flower"; "ring"; "u"]] is the
    binding [u] in the zone bound to [ring] in graph [flower].  Reserved
    segments: [":x"] a loop variable or parameter, ["@result"] a body result,
    ["~for"] / ["~let"] / ["~fn"] an unbound inline form, ["def:name"] the
    root of a [defn]. *)

module Paths : Set.S with type elt = path

type context = Sop | Value | Scene | World | Settings | Editor
(** [Flow.Context.t] has no [Settings] or [Editor] until W10, so the workspace
    language carries its own. *)

val context_name : context -> string

type pattern = Name of string | Seq of pattern list | Keys of string list
(** [a], [[a b]] (also over a vec3), [{:keys [a b]}]. *)

type term = { path : path option; ty : Ty.t; node : node; form : Syntax.t }
(** [path] is set on bindings, zones, results and graph/defn bodies.  [form] is
    the authored form (with its notes); for a macro call it is the call. *)

and node =
  | Lit of Param.value  (** int, float or bool *)
  | Text of string
  | Nil  (** empty geometry *)
  | Time  (** [t] *)
  | Vec of term list  (** vec3 literal *)
  | Ref_binding of string * string list  (** [name.field.field] *)
  | Call of { kind : string; args : (string * term) list }
      (** catalog kind, qualified; slots and keyword parameters in written
          order.  [sop/merge] names every input [input]. *)
  | Op of { op : string; args : (string * term) list }
      (** built-in operator ([+], [range], [value/rand], [scene/object],
          [ui/split-at], ...) with its slot names; a rest slot repeats its
          name. *)
  | Call_fn of { fn : string; args : term list }
      (** a [defn] (arguments in parameter order, defaults filled in) or a
          local [fn] *)
  | Fn_ref of string  (** a defn, operator or kind name used as a function value *)
  | Graph_ref of { graph : string; inputs : (string * term) list }
  | Let of (pattern * term) list * term
  | Loop of { kind : [ `For | `Fold | `Scan | `Sum ]; accs : (pattern * term) list;
              clauses : (pattern * term) list; body : term; zone : path }
  | If of term * term * term
  | Cond of (term * term) list * term
  | Case of term * (Syntax.t * term) list * term
  | Fn of { params : (pattern * Ty.t option) list; body : term; zone : path }
  | Hof of [ `Map | `Filter | `Reduce | `Sort_by ] * term list
  | List_lit of term list
  | Record of (string * term) list
  | Get of term * string
  | Assoc of term * (string * term) list
  | Str of term list
  | List_op of string * term list  (** [concat] *)
  | Bypass of term  (** [^:bypass] on a call *)
  | Expanded of { macro : string; body : term }  (** a macro call and its expansion *)

type graph = {
  name : string;
  context : context;
  inputs : (string * Ty.t * term option) list;  (** graph inputs always have a default *)
  body : term;
  form : Syntax.t;
}

type t = {
  name : string;
  graphs : graph list;
  defs : graph list;  (** [defn]s *)
  macros : Syntax.t list;  (** the [defmacro] forms *)
  source : Syntax.t list;
  live : Paths.t;
      (** terms that depend on [t]: they mention it, or depend on a live
          binding, capture, fold accumulator, [ref] override, graph or
          function (register T1).  A [defn] body is live when it is at any
          call site. *)
  invariant : Paths.t;
      (** bindings directly in a zone body that do not depend on the loop
          variables or the accumulator (register L7, the "same each time"
          mark) *)
}

val max_iterations : int
(** Iterations per zone: 4,096. *)

val check : Check.catalog -> Syntax.t list -> t option * Diagnostic.t list
(** Check one [(workspace name ...)] form.  The workspace is returned only
    without errors; warnings never block it. *)
