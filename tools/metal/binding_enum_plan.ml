type shard =
  { name : string
  ; family_names : string list
  ; expected_family_count : int
  ; expected_case_count : int
  ; expected_declaration_count : int
  }

let shards =
  [ { name = "stage/device"
    ; family_names = Binding_enum_stage_device.family_names
    ; expected_family_count =
        Binding_enum_stage_device.expected_family_count
    ; expected_case_count = Binding_enum_stage_device.expected_case_count
    ; expected_declaration_count =
        Binding_enum_stage_device.expected_declaration_count
    }
  ; { name = "acceleration/pipeline"
    ; family_names = Binding_enum_acceleration_pipeline.family_names
    ; expected_family_count =
        Binding_enum_acceleration_pipeline.expected_family_count
    ; expected_case_count =
        Binding_enum_acceleration_pipeline.expected_case_count
    ; expected_declaration_count =
        Binding_enum_acceleration_pipeline.expected_declaration_count
    }
  ; { name = "misc"
    ; family_names = Binding_enum_misc.family_names
    ; expected_family_count = Binding_enum_misc.expected_family_count
    ; expected_case_count = Binding_enum_misc.expected_case_count
    ; expected_declaration_count =
        Binding_enum_misc.expected_declaration_count
    }
  ]

let family_names = List.concat_map (fun shard -> shard.family_names) shards
let expected_family_count = 61
let expected_case_count = 326
let expected_declaration_count = 448

let source_paths =
  [ "tools/metal/binding_enum_plan.ml"
  ; "tools/metal/binding_enum_plan.mli"
  ; "tools/metal/binding_enum_stage_device.ml"
  ; "tools/metal/binding_enum_stage_device.mli"
  ; "tools/metal/binding_enum_acceleration_pipeline.ml"
  ; "tools/metal/binding_enum_acceleration_pipeline.mli"
  ; "tools/metal/binding_enum_misc.ml"
  ; "tools/metal/binding_enum_misc.mli"
  ]

let sum field = List.fold_left (fun total shard -> total + field shard) 0 shards

let validate_shard shard =
  if List.length shard.family_names <> shard.expected_family_count then
    invalid_arg ("Metal " ^ shard.name ^ " enum family count drift");
  if
    shard.expected_declaration_count
    <> shard.expected_case_count + (2 * shard.expected_family_count)
  then
    invalid_arg ("Metal " ^ shard.name ^ " enum declaration count drift")

let reject_duplicate_families names =
  let rec loop = function
    | left :: right :: _ when String.equal left right ->
        invalid_arg ("Duplicate Metal enum family name across shards: " ^ left)
    | _ :: rest -> loop rest
    | [] -> ()
  in
  loop (List.sort String.compare names)

let validate () =
  List.iter validate_shard shards;
  if List.exists (fun name -> String.equal name "") family_names then
    invalid_arg "Metal enum family name must not be empty";
  reject_duplicate_families family_names;
  if List.length family_names <> expected_family_count then
    invalid_arg "Metal aggregate enum family count drift";
  if sum (fun shard -> shard.expected_family_count) <> expected_family_count
  then
    invalid_arg "Metal aggregate enum expected-family count drift";
  if sum (fun shard -> shard.expected_case_count) <> expected_case_count then
    invalid_arg "Metal aggregate enum case count drift";
  if
    sum (fun shard -> shard.expected_declaration_count)
    <> expected_declaration_count
  then
    invalid_arg "Metal aggregate enum declaration count drift";
  if
    expected_declaration_count
    <> expected_case_count + (2 * expected_family_count)
  then
    invalid_arg "Metal aggregate enum declaration relationship drift"

let () = validate ()
