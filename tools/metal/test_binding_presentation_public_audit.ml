let () =
  let module A = Binding_presentation_public_audit in
  if List.length A.selector_reachable <> 21 then failwith "presentation selector closure drift";
  if List.length A.property_companions <> 13 then failwith "presentation companion closure drift";
  if List.length A.safe_reachable <> 34 then failwith "presentation safe closure drift";
  if List.length A.missing_public <> 91 then failwith "presentation public gap drift";
  List.iter (fun id -> if not (List.mem id Binding_presentation_manifest.ids) then failwith ("non-manifest safe ID: " ^ id)) A.safe_reachable;
  if List.sort_uniq String.compare (A.safe_reachable @ A.missing_public)
     <> List.sort_uniq String.compare Binding_presentation_manifest.ids
  then failwith "presentation public audit does not close exact125"
