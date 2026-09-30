(** Lowering of a checked workspace to SOP networks (plan W2).

    {!workspace} checks the source ({!Flow.Workspace.check}), evaluates every
    non-geometry term ({!Flow.Eval.static}) and turns the geometry plan into
    one {!Network.t} per evaluation of a [sop] graph: each top-level graph with
    its default inputs and each distinct [(ref g ...)] override tuple
    (the study's per-tuple cache).  An instance's network holds its own plan
    nodes and every node of another instance it references, so a shared
    sub-network is lowered once and appears (with the same ids) in each network
    that uses it.

    {2 Ids}

    A plan node keyed by [(site, iter)] in instance [i] gets the compiled id
    [compiled_ids.[i :: site_index :: List.map (fun k -> -(k + 1)) iter]],
    allocated on first use.  [site_index] numbers {!t.sites}; pass a previous
    result's [sites] and [compiled_ids] back to keep ids stable across edits.
    ponytail: negative-int encoding of an iteration segment (a site index and
    an instance index are never negative, so the key is unambiguous); switch
    to a variant if paths ever need other segment kinds.

    {2 Nodes}

    - A catalog call becomes its catalog factory node with literal parameters
      (colour text [#rrggbb] becomes a vec3).
    - Every [sop/merge] becomes one internal [flow.merge_n] node over
      [Procedural.Sop.merge ~source_attribute:{!source_attribute}] with one slot
      per collected input, so a spliced list is one node, not a chain.
    - [sop/curve] (a workspace operator) becomes a [flow.curve] node over
      {!Curve.factory} (a [flow.curve] node with an encoded [points] parameter).
    - [^:bypass] never reaches lowering: {!Flow.Eval} passes the input through
      and the call makes no plan node.

    A parameter that depends on [t] cooks at [t = 0] in the literal network
    and is listed in {!t.pending}; every network also carries one
    {!Drive.Live} drive per pending argument of its nodes, keyed (compiled id,
    argument name), which {!Value_lane.resolve} evaluates for each time.
    [sop/curve] lowers to {!Curve.factory} (a text-encoded [points]
    parameter), so a live list is one drive. *)

val source_attribute : string
(** ["__flow_src"]: the primitive int attribute every collecting merge writes. *)

type pending = { node : int; field : string; value : Flow.Eval.value }
(** A live parameter: compiled node id, argument name, and the argument as
    evaluated (a residual, or a list/vec3 holding residuals). *)

type origin = { merge : int; input : int; source : int;
                site : Flow.Workspace.path; iter : int list }
(** Where a merge input came from: the merge and input index, the compiled id
    of the source node and its plan key. *)

type zone = { cid : int; site : Flow.Workspace.path; iter : int list;
              body_site : Flow.Workspace.path; base : int; count : int Atomic.t }
(** A loop over geometry ({!zones}): its compiled id, plan key, the site of its body
    result, the first of the {!Procedural.Zone.max_elements} tags it reserves and the
    element count of the last cook that ran it ([-1] before any). *)

type graph = {
  name : string;
  instance : int;  (** index in [Flow.Eval.plan.instances] *)
  default : bool;  (** the graph with its own default inputs, not a [ref] override *)
  inputs : (string * Flow.Eval.value) list;
  network : Network.t;
  root : int option;  (** displayed node (the graph result); [None] for [nil] *)
}

type t = {
  graphs : graph list;  (** one per [sop] instance, in plan order *)
  compiled_ids : int Instance_path.Map.t;
  sites : Flow.Workspace.path list;
  compiled : int Network.Int_map.t;  (** plan node id -> compiled id *)
  pending : pending list;
  provenance : origin Network.Int_map.t;
      (** tag -> its origin: the value of {!source_attribute} is a running count over the
          inputs of every merge in lowering order, so it is deterministic for one
          source.   A merge of merges keeps the innermost tag, so a
          primitive of the displayed geometry names the merge input that made it *)
  zones : zone list;
  volatile : unit Network.Int_map.t;  (** compiled ids, see {!is_volatile} *)
  plan : Flow.Eval.plan;
}

val origin : t -> int -> origin option
(** The origin of a tag: {!t.provenance}, else a loop over geometry, whose element
    [i] has tag [base + i], site [body_site] and iteration [iter @ [i]] (the
    iteration of an enclosing loop is the template's, 0). *)

val tags : t -> site:Flow.Workspace.path -> iter:int list -> int list
(** Every tag whose origin is this site at this iteration tuple; the loop over geometry
    itself, at its own tuple, gives every element's tag. *)

val zone_count : t -> Flow.Workspace.path -> int option
(** The elements the loop over geometry bound at this path ran over in its last
    cook, [None] before it cooked. *)

val is_volatile : t -> int -> bool
(** A compiled node is volatile when it is live (an argument depends on [t])
    or fed by a volatile node: its cache key changes with the time.  Pass
    [is_volatile lowered] to [Procedural.Session.set_volatile]. *)

val objects : t -> (int * Network.t * int) list
(** Every graph that returns geometry as (instance index, network, displayed
    node): the [~objects] of the editor's [Cook.update] (the document-driven
    caller is W3). *)

val workspace :
  factories:Procedural.Edit_graph.factory list ->
  ?compiled_ids:int Instance_path.Map.t -> ?sites:Flow.Workspace.path list ->
  ?inputs:(string * (string * Flow.Eval.value) list) list ->
  Flow.Syntax.t list -> (t, Flow.Diagnostic.t) result
(** [factories] is the SOP catalog ([Sop_catalog.Editor.factories]).  Errors:
    the checker's first error, the evaluator's, or [E_LOWER]. *)

val counts : t -> int * int
(** (live, cached) node counts. *)

val status : t -> seconds:float -> string option
(** The viewport header [t N live · M cached · cook X ms] ([t] for the study's
    ◷, which DepartureMono lacks); [None] when nothing is live. *)
