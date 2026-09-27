type t = {
  value : int
    [@sop.default 3] [@sop.min 1] [@sop.max 8] [@sop.hard_min 1];
}
[@@deriving sop_params]

open Procedural

module Vector_fixture = struct
  type parameters = {
    center_x : float [@sop.default 0.] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.primary] [@sop.vec3 "center"];
    center_y : float [@sop.default 0.] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.vec3 "center"];
    center_z : float [@sop.default 0.] [@sop.min (-1.)] [@sop.max 1.]
      [@sop.vec3 "center"];
  } [@@deriving sop_params, sop_node]
    [@@sop.node_key "vector_fixture"] [@@sop.node_operation "match_size"]
    [@@sop.node_label "Vector Fixture"] [@@sop.node_category "Test"]
    [@@sop.node_inputs 2] [@@sop.node_optional "1"]
    [@@sop.node_slots "input, target"]
  let build = parameters_build (fun ~label _parameters input target ->
    Sop.match_size ~label ?target input)
  let factory = parameters_factory build
end

module Registered_vector = Vector_fixture [@@sop.register]
