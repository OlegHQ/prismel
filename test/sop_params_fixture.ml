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
    Sop.match_size ~label input target)
  let factory = parameters_factory build
end

module Registered_vector = Vector_fixture [@@sop.register]

module Optional_rest_fixture = struct
  type parameters = {
    tag : string [@sop.default ""] [@sop.label "Tag"];
  } [@@deriving sop_params, sop_node]
    [@@sop.node_key "optional_rest_fixture"] [@@sop.node_operation "merge"]
    [@@sop.node_label "Optional Rest Fixture"] [@@sop.node_category "Test"]
    [@@sop.node_inputs 3] [@@sop.node_optional "1,2"] [@@sop.node_rest 2]
    [@@sop.node_slots "base, fixed, extras"]

  let build = parameters_build (fun ~label parameters base fixed extras ->
    Sop.merge ~label ~source_attribute:parameters.tag
      (base :: Option.to_list fixed @ extras))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Dynamic_schema_fixture = struct
  type parameters = {
    input : int [@sop.default 0] [@sop.label "Source"]
      [@sop.min 0] [@sop.max 9999] [@sop.hard_min 0];
  } [@@deriving sop_params, sop_node]
    [@@sop.node_key "dynamic_schema_fixture"] [@@sop.node_operation "switch"]
    [@@sop.node_label "Dynamic Schema Fixture"] [@@sop.node_category "Test"]
    [@@sop.node_inputs 1] [@@sop.node_rest 0] [@@sop.node_slots "inputs"]
  let schema _parameters node =
    let labels = List.mapi (fun index node -> Printf.sprintf "%d · %s" index (Node.label node))
      (Node.inputs node) in
    Parameter.schema ~name:"parameters" ~default:parameters_default
      (List.map (fun (Parameter.Field field as original) -> match field.kind with
        | Parameter.Integer _ -> Parameter.Field {field with
            kind=Parameter.index_choice labels}
        | _ -> original) (Parameter.fields parameters_schema))
  let build = parameters_build ~schema (fun ~label parameters inputs ->
    match inputs with
    | a :: b :: rest -> Sop.switch ~label ~input:parameters.input a b rest
    | _ -> invalid_arg "dynamic schema fixture needs two inputs")
  let factory = parameters_factory build
  let fn = parameters_fn build
end
