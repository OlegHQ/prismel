open Binding_descriptor_property_spec

type inventory_symbol =
  { id : string
  ; kind : string
  ; owner : string option
  ; name : string
  ; header : string
  ; signature : string
  ; macos_introduced : string option
  ; attributes : string list
  ; classification : string
  }

let promotion_ids =
  Binding_render_pipeline_scalar_plan.entries
  |> List.concat_map inventory_ids |> List.sort String.compare

let expected_bound_count = 111

let fail format =
  Printf.ksprintf
    (fun message -> invalid_arg ("Metal render-pipeline scalar evidence: " ^ message))
    format

let capitalize value =
  String.init (String.length value) (fun index ->
    if index = 0 then Char.uppercase_ascii value.[index] else value.[index])

let validate_inventory symbols =
  if List.length promotion_ids <> expected_bound_count then
    fail "promotion count drift: expected %d, got %d" expected_bound_count
      (List.length promotion_ids);
  let table = Hashtbl.create (List.length symbols) in
  List.iter
    (fun symbol ->
      if Hashtbl.mem table symbol.id then fail "duplicate inventory ID %s" symbol.id;
      Hashtbl.add table symbol.id symbol)
    symbols;
  Binding_render_pipeline_scalar_plan.entries
  |> List.iter (fun (entry : Binding_descriptor_property_spec.entry) ->
    let setter_name = "set" ^ capitalize entry.name ^ ":" in
    let expected =
      [ property_sdk_id entry, "property", entry.name, entry.signature
      ; getter_sdk_id entry, "method", entry.getter_name,
        "instance () -> " ^ entry.signature
      ; setter_sdk_id entry, "method", setter_name,
        "instance (" ^ entry.signature ^ ") -> void"
      ]
    in
    List.iter
      (fun (id, kind, name, signature) ->
        let symbol =
          match Hashtbl.find_opt table id with
          | Some symbol -> symbol
          | None -> fail "missing inventory ID %s" id
        in
        if symbol.kind <> kind then fail "%s kind mismatch" id;
        if symbol.owner <> Some entry.owner then fail "%s owner mismatch" id;
        if symbol.name <> name then fail "%s name mismatch" id;
        if symbol.header <> entry.header then fail "%s header mismatch" id;
        if symbol.signature <> signature then
          fail "%s signature mismatch: expected %S, got %S" id signature
            symbol.signature;
        if symbol.macos_introduced <> Some entry.macos_introduced then
          fail "%s availability mismatch" id;
        if List.sort String.compare symbol.attributes
           <> List.sort String.compare entry.attributes
        then fail "%s attributes mismatch" id;
        if symbol.classification <> "unreviewed"
           && symbol.classification <> "bound"
        then fail "%s has invalid classification %s" id symbol.classification)
      expected)
