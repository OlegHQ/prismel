(* Group nodes, declared once: the record is the editor schema, the factory
   and the typed [Sop] constructor. *)

open Rays_math
open Sop_support

(* ocamldep must see the PPX's [Procedural.X] resolve inside this library. *)
module Procedural = Sop_support.Procedural

module Group_non_planar = struct
  type parameters = {
    name : string [@sop.default "nonplanar"] [@sop.label "Group name"] [@sop.nonblank "empty group name"];
    tolerance : float [@sop.default 1e-6] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.1] [@sop.hard_min 0.] [@sop.validate "tolerance must be finite and non-negative"];
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"] [@sop.nonblank "empty base group name"];
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_non_planar"] [@@sop.node_label "Group Non-Planar"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@sop.fn "group_non_planar"] [@@sop.args "?base ?merge ~tolerance ~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let base = optional_text parameters.base in
    let merge = parameters.merge in
    let tolerance = parameters.tolerance in
    let name = parameters.name in
    Node.Private.make ~label ~operation:"group_non_planar" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.group_non_planar ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ?base ~merge ~tolerance ~name inputs.(0)
        with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_backface = struct
  type parameters = {
    name : string [@sop.default "backface"] [@sop.label "Group name"] [@sop.nonblank "empty group name"];
    viewpoint_x : float [@sop.default 0.] [@sop.label "Viewpoint X"]
      [@sop.folder "Viewpoint"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "viewpoint"] [@sop.validate "viewpoint must be finite"]
    viewpoint_y : float [@sop.default 0.] [@sop.label "Viewpoint Y"]
      [@sop.folder "Viewpoint"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "viewpoint"] [@sop.validate "viewpoint must be finite"]
    viewpoint_z : float [@sop.default 10.] [@sop.label "Viewpoint Z"]
      [@sop.folder "Viewpoint"] [@sop.min (-100.)] [@sop.max 100.]; [@sop.vec3 "viewpoint"] [@sop.validate "viewpoint must be finite"]
    base : string [@sop.default ""] [@sop.label "Base group"]
      [@sop.folder "Combine"] [@sop.nonblank "empty base group name"];
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.folder "Combine"] [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_backface"] [@@sop.node_label "Group Backfaces"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@sop.fn "group_backface"] [@@sop.args "?base ?merge ~viewpoint ~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let base = optional_text parameters.base in
    let merge = parameters.merge in
    let viewpoint = Vec3.create parameters.viewpoint_x parameters.viewpoint_y
            parameters.viewpoint_z in
    let name = parameters.name in
    let viewpoint = vec3_copy viewpoint in
    Node.Private.make ~label ~operation:"group_backface" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.group_backface ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ?base ~merge ~viewpoint ~name inputs.(0)
        with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end

module Group_unshared = struct
  type parameters = {
    owner : Rdk.Group_ops.owner [@sop.default Rdk.Group_ops.Group_edges]
      [@sop.label "Group type"] [@sop.kind group_owner_parameter];
    name : string [@sop.default "unshared"] [@sop.label "Group name"] [@sop.nonblank "empty output group name"];
    merge : Rdk.Group_ops.boolean_operation
      [@sop.default Rdk.Group_ops.Group_replace] [@sop.label "Operation"]
      [@sop.kind group_merge_parameter];
  } [@@sop.node_key "group_unshared"] [@@sop.node_label "Group Unshared"]
    [@@sop.node_category "Group/Create"] [@@sop.node_inputs 1]
    [@@sop.fn "group_unshared"] [@@sop.args "?merge ~owner ~name in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let merge = parameters.merge in
    let owner = parameters.owner in
    let name = parameters.name in
    Node.Private.make ~label ~operation:"group_unshared" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match Rdk.Group_ops.group_unshared ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ~merge ~owner ~name inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error))
  let factory = parameters_factory build
  let fn = parameters_fn build
end
