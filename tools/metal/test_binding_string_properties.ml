open Binding_string_spec

let fail format = Printf.ksprintf failwith format

let inventory_by_id path =
  let json = Yojson.Safe.from_file path in
  let symbols = Yojson.Safe.Util.(json |> member "symbols" |> to_list) in
  let table = Hashtbl.create (List.length symbols) in
  List.iter
    (fun symbol ->
      let open Yojson.Safe.Util in
      Hashtbl.add table (symbol |> member "id" |> to_string) symbol)
    symbols;
  table

let string_field name json =
  Yojson.Safe.Util.(json |> member name |> to_string)

let optional_string_field name json =
  match Yojson.Safe.Util.(json |> member name) with
  | `Null -> None
  | `String value -> Some value
  | _ -> fail "invalid %s field" name

let version_string (version : Binding_availability.version) =
  if version.patch = 0 then Printf.sprintf "%d.%d" version.major version.minor
  else Printf.sprintf "%d.%d.%d" version.major version.minor version.patch

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let entries = Binding_string_properties.entries in
  let count = List.length entries in
  if count <> Binding_string_properties.expected_property_count then
    fail "property count: expected %d, got %d"
      Binding_string_properties.expected_property_count count;
  let ids = List.concat_map inventory_ids entries in
  if List.length ids <> Binding_string_properties.expected_inventory_id_count then
    fail "inventory ID count: expected %d, got %d"
      Binding_string_properties.expected_inventory_id_count (List.length ids);
  let setters = List.filter_map (fun entry -> entry.setter_sdk_id) entries in
  if List.length setters <> Binding_string_properties.expected_setter_count then
    fail "setter count: expected %d, got %d"
      Binding_string_properties.expected_setter_count (List.length setters);
  let sorted = List.sort String.compare ids in
  List.iter2
    (fun left right -> if String.equal left right then fail "duplicate ID: %s" left)
    sorted (List.tl sorted @ [ "" ]);
  let inventory = inventory_by_id Sys.argv.(1) in
  List.iter
    (fun entry ->
      List.iter
        (fun id ->
          let symbol =
            match Hashtbl.find_opt inventory id with
            | Some symbol -> symbol
            | None -> fail "missing inventory ID: %s" id
          in
          let expected =
            if Binding_argument_reflection_evidence.is_bound_identifier id then
              "bound"
            else if
              String.starts_with
                ~prefix:"property:MTLAccelerationStructureGeometryDescriptor:label"
                id
              || String.starts_with
                   ~prefix:"method:-[MTLAccelerationStructureGeometryDescriptor "
                   id
              || String.starts_with
                   ~prefix:"property:MTL4AccelerationStructureGeometryDescriptor:label"
                   id
              || String.starts_with
                   ~prefix:"method:-[MTL4AccelerationStructureGeometryDescriptor "
                   id
            then "bound"
            else if List.mem id Binding_resource_safe_reachability.promotable_ids
                    || List.mem id Binding_shader_safe_reachability.promotable_ids
                    || List.mem id Binding_mesh_tile_safe_reachability.promotable_ids
                    || List.mem id Binding_command_support_safe_reachability.promotable_ids
            then "bound"
            else "unreviewed"
          in
          if not (String.equal (string_field "classification" symbol) expected) then
            fail "expected %s inventory ID: %s" expected id)
        (inventory_ids entry);
      let property = Hashtbl.find inventory entry.property_sdk_id in
      if not (String.equal (string_field "signature" property) entry.signature) then
        fail "signature mismatch: %s" entry.property_sdk_id;
      if not (String.equal (string_field "header" property) entry.header) then
        fail "header mismatch: %s" entry.property_sdk_id;
      let expected_version = optional_string_field "macos_introduced" property in
      if expected_version <> Some (version_string entry.macos_introduced) then
        fail "availability mismatch: %s" entry.property_sdk_id;
      (match entry.nullability, getter_ocaml_type entry with
      | Nonnull, "string" | Nullable, "string option" -> ()
      | _ -> fail "nullable OCaml type mismatch: %s" entry.property_sdk_id);
      match entry.receiver_status with
      | Pending_receiver_catalog ->
          (try
             ignore (native_getter_expression entry);
             fail "unqualified receiver emitted native code: %s" entry.owner
           with Invalid_argument _ -> ())
      | Qualified_direct _ | Qualified_polymorphic _ ->
          if String.equal (native_getter_expression entry) "" then
            fail "empty native getter: %s" entry.property_sdk_id)
    entries;
  Printf.printf "Metal NSString shard: %d properties, %d getters, %d setters, %d inventory IDs\n"
    count Binding_string_properties.expected_getter_count
    (List.length setters) (List.length ids)
