type declaration =
  { id : string
  ; kind : string
  ; owner : string option
  ; signature : string
  ; classification : string
  }

type selection =
  { declarations : declaration list
  ; method_count : int
  ; property_count : int
  ; owner_count : int
  }

let expected_method_count = 96
let expected_property_count = 47
let expected_declaration_count = 143
let expected_owner_count = 34

let fail format =
  Printf.ksprintf (fun message -> invalid_arg ("Metal struct plan: " ^ message)) format

let relevant declaration =
  String.equal declaration.classification "unreviewed"
  && (String.equal declaration.kind "method"
      || String.equal declaration.kind "property")
  && Binding_struct_spec.mechanically_safe_signature declaration.signature
  && List.exists
       (Binding_struct_spec.contains_type declaration.signature)
       Binding_struct_spec.objc_types

let select declarations =
  let declarations = List.filter relevant declarations in
  let ids = List.map (fun declaration -> declaration.id) declarations in
  let sorted_ids = List.sort String.compare ids in
  let rec reject_duplicates = function
    | left :: right :: _ when String.equal left right ->
        fail "duplicate inventory identifier %s" left
    | _ :: rest -> reject_duplicates rest
    | [] -> ()
  in
  reject_duplicates sorted_ids;
  let method_count =
    List.fold_left
      (fun count declaration ->
        count + if String.equal declaration.kind "method" then 1 else 0)
      0 declarations
  in
  let property_count = List.length declarations - method_count in
  let owner_count =
    declarations
    |> List.filter_map (fun declaration -> declaration.owner)
    |> List.sort_uniq String.compare |> List.length
  in
  if method_count <> expected_method_count then
    fail "expected %d methods, found %d" expected_method_count method_count;
  if property_count <> expected_property_count then
    fail "expected %d properties, found %d" expected_property_count property_count;
  if List.length declarations <> expected_declaration_count then
    fail "expected %d declarations, found %d" expected_declaration_count
      (List.length declarations);
  if owner_count <> expected_owner_count then
    fail "expected %d owners, found %d" expected_owner_count owner_count;
  { declarations; method_count; property_count; owner_count }
