let render_native_type_checks symbols =
  let selected =
    List.filter
      (fun symbol ->
        symbol.Binding_render_encoder_evidence.owner
        = Some Binding_render_encoder_plan.owner)
      symbols
  in
  let output = Buffer.create 32768 in
  Buffer.add_string output
    "/* Exact MTLRenderCommandEncoder owner closure. Calls remain in typed\n   handwritten command templates; generic objc_msgSend is forbidden. */\n";
  List.iter
    (fun symbol ->
      Printf.bprintf output "/* %s :: %s */\n"
        symbol.Binding_render_encoder_evidence.id symbol.signature)
    (List.sort
       (fun (left : Binding_render_encoder_evidence.symbol)
            (right : Binding_render_encoder_evidence.symbol) ->
         String.compare left.id right.id)
       selected);
  Buffer.contents output

let render_manifest symbols =
  let identifiers = Binding_render_encoder_evidence.validate_inventory symbols in
  `Assoc
    [ "owner", `String Binding_render_encoder_plan.owner
    ; "declaration_count", `Int (List.length identifiers)
    ; "safe_bound_count", `Int 0
    ; "signature_digest",
      `String Binding_render_encoder_plan.expected_signature_digest
    ; "identifiers", `List (List.map (fun id -> `String id) identifiers)
    ]
