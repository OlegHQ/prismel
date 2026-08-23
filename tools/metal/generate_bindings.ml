open Support

module String_map = Map.Make (String)
module String_set = Set.Make (String)

type inventory_declaration =
  { identifier : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; header : string
  ; line : int option
  ; signature : string
  ; attributes : string list
  ; classification : string
  ; constant_value : string option
  ; macos_introduced : Binding_availability.version option
  }

type receiver_spec =
  { owner : string
  ; objc_type : string
  ; handle_kind : string
  ; raw_name : string
  ; local_name : string
  }

type direct_receiver_access =
  | Direct_object of string
  | Helper_object of string
  | Wrapped_object of
      { handle_kind : string
      ; wrapper_type : string
      ; property : string
      }
  | Polymorphic_object of string

type direct_receiver_spec =
  { objc_type : string
  ; raw_name : string
  ; local_name : string
  ; access : direct_receiver_access
  }

let catalog_receiver handle_kind =
  match
    List.find_opt
      (fun (receiver : Binding_receiver_catalog.receiver) ->
        String.equal receiver.handle_kind handle_kind)
      Binding_receiver_catalog.receivers
  with
  | Some receiver -> receiver
  | None -> fail "Metal receiver catalog has no Handle_kind::%s" handle_kind

let receiver_spec = function
  | Binding_plan.Render_encoder4 ->
      let receiver = catalog_receiver "Render_encoder4" in
      { owner = receiver.sdk_owner
      ; objc_type = receiver.objc_receiver_type
      ; handle_kind = receiver.handle_kind
      ; raw_name = "raw_encoder"
      ; local_name = "encoder"
      }
  | Binding_plan.Compute_encoder4 ->
      let receiver = catalog_receiver "Compute_encoder4" in
      { owner = receiver.sdk_owner
      ; objc_type = receiver.objc_receiver_type
      ; handle_kind = receiver.handle_kind
      ; raw_name = "raw_encoder"
      ; local_name = "encoder"
      }
  | Binding_plan.Device ->
      let receiver = catalog_receiver "Device" in
      { owner = receiver.sdk_owner
      ; objc_type = receiver.objc_receiver_type
      ; handle_kind = receiver.handle_kind
      ; raw_name = "raw_device"
      ; local_name = "device"
      }
  | Binding_plan.Compute_pipeline ->
      let receiver = catalog_receiver "Compute_pipeline" in
      { owner = receiver.sdk_owner
      ; objc_type = receiver.objc_receiver_type
      ; handle_kind = receiver.handle_kind
      ; raw_name = "raw_pipeline"
      ; local_name = "pipeline"
      }

let direct_receiver_spec owner =
  let direct =
    Binding_receiver_catalog.receivers
    |> List.filter (fun (receiver : Binding_receiver_catalog.receiver) ->
      String.equal receiver.sdk_owner owner)
  in
  let polymorphic =
    Binding_receiver_catalog.polymorphic_receivers
    |> List.filter
         (fun (receiver : Binding_receiver_catalog.polymorphic_receiver) ->
           String.equal receiver.sdk_owner owner)
  in
  match direct, polymorphic with
  | [ receiver ], [] ->
      let access =
        match receiver.bridge_access with
        | Binding_receiver_catalog.Object_of_handle ->
            Direct_object receiver.handle_kind
        | Binding_receiver_catalog.Object_of_helper helper ->
            Helper_object helper
        | Binding_receiver_catalog.Wrapped_property
            { wrapper_type; property } ->
            Wrapped_object
              { handle_kind = receiver.handle_kind; wrapper_type; property }
      in
      { objc_type = receiver.objc_receiver_type
      ; raw_name = receiver.raw_name
      ; local_name = receiver.local_name
      ; access
      }
  | [], [ receiver ] ->
      { objc_type = receiver.objc_receiver_type
      ; raw_name = receiver.raw_name
      ; local_name = receiver.local_name
      ; access = Polymorphic_object receiver.helper
      }
  | [], [] -> fail "Metal direct-call plan has no receiver for owner %s" owner
  | _ ->
      fail
        "Metal direct-call plan owner %s is ambiguous in the receiver catalog"
        owner

let enum_objc_type = function
  | Binding_plan.Winding -> "MTLWinding"
  | Binding_plan.Cull_mode -> "MTLCullMode"
  | Binding_plan.Depth_clip_mode -> "MTLDepthClipMode"
  | Binding_plan.Triangle_fill_mode -> "MTLTriangleFillMode"

let require_string name value =
  match member_string name value with
  | Some value -> value
  | None -> fail "Metal binding inventory field %s must be a string" name

let require_string_list name value =
  match member_list name value with
  | None -> fail "Metal binding inventory field %s must be a list" name
  | Some values ->
      List.map
        (function
          | `String value -> value
          | _ -> fail "Metal binding inventory field %s must contain strings" name)
        values

let parse_inventory_version identifier = function
  | None -> None
  | Some value ->
      let synthetic = "API_AVAILABLE(macos(" ^ value ^ "))" in
      (match Binding_availability.parse_site synthetic with
       | Ok (Some version)
         when String.equal (Binding_availability.canonical version) value ->
           Some version
       | Ok (Some version) ->
           fail
             "Metal inventory has non-canonical macOS introduction %S for %s (canonical %s)"
             value identifier (Binding_availability.canonical version)
       | Ok None ->
           fail "Metal inventory macOS introduction is absent for %s" identifier
       | Error error ->
           fail
             "Metal inventory has invalid macOS introduction %S for %s at %d: %s"
             value identifier error.offset error.message)

let inventory_declaration value =
  let identifier = require_string "id" value in
  { identifier
  ; kind = require_string "kind" value
  ; name = require_string "name" value
  ; owner = member_string "owner" value
  ; header = require_string "header" value
  ; line = member_int "line" value
  ; signature = require_string "signature" value
  ; attributes = require_string_list "attributes" value
  ; classification = require_string "classification" value
  ; constant_value = member_string "constant_value" value
  ; macos_introduced =
      parse_inventory_version identifier (member_string "macos_introduced" value)
  }

let load_inventory path =
  let value = read_file path |> Yojson.Safe.from_string in
  if member_int "schema" value <> Some 2 then
    fail "Metal binding inventory schema must be 2";
  let sdk_version = require_string "sdk_version" value in
  let inventory_plan_sha256 =
    require_string "binding_plan_source_sha256" value
  in
  if sdk_version <> Binding_plan.expected_sdk_version then
    fail "Metal binding plan requires SDK %s, inventory records SDK %s"
      Binding_plan.expected_sdk_version sdk_version;
  let symbols =
    match member_list "symbols" value with
    | Some values -> values
    | None -> fail "Metal binding inventory has no symbols list"
  in
  let declarations =
    List.fold_left
      (fun declarations value ->
        let declaration = inventory_declaration value in
        if String_map.mem declaration.identifier declarations then
          fail "duplicate Metal inventory identifier: %s" declaration.identifier;
        String_map.add declaration.identifier declaration declarations)
      String_map.empty symbols
  in
  sdk_version, inventory_plan_sha256, declarations

let select_mechanical_enums inventory =
  let declarations =
    inventory
    |> String_map.to_seq
    |> Seq.map (fun (_, declaration) ->
      ({ id = declaration.identifier
       ; kind = declaration.kind
       ; name = declaration.name
       ; owner = declaration.owner
       ; signature = declaration.signature
       ; classification = declaration.classification
       ; constant_value = declaration.constant_value
       ; macos_introduced = declaration.macos_introduced
       }
        : Binding_enum_codegen.declaration))
    |> List.of_seq
  in
  let selection =
    try
      Binding_enum_codegen.select
        ~family_names:Binding_enum_plan.family_names declarations
    with Binding_enum_codegen.Error message ->
      fail "invalid mechanical Metal enum batch: %s" message
  in
  if selection.family_count <> Binding_enum_plan.expected_family_count
     || selection.case_count <> Binding_enum_plan.expected_case_count
     || selection.declaration_count
        <> Binding_enum_plan.expected_declaration_count
  then
    fail
      "mechanical Metal enum batch cardinality drift: expected %d/%d/%d, found %d/%d/%d"
      Binding_enum_plan.expected_family_count
      Binding_enum_plan.expected_case_count
      Binding_enum_plan.expected_declaration_count selection.family_count
      selection.case_count selection.declaration_count;
  selection

let select_implicit_mechanical_enums inventory =
  let declarations =
    inventory |> String_map.to_seq
    |> Seq.map (fun (_, declaration) ->
      ({ id = declaration.identifier
       ; kind = declaration.kind
       ; name = declaration.name
       ; owner = declaration.owner
       ; header = declaration.header
       ; line = declaration.line
       ; signature = declaration.signature
       ; classification = declaration.classification
       ; constant_value = declaration.constant_value
       ; macos_introduced = declaration.macos_introduced
       }
        : Binding_enum_implicit_codegen.declaration))
    |> List.of_seq
  in
  let selection =
    try Binding_enum_implicit_codegen.select declarations with
    | Binding_enum_implicit_codegen.Error message ->
        fail "invalid implicit Metal enum batch: %s" message
  in
  let families = Binding_enum_implicit_codegen.family_count selection in
  let cases = Binding_enum_implicit_codegen.case_count selection in
  let declarations = Binding_enum_implicit_codegen.declaration_count selection in
  if families <> Binding_enum_implicit_plan.expected_family_count
     || cases <> Binding_enum_implicit_plan.expected_case_count
     || declarations <> Binding_enum_implicit_plan.expected_declaration_count
  then
    fail
      "implicit Metal enum batch cardinality drift: expected %d/%d/%d, found %d/%d/%d"
      Binding_enum_implicit_plan.expected_family_count
      Binding_enum_implicit_plan.expected_case_count
      Binding_enum_implicit_plan.expected_declaration_count families cases
      declarations;
  selection

let validate_struct_native_output inventory
    (output : Binding_struct_native_codegen.output) =
  let identifiers = output.method_ids @ output.property_ids in
  if List.length output.method_ids
     <> Binding_struct_native_codegen.expected_method_count
     || List.length output.property_ids
        <> Binding_struct_native_codegen.expected_property_count
     || List.length identifiers <> 27
     || List.length (List.sort_uniq String.compare identifiers) <> 27
  then fail "generated Metal struct-native identifier cardinality drift";
  let selected =
    inventory |> String_map.to_seq
    |> Seq.map (fun (_, declaration) ->
      ({ id = declaration.identifier
       ; kind = declaration.kind
       ; owner = declaration.owner
       ; signature = declaration.signature
       ; classification = declaration.classification
       }
        : Binding_struct_plan.declaration))
    |> List.of_seq |> Binding_struct_plan.select
  in
  let planned =
    selected.declarations
    |> List.fold_left
         (fun ids (declaration : Binding_struct_plan.declaration) ->
           String_set.add declaration.id ids)
         String_set.empty
  in
  let validate kind identifier =
    let declaration =
      match String_map.find_opt identifier inventory with
      | Some declaration -> declaration
      | None -> fail "generated Metal struct-native id is absent: %s" identifier
    in
    if declaration.kind <> kind || declaration.classification <> "unreviewed"
       || not (String_set.mem identifier planned)
    then fail "generated Metal struct-native inventory mismatch: %s" identifier
  in
  List.iter (validate "method") output.method_ids;
  List.iter (validate "property") output.property_ids

let validate_string_entries inventory entries =
  let validate_declaration entry ~identifier ~kind ~signature =
    let declaration =
      match String_map.find_opt identifier inventory with
      | Some declaration -> declaration
      | None -> fail "generated Metal NSString id is absent: %s" identifier
    in
    if declaration.kind <> kind || declaration.owner <> Some entry.Binding_string_spec.owner
       || declaration.header <> entry.header || declaration.signature <> signature
       || declaration.attributes <> entry.attributes
       || declaration.classification <> "unreviewed"
       ||
       (match declaration.macos_introduced with
        | Some version ->
            not (Binding_availability.equal version entry.macos_introduced)
        | None -> true)
    then fail "generated Metal NSString inventory mismatch: %s" identifier
  in
  List.iter
    (fun entry ->
      validate_declaration entry ~identifier:entry.Binding_string_spec.property_sdk_id
        ~kind:"property" ~signature:entry.signature;
      validate_declaration entry ~identifier:entry.getter_sdk_id ~kind:"method"
        ~signature:("instance () -> " ^ entry.signature);
      Option.iter
        (fun identifier ->
          validate_declaration entry ~identifier ~kind:"method"
            ~signature:("instance (" ^ entry.signature ^ ") -> void"))
        entry.setter_sdk_id)
    entries;
  let identifiers = List.concat_map Binding_string_spec.inventory_ids entries in
  if List.length entries <> 3 || List.length identifiers <> 8
     || List.length (List.sort_uniq String.compare identifiers) <> 8
  then fail "generated Metal NSString qualified cardinality drift"

let validate_global_string_entries inventory entries =
  if List.length entries <> Binding_global_string_evidence.bound_count then
    fail "generated Metal global-string cardinality drift";
  let seen = Hashtbl.create (List.length entries) in
  List.iter
    (fun entry ->
      let identifier = entry.Binding_global_string_spec.sdk_id in
      if Hashtbl.mem seen identifier then
        fail "duplicate generated Metal global-string id: %s" identifier;
      Hashtbl.add seen identifier ();
      let declaration =
        match String_map.find_opt identifier inventory with
        | Some declaration -> declaration
        | None -> fail "generated Metal global-string id is absent: %s" identifier
      in
      if declaration.kind <> "variable" || declaration.name <> entry.name
         || declaration.owner <> None || declaration.header <> entry.header
         || declaration.signature <> entry.signature
         || declaration.classification <> "bound"
         ||
         (match declaration.macos_introduced with
          | Some version ->
              not (Binding_availability.equal version entry.macos_introduced)
          | None -> true)
      then fail "generated Metal global-string inventory mismatch: %s" identifier)
    entries

let valid_identifier ~initial value =
  let valid_initial character =
    match initial with
    | `Lower -> character >= 'a' && character <= 'z'
    | `Any_letter ->
        (character >= 'a' && character <= 'z')
        || (character >= 'A' && character <= 'Z')
        || character = '_'
  in
  let valid_tail character =
    (character >= 'a' && character <= 'z')
    || (character >= 'A' && character <= 'Z')
    || (character >= '0' && character <= '9')
    || character = '_'
  in
  String.length value > 0
  && valid_initial value.[0]
  && String.for_all valid_tail value

let validate_identifier description ~initial value =
  if not (valid_identifier ~initial value) then
    fail "invalid %s in Metal binding plan: %S" description value

let selector_pieces selector argument_count =
  let pieces = String.split_on_char ':' selector in
  let pieces =
    if argument_count = 0 then pieces
    else
      match List.rev pieces with
      | "" :: reversed -> List.rev reversed
      | _ ->
          fail "Objective-C selector %s must end in a colon" selector
  in
  let expected_piece_count = if argument_count = 0 then 1 else argument_count in
  if List.length pieces <> expected_piece_count then
    fail "Objective-C selector %s has %d pieces for %d arguments" selector
      (List.length pieces) argument_count;
  List.iter
    (validate_identifier "Objective-C selector piece" ~initial:`Any_letter)
    pieces;
  pieces

