let properties = Binding_direct_properties.entries

let property_methods =
  properties
  |> List.concat_map (fun (entry : Binding_direct_spec.property_entry) ->
    entry.getter :: Option.to_list entry.setter)

let methods = Binding_direct_methods.entries @ property_methods

let inventory_ids =
  List.map (fun (entry : Binding_direct_spec.method_entry) -> entry.sdk_id) methods
  @ List.map
      (fun (entry : Binding_direct_spec.property_entry) -> entry.sdk_id)
      properties

let safe_device_properties =
  properties
  |> List.filter (fun (entry : Binding_direct_spec.property_entry) ->
    String.equal entry.owner "MTLDevice"
    && not (String.equal entry.name "shouldMaximizeConcurrentCompilation"))

let safe_device_identifiers =
  safe_device_properties
  |> List.concat_map (fun (entry : Binding_direct_spec.property_entry) ->
    [ entry.sdk_id; entry.getter.sdk_id ])

let is_safe_device_identifier identifier =
  List.mem identifier safe_device_identifiers

let expected_method_count = 59
let expected_property_count = 40
let expected_declaration_count = 99
let expected_owner_count = 14

let source_paths =
  [ "tools/metal/binding_direct_spec.ml"
  ; "tools/metal/binding_direct_spec.mli"
  ; "tools/metal/binding_direct_methods.ml"
  ; "tools/metal/binding_direct_methods.mli"
  ; "tools/metal/binding_direct_properties.ml"
  ; "tools/metal/binding_direct_properties.mli"
  ; "tools/metal/binding_direct_plan.ml"
  ; "tools/metal/binding_direct_plan.mli"
  ]

let fail format =
  Printf.ksprintf
    (fun message -> invalid_arg ("Metal direct-call plan: " ^ message))
    format

let reject_duplicates description values =
  let rec loop = function
    | left :: right :: _ when String.equal left right ->
        fail "duplicate %s: %s" description left
    | _ :: rest -> loop rest
    | [] -> ()
  in
  loop (List.sort String.compare values)

let validate () =
  Binding_direct_methods.validate ();
  Binding_direct_properties.validate ();
  if List.length methods <> expected_method_count then
    fail "expected %d methods, found %d" expected_method_count
      (List.length methods);
  if List.length properties <> expected_property_count then
    fail "expected %d properties, found %d" expected_property_count
      (List.length properties);
  if List.length inventory_ids <> expected_declaration_count then
    fail "expected %d declarations, found %d" expected_declaration_count
      (List.length inventory_ids);
  if List.length safe_device_properties <> 19
     || List.length safe_device_identifiers <> 38
  then fail "expected 19 safe Device properties and 38 identifiers";
  reject_duplicates "inventory identifier" inventory_ids;
  let presentation_promotable =
    Binding_presentation_public_audit.safe_reachable
    @ Binding_presentation_safe_handoff.promotable_ids
  in
  let generated_presentation =
    inventory_ids |> List.filter (fun id -> List.mem id presentation_promotable)
    |> List.sort_uniq String.compare
  in
  let expected_generated_presentation =
    [ "method:-[MTLCommandBuffer GPUEndTime]"
    ; "method:-[MTLCommandBuffer GPUStartTime]"
    ; "method:-[MTLCommandBuffer enqueue]"
    ; "method:-[MTLCommandBuffer errorOptions]"
    ; "method:-[MTLCommandBuffer kernelEndTime]"
    ; "method:-[MTLCommandBuffer kernelStartTime]"
    ; "method:-[MTLCommandBuffer popDebugGroup]"
    ; "method:-[MTLCommandBuffer retainedReferences]"
    ; "method:-[MTLCommandBuffer waitUntilScheduled]"
    ; "property:MTLCommandBuffer:GPUEndTime"
    ; "property:MTLCommandBuffer:GPUStartTime"
    ; "property:MTLCommandBuffer:errorOptions"
    ; "property:MTLCommandBuffer:kernelEndTime"
    ; "property:MTLCommandBuffer:kernelStartTime"
    ; "property:MTLCommandBuffer:retainedReferences" ]
  in
  if generated_presentation <> expected_generated_presentation then
    fail "promoted Presentation direct-call evidence drift: expected [%s], got [%s]"
      (String.concat "; " expected_generated_presentation)
      (String.concat "; " generated_presentation);
  let generated_compute =
    inventory_ids
    |> List.filter (fun id ->
         List.mem id Binding_compute_encoder35_safe_closure.callable_ids)
    |> List.sort_uniq String.compare
  in
  let expected_generated_compute =
    [ "method:-[MTLComputeCommandEncoder setBufferOffset:atIndex:]"
    ; "method:-[MTLComputeCommandEncoder setBufferOffset:attributeStride:atIndex:]" ]
  in
  if generated_compute <> expected_generated_compute then
    fail "promoted ComputeEncoder direct-call evidence drift: expected [%s], got [%s]"
      (String.concat "; " expected_generated_compute)
      (String.concat "; " generated_compute);
  reject_duplicates "OCaml external"
    (List.map
       (fun (entry : Binding_direct_spec.method_entry) -> entry.ocaml_name)
       methods);
  reject_duplicates "C primitive"
    (List.map
       (fun (entry : Binding_direct_spec.method_entry) -> entry.c_symbol)
       methods);
  let owner_count =
    methods
    |> List.map (fun (entry : Binding_direct_spec.method_entry) -> entry.owner)
    |> List.sort_uniq String.compare |> List.length
  in
  if owner_count <> expected_owner_count then
    fail "expected %d owners, found %d" expected_owner_count owner_count

let () = validate ()
