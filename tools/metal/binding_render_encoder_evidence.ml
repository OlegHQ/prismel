type symbol =
  { id : string
  ; kind : string
  ; owner : string option
  ; signature : string
  ; macos_introduced : string option
  ; attributes : string list
  ; classification : string
  }

let fail format =
  Printf.ksprintf
    (fun message -> invalid_arg ("Metal render-encoder evidence: " ^ message))
    format

let canonical symbol =
  String.concat "\t"
    [ symbol.id; symbol.kind; symbol.signature
    ; Option.value ~default:"" symbol.macos_introduced
    ; symbol.attributes |> List.sort String.compare |> String.concat ","
    ]

let validate_inventory symbols =
  let selected =
    List.filter
      (fun symbol -> symbol.owner = Some Binding_render_encoder_plan.owner)
      symbols
  in
  let methods = List.filter (fun symbol -> symbol.kind = "method") selected in
  let properties =
    List.filter (fun symbol -> symbol.kind = "property") selected
  in
  if List.length methods <> Binding_render_encoder_plan.expected_method_count
  then fail "expected %d methods, got %d"
      Binding_render_encoder_plan.expected_method_count (List.length methods);
  if List.length properties
     <> Binding_render_encoder_plan.expected_property_count
  then fail "expected %d properties, got %d"
      Binding_render_encoder_plan.expected_property_count
      (List.length properties);
  if List.length selected
     <> Binding_render_encoder_plan.expected_declaration_count
  then fail "owner closure count drift";
  let ids = List.map (fun symbol -> symbol.id) selected in
  if List.length ids <> List.length (List.sort_uniq String.compare ids) then
    fail "duplicate declaration ID";
  List.iter
    (fun symbol ->
      if symbol.signature = "" then fail "empty signature for %s" symbol.id;
      if symbol.classification <> "unreviewed"
         && symbol.classification <> "bound"
      then fail "unexpected classification for %s" symbol.id)
    selected;
  List.sort String.compare ids
