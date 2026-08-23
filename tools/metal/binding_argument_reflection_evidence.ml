open Binding_argument_reflection_plan

type symbol =
  { id : string
  ; kind : string
  ; owner : string option
  ; name : string
  ; header : string
  ; signature : string
  ; macos_introduced : string option
  ; classification : string
  }

let fail fmt =
  Printf.ksprintf (fun text -> invalid_arg ("Metal argument reflection evidence: " ^ text)) fmt

let result_signature entry =
  match entry.result with
  | Bool -> "BOOL"
  | Unsigned -> "NSUInteger"
  | Enum name -> name
  | String -> "NSString * _Nonnull"
  | Retained_object { objc_type; nullable } ->
      objc_type ^ " * " ^ if nullable then "_Nullable" else "_Nonnull"
  | Retained_array element -> "NSArray<" ^ element ^ " *> * _Nonnull"

let expected_signature entry =
  let result = result_signature entry in
  let arguments =
    match entry.arguments with
    | [] -> ""
    | [ String_argument ] -> "NSString * _Nonnull __strong"
    | _ -> fail "unsupported argument list for %s" entry.sdk_id
  in
  "instance (" ^ arguments ^ ") -> " ^ result

let validate_inventory symbols =
  if List.length entries <> expected_method_count then
    fail "expected %d methods, got %d" expected_method_count (List.length entries);
  if List.length inventory_ids <> expected_declaration_count then
    fail "expected %d declarations, got %d" expected_declaration_count
      (List.length inventory_ids);
  let unique = List.sort_uniq String.compare inventory_ids in
  if List.length unique <> List.length inventory_ids then fail "duplicate planned identifier";
  let table = Hashtbl.create (List.length symbols) in
  List.iter (fun symbol -> Hashtbl.replace table symbol.id symbol) symbols;
  List.iter
    (fun entry ->
      let method_symbol =
        match Hashtbl.find_opt table entry.sdk_id with
        | Some symbol -> symbol
        | None -> fail "missing %s" entry.sdk_id
      in
      if method_symbol.kind <> "method"
         || method_symbol.owner <> Some entry.owner
         || method_symbol.name <> entry.selector
         || method_symbol.header <> "Metal/MTLArgument.h"
         || method_symbol.signature <> expected_signature entry
         || method_symbol.macos_introduced <> Some entry.macos_introduced
         || method_symbol.classification <> "unreviewed"
      then fail "inventory drift for %s" entry.sdk_id;
      Option.iter
        (fun id ->
          let property =
            match Hashtbl.find_opt table id with
            | Some symbol -> symbol
            | None -> fail "missing %s" id
          in
          if property.kind <> "property"
             || property.owner <> Some entry.owner
             || id <> "property:" ^ entry.owner ^ ":" ^ property.name
             || property.header <> "Metal/MTLArgument.h"
             || property.signature <> result_signature entry
             || property.macos_introduced <> Some entry.macos_introduced
             || property.classification <> "unreviewed"
          then fail "inventory drift for %s" id)
        entry.property_id)
    entries;
  let pending_header_ids =
    symbols
    |> List.filter (fun symbol ->
         symbol.header = "Metal/MTLArgument.h"
         && symbol.classification = "unreviewed"
         && (symbol.kind = "method" || symbol.kind = "property"))
    |> List.map (fun symbol -> symbol.id) |> List.sort String.compare
  in
  if pending_header_ids <> List.sort String.compare inventory_ids then
    fail "plan does not exactly close the pending method/property header surface"
