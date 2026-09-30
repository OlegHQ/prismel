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
      [Procedural.Sop.polyline].  Its points are baked into the node
      (ponytail: a list parameter is not a catalog field; W2b replaces the
      node to animate it).
    - [^:bypass] never reaches lowering: {!Flow.Eval} passes the input through
      and the call makes no plan node.

    A parameter that depends on [t] is not evaluated: the node cooks with its
    value at [t = 0] and the argument is listed in {!t.pending} for W2b. *)

val source_attribute : string
(** ["__flow_src"]: the primitive int attribute every collecting merge writes. *)

type pending = { node : int; field : string; value : Flow.Eval.value }
(** A live parameter: compiled node id, argument name, and the argument as
    evaluated (a residual, or a list/vec3 holding residuals). *)

type origin = { source : int; site : Flow.Workspace.path; iter : int list }
(** Where a merge input came from: the compiled id of the source node and its
    plan key. *)

module Origins : Map.S with type key = int * int

type graph = {
  name : string;
  instance : int;  (** index in [Flow.Eval.plan.instances] *)
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
  provenance : origin Origins.t;
      (** (merge compiled id, input index) -> its source; the index is the
          value of the merge's {!source_attribute} for that input's primitives *)
  plan : Flow.Eval.plan;
}

val workspace :
  factories:Procedural.Edit_graph.factory list ->
  ?compiled_ids:int Instance_path.Map.t -> ?sites:Flow.Workspace.path list ->
  ?inputs:(string * (string * Flow.Eval.value) list) list ->
  Flow.Syntax.t list -> (t, Flow.Diagnostic.t) result
(** [factories] is the SOP catalog ([Sop_catalog.Editor.factories]).  Errors:
    the checker's first error, the evaluator's, or [E_LOWER]. *)