let reject_duplicates description values =
  let duplicates =
    values
    |> List.sort String.compare
    |> List.to_seq
    |> Seq.group String.equal
    |> Seq.filter_map (fun group ->
      match List.of_seq group with
      | value :: _ :: _ -> Some value
      | _ -> None)
    |> List.of_seq
  in
  if duplicates <> [] then
    fail "duplicate %s in Metal binding plan: %s" description
      (String.concat ", " duplicates)

let expected_argument_type = function
  | Binding_plan.Enum_int { enum_type; cases = _ } -> enum_objc_type enum_type
  | Binding_plan.Unsigned_int _ -> "NSUInteger"

let validate_enum_cases inventory binding_id enum_type
    (cases : Binding_plan.enum_case list) =
  if cases = [] then fail "Metal binding %s has no enum cases" binding_id;
  reject_duplicates "enum-case SDK identifier"
    (List.map (fun (case : Binding_plan.enum_case) -> case.sdk_id) cases);
  reject_duplicates "enum-case value"
    (List.map (fun (case : Binding_plan.enum_case) ->
       string_of_int case.value)
       cases);
  let owner = enum_objc_type enum_type in
  let planned_identifiers =
    cases |> List.map (fun (case : Binding_plan.enum_case) -> case.sdk_id)
    |> String_set.of_list
  in
  let inventory_identifiers =
    inventory
    |> String_map.to_seq
    |> Seq.map snd
    |> Seq.filter_map (fun declaration ->
      if declaration.kind = "enum-case"
         && declaration.owner = Some owner
      then Some declaration.identifier
      else None)
    |> String_set.of_seq
  in
  if not (String_set.equal planned_identifiers inventory_identifiers) then
    fail "Metal enum-case inventory drift for %s used by %s" owner binding_id;
  List.iter
    (fun (case : Binding_plan.enum_case) ->
      let declaration =
        match String_map.find_opt case.Binding_plan.sdk_id inventory with
        | Some declaration -> declaration
        | None ->
            fail "Metal enum case is absent from the pinned inventory: %s"
              case.sdk_id
      in
      if declaration.kind <> "enum-case"
         || declaration.owner <> Some owner
         || declaration.signature <> owner
      then
        fail "Metal enum-case type drift for %s" case.sdk_id;
      if declaration.constant_value <> Some (string_of_int case.value) then
        fail "Metal enum-case value drift for %s" case.sdk_id;
      if declaration.classification <> "bound" then
        fail "generated Metal enum case must be bound: %s" case.sdk_id)
    cases

let compare_declaration identifier field expected actual =
  if expected <> actual then
    fail "Metal inventory drift for %s (%s): expected %S, found %S" identifier
      field expected actual

let require_declaration inventory identifier =
  match String_map.find_opt identifier inventory with
  | Some declaration -> declaration
  | None ->
      fail "generated Metal identifier is absent from the pinned inventory: %s"
        identifier

let deployment_floor : Binding_availability.version =
  { major = 14; minor = 0; patch = 0 }

let validate_direct_availability identifier planned actual =
  match actual with
  | Some actual when Binding_availability.equal planned actual -> ()
  | Some actual ->
      fail
        "Metal direct-call availability drift for %s: planned %s, inventory %s"
        identifier (Binding_availability.canonical planned)
        (Binding_availability.canonical actual)
  | None when Binding_availability.compare planned deployment_floor <= 0 -> ()
  | None ->
      fail
        "Metal direct-call %s has no pinned introduction but requests post-floor guard %s"
        identifier (Binding_availability.canonical planned)

let expected_direct_signature (entry : Binding_direct_spec.method_entry) =
  let arguments =
    entry.arguments
    |> List.map Binding_direct_spec.scalar_objc_type
    |> String.concat ", "
  in
  let result =
    match entry.result with
    | None -> "void"
    | Some result -> Binding_direct_spec.scalar_objc_type result
  in
  Printf.sprintf "instance (%s) -> %s" arguments result

let validate_direct_method inventory
    (entry : Binding_direct_spec.method_entry) =
  let declaration = require_declaration inventory entry.sdk_id in
  compare_declaration entry.sdk_id "kind" "method" declaration.kind;
  (match declaration.owner with
   | Some owner ->
       compare_declaration entry.sdk_id "owner" entry.owner owner
   | None -> fail "Metal direct-call inventory owner is absent for %s" entry.sdk_id);
  compare_declaration entry.sdk_id "selector" entry.selector declaration.name;
  compare_declaration entry.sdk_id "header" entry.header declaration.header;
  compare_declaration entry.sdk_id "signature" entry.signature
    declaration.signature;
  compare_declaration entry.sdk_id "template-derived signature"
    (expected_direct_signature entry) entry.signature;
  if entry.attributes <> declaration.attributes then
    fail "Metal direct-call inventory attributes drift for %s" entry.sdk_id;
  validate_direct_availability entry.sdk_id entry.macos_introduced
    declaration.macos_introduced;
  let expected_classification =
    if Binding_direct_plan.is_safe_device_identifier entry.sdk_id then "bound"
    else "unreviewed"
  in
  if declaration.classification <> expected_classification then
    fail "generated Metal direct-call classification must be %s, found %s for %s"
      expected_classification declaration.classification entry.sdk_id;
  validate_identifier "direct-call OCaml external" ~initial:`Lower
    entry.ocaml_name;
  validate_identifier "direct-call C primitive" ~initial:`Any_letter
    entry.c_symbol;
  if not (String.starts_with ~prefix:"caml_prismel_metal_" entry.c_symbol)
  then
    fail "generated Metal direct-call C symbol has the wrong namespace: %s"
      entry.c_symbol;
  ignore (selector_pieces entry.selector (List.length entry.arguments));
  if List.length entry.arguments + 1 > 5 then
    fail "generated Metal direct call exceeds native arity five: %s"
      entry.sdk_id;
  ignore (direct_receiver_spec entry.owner);
  (match entry.semantics, entry.result, entry.arguments with
   | Binding_direct_spec.Query, Some _, _ -> ()
   | Binding_direct_spec.Command, None, _ -> ()
   | Binding_direct_spec.Blocking, None, [] -> ()
   | Binding_direct_spec.Process_identity, Some _, [ _ ] -> ()
   | _ -> fail "invalid direct-call semantics/result shape for %s" entry.sdk_id)

let validate_direct_property inventory
    (property : Binding_direct_spec.property_entry) =
  let declaration = require_declaration inventory property.sdk_id in
  compare_declaration property.sdk_id "kind" "property" declaration.kind;
  (match declaration.owner with
   | Some owner ->
       compare_declaration property.sdk_id "owner" property.owner owner
   | None ->
       fail "Metal direct-property inventory owner is absent for %s"
         property.sdk_id);
  compare_declaration property.sdk_id "name" property.name declaration.name;
  compare_declaration property.sdk_id "header" property.header
    declaration.header;
  compare_declaration property.sdk_id "signature" property.signature
    declaration.signature;
  if property.attributes <> declaration.attributes then
    fail "Metal direct-property inventory attributes drift for %s"
      property.sdk_id;
  validate_direct_availability property.sdk_id property.macos_introduced
    declaration.macos_introduced;
  let expected_classification =
    if Binding_direct_plan.is_safe_device_identifier property.sdk_id then "bound"
    else "unreviewed"
  in
  if declaration.classification <> expected_classification then
    fail "generated Metal direct-property classification must be %s, found %s for %s"
      expected_classification declaration.classification property.sdk_id;
  let getter = property.getter in
  if getter.owner <> property.owner || getter.header <> property.header then
    fail "Metal direct-property getter ownership drift for %s" property.sdk_id;
  (match getter.result with
   | Some result ->
       compare_declaration property.sdk_id "getter result representation"
         property.signature (Binding_direct_spec.scalar_objc_type result)
   | None -> fail "Metal direct property has a void getter: %s" property.sdk_id);
  validate_direct_method inventory getter;
  match property.setter with
  | None -> ()
  | Some setter ->
      if setter.owner <> property.owner || setter.header <> property.header then
        fail "Metal direct-property setter ownership drift for %s"
          property.sdk_id;
      (match setter.arguments, setter.result with
       | [ argument ], None ->
           compare_declaration property.sdk_id "setter argument representation"
             property.signature (Binding_direct_spec.scalar_objc_type argument)
       | _ ->
           fail "Metal direct property has an invalid setter: %s"
             property.sdk_id);
      validate_direct_method inventory setter

let validate_companion inventory safe_api (companion : Binding_plan.companion) =
  let declaration = require_declaration inventory companion.sdk_id in
  let compare field expected actual =
    compare_declaration companion.sdk_id field expected actual
  in
  compare "kind" companion.kind declaration.kind;
  (match declaration.owner with
   | Some owner -> compare "owner" companion.owner owner
   | None ->
       fail "Metal inventory drift for %s: owner is absent" companion.sdk_id);
  compare "name" companion.name declaration.name;
  compare "header" companion.header declaration.header;
  compare "signature" companion.signature declaration.signature;
  if companion.attributes <> declaration.attributes then
    fail "Metal inventory drift for %s (attributes)" companion.sdk_id;
  match safe_api with
  | Some _ when declaration.classification <> "bound" ->
      fail "safe generated Metal companion must be bound, found %s for %s"
        declaration.classification companion.sdk_id
  | None when declaration.classification = "bound" ->
      fail "generated Metal companion lacks safe-API evidence: %s"
        companion.sdk_id
  | Some _ | None -> ()

let generation_identity = function
  | Binding_plan.Direct_void binding ->
      binding.ocaml_name, binding.c_symbol, binding.receiver
  | Binding_plan.Direct_getter binding ->
      binding.ocaml_name, binding.c_symbol, binding.receiver

let generated_identity entry =
  match entry.Binding_plan.disposition with
  | Binding_plan.Generate generation -> generation_identity generation
  | Binding_plan.Manual | Binding_plan.Exclude _ | Binding_plan.Pending ->
      fail "internal error: non-generated Metal binding %s" entry.sdk_id

let generated_ocaml_name entry =
  let ocaml_name, _, _ = generated_identity entry in
  ocaml_name

let generated_c_symbol entry =
  let _, c_symbol, _ = generated_identity entry in
  c_symbol

let validate_binding_identity entry generation =
  let ocaml_name, c_symbol, receiver_kind = generation_identity generation in
  validate_identifier "OCaml external name" ~initial:`Lower ocaml_name;
  validate_identifier "C primitive symbol" ~initial:`Any_letter c_symbol;
  if not (String.starts_with ~prefix:"caml_prismel_metal_" c_symbol) then
    fail "generated Metal C symbol has the wrong namespace: %s" c_symbol;
  let receiver = receiver_spec receiver_kind in
  compare_declaration entry.Binding_plan.sdk_id "generated receiver owner"
    entry.expect.owner receiver.owner;
  receiver

