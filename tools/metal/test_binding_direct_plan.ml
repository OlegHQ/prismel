open Support

module String_map = Map.Make (String)
module String_set = Set.Make (String)

type availability_source =
  { header : string
  ; line : int
  }

type declaration =
  { identifier : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; header : string
  ; signature : string
  ; attributes : string list
  ; classification : string
  ; macos_introduced : Binding_availability.version option
  ; availability_sources : availability_source list
  }

let parse_options () =
  let inventory = ref "" in
  Arg.parse
    [ ( "--inventory"
      , Arg.Set_string inventory
      , "Schema-2 Metal API inventory to validate" )
    ]
    (fun value -> fail "unexpected direct-plan test argument: %s" value)
    "Test the fail-closed handle-backed Metal direct-call plan";
  if String.equal !inventory "" then
    fail "missing direct-plan test option --inventory";
  !inventory

let require_string field value =
  match member_string field value with
  | Some value -> value
  | None -> fail "Metal direct-plan inventory field %s must be a string" field

let require_int field value =
  match member_int field value with
  | Some value -> value
  | None -> fail "Metal direct-plan inventory field %s must be an integer" field

let nullable_string field value =
  match member field value with
  | Some (`String value) -> Some value
  | Some `Null -> None
  | Some _ ->
      fail "Metal direct-plan inventory field %s must be a string or null"
        field
  | None -> fail "Metal direct-plan inventory field %s is absent" field

let string_list field value =
  match member_list field value with
  | Some values ->
      List.map
        (function
          | `String value -> value
          | _ ->
              fail
                "Metal direct-plan inventory field %s has a non-string member"
                field)
        values
  | None -> fail "Metal direct-plan inventory field %s must be a list" field

let parse_version identifier = function
  | None -> None
  | Some canonical ->
      let source = "API_AVAILABLE(macos(" ^ canonical ^ "))" in
      (match Binding_availability.parse_site source with
      | Ok (Some version)
        when String.equal canonical (Binding_availability.canonical version) ->
          Some version
      | Ok (Some version) ->
          fail "non-canonical macOS version %S for %s (canonical %s)" canonical
            identifier (Binding_availability.canonical version)
      | Ok None ->
          fail "macOS version %S parsed as absent for %s" canonical identifier
      | Result.Error (error : Binding_availability.error) ->
          fail "invalid macOS version %S for %s at %d: %s" canonical
            identifier error.Binding_availability.offset
            error.Binding_availability.message)

let normalized_header header =
  (String.starts_with ~prefix:"Metal/" header
  && not (String.contains header '\\')
  && not (contains ~needle:".." header))
  || String.equal header "QuartzCore/CAMetalLayer.h"

let parse_availability_sources identifier value =
  let values =
    match member_list "availability_sources" value with
    | Some values -> values
    | None ->
        fail "availability_sources must be a list for %s" identifier
  in
  let sources =
    List.map
      (fun value ->
        let header = require_string "header" value in
        let line = require_int "line" value in
        if not (normalized_header header) then
          fail "non-normalized availability header %S for %s" header
            identifier;
        if line <= 0 then
          fail "non-positive availability line %d for %s" line identifier;
        ({ header; line } : availability_source))
      values
  in
  let compare (left : availability_source) (right : availability_source) =
    let by_header = String.compare left.header right.header in
    if by_header <> 0 then by_header else Int.compare left.line right.line
  in
  let rec require_strict_order = function
    | left :: (right :: _ as rest) ->
        if compare left right >= 0 then
          fail "unsorted or duplicate availability evidence for %s" identifier;
        require_strict_order rest
    | [ _ ] | [] -> ()
  in
  require_strict_order sources;
  sources

let parse_declaration value =
  let identifier = require_string "id" value in
  let attributes = string_list "attributes" value in
  if List.length attributes <> List.length (List.sort_uniq String.compare attributes)
  then fail "duplicate inventory attribute for %s" identifier;
  { identifier
  ; kind = require_string "kind" value
  ; name = require_string "name" value
  ; owner = nullable_string "owner" value
  ; header = require_string "header" value
  ; signature = require_string "signature" value
  ; attributes
  ; classification = require_string "classification" value
  ; macos_introduced =
      parse_version identifier (nullable_string "macos_introduced" value)
  ; availability_sources = parse_availability_sources identifier value
  }

let index_inventory path =
  let root = read_file path |> Yojson.Safe.from_string in
  if member_int "schema" root <> Some 2 then
    fail "Metal direct-plan test requires inventory schema 2";
  if member_string "sdk_version" root <> Some "26.5" then
    fail "Metal direct-plan test requires macOS SDK 26.5";
  if member_string "kind" root <> Some "metal_api_inventory" then
    fail "Metal direct-plan inventory kind drift";
  let symbols =
    match member_list "symbols" root with
    | Some symbols -> symbols
    | None -> fail "Metal direct-plan inventory symbols field must be a list"
  in
  if member_int "symbol_count" root <> Some (List.length symbols) then
    fail "Metal direct-plan inventory symbol_count does not match symbols";
  if List.length symbols <> 5_286 then
    fail "Metal direct-plan inventory expected 5286 symbols, found %d"
      (List.length symbols);
  List.fold_left
    (fun declarations value ->
      let declaration = parse_declaration value in
      if String_map.mem declaration.identifier declarations then
        fail "duplicate Metal inventory identifier: %s" declaration.identifier;
      String_map.add declaration.identifier declaration declarations)
    String_map.empty symbols

let require_declaration inventory identifier =
  match String_map.find_opt identifier inventory with
  | Some declaration -> declaration
  | None -> fail "direct-plan identifier is absent from inventory: %s" identifier

let compare_string identifier field expected actual =
  if not (String.equal expected actual) then
    fail "direct-plan %s drift for %s: expected %S, found %S" field
      identifier expected actual

let compare_owner identifier expected = function
  | Some actual -> compare_string identifier "owner" expected actual
  | None -> fail "direct-plan inventory owner is absent for %s" identifier

let deployment_floor : Binding_availability.version =
  { major = 14; minor = 0; patch = 0 }

let validate_availability identifier planned actual =
  match actual with
  | Some actual when Binding_availability.equal planned actual -> ()
  | Some actual ->
      fail "direct-plan availability drift for %s: planned %s, inventory %s"
        identifier (Binding_availability.canonical planned)
        (Binding_availability.canonical actual)
  | None when Binding_availability.compare planned deployment_floor <= 0 -> ()
  | None ->
      fail
        "direct-plan %s has nullable baseline availability but a post-14.0 guard %s"
        identifier (Binding_availability.canonical planned)

let require_classification declaration =
  let expected =
    if Binding_direct_plan.is_safe_device_identifier declaration.identifier
       || List.mem declaration.identifier
            Binding_resource_safe_reachability.promotable_ids
       || List.mem declaration.identifier
            Binding_pipeline_state_safe_reachability.promotable_ids
    then "bound"
    else "unreviewed"
  in
  if not (String.equal declaration.classification expected) then
    fail "direct-plan declaration %s must be %s, found %s"
      declaration.identifier expected declaration.classification;
  if
    Option.is_some declaration.macos_introduced
    && declaration.availability_sources = []
  then
    fail "introduced direct-plan declaration has no availability evidence: %s"
      declaration.identifier

let selector_arity selector =
  String.fold_left
    (fun count character -> if Char.equal character ':' then count + 1 else count)
    0 selector

let expected_method_signature (entry : Binding_direct_spec.method_entry) =
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
  "instance (" ^ arguments ^ ") -> " ^ result

let validate_method inventory (entry : Binding_direct_spec.method_entry) =
  let declaration = require_declaration inventory entry.sdk_id in
  compare_string entry.sdk_id "kind" "method" declaration.kind;
  compare_owner entry.sdk_id entry.owner declaration.owner;
  compare_string entry.sdk_id "name" entry.selector declaration.name;
  compare_string entry.sdk_id "header" entry.header declaration.header;
  compare_string entry.sdk_id "signature" entry.signature
    declaration.signature;
  compare_string entry.sdk_id "derived signature"
    (expected_method_signature entry) entry.signature;
  if entry.attributes <> declaration.attributes then
    fail "direct-plan attributes drift for %s" entry.sdk_id;
  validate_availability entry.sdk_id entry.macos_introduced
    declaration.macos_introduced;
  require_classification declaration;
  if selector_arity entry.selector <> List.length entry.arguments then
    fail "direct-plan selector arity drift for %s" entry.sdk_id;
  if List.length entry.arguments + 1 > 5 then
    fail "direct-plan native call exceeds the five-argument ceiling: %s"
      entry.sdk_id;
  if String.equal entry.ocaml_name "" then
    fail "direct-plan OCaml name is empty for %s" entry.sdk_id;
  if
    not (String.starts_with ~prefix:"caml_prismel_metal_" entry.c_symbol)
  then fail "direct-plan C symbol has the wrong namespace: %s" entry.c_symbol

let validate_property inventory methods_by_id
    (entry : Binding_direct_spec.property_entry) =
  let declaration = require_declaration inventory entry.sdk_id in
  compare_string entry.sdk_id "kind" "property" declaration.kind;
  compare_owner entry.sdk_id entry.owner declaration.owner;
  compare_string entry.sdk_id "name" entry.name declaration.name;
  compare_string entry.sdk_id "header" entry.header declaration.header;
  compare_string entry.sdk_id "signature" entry.signature
    declaration.signature;
  if entry.attributes <> declaration.attributes then
    fail "direct-property attributes drift for %s" entry.sdk_id;
  validate_availability entry.sdk_id entry.macos_introduced
    declaration.macos_introduced;
  require_classification declaration;
  let expected_property_id =
    "property:" ^ entry.owner ^ ":" ^ entry.name
  in
  compare_string entry.sdk_id "canonical identifier" expected_property_id
    entry.sdk_id;
  let getter = entry.getter in
  let registered_getter =
    match String_map.find_opt getter.sdk_id methods_by_id with
    | Some method_ -> method_
    | None -> fail "property getter is absent from aggregate methods: %s" getter.sdk_id
  in
  if registered_getter <> getter then
    fail "property getter is not the aggregate plan entry: %s" getter.sdk_id;
  if
    not
      (String.equal getter.owner entry.owner
      && String.equal getter.header entry.header
      && getter.attributes = entry.attributes
      && Binding_availability.equal getter.macos_introduced
           entry.macos_introduced)
  then fail "property/getter metadata drift for %s" entry.sdk_id;
  (match getter.arguments, getter.result, getter.semantics with
  | [], Some result, Binding_direct_spec.Query ->
      compare_string entry.sdk_id "getter scalar" entry.signature
        (Binding_direct_spec.scalar_objc_type result)
  | _ -> fail "invalid getter closure for %s" entry.sdk_id);
  (match entry.setter, getter.result with
  | None, _ -> ()
  | Some _, None -> fail "writable property has no getter result: %s" entry.sdk_id
  | Some setter, Some getter_result ->
      let registered_setter =
        match String_map.find_opt setter.sdk_id methods_by_id with
        | Some method_ -> method_
        | None ->
            fail "property setter is absent from aggregate methods: %s"
              setter.sdk_id
      in
      if registered_setter <> setter then
        fail "property setter is not the aggregate plan entry: %s"
          setter.sdk_id;
      if
        not
          (String.equal setter.owner entry.owner
          && String.equal setter.header entry.header
          && setter.attributes = entry.attributes
          && Binding_availability.equal setter.macos_introduced
               entry.macos_introduced)
      then fail "property/setter metadata drift for %s" entry.sdk_id;
      if
        setter.arguments <> [ getter_result ] || setter.result <> None
        || setter.semantics <> Binding_direct_spec.Command
      then fail "invalid setter closure for %s" entry.sdk_id)

let reject_duplicates description values =
  let rec loop = function
    | left :: right :: _ when String.equal left right ->
        fail "duplicate direct-plan %s: %s" description left
    | _ :: rest -> loop rest
    | [] -> ()
  in
  loop (List.sort String.compare values)

let method_map methods =
  List.fold_left
    (fun methods (entry : Binding_direct_spec.method_entry) ->
      if String_map.mem entry.sdk_id methods then
        fail "duplicate direct-plan method ID: %s" entry.sdk_id;
      String_map.add entry.sdk_id entry methods)
    String_map.empty methods

let count_semantics entries semantics =
  List.fold_left
    (fun count (entry : Binding_direct_spec.method_entry) ->
      if entry.semantics = semantics then count + 1 else count)
    0 entries

let require_count description expected actual =
  if actual <> expected then
    fail "direct-plan %s count drift: expected %d, found %d" description
      expected actual

type receiver_access =
  | Direct of Binding_receiver_catalog.receiver
  | Polymorphic of Binding_receiver_catalog.polymorphic_receiver

let receiver_for_owner owner =
  let direct =
    Binding_receiver_catalog.receivers
    |> List.filter (fun (entry : Binding_receiver_catalog.receiver) ->
      String.equal entry.sdk_owner owner)
    |> List.map (fun entry -> Direct entry)
  in
  let polymorphic =
    Binding_receiver_catalog.polymorphic_receivers
    |> List.filter
         (fun (entry : Binding_receiver_catalog.polymorphic_receiver) ->
           String.equal entry.sdk_owner owner)
    |> List.map (fun entry -> Polymorphic entry)
  in
  match direct @ polymorphic with
  | [ receiver ] -> receiver
  | [] -> fail "direct-plan owner has no receiver-catalog access: %s" owner
  | _ -> fail "direct-plan owner has ambiguous receiver-catalog access: %s" owner

let require_nonempty description owner value =
  if String.equal value "" then
    fail "direct-plan receiver %s has empty %s" owner description

let validate_receiver owner =
  let expected_type = "id<" ^ owner ^ ">" in
  match receiver_for_owner owner with
  | Direct receiver ->
      compare_string owner "receiver Objective-C type" expected_type
        receiver.objc_receiver_type;
      require_nonempty "Handle_kind" owner receiver.handle_kind;
      require_nonempty "local name" owner receiver.local_name;
      compare_string owner "receiver raw name"
        ("raw_" ^ receiver.local_name) receiver.raw_name;
      (match receiver.bridge_access with
      | Binding_receiver_catalog.Object_of_handle -> ()
      | Object_of_helper helper ->
          require_nonempty "object helper" owner helper
      | Wrapped_property { wrapper_type; property } ->
          require_nonempty "wrapper type" owner wrapper_type;
          require_nonempty "wrapper property" owner property)
  | Polymorphic receiver ->
      if not (String.equal owner "MTLResource") then
        fail "unexpected polymorphic direct-plan receiver: %s" owner;
      compare_string owner "receiver Objective-C type" expected_type
        receiver.objc_receiver_type;
      require_nonempty "polymorphic helper" owner receiver.helper;
      require_nonempty "local name" owner receiver.local_name;
      compare_string owner "receiver raw name"
        ("raw_" ^ receiver.local_name) receiver.raw_name;
      if receiver.accepted_handle_kinds <>
           [ "Buffer"; "Texture"; "Visible_function_table"
           ; "Intersection_function_table" ] then
        fail "MTLResource receiver Handle_kind closure drift"

let binding_plan_ids () =
  Binding_plan.entries
  |> List.concat_map (fun (entry : Binding_plan.entry) ->
    entry.sdk_id
    :: List.map
         (fun (companion : Binding_plan.companion) -> companion.sdk_id)
         entry.companions)
  |> String_set.of_list

let validate_plan inventory =
  let methods = Binding_direct_plan.methods in
  let properties = Binding_direct_plan.properties in
  require_count "method" 59 (List.length methods);
  require_count "property" 40 (List.length properties);
  let method_ids =
    List.map (fun (entry : Binding_direct_spec.method_entry) -> entry.sdk_id)
      methods
  in
  let property_ids =
    List.map
      (fun (entry : Binding_direct_spec.property_entry) -> entry.sdk_id)
      properties
  in
  let inventory_ids = method_ids @ property_ids in
  require_count "unique declaration" 99
    (List.length (List.sort_uniq String.compare inventory_ids));
  reject_duplicates "inventory ID" inventory_ids;
  if
    List.sort String.compare Binding_direct_plan.inventory_ids
    <> List.sort String.compare inventory_ids
  then fail "aggregate direct-plan inventory ID closure drift";
  reject_duplicates "OCaml external"
    (List.map
       (fun (entry : Binding_direct_spec.method_entry) -> entry.ocaml_name)
       methods);
  reject_duplicates "C primitive"
    (List.map
       (fun (entry : Binding_direct_spec.method_entry) -> entry.c_symbol)
       methods);
  let methods_by_id = method_map methods in
  List.iter (validate_method inventory) methods;
  List.iter (validate_property inventory methods_by_id) properties;
  let property_methods =
    properties
    |> List.concat_map (fun (entry : Binding_direct_spec.property_entry) ->
      entry.getter :: Option.to_list entry.setter)
  in
  require_count "property getter" 40
    (List.length
       (List.filter
          (fun (entry : Binding_direct_spec.method_entry) ->
            entry.semantics = Binding_direct_spec.Query)
          property_methods));
  require_count "property setter" 1
    (List.length
       (List.filter
          (fun (entry : Binding_direct_spec.method_entry) ->
            entry.semantics = Binding_direct_spec.Command)
          property_methods));
  let standalone = Binding_direct_methods.entries in
  require_count "standalone method" 18 (List.length standalone);
  require_count "standalone Query" 5
    (count_semantics standalone Binding_direct_spec.Query);
  require_count "standalone Command" 11
    (count_semantics standalone Binding_direct_spec.Command);
  require_count "standalone Blocking" 1
    (count_semantics standalone Binding_direct_spec.Blocking);
  require_count "standalone Process_identity" 1
    (count_semantics standalone Binding_direct_spec.Process_identity);
  let derived_methods = standalone @ property_methods in
  if
    List.map (fun (entry : Binding_direct_spec.method_entry) -> entry.sdk_id)
      derived_methods
    <> method_ids
  then fail "aggregate direct-plan method closure/order drift";
  let owners =
    methods
    |> List.map (fun (entry : Binding_direct_spec.method_entry) -> entry.owner)
    |> List.sort_uniq String.compare
  in
  require_count "receiver owner" 14 (List.length owners);
  List.iter validate_receiver owners;
  let legacy = binding_plan_ids () in
  let overlap =
    inventory_ids
    |> List.filter (fun identifier -> String_set.mem identifier legacy)
    |> List.sort_uniq String.compare
  in
  if overlap <> [] then
    fail "direct plan overlaps Binding_plan primary/companions: %s"
      (String.concat ", " overlap);
  Printf.printf
    "Metal direct plan validates 59 methods, 40 properties, 38 safe Device IDs, \
     and 61 raw-only inventory declarations\n%!"

let main () =
  let inventory_path = parse_options () in
  let inventory = index_inventory inventory_path in
  validate_plan inventory

let () = protect_main main
