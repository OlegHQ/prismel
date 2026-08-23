type declaration =
  { id : string; kind : string; owner : string option; name : string
  ; header : string; signature : string; macos_introduced : string option
  ; classification : string }

type selection =
  { declarations : declaration list
  ; identifiers : string list
  ; owners : string list
  ; method_count : int }

let expected_identifier_count = 115
let expected_owner_count = 17

let complete_headers =
  [ "Metal/MTLAccelerationStructureCommandEncoder.h"
  ; "Metal/MTLIntersectionFunctionTable.h"
  ; "Metal/MTLVisibleFunctionTable.h" ]

let tokens =
  [ "AccelerationStructure"; "IntersectionFunctionTable"
  ; "VisibleFunctionTable"; "FunctionHandle" ]

let contains source needle =
  let source_length = String.length source and needle_length = String.length needle in
  let rec loop index =
    index + needle_length <= source_length
    && (String.sub source index needle_length = needle || loop (index + 1))
  in
  needle_length = 0 || loop 0

let selected declaration =
  (declaration.classification = "unreviewed"
   || declaration.classification = "bound")
  && ((List.mem declaration.header complete_headers
       && List.mem declaration.kind
            [ "class"; "protocol"; "typedef"; "property"; "method" ]
       && declaration.id <> "typedef:MTLIntersectionFunctionSignature")
      || (declaration.kind = "method"
          && declaration.header <> "Metal/MTLAccelerationStructure.h"
          && declaration.header <> "Metal/MTL4AccelerationStructure.h"
          && List.exists
               (fun token ->
                 contains declaration.name token
                 || contains declaration.signature token)
               tokens))

let select declarations =
  let declarations = List.filter selected declarations in
  let identifiers = List.map (fun value -> value.id) declarations in
  let owners =
    declarations |> List.filter_map (fun value -> value.owner)
    |> List.sort_uniq String.compare
  in
  let method_count =
    List.fold_left
      (fun count value -> count + if value.kind = "method" then 1 else 0)
      0 declarations
  in
  if List.length identifiers <> expected_identifier_count then
    invalid_arg
      (Printf.sprintf "Metal acceleration operations: expected %d IDs, got %d"
         expected_identifier_count (List.length identifiers));
  if List.length (List.sort_uniq String.compare identifiers)
     <> List.length identifiers
  then invalid_arg "Metal acceleration operations: duplicate identifier";
  if List.length owners <> expected_owner_count then
    invalid_arg "Metal acceleration operations: owner closure drift";
  { declarations; identifiers; owners; method_count }

let source_paths =
  [ "tools/metal/binding_acceleration_operations_plan.ml"
  ; "tools/metal/binding_acceleration_operations_plan.mli"
  ; "tools/metal/binding_acceleration_operations_codegen.ml"
  ; "tools/metal/binding_acceleration_operations_codegen.mli"
  ; "tools/metal/binding_acceleration_operations_evidence.ml"
  ; "tools/metal/binding_acceleration_operations_evidence.mli" ]
