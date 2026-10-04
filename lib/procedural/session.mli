(** Explicit, bounded graph-evaluation state. A session is single-caller: it
    may run parallel RDK kernels internally, but concurrent calls to [cook] on
    the same session are not supported. *)

type t

type node_timing = {
  node_id : int;
  label : string;
  operation : string;
  seconds : float;
  cache_hit : bool;
}

type stats = {
  cooks : int;
  hits : int;
  misses : int;
  evictions : int;
  volatile_hits : int;  (* subset of [hits] *)
  volatile_misses : int;  (* subset of [misses] *)
  retained_entries : int;
  volatile_entries : int;  (* one slot per volatile node, outside the LRU *)
  retained_payload_bytes : int;
  last_node : node_timing option;
}

type output = {
  geometry : Rdk.Geometry.t;
  diagnostics : Diagnostic.t list;
  instances : Rays_math.Mat4.t array option;
  (** A packed result (e.g. Copy to Points with Pack and instance): draw
      [geometry] once per transform. A node that consumes it receives it
      materialized. *)
}

val create : max_entries:int -> max_payload_bytes:int -> (t, string) result

val set_volatile : t -> (int -> bool) -> unit
(** [set_volatile session predicate] (by node id; default none) marks nodes whose cache key changes
    every cook (time-driven nodes and what is downstream of them). A volatile
    node keeps exactly one entry, its latest, replaced in place; it is never
    counted in or evicted from the LRU, so it cannot push static entries out.
    Its lookups count in [hits] and [misses] and in [volatile_hits] and
    [volatile_misses]; its payload is not counted in [retained_payload_bytes]
    (bounded by the volatile node count; ponytail: one slot, so scrubbing
    back recooks). Replaces the previous predicate (a new lowering) and drops
    the slots of nodes that stopped being volatile. *)

(** Bounded graph-inspection reuse for repeated queries within a session.
    [clear] and [close] discard the retained metadata. *)
val inspect : t -> Graph.t -> Graph.info list

val cook : t -> context:Context.t -> Node.t -> (output, Diagnostic.error) result

val stats : t -> stats
val clear : t -> unit
val close : t -> unit
val is_closed : t -> bool