let validate_entry inventory entry =
  let declaration = require_declaration inventory entry.Binding_plan.sdk_id in
  let expect = entry.expect in
  let compare field expected actual =
    compare_declaration entry.sdk_id field expected actual
  in
  compare "kind" expect.kind declaration.kind;
  (match declaration.owner with
   | Some owner -> compare "owner" expect.owner owner
   | None -> fail "Metal inventory drift for %s: owner is absent" entry.sdk_id);
  compare "name" expect.name declaration.name;
  compare "header" expect.header declaration.header;
  compare "signature" expect.signature declaration.signature;
  if expect.attributes <> declaration.attributes then
    fail "Metal inventory drift for %s (attributes)" entry.sdk_id;
  (match entry.safe_api with
   | Some _ when declaration.classification <> "bound" ->
       fail "safe generated Metal identifier must be bound, found %s for %s"
         declaration.classification entry.sdk_id
   | None when declaration.classification = "bound" ->
       fail "generated Metal identifier lacks safe-API evidence: %s" entry.sdk_id
   | Some _ | None -> ());
  List.iter (validate_companion inventory entry.safe_api) entry.companions;
  let availability = expect.availability in
  if availability.macos_major <= 0 || availability.macos_minor < 0 then
    fail "invalid macOS availability for Metal binding %s" entry.sdk_id;
  if availability.unavailable_error = "" then
    fail "empty availability error for Metal binding %s" entry.sdk_id;
  validate_direct_availability entry.sdk_id
    { Binding_availability.major = availability.macos_major
    ; minor = availability.macos_minor
    ; patch = 0
    }
    declaration.macos_introduced;
  match entry.disposition with
  | Binding_plan.Generate (Binding_plan.Direct_void binding as generation) ->
      ignore (validate_binding_identity entry generation);
      let argument_count = List.length binding.arguments in
      ignore (selector_pieces expect.name argument_count);
      if argument_count + 1 > 5 then
        fail "generated Metal primitive %s exceeds native arity five"
          binding.ocaml_name;
      let argument_names =
        List.map
          (fun (argument : Binding_plan.argument) ->
            validate_identifier "native argument name" ~initial:`Lower
              argument.Binding_plan.name;
            if argument.error = "" then
              fail "generated Metal argument %s has an empty validation error"
                argument.name;
            (match argument.kind with
             | Binding_plan.Enum_int { enum_type; cases } ->
                 validate_enum_cases inventory entry.sdk_id enum_type cases
             | Binding_plan.Unsigned_int { minimum; multiple_of } ->
                 if minimum < 0 then
                   fail
                     "generated Metal unsigned argument %s has a negative minimum"
                     argument.name;
                 (match multiple_of with
                  | Some divisor when divisor <= 0 ->
                      fail
                        "generated Metal unsigned argument %s has a nonpositive multiple"
                        argument.name
                  | None | Some _ -> ()));
            argument.name)
          binding.arguments
      in
      let unique_argument_names = List.sort_uniq String.compare argument_names in
      if List.length unique_argument_names <> List.length argument_names then
        fail "generated Metal primitive %s has duplicate argument names"
          binding.ocaml_name;
      let expected_signature =
        Printf.sprintf "instance (%s) -> void"
          (binding.arguments
           |> List.map (fun (argument : Binding_plan.argument) ->
             expected_argument_type argument.kind)
           |> String.concat ", ")
      in
      compare "template-derived signature" expected_signature expect.signature
  | Binding_plan.Generate (Binding_plan.Direct_getter binding as generation) ->
      ignore (validate_binding_identity entry generation);
      ignore (selector_pieces expect.name 0);
      (match binding.result with
       | Binding_plan.Nsuint_to_checked_int64 { overflow_error } ->
           if overflow_error = "" then
             fail "generated Metal getter %s has an empty overflow error"
               binding.ocaml_name;
           compare "template-derived signature" "instance () -> NSUInteger"
             expect.signature)
  | Binding_plan.Manual | Binding_plan.Exclude _ | Binding_plan.Pending ->
      fail "non-generated disposition reached the Metal generator for %s"
        entry.sdk_id

let identifier_start character =
  (character >= 'a' && character <= 'z')
  || (character >= 'A' && character <= 'Z')
  || character = '_'

let identifier_tail character =
  identifier_start character || (character >= '0' && character <= '9')

let skip_quoted source quote start =
  let length = String.length source in
  let rec loop index =
    if index >= length then length
    else if source.[index] = '\\' then loop (min length (index + 2))
    else if source.[index] = quote then index + 1
    else loop (index + 1)
  in
  loop start

let c_identifiers source =
  let length = String.length source in
  let rec skip_line index =
    if index >= length || source.[index] = '\n' then index
    else skip_line (index + 1)
  in
  let rec skip_block index =
    if index + 1 >= length then length
    else if source.[index] = '*' && source.[index + 1] = '/' then index + 2
    else skip_block (index + 1)
  in
  let rec identifier_end index =
    if index < length && identifier_tail source.[index] then
      identifier_end (index + 1)
    else index
  in
  let rec collect index identifiers =
    if index >= length then identifiers
    else if index + 1 < length && source.[index] = '/'
            && source.[index + 1] = '/'
    then collect (skip_line (index + 2)) identifiers
    else if index + 1 < length && source.[index] = '/'
            && source.[index + 1] = '*'
    then collect (skip_block (index + 2)) identifiers
    else if source.[index] = '"' then
      collect (skip_quoted source source.[index] (index + 1)) identifiers
    else if source.[index] = '\''
            && not
                 (index > 0 && index + 1 < length
                 && source.[index - 1] >= '0' && source.[index - 1] <= '9'
                 && source.[index + 1] >= '0' && source.[index + 1] <= '9')
    then collect (skip_quoted source '\'' (index + 1)) identifiers
    else if identifier_start source.[index] then
      let ending = identifier_end (index + 1) in
      let identifier = String.sub source index (ending - index) in
      collect ending (String_set.add identifier identifiers)
    else collect (index + 1) identifiers
  in
  collect 0 String_set.empty

type ocaml_tokens =
  { identifiers : String_set.t
  ; strings : String_set.t
  }

let ocaml_tokens source =
  let length = String.length source in
  let rec skip_comment depth index =
    if index >= length then length
    else if index + 1 < length && source.[index] = '('
            && source.[index + 1] = '*'
    then skip_comment (depth + 1) (index + 2)
    else if index + 1 < length && source.[index] = '*'
            && source.[index + 1] = ')'
    then if depth = 1 then index + 2 else skip_comment (depth - 1) (index + 2)
    else skip_comment depth (index + 1)
  in
  let rec identifier_end index =
    if index < length
       && (identifier_tail source.[index] || source.[index] = '\'')
    then identifier_end (index + 1)
    else index
  in
  let read_string start =
    let output = Buffer.create 64 in
    let rec loop index escaped =
      if index >= length then None, length
      else
        match source.[index] with
        | '"' ->
            (if escaped then None else Some (Buffer.contents output)), index + 1
        | '\\' ->
            if index + 1 >= length then None, length
            else begin
              Buffer.add_char output source.[index];
              Buffer.add_char output source.[index + 1];
              loop (index + 2) true
            end
        | character ->
            Buffer.add_char output character;
            loop (index + 1) escaped
    in
    loop start false
  in
  let rec collect index tokens =
    if index >= length then tokens
    else if index + 1 < length && source.[index] = '('
            && source.[index + 1] = '*'
    then collect (skip_comment 1 (index + 2)) tokens
    else if source.[index] = '"' then
      let literal, ending = read_string (index + 1) in
      let strings =
        match literal with
        | Some literal -> String_set.add literal tokens.strings
        | None -> tokens.strings
      in
      collect ending { tokens with strings }
    else if identifier_start source.[index] then
      let ending = identifier_end (index + 1) in
      let identifier = String.sub source index (ending - index) in
      collect ending
        { tokens with
          identifiers = String_set.add identifier tokens.identifiers
        }
    else collect (index + 1) tokens
  in
  collect 0 { identifiers = String_set.empty; strings = String_set.empty }

let parse_implementation description source =
  let lexbuf = Lexing.from_string source in
  Location.init lexbuf description;
  try Parse.implementation lexbuf with
  | exception_value ->
      fail "cannot parse %s for Metal safe-API evidence: %s" description
        (Printexc.to_string exception_value)

let rec longident_path = function
  | Longident.Lident name -> Some [ name ]
  | Longident.Ldot (prefix, name) ->
      Option.map (fun path -> path @ [ name ]) (longident_path prefix)
  | Longident.Lapply _ -> None

let expression_calls path expression =
  let found = ref false in
  let expr iterator expression =
    (match expression.Parsetree.pexp_desc with
     | Parsetree.Pexp_apply
         ({ pexp_desc = Pexp_ident identifier; _ }, _)
       when longident_path identifier.txt = Some path -> found := true
     | _ -> ());
    Ast_iterator.default_iterator.expr iterator expression
  in
  let iterator = { Ast_iterator.default_iterator with expr } in
  iterator.expr iterator expression;
  !found

let rec module_structure = function
  | { Parsetree.pmod_desc = Pmod_structure structure; _ } -> Some structure
  | { pmod_desc = Pmod_constraint (expression, _); _ } ->
      module_structure expression
  | _ -> None

let descend_module name structure =
  List.find_map
    (fun item ->
      match item.Parsetree.pstr_desc with
      | Parsetree.Pstr_module binding when binding.pmb_name.txt = Some name ->
          module_structure binding.pmb_expr
      | _ -> None)
    structure

let rec find_module_path path structure =
  match path with
  | [] -> Some structure
  | name :: rest ->
      Option.bind (descend_module name structure)
        (find_module_path rest)

let rec pattern_name pattern =
  match pattern.Parsetree.ppat_desc with
  | Parsetree.Ppat_var name -> Some name.txt
  | Parsetree.Ppat_constraint (pattern, _)
  | Parsetree.Ppat_alias (pattern, _) -> pattern_name pattern
  | _ -> None

let value_expression name structure =
  let expressions =
    structure
    |> List.concat_map (fun item ->
      match item.Parsetree.pstr_desc with
      | Parsetree.Pstr_value (_, bindings) ->
          List.filter_map
            (fun binding ->
              if pattern_name binding.Parsetree.pvb_pat = Some name then
                Some binding.pvb_expr
              else None)
            bindings
      | _ -> [])
  in
  match expressions with
  | [ expression ] -> Some expression
  | [] -> None
  | _ -> fail "duplicate safe-evidence OCaml value binding: %s" name

let rec is_function_expression expression =
  match expression.Parsetree.pexp_desc with
  | Parsetree.Pexp_function _ -> true
  | Parsetree.Pexp_constraint (expression, _)
  | Parsetree.Pexp_coerce (expression, _, _)
  | Parsetree.Pexp_poly (expression, _) -> is_function_expression expression
  | _ -> false

let function_execution_expressions expression =
  let rec descend expression =
    match expression.Parsetree.pexp_desc with
    | Parsetree.Pexp_function
        (_, _, Parsetree.Pfunction_body expression) -> descend expression
    | Parsetree.Pexp_function
        (_, _, Parsetree.Pfunction_cases (cases, _, _)) ->
        List.concat_map
          (fun case -> Option.to_list case.Parsetree.pc_guard @ [ case.pc_rhs ])
          cases
    | Parsetree.Pexp_constraint (expression, _)
    | Parsetree.Pexp_coerce (expression, _, _)
    | Parsetree.Pexp_poly (expression, _) -> descend expression
    | _ -> [ expression ]
  in
  descend expression

let direct_local_calls expressions =
  let calls = ref String_set.empty in
  let expr iterator expression =
    match expression.Parsetree.pexp_desc with
    | Parsetree.Pexp_function _ | Parsetree.Pexp_lazy _ -> ()
    | Parsetree.Pexp_apply
        ({ pexp_desc = Pexp_ident identifier; _ }, _arguments) ->
        (match identifier.txt with
         | Longident.Lident name -> calls := String_set.add name !calls
         | Longident.Ldot _ | Longident.Lapply _ -> ());
        Ast_iterator.default_iterator.expr iterator expression
    | _ -> Ast_iterator.default_iterator.expr iterator expression
  in
  let iterator = { Ast_iterator.default_iterator with expr } in
  List.iter (iterator.expr iterator) expressions;
  !calls

let reachable_top_level_values structure =
  let bindings =
    List.fold_left
      (fun bindings item ->
        match item.Parsetree.pstr_desc with
        | Parsetree.Pstr_value (_, value_bindings) ->
            List.fold_left
              (fun bindings binding ->
                match pattern_name binding.Parsetree.pvb_pat with
                | None -> bindings
                | Some name ->
                    String_map.update name
                      (function
                        | None -> Some [ binding.pvb_expr ]
                        | Some expressions ->
                            Some (binding.pvb_expr :: expressions))
                      bindings)
              bindings value_bindings
        | _ -> bindings)
      String_map.empty structure
  in
  let graph =
    String_map.map
      (fun expressions ->
        expressions
        |> List.concat_map function_execution_expressions
        |> direct_local_calls)
      bindings
  in
  let roots =
    structure
    |> List.concat_map (fun item ->
      match item.Parsetree.pstr_desc with
      | Parsetree.Pstr_eval (expression, _) -> [ expression ]
      | Parsetree.Pstr_value (_, value_bindings) ->
          List.filter_map
            (fun binding ->
              match pattern_name binding.Parsetree.pvb_pat with
              | None -> Some binding.pvb_expr
              | Some _ when not (is_function_expression binding.pvb_expr) ->
                  Some binding.pvb_expr
              | Some _ -> None)
            value_bindings
      | _ -> [])
    |> direct_local_calls
  in
  let rec visit reachable pending =
    match pending with
    | [] -> reachable
    | name :: rest when String_set.mem name reachable -> visit reachable rest
    | name :: rest ->
        let reachable = String_set.add name reachable in
        let successors =
          match String_map.find_opt name graph with
          | None -> []
          | Some successors -> String_set.elements successors
        in
        visit reachable (successors @ rest)
  in
  visit String_set.empty (String_set.elements roots)

let validate_safe_api safe_structure test_structure reachable_test_values entry =
  match entry.Binding_plan.safe_api with
  | None -> ()
  | Some evidence ->
      let ocaml_name = generated_ocaml_name entry in
      if evidence.operation = "" || evidence.module_path = []
         || evidence.value_name = "" || evidence.test_value = ""
         || evidence.test_call = []
      then
        fail "empty safe-API evidence for generated Metal binding %s" entry.sdk_id;
      let expected_operation =
        String.concat "."
          ("Metal" :: evidence.module_path @ [ evidence.value_name ])
      in
      if evidence.operation <> expected_operation then
        fail "safe Metal operation path drift for generated binding %s"
          entry.sdk_id;
      let safe_module =
        match find_module_path evidence.module_path safe_structure with
        | Some structure -> structure
        | None ->
            fail "safe Metal module is absent for generated binding %s"
              entry.sdk_id
      in
      let safe_expression =
        match value_expression evidence.value_name safe_module with
        | Some expression -> expression
        | None ->
            fail "safe Metal operation is absent for generated binding %s"
              entry.sdk_id
      in
      if not
           (expression_calls [ "Metal_raw"; ocaml_name ] safe_expression)
      then
        fail "safe Metal operation does not call generated raw binding %s"
          entry.sdk_id;
      let test_expression =
        match value_expression evidence.test_value test_structure with
        | Some expression -> expression
        | None ->
            fail "conformance function is absent for generated Metal binding %s"
              entry.sdk_id
      in
      if not (expression_calls evidence.test_call test_expression) then
        fail "conformance function does not call generated Metal operation %s"
          entry.sdk_id;
      if not (String_set.mem evidence.test_value reachable_test_values) then
        fail
          "conformance function is not reachable from an executable top-level runner for generated Metal binding %s"
          entry.sdk_id

let validate_direct_safe_device safe_structure test_structure
    reachable_test_values =
  let operation = "Metal.Device.capabilities" in
  let safe_expression =
    match find_module_path [ "Device" ] safe_structure with
    | None -> fail "safe Metal Device module is absent for direct capability bindings"
    | Some structure ->
        (match value_expression "capabilities" structure with
        | Some expression -> expression
        | None -> fail "safe Metal operation is absent: %s" operation)
  in
  List.iter
    (fun (property : Binding_direct_spec.property_entry) ->
      if not
           (expression_calls [ "Metal_raw"; property.getter.ocaml_name ]
              safe_expression)
      then
        fail "safe %s does not call generated raw getter for %s" operation
          property.sdk_id)
    Binding_direct_plan.safe_device_properties;
  let test_value = "test_generated_device_capabilities" in
  let test_expression =
    match value_expression test_value test_structure with
    | Some expression -> expression
    | None -> fail "direct Device capability conformance function is absent"
  in
  if not (expression_calls [ "Device"; "capabilities" ] test_expression) then
    fail "direct Device capability conformance does not call %s" operation;
  if not (String_set.mem test_value reachable_test_values) then
    fail "direct Device capability conformance is not reachable from the runner"

let validate_plan inventory manual_native manual_raw_ml manual_raw_mli safe_source
    safe_tests =
  let entries = Binding_plan.generated_entries in
  if entries = [] then fail "Metal binding plan has no generated entries";
  reject_duplicates "SDK identifier"
    (Binding_plan.entries
     |> List.concat_map (fun entry ->
       entry.Binding_plan.sdk_id
       :: List.map
            (fun (companion : Binding_plan.companion) -> companion.sdk_id)
            entry.companions));
  reject_duplicates "generated OCaml name"
    (List.map generated_ocaml_name entries);
  reject_duplicates "generated C symbol"
    (List.map generated_c_symbol entries);
  List.iter (validate_entry inventory) entries;
  let safe_structure = parse_implementation "Metal safe source" safe_source in
  let test_structure = parse_implementation "Metal conformance tests" safe_tests in
  let reachable_test_values = reachable_top_level_values test_structure in
  List.iter
    (validate_safe_api safe_structure test_structure reachable_test_values)
    entries;
  validate_direct_safe_device safe_structure test_structure reachable_test_values;
  let manual_native_identifiers = c_identifiers manual_native in
  let manual_raw_tokens =
    let ml = ocaml_tokens manual_raw_ml in
    let mli = ocaml_tokens manual_raw_mli in
    { identifiers = String_set.union ml.identifiers mli.identifiers
    ; strings = String_set.union ml.strings mli.strings
    }
  in
  List.iter
    (fun entry ->
      let ocaml_name = generated_ocaml_name entry in
      let c_symbol = generated_c_symbol entry in
      if String_set.mem c_symbol manual_native_identifiers then
        fail "generated C symbol still exists in the handwritten bridge: %s"
          c_symbol;
      if String_set.mem ocaml_name manual_raw_tokens.identifiers then
        fail "generated OCaml external still exists in handwritten Metal_raw: %s"
          ocaml_name;
      if String_set.mem c_symbol manual_raw_tokens.strings then
        fail "generated C primitive still exists in handwritten Metal_raw: %s"
          c_symbol)
    entries;
  List.sort
    (fun left right -> String.compare left.Binding_plan.sdk_id right.sdk_id)
    entries

let validate_direct_plan inventory manual_native manual_raw_ml manual_raw_mli
    legacy_entries =
  Binding_direct_plan.validate ();
  let methods = Binding_direct_plan.methods in
  let properties = Binding_direct_plan.properties in
  if methods = [] || properties = [] then
    fail "Metal direct-call plan must contain methods and properties";
  let direct_inventory_ids =
    List.map (fun (entry : Binding_direct_spec.method_entry) -> entry.sdk_id)
      methods
    @ List.map
        (fun (entry : Binding_direct_spec.property_entry) -> entry.sdk_id)
        properties
  in
  reject_duplicates "direct-call inventory identifier" direct_inventory_ids;
  let legacy_inventory_ids =
    Binding_plan.entries
    |> List.concat_map (fun entry ->
      entry.Binding_plan.sdk_id
      :: List.map
           (fun (companion : Binding_plan.companion) -> companion.sdk_id)
           entry.companions)
  in
  reject_duplicates "legacy/direct-call inventory identifier"
    (legacy_inventory_ids @ direct_inventory_ids);
  reject_duplicates "direct-call generated OCaml name"
    (List.map
       (fun (entry : Binding_direct_spec.method_entry) -> entry.ocaml_name)
       methods);
  reject_duplicates "direct-call generated C symbol"
    (List.map
       (fun (entry : Binding_direct_spec.method_entry) -> entry.c_symbol)
       methods);
  reject_duplicates "all generated OCaml name"
    (List.map generated_ocaml_name legacy_entries
    @ List.map
        (fun (entry : Binding_direct_spec.method_entry) -> entry.ocaml_name)
        methods);
  reject_duplicates "all generated C symbol"
    (List.map generated_c_symbol legacy_entries
    @ List.map
        (fun (entry : Binding_direct_spec.method_entry) -> entry.c_symbol)
        methods);
  List.iter (validate_direct_method inventory) methods;
  List.iter (validate_direct_property inventory) properties;
  let manual_native_identifiers = c_identifiers manual_native in
  let manual_raw_tokens =
    let ml = ocaml_tokens manual_raw_ml in
    let mli = ocaml_tokens manual_raw_mli in
    { identifiers = String_set.union ml.identifiers mli.identifiers
    ; strings = String_set.union ml.strings mli.strings
    }
  in
  List.iter
    (fun (entry : Binding_direct_spec.method_entry) ->
      if String_set.mem entry.c_symbol manual_native_identifiers then
        fail
          "generated direct-call C symbol still exists in the handwritten bridge: %s"
          entry.c_symbol;
      if String_set.mem entry.ocaml_name manual_raw_tokens.identifiers then
        fail
          "generated direct-call OCaml external still exists in handwritten Metal_raw: %s"
          entry.ocaml_name;
      if String_set.mem entry.c_symbol manual_raw_tokens.strings then
        fail
          "generated direct-call C primitive still exists in handwritten Metal_raw: %s"
          entry.c_symbol)
    methods;
  let methods =
    List.sort
      (fun (left : Binding_direct_spec.method_entry) right ->
        String.compare left.sdk_id right.sdk_id)
      methods
  in
  let properties =
    List.sort
      (fun (left : Binding_direct_spec.property_entry) right ->
        String.compare left.sdk_id right.sdk_id)
      properties
  in
  methods, properties

let generated_header ~plan_sha256 ~inventory_sha256 =
  Printf.sprintf
    "Generated by tools/metal/generate_bindings.ml.\nPlan SHA-256: %s\nInventory SHA-256: %s\nDo not edit."
    plan_sha256 inventory_sha256

let raw_type = function
  | Binding_plan.Enum_int _ -> "int"
  | Binding_plan.Unsigned_int _ -> "int"

let add_raw_external output entry =
  let ocaml_name, c_symbol, _ = generated_identity entry in
  let arguments =
    match entry.Binding_plan.disposition with
    | Binding_plan.Generate (Binding_plan.Direct_void binding) ->
        "Types.handle"
        :: List.map
             (fun (argument : Binding_plan.argument) -> raw_type argument.kind)
             binding.arguments
        @ [ "(unit, string) result" ]
    | Binding_plan.Generate (Binding_plan.Direct_getter binding) ->
        let result_type =
          match binding.result with
          | Binding_plan.Nsuint_to_checked_int64 _ -> "int64"
        in
        [ "Types.handle"; Printf.sprintf "(%s, string) result" result_type ]
    | Binding_plan.Manual | Binding_plan.Exclude _ | Binding_plan.Pending ->
        fail "internal error: non-generated Metal binding %s" entry.sdk_id
  in
  Buffer.add_string output "  external ";
  Buffer.add_string output ocaml_name;
  Buffer.add_string output " :\n    ";
  Buffer.add_string output (String.concat " -> " arguments);
  Buffer.add_string output " =\n    ";
  Buffer.add_string output (Printf.sprintf "%S\n\n" c_symbol)

let add_direct_raw_external output
    (entry : Binding_direct_spec.method_entry) =
  let result_type =
    match entry.result with
    | None -> "unit"
    | Some result -> Binding_direct_spec.scalar_ocaml_type result
  in
  let arguments =
    "Types.handle"
    :: List.map Binding_direct_spec.scalar_ocaml_type entry.arguments
    @ [ Printf.sprintf "(%s, string) result" result_type ]
  in
  Buffer.add_string output "  external ";
  Buffer.add_string output entry.ocaml_name;
  Buffer.add_string output " :\n    ";
  Buffer.add_string output (String.concat " -> " arguments);
  Buffer.add_string output " =\n    ";
  Buffer.add_string output (Printf.sprintf "%S\n\n" entry.c_symbol)

let raw_ml ~header ~enum_selection ~implicit_enum_selection ~struct_output
    ~string_entries ~global_string_entries ~direct_methods entries =
  let output = Buffer.create 4096 in
  Printf.bprintf output "(* %s *)\n\n" header;
  Buffer.add_string output "module Make (Types : sig\n  type handle\nend) = struct\n";
  Buffer.add_string output
    (Binding_enum_codegen.render_raw_ml enum_selection);
  Buffer.add_char output '\n';
  Buffer.add_string output
    (Binding_enum_implicit_codegen.render_raw_ml implicit_enum_selection);
  Buffer.add_char output '\n';
  Buffer.add_string output struct_output.Binding_struct_native_codegen.raw_ml;
  Buffer.add_char output '\n';
  Buffer.add_string output
    (Binding_string_codegen.render_raw_body string_entries);
  Buffer.add_char output '\n';
  Buffer.add_string output
    (Binding_global_string_codegen.render_raw_ml global_string_entries);
  Buffer.add_char output '\n';
  List.iter (add_raw_external output) entries;
  List.iter (add_direct_raw_external output) direct_methods;
  Buffer.add_string output "end\n";
  Buffer.contents output

let raw_mli ~header ~enum_selection ~implicit_enum_selection ~struct_output
    ~string_entries ~global_string_entries ~direct_methods entries =
  let output = Buffer.create 4096 in
  Printf.bprintf output "(* %s *)\n\n" header;
  Buffer.add_string output
    "module Make (Types : sig\n  type handle\nend) : sig\n";
  Buffer.add_string output
    (Binding_enum_codegen.render_raw_mli enum_selection);
  Buffer.add_char output '\n';
  Buffer.add_string output
    (Binding_enum_implicit_codegen.render_raw_mli implicit_enum_selection);
  Buffer.add_char output '\n';
  Buffer.add_string output struct_output.Binding_struct_native_codegen.raw_mli;
  Buffer.add_char output '\n';
  Buffer.add_string output
    (Binding_string_codegen.render_raw_body string_entries);
  Buffer.add_char output '\n';
  Buffer.add_string output
    (Binding_global_string_codegen.render_raw_mli global_string_entries);
  Buffer.add_char output '\n';
  List.iter (add_raw_external output) entries;
  List.iter (add_direct_raw_external output) direct_methods;
  Buffer.add_string output "end\n";
  Buffer.contents output

let c_string value =
  let output = Buffer.create (String.length value + 2) in
  Buffer.add_char output '"';
  String.iter
    (function
      | '"' -> Buffer.add_string output "\\\""
      | '\\' -> Buffer.add_string output "\\\\"
      | '\n' -> Buffer.add_string output "\\n"
      | '\r' -> Buffer.add_string output "\\r"
      | '\t' -> Buffer.add_string output "\\t"
      | '\000' -> fail "NUL byte in generated Metal C string"
      | character -> Buffer.add_char output character)
    value;
  Buffer.add_char output '"';
  Buffer.contents output

let validation_condition name (cases : Binding_plan.enum_case list) =
  let values =
    cases |> List.map (fun (case : Binding_plan.enum_case) -> case.value)
    |> List.sort Int.compare
  in
  let rec consecutive = function
    | [] | [ _ ] -> true
    | left :: (right :: _ as rest) ->
        right = left + 1 && consecutive rest
  in
  match values with
  | minimum :: _ when consecutive values ->
      let maximum = List.hd (List.rev values) in
      Printf.sprintf "%s < %d || %s > %d" name minimum name maximum
  | _ ->
      values
      |> List.map (fun value -> Printf.sprintf "%s != %d" name value)
      |> String.concat " && "

let argument_conversion output (argument : Binding_plan.argument) =
  match argument.Binding_plan.kind with
  | Binding_plan.Enum_int { cases; _ } ->
      Printf.bprintf output "        const intnat %s = Long_val(raw_%s);\n"
        argument.name argument.name;
      Printf.bprintf output "        if (%s) {\n"
        (validation_condition argument.name cases);
      Printf.bprintf output "          CAMLreturn(result_error_text(%s));\n"
        (c_string argument.error);
      Buffer.add_string output "        }\n"
  | Binding_plan.Unsigned_int { minimum; multiple_of } ->
      Printf.bprintf output "        const intnat %s = Long_val(raw_%s);\n"
        argument.name argument.name;
      let conditions =
        (if minimum = 0 then [ Printf.sprintf "%s < 0" argument.name ]
         else [ Printf.sprintf "%s < %d" argument.name minimum ])
        @
        match multiple_of with
        | None -> []
        | Some divisor ->
            [ Printf.sprintf "%s %% %d != 0" argument.name divisor ]
      in
      Printf.bprintf output "        if (%s) {\n"
        (String.concat " || " conditions);
      Printf.bprintf output "          CAMLreturn(result_error_text(%s));\n"
        (c_string argument.error);
      Buffer.add_string output "        }\n"

let argument_expression (argument : Binding_plan.argument) =
  match argument.Binding_plan.kind with
  | Binding_plan.Enum_int { enum_type; _ } ->
      Printf.sprintf "static_cast<%s>(%s)" (enum_objc_type enum_type)
        argument.name
  | Binding_plan.Unsigned_int _ ->
      Printf.sprintf "static_cast<NSUInteger>(%s)" argument.name

let objc_call (receiver : receiver_spec) selector arguments =
  match arguments with
  | [] -> Printf.sprintf "[%s %s]" receiver.local_name selector
  | _ ->
      let pieces = selector_pieces selector (List.length arguments) in
      let components =
        List.map2
          (fun piece argument ->
            Printf.sprintf "%s:%s" piece (argument_expression argument))
          pieces arguments
      in
      Printf.sprintf "[%s %s]" receiver.local_name
        (String.concat " " components)

let camlparam arguments =
  let count = List.length arguments in
  if count < 1 || count > 5 then fail "unsupported CAMLparam arity: %d" count;
  Printf.sprintf "CAMLparam%d(%s);" count (String.concat ", " arguments)

let direct_argument_name index = Printf.sprintf "argument_%d" index
let direct_raw_argument_name index = "raw_" ^ direct_argument_name index

let direct_argument_conversion output index scalar =
  let name = direct_argument_name index in
  let raw_name = direct_raw_argument_name index in
  let objc_type = Binding_direct_spec.scalar_objc_type scalar in
  match scalar with
  | Binding_direct_spec.Bool ->
      Printf.bprintf output "        const BOOL %s = Bool_val(%s) ? YES : NO;\n"
        name raw_name
  | Binding_direct_spec.Float64 _ ->
      Printf.bprintf output
        "        const %s %s = static_cast<%s>(Double_val(%s));\n"
        objc_type name objc_type raw_name
  | Binding_direct_spec.Signed { width; _ } ->
      Printf.bprintf output
        "        const std::int64_t signed_%s = Int64_val(%s);\n" name
        raw_name;
      (match width with
       | Binding_direct_spec.Bits32 ->
           Printf.bprintf output
             "        if (signed_%s < INT32_MIN || signed_%s > INT32_MAX) {\n"
             name name;
           Buffer.add_string output
             "          CAMLreturn(result_error_text(\"signed Metal argument is outside 32-bit range\"));\n";
           Buffer.add_string output "        }\n"
       | Binding_direct_spec.Native | Binding_direct_spec.Bits64 -> ());
      Printf.bprintf output
        "        const %s %s = static_cast<%s>(signed_%s);\n" objc_type
        name objc_type name
  | Binding_direct_spec.Unsigned { width; _ } ->
      Printf.bprintf output
        "        const std::int64_t signed_%s = Int64_val(%s);\n" name
        raw_name;
      (match width with
       | Binding_direct_spec.Bits32 ->
           Printf.bprintf output
             "        if (signed_%s < 0 || static_cast<std::uint64_t>(signed_%s) > UINT32_MAX) {\n"
             name name;
           Buffer.add_string output
             "          CAMLreturn(result_error_text(\"unsigned Metal argument is outside 32-bit range\"));\n";
           Buffer.add_string output "        }\n"
       | Binding_direct_spec.Native | Binding_direct_spec.Bits64 -> ());
      Printf.bprintf output
        "        const %s %s = static_cast<%s>(static_cast<std::uint64_t>(signed_%s));\n"
        objc_type name objc_type name

let direct_objc_call (receiver : direct_receiver_spec) selector argument_count =
  if argument_count = 0 then
    Printf.sprintf "[%s %s]" receiver.local_name selector
  else
    let pieces = selector_pieces selector argument_count in
    pieces
    |> List.mapi (fun index piece ->
      Printf.sprintf "%s:%s" piece (direct_argument_name index))
    |> String.concat " "
    |> Printf.sprintf "[%s %s]" receiver.local_name

let add_direct_receiver_recovery output (receiver : direct_receiver_spec) =
  match receiver.access with
  | Direct_object handle_kind ->
      Printf.bprintf output "        %s %s =\n" receiver.objc_type
        receiver.local_name;
      Printf.bprintf output
        "            object_of_handle(%s, Handle_kind::%s);\n"
        receiver.raw_name handle_kind
  | Helper_object helper | Polymorphic_object helper ->
      Printf.bprintf output "        %s %s = %s(%s);\n" receiver.objc_type
        receiver.local_name helper receiver.raw_name
  | Wrapped_object { handle_kind; wrapper_type; property } ->
      Printf.bprintf output "        %s receiver_state =\n" wrapper_type;
      Printf.bprintf output
        "            object_of_handle(%s, Handle_kind::%s);\n"
        receiver.raw_name handle_kind;
      Printf.bprintf output "        %s %s = receiver_state.%s;\n"
        receiver.objc_type receiver.local_name property

let direct_unavailable_error (entry : Binding_direct_spec.method_entry) =
  Printf.sprintf "Metal selector %s requires macOS %s" entry.selector
    (Binding_availability.canonical entry.macos_introduced)

let add_native_void_binding output (entry : Binding_plan.entry)
    (binding : Binding_plan.direct_void) =
  let receiver = receiver_spec binding.receiver in
  let raw_arguments =
    receiver.raw_name
    :: List.map
         (fun (argument : Binding_plan.argument) -> "raw_" ^ argument.name)
         binding.arguments
  in
  Buffer.add_string output "extern \"C\" CAMLprim value\n";
  Printf.bprintf output "%s(\n    %s) {\n" binding.c_symbol
    (raw_arguments
     |> List.map (fun argument -> "value " ^ argument)
     |> String.concat ", ");
  Printf.bprintf output "  %s\n" (camlparam raw_arguments);
  Buffer.add_string output "  @autoreleasepool {\n";
  Printf.bprintf output "    if (@available(macOS %d.%d, *)) {\n"
    entry.expect.availability.macos_major
    entry.expect.availability.macos_minor;
  Buffer.add_string output "      @try {\n";
  Printf.bprintf output "        %s %s =\n" receiver.objc_type receiver.local_name;
  Printf.bprintf output "            object_of_handle(%s, Handle_kind::%s);\n"
    receiver.raw_name receiver.handle_kind;
  List.iter (argument_conversion output) binding.arguments;
  Printf.bprintf output "        %s;\n"
    (objc_call receiver entry.expect.name binding.arguments);
  Buffer.add_string output "        CAMLreturn(result_unit());\n";
  Buffer.add_string output "      } @catch (NSException *exception) {\n";
  Buffer.add_string output "        CAMLreturn(result_error(exception.reason));\n";
  Buffer.add_string output "      }\n";
  Buffer.add_string output "    }\n";
  Printf.bprintf output "    CAMLreturn(result_error_text(%s));\n"
    (c_string entry.expect.availability.unavailable_error);
  Buffer.add_string output "  }\n";
  Buffer.add_string output "}\n\n"

let add_native_getter_binding output (entry : Binding_plan.entry)
    (binding : Binding_plan.direct_getter) =
  let receiver = receiver_spec binding.receiver in
  Buffer.add_string output "extern \"C\" CAMLprim value\n";
  Printf.bprintf output "%s(value %s) {\n" binding.c_symbol receiver.raw_name;
  Printf.bprintf output "  %s\n" (camlparam [ receiver.raw_name ]);
  Buffer.add_string output "  CAMLlocal2(result, copied_result);\n";
  Buffer.add_string output "  @autoreleasepool {\n";
  Printf.bprintf output "    if (@available(macOS %d.%d, *)) {\n"
    entry.expect.availability.macos_major
    entry.expect.availability.macos_minor;
  Buffer.add_string output "      @try {\n";
  Printf.bprintf output "        %s %s =\n" receiver.objc_type receiver.local_name;
  Printf.bprintf output "            object_of_handle(%s, Handle_kind::%s);\n"
    receiver.raw_name receiver.handle_kind;
  (match binding.result with
   | Binding_plan.Nsuint_to_checked_int64 { overflow_error } ->
       Printf.bprintf output "        const NSUInteger native_result = %s;\n"
         (objc_call receiver entry.expect.name []);
       Buffer.add_string output
         "        if (native_result > static_cast<NSUInteger>(INT64_MAX)) {\n";
       Printf.bprintf output "          CAMLreturn(result_error_text(%s));\n"
         (c_string overflow_error);
       Buffer.add_string output "        }\n";
       Buffer.add_string output
         "        copied_result = caml_copy_int64(\n            static_cast<std::int64_t>(native_result));\n";
       Buffer.add_string output "        result = result_ok(copied_result);\n";
       Buffer.add_string output "        CAMLreturn(result);\n");
  Buffer.add_string output "      } @catch (NSException *exception) {\n";
  Buffer.add_string output "        CAMLreturn(result_error(exception.reason));\n";
  Buffer.add_string output "      }\n";
  Buffer.add_string output "    }\n";
  Printf.bprintf output "    CAMLreturn(result_error_text(%s));\n"
    (c_string entry.expect.availability.unavailable_error);
  Buffer.add_string output "  }\n";
  Buffer.add_string output "}\n\n"

let add_direct_result output scalar call =
  let objc_type = Binding_direct_spec.scalar_objc_type scalar in
  Printf.bprintf output "        const %s native_result = %s;\n" objc_type
    call;
  (match scalar with
   | Binding_direct_spec.Bool ->
       Buffer.add_string output
         "        copied_result = Val_bool(native_result);\n"
   | Binding_direct_spec.Float64 _ ->
       Buffer.add_string output
         "        copied_result = caml_copy_double(static_cast<double>(native_result));\n"
   | Binding_direct_spec.Signed _ ->
       Buffer.add_string output
         "        copied_result = caml_copy_int64(static_cast<std::int64_t>(native_result));\n"
   | Binding_direct_spec.Unsigned _ ->
       Buffer.add_string output
         "        copied_result = caml_copy_int64(static_cast<std::int64_t>(static_cast<std::uint64_t>(native_result)));\n");
  Buffer.add_string output "        result = result_ok(copied_result);\n";
  Buffer.add_string output "        CAMLreturn(result);\n"

let add_direct_native_binding output
    (entry : Binding_direct_spec.method_entry) =
  let receiver = direct_receiver_spec entry.owner in
  let raw_arguments =
    receiver.raw_name
    :: List.mapi (fun index _ -> direct_raw_argument_name index) entry.arguments
  in
  Buffer.add_string output "extern \"C\" CAMLprim value\n";
  Printf.bprintf output "%s(\n    %s) {\n" entry.c_symbol
    (raw_arguments
     |> List.map (fun argument -> "value " ^ argument)
     |> String.concat ", ");
  Printf.bprintf output "  %s\n" (camlparam raw_arguments);
  (match entry.result with
   | None -> ()
   | Some _ -> Buffer.add_string output "  CAMLlocal2(result, copied_result);\n");
  Buffer.add_string output "  @autoreleasepool {\n";
  Printf.bprintf output "    if (@available(macOS %s, *)) {\n"
    (Binding_availability.canonical entry.macos_introduced);
  (match entry.semantics with
   | Binding_direct_spec.Blocking ->
       Buffer.add_string output "      @try {\n";
       add_direct_receiver_recovery output receiver;
       Buffer.add_string output
         "        NSException *__strong caught_exception = nil;\n";
       Buffer.add_string output "        caml_enter_blocking_section();\n";
       Buffer.add_string output "        @try {\n";
       Printf.bprintf output "          %s;\n"
         (direct_objc_call receiver entry.selector 0);
       Buffer.add_string output "        } @catch (NSException *exception) {\n";
       Buffer.add_string output "          caught_exception = exception;\n";
       Buffer.add_string output "        }\n";
       Buffer.add_string output "        caml_leave_blocking_section();\n";
       Buffer.add_string output "        if (caught_exception != nil) {\n";
       Buffer.add_string output
         "          CAMLreturn(result_error(caught_exception.reason));\n";
       Buffer.add_string output "        }\n";
       Buffer.add_string output "        CAMLreturn(result_unit());\n";
       Buffer.add_string output "      } @catch (NSException *exception) {\n";
       Buffer.add_string output
         "        CAMLreturn(result_error(exception.reason));\n";
       Buffer.add_string output "      }\n"
   | (Binding_direct_spec.Query | Binding_direct_spec.Command
     | Binding_direct_spec.Process_identity) ->
       Buffer.add_string output "      @try {\n";
       add_direct_receiver_recovery output receiver;
       List.iteri (direct_argument_conversion output) entry.arguments;
       let call =
         direct_objc_call receiver entry.selector (List.length entry.arguments)
       in
       (match entry.result with
        | None ->
            Printf.bprintf output "        %s;\n" call;
            Buffer.add_string output "        CAMLreturn(result_unit());\n"
        | Some result -> add_direct_result output result call);
       Buffer.add_string output "      } @catch (NSException *exception) {\n";
       Buffer.add_string output
         "        CAMLreturn(result_error(exception.reason));\n";
       Buffer.add_string output "      }\n");
  Buffer.add_string output "    }\n";
  Printf.bprintf output "    CAMLreturn(result_error_text(%s));\n"
    (c_string (direct_unavailable_error entry));
  Buffer.add_string output "  }\n";
  Buffer.add_string output "}\n\n"

let add_native_binding output entry =
  match entry.Binding_plan.disposition with
  | Binding_plan.Generate (Binding_plan.Direct_void binding) ->
      add_native_void_binding output entry binding
  | Binding_plan.Generate (Binding_plan.Direct_getter binding) ->
      add_native_getter_binding output entry binding
  | Binding_plan.Manual | Binding_plan.Exclude _ | Binding_plan.Pending ->
      fail "internal error: non-generated Metal binding %s" entry.sdk_id

let native_include ~header ~implicit_enum_selection ~struct_output
    ~value_record_checks ~string_entries ~global_string_entries ~direct_methods entries =
  let output = Buffer.create 8192 in
  Printf.bprintf output "/* %s */\n\n" header;
  Buffer.add_string output
    (Binding_enum_implicit_codegen.render_static_asserts
       implicit_enum_selection);
  Buffer.add_char output '\n';
  Buffer.add_string output struct_output.Binding_struct_native_codegen.native;
  Buffer.add_char output '\n';
  Buffer.add_string output value_record_checks;
  Buffer.add_char output '\n';
  Buffer.add_string output (Binding_string_codegen.render_native string_entries);
  Buffer.add_char output '\n';
  Buffer.add_string output
    (Binding_global_string_codegen.render_native global_string_entries);
  Buffer.add_char output '\n';
  List.iter (add_native_binding output) entries;
  List.iter (add_direct_native_binding output) direct_methods;
  let contents = Buffer.contents output in
  [ "objc_msgSend"; "performSelector"; "valueForKey" ]
  |> List.iter (fun forbidden ->
    if contains ~needle:forbidden contents then
      fail "forbidden dynamic Objective-C dispatch in generated bridge: %s"
        forbidden);
  contents

let argument_json (argument : Binding_plan.argument) =
  match argument.kind with
  | Binding_plan.Enum_int { enum_type; cases } ->
      `Assoc
        [ "name", `String argument.name
        ; "abi", `String "ocaml_int_to_objc_enum"
        ; "objc_type", `String (enum_objc_type enum_type)
        ; "error", `String argument.error
        ; "cases",
          `List
            (List.map
               (fun (case : Binding_plan.enum_case) ->
                 `Assoc
                   [ "sdk_id", `String case.Binding_plan.sdk_id
                   ; "value", `Int case.value
                   ])
               cases)
        ]
  | Binding_plan.Unsigned_int { minimum; multiple_of } ->
      `Assoc
        [ "name", `String argument.name
        ; "abi", `String "ocaml_int_to_nsuint"
        ; "objc_type", `String "NSUInteger"
        ; "error", `String argument.error
        ; "minimum", `Int minimum
        ; "multiple_of",
          (match multiple_of with None -> `Null | Some value -> `Int value)
        ]

