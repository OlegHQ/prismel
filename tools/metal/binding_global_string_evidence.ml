module String_set = Set.Make (String)

let bound_count = 33

(* SHA-256 of sorted, newline-terminated selected inventory identifiers. *)
let identifier_sha256 =
  "6d76d299d8fa78a8329731d3e1d9033991ae41672720ce2ebbcd893dbe27b234"

(* SHA-256 of sorted, newline-terminated TSV rows containing identifier,
   header, line, exact SDK signature, macOS introduction, and sorted
   availability-source header:line sites. *)
let availability_sha256 =
  "6400b68a92aed651379caef83f30e1926d2e093436b8a039d5395fadc9d91172"

let identifiers =
  Binding_global_string_spec.entries
  |> List.map (fun entry -> entry.Binding_global_string_spec.sdk_id)

let identifier_set = String_set.of_list identifiers
let is_bound_identifier identifier = String_set.mem identifier identifier_set

let source_paths =
  [ "tools/metal/binding_global_string_spec.ml"
  ; "tools/metal/binding_global_string_spec.mli"
  ; "tools/metal/binding_global_string_codegen.ml"
  ; "tools/metal/binding_global_string_codegen.mli"
  ; "tools/metal/binding_global_string_evidence.ml"
  ; "tools/metal/binding_global_string_evidence.mli"
  ; "tools/metal/binding_global_string_conformance_codegen.ml"
  ; "tools/metal/binding_global_string_conformance_codegen.mli"
  ]

let () =
  if List.length identifiers <> bound_count then
    invalid_arg "Metal global-string evidence cardinality drift";
  if String_set.cardinal identifier_set <> bound_count then
    invalid_arg "Metal global-string evidence duplicate identifier"

