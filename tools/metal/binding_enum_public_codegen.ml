type case =
  { id : string
  ; sdk_name : string
  ; ocaml_name : string
  ; bits : int64
  ; availability : Binding_availability.version option
  }

type family =
  { sdk_name : string
  ; module_name : string
  ; enum_id : string
  ; typedef_id : string
  ; availability : Binding_availability.version option
  ; cases : case list
  }

type output =
  { ml : string
  ; mli : string
  ; test_ml : string
  ; identifiers : string list
  ; family_count : int
  ; case_count : int
  }

let effective_availability values = Binding_availability.maximum values

let explicit_family (family : Binding_enum_codegen.family) =
  let cases =
    family.cases
    |> List.filter (fun (case : Binding_enum_codegen.selected_case) ->
      case.declaration.classification <> "scope-excluded")
    |> List.map (fun (case : Binding_enum_codegen.selected_case) ->
      { id = case.declaration.id
      ; sdk_name = case.declaration.name
      ; ocaml_name = case.ocaml_name
      ; bits = case.bits
      ; availability = case.declaration.macos_introduced
      })
  in
  { sdk_name = family.sdk_name
  ; module_name = family.module_name
  ; enum_id = family.enum_declaration.id
  ; typedef_id = family.typedef_declaration.id
  ; availability =
      effective_availability
        [ family.enum_declaration.macos_introduced
        ; family.typedef_declaration.macos_introduced
        ]
  ; cases
  }

let implicit_family
    (family : Binding_enum_implicit_codegen.selected_family) =
  let cases =
    List.map
      (fun (case : Binding_enum_implicit_codegen.selected_case) ->
        { id = case.declaration.id
        ; sdk_name = case.spec.sdk_name
        ; ocaml_name = case.ocaml_name
        ; bits = case.bits
        ; availability = case.declaration.macos_introduced
        })
      family.cases
  in
  { sdk_name = family.spec.sdk_name
  ; module_name = family.module_name
  ; enum_id = family.enum_declaration.id
  ; typedef_id = family.typedef_declaration.id
  ; availability =
      effective_availability
        [ family.enum_declaration.macos_introduced
        ; family.typedef_declaration.macos_introduced
        ]
  ; cases
  }

let availability = function
  | None -> "Always"
  | Some (version : Binding_availability.version) ->
      Printf.sprintf "Macos { major = %d; minor = %d; patch = %d }"
        version.major version.minor version.patch

let add_evidence output =
  Printf.bprintf output
    "(* metal-enum-evidence identifier-sha256: %s\n\
     \   metal-enum-evidence availability-sha256: %s\n\
     \   metal-enum-evidence declaration-count: %d *)\n"
    Binding_enum_bound_evidence.identifier_sha256
    Binding_enum_bound_evidence.availability_sha256
    Binding_enum_bound_evidence.bound_count

let add_common_header output =
  add_evidence output;
  Buffer.add_string output
    "type version = { major : int; minor : int; patch : int }\n\
     type availability = Always | Macos of version\n\n"

let render_ml families =
  let output = Buffer.create 65536 in
  add_common_header output;
  List.iter
    (fun (family : family) ->
      Printf.bprintf output "module %s = struct\n" family.module_name;
      Buffer.add_string output "  type t = int64\n";
      Printf.bprintf output "  let sdk_name = %S\n" family.sdk_name;
      Printf.bprintf output "  let availability = %s\n"
        (availability family.availability);
      List.iter
        (fun (case : case) ->
          Printf.bprintf output "  let %s : t = 0x%016LxL\n"
            case.ocaml_name case.bits;
          Printf.bprintf output "  let %s_availability = %s\n"
            case.ocaml_name (availability case.availability))
        family.cases;
      Buffer.add_string output "  let to_int64 (value : t) = value\n";
      Buffer.add_string output "  let all =\n    [ ";
      List.iteri
        (fun index (case : case) ->
          if index > 0 then Buffer.add_string output "    ; ";
          Printf.bprintf output "%S, %s, %s_availability\n"
            case.sdk_name case.ocaml_name case.ocaml_name)
        family.cases;
      Buffer.add_string output "    ]\n";
      Buffer.add_string output
        "  let of_int64 bits =\n\
         \    if List.exists (fun (_, value, _) -> Int64.equal bits value) all\n\
         \    then Some bits else None\n\
         \  let names value =\n\
         \    List.filter_map\n\
         \      (fun (name, candidate, _) ->\n\
         \        if Int64.equal value candidate then Some name else None)\n\
         \      all\n\
         end\n\n")
    families;
  Buffer.add_string output "let families =\n  [ ";
  List.iteri
    (fun index (family : family) ->
      if index > 0 then Buffer.add_string output "  ; ";
      Printf.bprintf output "%S, List.map (fun (name, value, available) ->\n\
                            \      name, %s.to_int64 value, available) %s.all\n"
        family.sdk_name family.module_name family.module_name)
    families;
  Buffer.add_string output "  ]\n";
  Buffer.contents output

