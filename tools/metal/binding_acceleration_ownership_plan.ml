type declaration =
  { id : string; kind : string; owner : string option; name : string
  ; header : string; signature : string; macos_introduced : string option
  ; classification : string }
type ownership = Borrowed_buffer | Copied_string | Copied_retained_array | Buffer_range | Resource_id
type property = { property : declaration; getter : declaration; setter : declaration option; ownership : ownership }
type selection = { properties : property list; identifiers : string list; owners : string list }
let expected_property_count = 49
let expected_identifier_count = 146
let expected_owner_count = 22
let headers = [ "Metal/MTLAccelerationStructure.h"; "Metal/MTL4AccelerationStructure.h" ]
let ownership signature =
  if signature = "MTL4BufferRange" then Some Buffer_range
  else if signature = "NSString * _Nullable" then Some Copied_string
  else if signature = "MTLResourceID" then Some Resource_id
  else if String.starts_with ~prefix:"NSArray<" signature then Some Copied_retained_array
  else if signature = "id<MTLBuffer> _Nullable" then Some Borrowed_buffer
  else None
let fail format = Printf.ksprintf (fun text -> invalid_arg ("Metal acceleration ownership plan: " ^ text)) format
let capitalize name = String.mapi (fun index c -> if index = 0 then Char.uppercase_ascii c else c) name
let select declarations =
  let table = Hashtbl.create (List.length declarations) in
  List.iter (fun declaration -> Hashtbl.replace table declaration.id declaration) declarations;
  let properties = declarations |> List.filter_map (fun property ->
    match property.kind, property.owner, ownership property.signature with
    | "property", Some owner, Some ownership
      when property.classification = "unreviewed" && List.mem property.header headers ->
        let getter_id = "method:-[" ^ owner ^ " " ^ property.name ^ "]" in
        let setter_id = "method:-[" ^ owner ^ " set" ^ capitalize property.name ^ ":]" in
        let getter = match Hashtbl.find_opt table getter_id with Some value -> value | None -> fail "missing getter %s" getter_id in
        Some { property; getter; setter = Hashtbl.find_opt table setter_id; ownership }
    | _ -> None) in
  let identifiers = List.concat_map (fun value -> value.property.id :: value.getter.id :: Option.fold ~none:[] ~some:(fun setter -> [setter.id]) value.setter) properties in
  let owners = properties |> List.filter_map (fun value -> value.property.owner) |> List.sort_uniq String.compare in
  if List.length properties <> expected_property_count then fail "expected %d properties, got %d" expected_property_count (List.length properties);
  if List.length identifiers <> expected_identifier_count then fail "expected %d IDs, got %d" expected_identifier_count (List.length identifiers);
  if List.length (List.sort_uniq String.compare identifiers) <> List.length identifiers then fail "duplicate identifier";
  if List.length owners <> expected_owner_count then fail "expected %d owners, got %d" expected_owner_count (List.length owners);
  { properties; identifiers; owners }
let source_paths =
  [ "tools/metal/binding_acceleration_ownership_plan.ml"; "tools/metal/binding_acceleration_ownership_plan.mli"
  ; "tools/metal/binding_acceleration_ownership_codegen.ml"; "tools/metal/binding_acceleration_ownership_codegen.mli"
  ; "tools/metal/binding_acceleration_ownership_evidence.ml"; "tools/metal/binding_acceleration_ownership_evidence.mli" ]
