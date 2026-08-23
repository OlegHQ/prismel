open Binding_render_encoder_resource_plan

let fail message = failwith message
let has check entry = List.mem check entry.checks

let () =
  if List.length entries <> expected_count then fail "entry count drift";
  List.iter (fun entry ->
    if not (has Encoder_open entry) then fail (entry.id ^ " lacks encoder state check");
    if List.mem Fence entry.resources && not (has Same_device entry && has Retain_resource entry)
    then fail (entry.id ^ " lacks fence ownership checks");
    if List.mem Heap entry.resources && not (has Same_device entry && has Retain_resource entry)
    then fail (entry.id ^ " lacks heap ownership checks");
    if List.mem Indirect_command_buffer entry.resources
       && not (has Pipeline_supports_icb entry && has Retain_resource entry)
    then fail (entry.id ^ " lacks ICB pipeline/ownership checks");
    if List.mem Depth_attachment entry.resources || List.mem Stencil_attachment entry.resources
    then if not (has Attachment_present entry) then fail (entry.id ^ " lacks attachment check")
  ) entries;
  let deprecated = List.filter (fun entry -> entry.deprecated_alias) entries in
  if List.length deprecated <> 5 then fail "deprecated alias partition drift"