let render_mli families =
  let output = Buffer.create 49152 in
  add_common_header output;
  List.iter
    (fun (family : family) ->
      Printf.bprintf output "module %s : sig\n" family.module_name;
      Buffer.add_string output "  type t = private int64\n";
      Buffer.add_string output "  val sdk_name : string\n";
      Buffer.add_string output "  val availability : availability\n";
      List.iter
        (fun (case : case) ->
          Printf.bprintf output "  val %s : t\n" case.ocaml_name;
          Printf.bprintf output "  val %s_availability : availability\n"
            case.ocaml_name)
        family.cases;
      Buffer.add_string output "  val to_int64 : t -> int64\n";
      Buffer.add_string output "  val of_int64 : int64 -> t option\n";
      Buffer.add_string output "  val names : t -> string list\n";
      Buffer.add_string output
        "  val all : (string * t * availability) list\nend\n\n")
    families;
  Buffer.add_string output
    "val families : (string * (string * int64 * availability) list) list\n";
  Buffer.contents output

let render_test families identifiers =
  let output = Buffer.create 65536 in
  add_evidence output;
  Buffer.add_string output
    "let fail format = Printf.ksprintf failwith format\n\n\
     let () =\n";
  List.iter
    (fun (family : family) ->
      List.iter
        (fun (case : case) ->
          Printf.bprintf output
            "  let value = Metal.Enum.%s.%s in\n\
             \  let bits = Metal.Enum.%s.to_int64 value in\n\
             \  if not (Int64.equal bits 0x%016LxL) then\n\
             \    fail %S bits;\n\
             \  (match Metal.Enum.%s.of_int64 bits with\n\
             \   | Some round_trip when Int64.equal (Metal.Enum.%s.to_int64 round_trip) bits -> ()\n\
             \   | _ -> fail %S);\n\
             \  if not (List.mem %S (Metal.Enum.%s.names value)) then\n\
             \    fail %S;\n"
            family.module_name case.ocaml_name family.module_name case.bits
            ("Metal enum value drift for " ^ case.id ^ ": %Ld")
            family.module_name family.module_name
            ("Metal enum round-trip failed for " ^ case.id)
            case.sdk_name family.module_name
            ("Metal enum name mapping failed for " ^ case.id))
        family.cases)
    families;
  Printf.bprintf output
    "  let family_count = List.length Metal.Enum.families in\n\
     \  let case_count = List.fold_left (fun n (_, cases) -> n + List.length cases) 0 Metal.Enum.families in\n\
     \  if family_count <> %d then fail \"Metal enum family count %%d, expected %d\" family_count;\n\
     \  if case_count <> %d then fail \"Metal enum case count %%d, expected %d\" case_count;\n\
     \  Printf.printf \"Metal public enum surface: %%d families, %%d cases, %d declaration IDs\\n%%!\" family_count case_count\n"
    (List.length families) (List.length families)
    (List.fold_left (fun n family -> n + List.length family.cases) 0 families)
    (List.fold_left (fun n family -> n + List.length family.cases) 0 families)
    (List.length identifiers);
  Buffer.contents output

let generate ~explicit ~implicit =
  let families =
    List.map explicit_family explicit.Binding_enum_codegen.families
    @ List.map implicit_family implicit
  in
  let module_names = List.map (fun (family : family) -> family.module_name) families in
  let sorted = List.sort String.compare module_names in
  let unique = List.sort_uniq String.compare module_names in
  if sorted <> unique then invalid_arg "duplicate public Metal enum module name";
  let identifiers =
    families
    |> List.concat_map (fun (family : family) ->
      family.enum_id :: family.typedef_id
      :: List.map (fun (case : case) -> case.id) family.cases)
    |> List.sort String.compare
  in
  let family_count = List.length families in
  let case_count =
    List.fold_left (fun count (family : family) -> count + List.length family.cases) 0
      families
  in
  { ml = render_ml families
  ; mli = render_mli families
  ; test_ml = render_test families identifiers
  ; identifiers
  ; family_count
  ; case_count
  }