let companion_json (companion : Binding_plan.companion) =
  `Assoc
    [ "sdk_id", `String companion.sdk_id
    ; "kind", `String companion.kind
    ; "owner", `String companion.owner
    ; "name", `String companion.name
    ; "header", `String companion.header
    ; "signature", `String companion.signature
    ; "attributes", `List (List.map (fun value -> `String value) companion.attributes)
    ]

let safe_api_json = function
  | Some evidence ->
      `Assoc
        [ "operation", `String evidence.Binding_plan.operation
        ; "module_path",
          `List (List.map (fun name -> `String name) evidence.module_path)
        ; "value_name", `String evidence.value_name
        ; "test_value", `String evidence.test_value
        ; "test_call",
          `List (List.map (fun name -> `String name) evidence.test_call)
        ]
  | None -> `Null

let result_json = function
  | Binding_plan.Nsuint_to_checked_int64 { overflow_error } ->
      `Assoc
        [ "abi", `String "objc_nsuint_to_checked_ocaml_int64"
        ; "objc_type", `String "NSUInteger"
        ; "ocaml_type", `String "int64"
        ; "overflow_error", `String overflow_error
        ]

let entry_json entry =
  let ocaml_name, c_symbol, receiver_kind = generated_identity entry in
  let receiver = receiver_spec receiver_kind in
  let generation_fields =
    match entry.Binding_plan.disposition with
    | Binding_plan.Generate (Binding_plan.Direct_void binding) ->
        [ "arguments", `List (List.map argument_json binding.arguments)
        ; "template", `String "direct_void_scalar"
        ]
    | Binding_plan.Generate (Binding_plan.Direct_getter binding) ->
        [ "arguments", `List []
        ; "result", result_json binding.result
        ; "template", `String "direct_getter"
        ]
    | Binding_plan.Manual | Binding_plan.Exclude _ | Binding_plan.Pending ->
        fail "internal error: non-generated Metal binding %s" entry.sdk_id
  in
  `Assoc
    ([ "sdk_id", `String entry.Binding_plan.sdk_id
     ; "owner", `String entry.expect.owner
     ; "selector", `String entry.expect.name
     ; "header", `String entry.expect.header
     ; "signature", `String entry.expect.signature
     ; "macos_introduced",
       `String
         (Printf.sprintf "%d.%d" entry.expect.availability.macos_major
            entry.expect.availability.macos_minor)
     ; "ocaml_name", `String ocaml_name
     ; "c_symbol", `String c_symbol
     ; "receiver_handle_kind", `String receiver.handle_kind
     ]
     @ generation_fields
     @ [ "companions", `List (List.map companion_json entry.companions)
       ; "safe_api", safe_api_json entry.safe_api
       ])

let direct_width_json = function
  | Binding_direct_spec.Native -> `String "native64"
  | Binding_direct_spec.Bits32 -> `String "32"
  | Binding_direct_spec.Bits64 -> `String "64"

let direct_scalar_json scalar =
  let common abi =
    [ "abi", `String abi
    ; "objc_type", `String (Binding_direct_spec.scalar_objc_type scalar)
    ; "ocaml_type", `String (Binding_direct_spec.scalar_ocaml_type scalar)
    ]
  in
  match scalar with
  | Binding_direct_spec.Bool -> `Assoc (common "objc_bool")
  | Binding_direct_spec.Float64 _ -> `Assoc (common "objc_float64")
  | Binding_direct_spec.Signed { width; _ } ->
      `Assoc (common "signed_integer" @ [ "width", direct_width_json width ])
  | Binding_direct_spec.Unsigned { width; _ } ->
      `Assoc
        (common "unsigned_bit_pattern"
        @ [ "width", direct_width_json width ])

let direct_semantics_json = function
  | Binding_direct_spec.Query -> `String "query"
  | Binding_direct_spec.Command -> `String "command"
  | Binding_direct_spec.Blocking -> `String "blocking"
  | Binding_direct_spec.Process_identity -> `String "process_identity"

let direct_receiver_json owner =
  let receiver = direct_receiver_spec owner in
  let access_fields =
    match receiver.access with
    | Direct_object handle_kind ->
        [ "access", `String "object_of_handle"
        ; "handle_kinds", `List [ `String handle_kind ]
        ]
    | Helper_object helper ->
        let handle_kind =
          Binding_receiver_catalog.receivers
          |> List.find (fun (catalog : Binding_receiver_catalog.receiver) ->
            String.equal catalog.sdk_owner owner)
          |> fun catalog -> catalog.handle_kind
        in
        [ "access", `String helper
        ; "handle_kinds", `List [ `String handle_kind ]
        ]
    | Wrapped_object { handle_kind; wrapper_type; property } ->
        [ "access", `String "wrapped_property"
        ; "handle_kinds", `List [ `String handle_kind ]
        ; "wrapper_type", `String wrapper_type
        ; "wrapper_property", `String property
        ]
    | Polymorphic_object helper ->
        let accepted =
          Binding_receiver_catalog.polymorphic_receivers
          |> List.find
               (fun (catalog :
                       Binding_receiver_catalog.polymorphic_receiver) ->
                 String.equal catalog.sdk_owner owner)
          |> fun catalog -> catalog.accepted_handle_kinds
        in
        [ "access", `String helper
        ; "handle_kinds", `List (List.map (fun value -> `String value) accepted)
        ]
  in
  `Assoc
    ([ "objc_type", `String receiver.objc_type
     ; "raw_name", `String receiver.raw_name
     ; "local_name", `String receiver.local_name
     ]
    @ access_fields)

let direct_method_json (entry : Binding_direct_spec.method_entry) =
  `Assoc
    [ "sdk_id", `String entry.sdk_id
    ; "owner", `String entry.owner
    ; "selector", `String entry.selector
    ; "header", `String entry.header
    ; "signature", `String entry.signature
    ; "attributes", `List (List.map (fun value -> `String value) entry.attributes)
    ; ( "macos_introduced"
      , `String (Binding_availability.canonical entry.macos_introduced) )
    ; "semantics", direct_semantics_json entry.semantics
    ; "arguments", `List (List.map direct_scalar_json entry.arguments)
    ; ( "result"
      , match entry.result with
        | None -> `Null
        | Some result -> direct_scalar_json result )
    ; "ocaml_name", `String entry.ocaml_name
    ; "c_symbol", `String entry.c_symbol
    ; "receiver", direct_receiver_json entry.owner
    ; "safe_api", `Null
    ]

let direct_property_json (entry : Binding_direct_spec.property_entry) =
  `Assoc
    [ "sdk_id", `String entry.sdk_id
    ; "owner", `String entry.owner
    ; "name", `String entry.name
    ; "header", `String entry.header
    ; "signature", `String entry.signature
    ; "attributes", `List (List.map (fun value -> `String value) entry.attributes)
    ; ( "macos_introduced"
      , `String (Binding_availability.canonical entry.macos_introduced) )
    ; "getter_sdk_id", `String entry.getter.sdk_id
    ; ( "setter_sdk_id"
      , match entry.setter with
        | None -> `Null
        | Some setter -> `String setter.sdk_id )
    ]

