let render_contract
    (selection : Binding_acceleration_operations_plan.selection) =
  let output = Buffer.create 30000 in
  List.iter
    (fun (value : Binding_acceleration_operations_plan.declaration) ->
      Printf.bprintf output "%s\t%s\t%s\t%s\n" value.id value.kind
        (Option.value ~default:"global" value.owner) value.signature)
    selection.declarations;
  Buffer.contents output

let render_safe_model
    (selection : Binding_acceleration_operations_plan.selection) =
  let output = Buffer.create 12000 in
  Buffer.add_string output
    "type ownership = Owned_handle | Completion_retained | Copied_value | Capability_rejected\n";
  List.iter
    (fun (value : Binding_acceleration_operations_plan.declaration) ->
      let ownership =
        if value.kind = "class" || value.kind = "protocol" then "Owned_handle"
        else if String.starts_with ~prefix:"instance () ->" value.signature then
          "Copied_value"
        else if value.kind = "method" then "Completion_retained"
        else "Capability_rejected"
      in
      Printf.bprintf output "let evidence_%d = (%S, %s)\n"
        (Buffer.length output) value.id ownership)
    selection.declarations;
  Buffer.contents output
