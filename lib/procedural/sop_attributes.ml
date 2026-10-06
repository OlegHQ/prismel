(* Attribute nodes, declared once: the record is the editor schema, the
   factory and the typed [Sop] constructor. *)

open Sop_support

(* ocamldep must see the PPX's [Procedural.X] resolve inside this library. *)
module Procedural = Sop_support.Procedural

module Uv_flatten = struct
  type parameters = {
    name : string [@sop.default "uv"] [@sop.label "UV attribute"] [@sop.nonblank "empty attribute name"];
    seams : string [@sop.default ""] [@sop.label "Seam group"] [@sop.nonblank "empty seam group name"];
    iterations : int [@sop.default 500] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 2000] [@sop.hard_min 1];
    tolerance : float [@sop.default 1e-7] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.01] [@sop.hard_min 0.];
  } [@@sop.node_key "uv_flatten"] [@@sop.node_label "UV Flatten"]
    [@@sop.node_category "UV/Layout"] [@@sop.node_inputs 1]
    [@@sop.fn "uv_flatten"] [@@sop.args "?name ?seams ?iterations ?tolerance in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let name = parameters.name in
    let seams = optional_text parameters.seams in
    let iterations = parameters.iterations in
    let tolerance = parameters.tolerance in
    Node.Private.make ?label ~operation:"uv_flatten" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match uv_parameterize_seams "uv_flatten" inputs.(0) seams with
        | Error _ as error -> error
        | Ok (edge_seams, seams) ->
            match Rdk.Uv_ops.flatten ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ~name ?seams ?edge_seams
                ~iterations ~tolerance inputs.(0) with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )
  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Uv_relax = struct
  type parameters = {
    name : string [@sop.default "uv"] [@sop.label "UV attribute"] [@sop.nonblank "empty attribute name"];
    seams : string [@sop.default ""] [@sop.label "Seam group"] [@sop.nonblank "empty seam group name"];
    uv_tolerance : float [@sop.default 1e-9] [@sop.label "UV tolerance"]
      [@sop.min 0.] [@sop.max 0.01] [@sop.hard_min 0.];
    iterations : int [@sop.default 500] [@sop.label "Iterations"]
      [@sop.min 1] [@sop.max 2000] [@sop.hard_min 1];
    tolerance : float [@sop.default 1e-7] [@sop.label "Tolerance"]
      [@sop.min 0.] [@sop.max 0.01] [@sop.hard_min 0.];
  } [@@sop.node_key "uv_relax"] [@@sop.node_label "UV Relax"]
    [@@sop.node_category "UV/Layout"] [@@sop.node_inputs 1]
    [@@sop.fn "uv_relax"] [@@sop.args "?name ?seams ?uv_tolerance ?iterations ?tolerance in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let name = parameters.name in
    let seams = optional_text parameters.seams in
    let uv_tolerance = parameters.uv_tolerance in
    let iterations = parameters.iterations in
    let tolerance = parameters.tolerance in
    Node.Private.make ?label ~operation:"uv_relax" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
      ~inputs:[|input|] (fun ~node_id:_ context inputs ->
        match uv_parameterize_seams "uv_relax" inputs.(0) seams with
        | Error _ as error -> error
        | Ok (edge_seams, seams) ->
            match Rdk.Uv_ops.relax ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ~name ?seams ?edge_seams
                ~uv_tolerance ~iterations ~tolerance inputs.(0) with
            | Ok geometry -> cooked geometry
            | Error error -> structured_rdk_error error)
  )
  let factory = parameters_factory build
  let fn = parameters_fn build
end


module Rename_attributes = struct
  let conflict_token = function
    | Rdk.Attribute_ops.Attribute_rename_skip -> "skip"
    | Rdk.Attribute_ops.Attribute_rename_error -> "error"
    | Rdk.Attribute_ops.Attribute_rename_overwrite -> "overwrite"
  let conflict_of_token = function
    | "skip" -> Ok Rdk.Attribute_ops.Attribute_rename_skip
    | "error" -> Ok Rdk.Attribute_ops.Attribute_rename_error
    | "overwrite" -> Ok Rdk.Attribute_ops.Attribute_rename_overwrite
    | token -> Error (Printf.sprintf
        "unknown attribute rename conflict %S" token)
  let encode_rule (rule : Rdk.Attribute_ops.rename_rule) = [
      (match rule.rename_attribute_owner with None -> "any"
       | Some owner -> attribute_owner_token owner);
      rule.rename_attribute_pattern; rule.rename_attribute_replacement;
      conflict_token rule.rename_attribute_conflict;
    ]
  let decode_rule = function
    | [owner; pattern; replacement; conflict] ->
        let owner = String.lowercase_ascii (String.trim owner)
        and conflict = String.lowercase_ascii (String.trim conflict) in
        let owner = if owner = "any" || owner = "*" then Ok None
          else Result.map Option.some (attribute_owner_of_token owner) in
        Result.bind owner (fun rename_attribute_owner ->
          Result.map (fun rename_attribute_conflict -> {
            Rdk.Attribute_ops.rename_attribute_owner;
            rename_attribute_pattern = pattern;
            rename_attribute_replacement = replacement;
            rename_attribute_conflict }) (conflict_of_token conflict))
    | row -> Error (Printf.sprintf
        "Attribute Rename rule needs owner, pattern, replacement, and conflict; got %d columns"
        (List.length row))
  let decode text = Result.bind (decode_table text) (fun rows ->
      List.fold_left (fun result row -> Result.bind result (fun rules ->
        Result.map (fun rule -> rule :: rules) (decode_rule row))) (Ok []) rows
      |> Result.map List.rev)
  let rules_parameter = Parameter.encoded ~equal:( = )
      ~encode:(fun rules -> encode_table (List.map encode_rule rules)) ~decode
  type parameters = {
    rules : Rdk.Attribute_ops.rename_rule list [@sop.default []]
      [@sop.label "Rules (owner, pattern, replacement, conflict)"]
      [@sop.kind rules_parameter];
  } [@@sop.node_key "rename_attributes"]
    [@@sop.node_operation "attribute_rename_pattern"]
    [@@sop.node_label "Rename Attributes"]
    [@@sop.node_category "Attribute/Manage"] [@@sop.node_inputs 1]
    [@@sop.fn "rename_attributes"] [@@sop.args "~rules in0"]
    [@@deriving sop_params, sop_node]
  let build = parameters_build (fun ~label parameters input ->
    let label = Some label in
    let rules = parameters.rules in
    let rules = List.map (fun (rule : Rdk.Attribute_ops.rename_rule) ->
        match Rdk.Attribute_pattern.compile_rewrite
            ~pattern:rule.rename_attribute_pattern
            ~replacement:rule.rename_attribute_replacement with
        | Ok _ -> rule
        | Error message -> invalid_arg ("Sop.rename_attributes: " ^ message))
        rules in
    Node.Private.make ?label ~operation:"attribute_rename_pattern" ~version:1
      ~parameters:""
      ~cook_mode:(Node.Duplicate_input 0)
      ~dependencies:Context.Dependencies.static ~inputs:[|input|]
      (fun ~node_id:_ context inputs ->
        match Rdk.Attribute_ops.rename ~cancel:(Context.cancel_token context)
            ~rules inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_rdk_error error)
  )
  let factory = parameters_factory build
  let fn = parameters_fn build
end

