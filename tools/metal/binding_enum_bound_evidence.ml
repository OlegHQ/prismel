module String_set = Set.Make (String)

let explicit_bound_count = 522
let implicit_bound_count = 37
let bound_count = 559
let excluded_count = 25
let case_count = 421
let selected_case_count = 446

(* SHA-256 of the sorted, newline-terminated selected in-scope identifiers. *)
let identifier_sha256 =
  "9dba9c127b24c36b0787937f00ef68ac8bcd3aebbe3e5b7be053926953073fb4"

(* SHA-256 of sorted TSV rows:
   id, header, line, signature, macOS introduction, availability sources. *)
let availability_sha256 =
  "6a5836e6cb1585dd97e107f6c2edbf58e999a9336a425f5ea0292b755ed33d55"

let explicit_family_names = Binding_enum_plan.family_names

let implicit_family_names =
  List.map
    (fun (family : Binding_enum_implicit_plan.family) -> family.sdk_name)
    Binding_enum_implicit_plan.families

let family_names = explicit_family_names @ implicit_family_names
let family_set = String_set.of_list family_names

let excluded_identifiers =
  [ "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily1_v1"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily1_v2"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily1_v3"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily1_v4"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily1_v5"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily2_v1"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily2_v2"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily2_v3"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily2_v4"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily2_v5"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily3_v1"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily3_v2"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily3_v3"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily3_v4"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily4_v1"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily4_v2"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_iOS_GPUFamily5_v1"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_tvOS_GPUFamily1_v1"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_TVOS_GPUFamily1_v1"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_tvOS_GPUFamily1_v2"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_tvOS_GPUFamily1_v3"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_tvOS_GPUFamily1_v4"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_tvOS_GPUFamily2_v1"
  ; "enum-case:MTLFeatureSet:MTLFeatureSet_tvOS_GPUFamily2_v2"
  ; "enum-case:MTLLanguageVersion:MTLLanguageVersion1_0"
  ]

let excluded_set = String_set.of_list excluded_identifiers

let family_after_prefix ~prefix identifier =
  if not (String.starts_with ~prefix identifier) then None
  else
    let start = String.length prefix in
    let suffix = String.sub identifier start (String.length identifier - start) in
    match String.index_opt suffix ':' with
    | None -> Some suffix
    | Some separator -> Some (String.sub suffix 0 separator)

let selected_family identifier =
  match family_after_prefix ~prefix:"enum:" identifier with
  | Some family -> Some family
  | None ->
      (match family_after_prefix ~prefix:"typedef:" identifier with
       | Some family -> Some family
       | None -> family_after_prefix ~prefix:"enum-case:" identifier)

let is_selected_identifier identifier =
  match selected_family identifier with
  | Some family when String_set.mem family family_set ->
      String.equal identifier ("enum:" ^ family)
      || String.equal identifier ("typedef:" ^ family)
      || String.starts_with ~prefix:("enum-case:" ^ family ^ ":") identifier
  | Some _ | None -> false

let is_scope_excluded_identifier identifier =
  String_set.mem identifier excluded_set

let is_bound_identifier identifier =
  is_selected_identifier identifier && not (is_scope_excluded_identifier identifier)

let source_paths =
  [ "tools/metal/binding_enum_bound_evidence.ml"
  ; "tools/metal/binding_enum_bound_evidence.mli"
  ]

let reject_duplicates description values =
  let unique = String_set.of_list values in
  if String_set.cardinal unique <> List.length values then
    invalid_arg ("duplicate " ^ description)

let () =
  if List.length explicit_family_names <> 62 then
    invalid_arg "bound Metal explicit enum family count drift";
  if List.length implicit_family_names <> 7 then
    invalid_arg "bound Metal implicit enum family count drift";
  reject_duplicates "bound Metal enum family" family_names;
  if List.length excluded_identifiers <> excluded_count then
    invalid_arg "bound Metal enum exclusion count drift";
  reject_duplicates "bound Metal enum exclusion" excluded_identifiers;
  if List.exists (fun id -> not (is_selected_identifier id)) excluded_identifiers then
    invalid_arg "bound Metal enum exclusion escaped selected families";
  if explicit_bound_count + implicit_bound_count <> bound_count then
    invalid_arg "bound Metal enum declaration total drift";
  if case_count + excluded_count <> selected_case_count then
    invalid_arg "bound Metal enum case total drift"
