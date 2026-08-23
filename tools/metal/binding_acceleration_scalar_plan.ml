type declaration =
  { id : string; kind : string; owner : string option; name : string
  ; header : string; signature : string; macos_introduced : string option
  ; classification : string }

type representation = Bool | Float | Unsigned | Enum of string
type property =
  { property : declaration; getter : declaration; setter : declaration option
  ; representation : representation }
type selection = { properties : property list; identifiers : string list; owners : string list }

let expected_property_count = 140
let expected_getter_count = 140
let expected_setter_count = 139
let expected_identifier_count = 419
let expected_owner_count = 23

let headers = [ "Metal/MTLAccelerationStructure.h"; "Metal/MTL4AccelerationStructure.h" ]
let enums =
  [ "MTLAccelerationStructureInstanceDescriptorType"; "MTLAccelerationStructureUsage"
  ; "MTLAttributeFormat"; "MTLCurveBasis"; "MTLCurveEndCaps"; "MTLCurveType"
  ; "MTLIndexType"; "MTLMatrixLayout"; "MTLMotionBorderMode"; "MTLTransformType" ]

let representation = function
  | "BOOL" -> Some Bool | "float" -> Some Float | "NSUInteger" -> Some Unsigned
  | signature when List.mem signature enums -> Some (Enum signature)
  | _ -> None

let fail format = Printf.ksprintf (fun text -> invalid_arg ("Metal acceleration scalar plan: " ^ text)) format
let capitalize name = String.mapi (fun index c -> if index = 0 then Char.uppercase_ascii c else c) name

let select declarations =
  let table = Hashtbl.create (List.length declarations) in
  List.iter (fun declaration -> Hashtbl.replace table declaration.id declaration) declarations;
  let properties =
    declarations
    |> List.filter_map (fun property ->
      match property.kind, property.owner, representation property.signature with
      | "property", Some owner, Some representation
        when (property.classification = "unreviewed" || property.classification = "bound")
             && List.mem property.header headers ->
          let getter_name = if property.name = "active" then "isActive" else property.name in
          let getter_id = "method:-[" ^ owner ^ " " ^ getter_name ^ "]" in
          let setter_id = "method:-[" ^ owner ^ " set" ^ capitalize property.name ^ ":]" in
          let getter = match Hashtbl.find_opt table getter_id with Some value -> value | None -> fail "missing getter %s" getter_id in
          let setter = Hashtbl.find_opt table setter_id in
          Some { property; getter; setter; representation }
      | _ -> None)
  in
  let identifiers =
    List.concat_map (fun value -> value.property.id :: value.getter.id :: Option.fold ~none:[] ~some:(fun setter -> [ setter.id ]) value.setter) properties
  in
  let owners = properties |> List.filter_map (fun value -> value.property.owner) |> List.sort_uniq String.compare in
  let getters = List.length properties in
  let setters = List.fold_left (fun count value -> count + Option.fold ~none:0 ~some:(fun _ -> 1) value.setter) 0 properties in
  if List.length properties <> expected_property_count then fail "expected %d properties, got %d" expected_property_count (List.length properties);
  if getters <> expected_getter_count || setters <> expected_setter_count then fail "getter/setter cardinality drift";
  if List.length identifiers <> expected_identifier_count then fail "expected %d IDs, got %d" expected_identifier_count (List.length identifiers);
  if List.length (List.sort_uniq String.compare identifiers) <> List.length identifiers then fail "duplicate identifier";
  if List.length owners <> expected_owner_count then fail "expected %d owners, got %d" expected_owner_count (List.length owners);
  { properties; identifiers; owners }

let source_paths =
  [ "tools/metal/binding_acceleration_scalar_plan.ml"
  ; "tools/metal/binding_acceleration_scalar_plan.mli"
  ; "tools/metal/binding_acceleration_scalar_codegen.ml"
  ; "tools/metal/binding_acceleration_scalar_codegen.mli"
  ; "tools/metal/binding_acceleration_scalar_evidence.ml"
  ; "tools/metal/binding_acceleration_scalar_evidence.mli" ]