let direct_batch_json methods properties =
  `Assoc
    [ "method_count", `Int (List.length methods)
    ; "property_count", `Int (List.length properties)
    ; "declaration_count", `Int (List.length methods + List.length properties)
    ; "safe_bound_count", `Int 0
    ; "methods", `List (List.map direct_method_json methods)
    ; "properties", `List (List.map direct_property_json properties)
    ]

let manifest ~sdk_version ~plan_sha256 ~generator_sha256 ~inventory_sha256
    ~raw_ml_contents ~raw_mli_contents ~native_contents ~enum_selection
    ~implicit_enum_selection ~struct_output ~string_entries ~direct_methods
    ~direct_properties ~value_record_ids ~global_string_entries
    ~descriptor_property_ids entries =
  pretty_json
    (`Assoc
       [ "schema", `Int 2
       ; "kind", `String "metal_generated_bindings"
       ; "generator", `String "tools/metal/generate_bindings.exe"
       ; "sdk_version", `String sdk_version
       ; "binding_plan_source_sha256", `String plan_sha256
       ; "generator_source_sha256", `String generator_sha256
       ; "inventory_sha256", `String inventory_sha256
       ; "raw_ml_sha256", `String (sha256 raw_ml_contents)
       ; "raw_mli_sha256", `String (sha256 raw_mli_contents)
       ; "native_include_sha256", `String (sha256 native_contents)
       ; "entry_count", `Int (List.length entries)
       ; "entries", `List (List.map entry_json entries)
       ; ( "mechanical_enum_batch"
         , Binding_enum_codegen.manifest_json enum_selection )
       ; ( "mechanical_implicit_enum_batch"
         , Binding_enum_implicit_codegen.manifest_json
             implicit_enum_selection )
       ; ( "mechanical_struct_native_batch"
         , `Assoc
             [ "method_count", `Int (List.length struct_output.Binding_struct_native_codegen.method_ids)
             ; "property_count", `Int (List.length struct_output.property_ids)
             ; "declaration_count", `Int 27
             ; "safe_bound_count", `Int 0
             ; "method_ids", `List (List.map (fun id -> `String id) struct_output.method_ids)
             ; "property_ids", `List (List.map (fun id -> `String id) struct_output.property_ids)
             ] )
       ; ( "generated_value_record_batch"
         , `Assoc
             [ "record_count", `Int Binding_value_record_plan.expected_record_count
             ; "field_count", `Int Binding_value_record_plan.expected_field_count
             ; "declaration_count", `Int (List.length value_record_ids)
             ; "safe_bound_count", `Int (List.length value_record_ids)
             ; "layout_digest", `String Binding_value_record_evidence.expected_layout_digest
             ; "identifiers", `List (List.map (fun id -> `String id) value_record_ids)
             ] )
       ; ( "mechanical_string_batch"
         , let identifiers =
             List.concat_map Binding_string_spec.inventory_ids string_entries
           in
           `Assoc
             [ "property_count", `Int (List.length string_entries)
             ; "declaration_count", `Int (List.length identifiers)
             ; "safe_bound_count", `Int 0
             ; "identifiers", `List (List.map (fun id -> `String id) identifiers)
             ] )
       ; ( "generated_global_string_batch"
         , `Assoc
             [ "declaration_count", `Int (List.length global_string_entries)
             ; "safe_bound_count", `Int (List.length global_string_entries)
             ; "identifier_sha256", `String Binding_global_string_evidence.identifier_sha256
             ; "availability_sha256", `String Binding_global_string_evidence.availability_sha256
             ; "identifiers"
             , `List
                 (List.map
                    (fun entry ->
                      `String entry.Binding_global_string_spec.sdk_id)
                    global_string_entries)
             ] )
       ; ( "mechanical_direct_handle_batch"
         , direct_batch_json direct_methods direct_properties )
       ; ( "generated_descriptor_property_batch"
         , `Assoc
             [ "property_count"
             , `Int
                 (Binding_descriptor_property_plan.expected_property_count
                 + Binding_render_pipeline_scalar_plan.expected_property_count)
             ; "declaration_count", `Int (List.length descriptor_property_ids)
             ; "safe_bound_count"
             , `Int
                 (Binding_descriptor_property_evidence.expected_bound_count
                 + Binding_render_pipeline_scalar_evidence.expected_bound_count)
             ; "pending_icb_count", `Int Binding_descriptor_property_evidence.expected_pending_count
             ; "identifiers", `List (List.map (fun id -> `String id) descriptor_property_ids)
             ] )
       ])

let generator_source_paths =
  [ "tools/metal/generate_bindings.ml"
  ; "tools/metal/binding_availability.ml"
  ; "tools/metal/binding_availability.mli"
  ; "tools/metal/binding_enum_codegen.ml"
  ; "tools/metal/binding_enum_codegen.mli"
  ; "tools/metal/binding_enum_implicit_plan.ml"
  ; "tools/metal/binding_enum_implicit_plan.mli"
  ; "tools/metal/binding_enum_implicit_codegen.ml"
  ; "tools/metal/binding_enum_implicit_codegen.mli"
  ; "tools/metal/binding_enum_bound_evidence.ml"
  ; "tools/metal/binding_enum_bound_evidence.mli"
  ; "tools/metal/binding_enum_public_codegen.ml"
  ; "tools/metal/binding_enum_public_codegen.mli"
  ; "tools/metal/binding_value_record_plan.ml"
  ; "tools/metal/binding_value_record_plan.mli"
  ; "tools/metal/binding_value_record_codegen.ml"
  ; "tools/metal/binding_value_record_codegen.mli"
  ; "tools/metal/binding_value_record_evidence.ml"
  ; "tools/metal/binding_value_record_evidence.mli"
  ; "tools/metal/binding_global_string_spec.ml"
  ; "tools/metal/binding_global_string_spec.mli"
  ; "tools/metal/binding_global_string_codegen.ml"
  ; "tools/metal/binding_global_string_codegen.mli"
  ; "tools/metal/binding_global_string_evidence.ml"
  ; "tools/metal/binding_global_string_evidence.mli"
  ; "tools/metal/binding_global_string_conformance_codegen.ml"
  ; "tools/metal/binding_global_string_conformance_codegen.mli"
  ; "tools/metal/binding_descriptor_property_spec.ml"
  ; "tools/metal/binding_descriptor_property_spec.mli"
  ; "tools/metal/binding_descriptor_property_plan.ml"
  ; "tools/metal/binding_descriptor_property_plan.mli"
  ; "tools/metal/binding_descriptor_property_codegen.ml"
  ; "tools/metal/binding_descriptor_property_codegen.mli"
  ; "tools/metal/binding_descriptor_property_evidence.ml"
  ; "tools/metal/binding_descriptor_property_evidence.mli"
  ; "tools/metal/binding_render_pipeline_scalar_plan.ml"
  ; "tools/metal/binding_render_pipeline_scalar_plan.mli"
  ; "tools/metal/binding_render_pipeline_scalar_codegen.ml"
  ; "tools/metal/binding_render_pipeline_scalar_codegen.mli"
  ; "tools/metal/binding_render_pipeline_scalar_evidence.ml"
  ; "tools/metal/binding_render_pipeline_scalar_evidence.mli"
  ; "tools/metal/binding_descriptor_default_evidence.ml"
  ; "tools/metal/binding_descriptor_default_evidence.mli"
  ; "tools/metal/binding_argument_reflection_plan.ml"
  ; "tools/metal/binding_argument_reflection_plan.mli"
  ; "tools/metal/binding_argument_reflection_codegen.ml"
  ; "tools/metal/binding_argument_reflection_codegen.mli"
  ; "tools/metal/binding_argument_reflection_evidence.ml"
  ; "tools/metal/binding_argument_reflection_evidence.mli"
  ; "tools/metal/binding_struct_spec.ml"
  ; "tools/metal/binding_struct_spec.mli"
  ; "tools/metal/binding_struct_plan.ml"
  ; "tools/metal/binding_struct_plan.mli"
  ; "tools/metal/binding_struct_native_codegen.ml"
  ; "tools/metal/binding_struct_native_codegen.mli"
  ; "tools/metal/binding_string_spec.ml"
  ; "tools/metal/binding_string_spec.mli"
  ; "tools/metal/binding_string_properties.ml"
  ; "tools/metal/binding_string_properties.mli"
  ; "tools/metal/binding_string_codegen.ml"
  ; "tools/metal/binding_string_codegen.mli"
  ; "tools/metal/binding_receiver_catalog.ml"
  ; "tools/metal/binding_receiver_catalog.mli"
  ]

let generator_source_root entry_source =
  let metal_directory =
    if Filename.dirname entry_source = "." then Sys.getcwd ()
    else Filename.dirname entry_source
  in
  let tools_directory = Filename.dirname metal_directory in
  if
    Filename.basename entry_source <> "generate_bindings.ml"
    || Filename.basename metal_directory <> "metal"
    || Filename.basename tools_directory <> "tools"
  then
    fail
      "--generator-source must name tools/metal/generate_bindings.ml, found %s"
      entry_source;
  Filename.dirname tools_directory

let generator_source_sha256 ~entry_source =
  let root = generator_source_root entry_source in
  generator_source_paths
  |> List.map (fun relative ->
    relative, read_file (Filename.concat root relative))
  |> Binding_spec.aggregate_source_sha256

type options =
  { inventory : string
  ; plan_root : string
  ; generator_source : string
  ; manual_native : string
  ; manual_raw_ml : string
  ; manual_raw_mli : string
  ; safe_source : string
  ; safe_tests : string
  ; output_raw_ml : string
  ; output_raw_mli : string
  ; output_native : string
  ; output_manifest : string
  ; output_public_enum_ml : string
  ; output_public_enum_mli : string
  ; output_public_enum_test : string
  ; output_public_value_ml : string
  ; output_public_value_mli : string
  ; output_public_value_test : string
  ; output_public_global_ml : string
  ; output_public_global_mli : string
  ; output_public_global_test : string
  ; output_public_descriptor_ml : string
  ; output_public_descriptor_mli : string
  ; output_public_descriptor_test : string
  ; output_native_descriptor_test : string
  }

let options () =
  let inventory = ref "" in
  let plan_root = ref "" in
  let plan_source = ref "" in
  let generator_source = ref "" in
  let manual_native = ref "" in
  let manual_raw_ml = ref "" in
  let manual_raw_mli = ref "" in
  let safe_source = ref "" in
  let safe_tests = ref "" in
  let output_raw_ml = ref "" in
  let output_raw_mli = ref "" in
  let output_native = ref "" in
  let output_manifest = ref "" in
  let output_public_enum_ml = ref "" in
  let output_public_enum_mli = ref "" in
  let output_public_enum_test = ref "" in
  let output_public_value_ml = ref "" in
  let output_public_value_mli = ref "" in
  let output_public_value_test = ref "" in
  let output_public_global_ml = ref "" in
  let output_public_global_mli = ref "" in
  let output_public_global_test = ref "" in
  let output_public_descriptor_ml = ref "" in
  let output_public_descriptor_mli = ref "" in
  let output_public_descriptor_test = ref "" in
  let output_native_descriptor_test = ref "" in
  let set target value = target := value in
  let arguments =
    [ "--inventory", Arg.String (set inventory), "Pinned inventory JSON"
    ; ( "--plan-root"
      , Arg.String (set plan_root)
      , "Workspace root containing every binding-plan source" )
    ; ( "--plan-source"
      , Arg.String (set plan_source)
      , "Legacy binding_plan.ml path used to derive the plan root" )
    ; ( "--generator-source"
      , Arg.String (set generator_source)
      , "Generator source" )
    ; "--manual-native", Arg.String (set manual_native), "Manual bridge source"
    ; "--manual-raw-ml", Arg.String (set manual_raw_ml), "Manual raw ML source"
    ; "--manual-raw-mli", Arg.String (set manual_raw_mli), "Manual raw MLI source"
    ; "--safe-source", Arg.String (set safe_source), "Handwritten safe Metal API"
    ; "--safe-tests", Arg.String (set safe_tests), "Metal conformance tests"
    ; "--output-raw-ml", Arg.String (set output_raw_ml), "Generated raw ML"
    ; "--output-raw-mli", Arg.String (set output_raw_mli), "Generated raw MLI"
    ; "--output-native", Arg.String (set output_native), "Generated native include"
    ; ( "--output-manifest"
      , Arg.String (set output_manifest)
      , "Generated provenance manifest" )
    ; "--output-public-enum-ml", Arg.String (set output_public_enum_ml), "Generated public enum ML"
    ; "--output-public-enum-mli", Arg.String (set output_public_enum_mli), "Generated public enum MLI"
    ; "--output-public-enum-test", Arg.String (set output_public_enum_test), "Generated public enum test"
    ; "--output-public-value-ml", Arg.String (set output_public_value_ml), "Generated public value-record ML"
    ; "--output-public-value-mli", Arg.String (set output_public_value_mli), "Generated public value-record MLI"
    ; "--output-public-value-test", Arg.String (set output_public_value_test), "Generated public value-record test"
    ; "--output-public-global-ml", Arg.String (set output_public_global_ml), "Generated public global-string ML"
    ; "--output-public-global-mli", Arg.String (set output_public_global_mli), "Generated public global-string MLI"
    ; "--output-public-global-test", Arg.String (set output_public_global_test), "Generated public global-string test"
    ; "--output-public-descriptor-ml", Arg.String (set output_public_descriptor_ml), "Generated public descriptor ML"
    ; "--output-public-descriptor-mli", Arg.String (set output_public_descriptor_mli), "Generated public descriptor MLI"
    ; "--output-public-descriptor-test", Arg.String (set output_public_descriptor_test), "Generated public descriptor construction test"
    ; "--output-native-descriptor-test", Arg.String (set output_native_descriptor_test), "Generated native descriptor conformance test"
    ]
  in
  Arg.parse arguments
    (fun argument -> fail "unexpected Metal generator argument: %s" argument)
    "Generate typed Metal raw/native bindings";
  let require name value =
    if !value = "" then fail "missing required Metal generator option %s" name;
    !value
  in
  let plan_root =
    match !plan_root, !plan_source with
    | root, "" when root <> "" -> root
    | "", source when source <> "" ->
        let metal_directory = Filename.dirname source in
        let tools_directory = Filename.dirname metal_directory in
        if
          Filename.basename source <> "binding_plan.ml"
          || Filename.basename metal_directory <> "metal"
          || Filename.basename tools_directory <> "tools"
        then
          fail
            "legacy --plan-source must name tools/metal/binding_plan.ml, found %s"
            source;
        Filename.dirname tools_directory
    | "", "" ->
        fail "missing required Metal generator option --plan-root"
    | _, _ ->
        fail "pass exactly one of --plan-root and legacy --plan-source"
  in
  { inventory = require "--inventory" inventory
  ; plan_root
  ; generator_source = require "--generator-source" generator_source
  ; manual_native = require "--manual-native" manual_native
  ; manual_raw_ml = require "--manual-raw-ml" manual_raw_ml
  ; manual_raw_mli = require "--manual-raw-mli" manual_raw_mli
  ; safe_source = require "--safe-source" safe_source
  ; safe_tests = require "--safe-tests" safe_tests
  ; output_raw_ml = require "--output-raw-ml" output_raw_ml
  ; output_raw_mli = require "--output-raw-mli" output_raw_mli
  ; output_native = require "--output-native" output_native
  ; output_manifest = require "--output-manifest" output_manifest
  ; output_public_enum_ml = require "--output-public-enum-ml" output_public_enum_ml
  ; output_public_enum_mli = require "--output-public-enum-mli" output_public_enum_mli
  ; output_public_enum_test = require "--output-public-enum-test" output_public_enum_test
  ; output_public_value_ml = require "--output-public-value-ml" output_public_value_ml
  ; output_public_value_mli = require "--output-public-value-mli" output_public_value_mli
  ; output_public_value_test = require "--output-public-value-test" output_public_value_test
  ; output_public_global_ml = require "--output-public-global-ml" output_public_global_ml
  ; output_public_global_mli = require "--output-public-global-mli" output_public_global_mli
  ; output_public_global_test = require "--output-public-global-test" output_public_global_test
  ; output_public_descriptor_ml = require "--output-public-descriptor-ml" output_public_descriptor_ml
  ; output_public_descriptor_mli = require "--output-public-descriptor-mli" output_public_descriptor_mli
  ; output_public_descriptor_test = require "--output-public-descriptor-test" output_public_descriptor_test
  ; output_native_descriptor_test = require "--output-native-descriptor-test" output_native_descriptor_test
  }

let main () =
  let options = options () in
  let inventory_contents = read_file options.inventory in
  let inventory_json = Yojson.Safe.from_string inventory_contents in
  let plan_sha256 = Binding_plan.source_sha256 ~root:options.plan_root in
  let sdk_version, inventory_plan_sha256, inventory =
    load_inventory options.inventory
  in
  if inventory_plan_sha256 <> plan_sha256 then
    fail
      "Metal inventory binding-plan provenance drift: regenerate the pinned inventory";
  let generator_sha256 =
    generator_source_sha256 ~entry_source:options.generator_source
  in
  let inventory_sha256 = sha256 inventory_contents in
  let enum_selection = select_mechanical_enums inventory in
  let implicit_enum_selection =
    select_implicit_mechanical_enums inventory
  in
  let public_enums =
    Binding_enum_public_codegen.generate ~explicit:enum_selection
      ~implicit:implicit_enum_selection
  in
  if public_enums.family_count <> 68 || public_enums.case_count <> 324
     || List.length public_enums.identifiers <> 460
  then
    fail
      "public Metal enum cardinality drift: %d families, %d cases, %d declarations"
      public_enums.family_count public_enums.case_count
      (List.length public_enums.identifiers);
  let struct_output = Binding_struct_native_codegen.generate () in
  validate_struct_native_output inventory struct_output;
  let value_record_selection = Binding_value_record_plan.select inventory_json in
  let value_records = Binding_value_record_codegen.generate value_record_selection in
  let value_record_ids =
    Binding_value_record_evidence.bound_ids ~inventory:inventory_json
      ~public_interface:value_records.ocaml_mli ~test_source:value_records.test_ml
  in
  List.iter
    (fun identifier ->
      let declaration = require_declaration inventory identifier in
      if declaration.classification <> "bound" then
        fail "generated Metal value record must be bound: %s" identifier)
    value_record_ids;
  let string_entries = Binding_string_codegen.qualified_entries () in
  validate_string_entries inventory string_entries;
  let global_string_entries = Binding_global_string_spec.entries in
  validate_global_string_entries inventory global_string_entries;
  let descriptor_property_entries =
    Binding_descriptor_property_plan.entries
    @ Binding_render_pipeline_scalar_plan.entries
  in
  let descriptor_symbols =
    String_map.bindings inventory
    |> List.map (fun (_, declaration) ->
      { Binding_descriptor_property_evidence.id = declaration.identifier
      ; kind = declaration.kind
      ; owner = declaration.owner
      ; name = declaration.name
      ; header = declaration.header
      ; signature = declaration.signature
      ; macos_introduced =
          Option.map Binding_availability.canonical
            declaration.macos_introduced
      ; attributes = declaration.attributes
      ; classification = declaration.classification
      })
  in
  Binding_descriptor_property_evidence.validate_inventory descriptor_symbols;
  let render_pipeline_scalar_symbols =
    String_map.bindings inventory
    |> List.map (fun (_, declaration) ->
      { Binding_render_pipeline_scalar_evidence.id = declaration.identifier
      ; kind = declaration.kind
      ; owner = declaration.owner
      ; name = declaration.name
      ; header = declaration.header
      ; signature = declaration.signature
      ; macos_introduced =
          Option.map Binding_availability.canonical declaration.macos_introduced
      ; attributes = declaration.attributes
      ; classification = declaration.classification
      })
  in
  Binding_render_pipeline_scalar_evidence.validate_inventory
    render_pipeline_scalar_symbols;
  Binding_descriptor_default_evidence.validate ();
  let reflection_symbols =
    String_map.bindings inventory
    |> List.map (fun (_, declaration) ->
      { Binding_argument_reflection_evidence.id = declaration.identifier
      ; kind = declaration.kind
      ; owner = declaration.owner
      ; name = declaration.name
      ; header = declaration.header
      ; signature = declaration.signature
      ; macos_introduced =
          Option.map Binding_availability.canonical declaration.macos_introduced
      ; classification = declaration.classification
      })
  in
  Binding_argument_reflection_evidence.validate_inventory reflection_symbols;
  let manual_native = read_file options.manual_native in
  let manual_raw_ml = read_file options.manual_raw_ml in
  let manual_raw_mli = read_file options.manual_raw_mli in
  let entries =
    validate_plan inventory manual_native manual_raw_ml manual_raw_mli
      (read_file options.safe_source) (read_file options.safe_tests)
  in
  let direct_methods, direct_properties =
    validate_direct_plan inventory manual_native manual_raw_ml manual_raw_mli
      entries
  in
  let header = generated_header ~plan_sha256 ~inventory_sha256 in
  let raw_ml_contents =
    raw_ml ~header ~enum_selection ~implicit_enum_selection ~struct_output
      ~string_entries ~global_string_entries ~direct_methods entries
  in
  let raw_mli_contents =
    raw_mli ~header ~enum_selection ~implicit_enum_selection ~struct_output
      ~string_entries ~global_string_entries ~direct_methods entries
  in
  let native_contents =
    native_include ~header ~implicit_enum_selection ~struct_output
      ~value_record_checks:value_records.native_checks
      ~string_entries ~global_string_entries ~direct_methods entries
    ^ "\n"
    ^ Binding_descriptor_property_codegen.render_native_materializers
        descriptor_property_entries
    ^ "\n"
    ^ Binding_argument_reflection_codegen.render_snapshot_ownership_helpers ()
  in
  let manifest_contents =
    manifest ~sdk_version ~plan_sha256 ~generator_sha256 ~inventory_sha256
      ~raw_ml_contents ~raw_mli_contents ~native_contents ~enum_selection
      ~implicit_enum_selection ~struct_output ~string_entries ~direct_methods
      ~descriptor_property_ids:
        (Binding_descriptor_property_evidence.promotion_ids
        @ Binding_render_pipeline_scalar_evidence.promotion_ids)
      ~direct_properties ~value_record_ids ~global_string_entries entries
  in
  write_file options.output_raw_ml raw_ml_contents;
  write_file options.output_raw_mli raw_mli_contents;
  write_file options.output_native native_contents;
  write_file options.output_manifest manifest_contents;
  write_file options.output_public_enum_ml
    (Printf.sprintf "(* %s *)\n\n%s" header public_enums.ml);
  write_file options.output_public_enum_mli
    (Printf.sprintf "(* %s *)\n\n%s" header public_enums.mli);
  write_file options.output_public_enum_test
    (Printf.sprintf "(* %s *)\n\n%s" header public_enums.test_ml);
  write_file options.output_public_value_ml
    (Printf.sprintf "(* %s *)\n\n%s" header value_records.ocaml_ml);
  write_file options.output_public_value_mli
    (Printf.sprintf "(* %s *)\n\n%s" header value_records.ocaml_mli);
  write_file options.output_public_value_test
    (Printf.sprintf "(* %s *)\n\n%s" header value_records.test_ml);
  write_file options.output_public_global_ml
    (Printf.sprintf "(* %s *)\n\n%s" header
       (Binding_global_string_codegen.render_safe_ml global_string_entries));
  write_file options.output_public_global_mli
    (Printf.sprintf "(* %s *)\n\n%s" header
       (Binding_global_string_codegen.render_safe_mli global_string_entries));
  write_file options.output_public_global_test
    (Printf.sprintf "(* %s *)\n\n%s" header
       (Binding_global_string_conformance_codegen.render_executable
          global_string_entries));
  write_file options.output_public_descriptor_ml
    (Printf.sprintf "(* %s *)\n\n%s" header
       (Binding_descriptor_property_codegen.render_public_ml
          descriptor_property_entries));
  write_file options.output_public_descriptor_mli
    (Printf.sprintf "(* %s *)\n\n%s" header
       (Binding_descriptor_property_codegen.render_public_mli
          descriptor_property_entries));
  write_file options.output_public_descriptor_test
    (Printf.sprintf "(* %s *)\n\n%s" header
       (Binding_descriptor_property_codegen.render_public_tests
          descriptor_property_entries));
  write_file options.output_native_descriptor_test
    (Printf.sprintf "/* %s */\n\n%s" header
       (Binding_descriptor_property_codegen.render_native_conformance_executable
          descriptor_property_entries));
  Printf.printf
    "generated %d checked-plan calls, %d direct calls (%d safe Device IDs), %d direct properties, %d explicit-value enum declarations, and %d implicit-value enum declarations\n%!"
    (List.length entries) (List.length direct_methods)
    (List.length Binding_direct_plan.safe_device_identifiers)
    (List.length direct_properties) enum_selection.declaration_count
    (Binding_enum_implicit_codegen.declaration_count implicit_enum_selection)

let () = protect_main main
