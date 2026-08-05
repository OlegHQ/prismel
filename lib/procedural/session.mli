(** Explicit, bounded graph-evaluation state. A session is single-caller: it
    may run parallel PDK kernels internally, but concurrent calls to [cook] on
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
  retained_entries : int;
  retained_payload_bytes : int;
  mesh_hits : int;
  mesh_misses : int;
  retained_meshes : int;
  last_node : node_timing option;
}

type output = {
  geometry : Pdk.Geometry.t;
  diagnostics : Diagnostic.t list;
}

val create : max_entries:int -> max_payload_bytes:int -> (t, string) result
val cook : t -> context:Context.t -> Node.t -> (output, Diagnostic.error) result

(** Convert and cache a render mesh by immutable geometry identity. The cache
    uses the session's entry and payload bounds and is cleared with the cook
    cache. *)
val mesh : ?cancel:Pdk.Cancel.t -> t -> Pdk.Geometry.t ->
  (Prismel.Mesh.t, Pdk.Error.t) result
val stats : t -> stats
val clear : t -> unit
val close : t -> unit
val is_closed : t -> bool
