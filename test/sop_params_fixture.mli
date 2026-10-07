type t = {
  value : int
    [@sop.default 3] [@sop.min 1] [@sop.max 8] [@sop.hard_min 1];
}
[@@deriving sop_params]

module Editor : sig
  val factories : Procedural.Edit_graph.factory list
end

module Optional_rest_fixture : sig
  val factory : Procedural.Edit_graph.factory
  val fn : ?label:string -> ?tag:string -> Procedural.Node.t ->
    Procedural.Node.t option -> Procedural.Node.t list -> Procedural.Node.t
end

module Dynamic_schema_fixture : sig
  val factory : Procedural.Edit_graph.factory
  val fn : ?label:string -> ?input:int -> Procedural.Node.t list -> Procedural.Node.t
end
