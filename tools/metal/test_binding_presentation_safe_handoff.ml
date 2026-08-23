let name = function
  | Binding_presentation_safe_handoff.Render_pass_descriptor ->
      "Render_pass_descriptor"
  | Layer -> "Layer"
  | Drawable -> "Drawable"
  | Command_buffer -> "Command_buffer"

let () =
  Binding_presentation_safe_handoff.validate ();
  let counts =
    List.map
      (fun public_module ->
        ( name public_module
        , List.length
            (Binding_presentation_safe_handoff.items_for public_module) ))
      Binding_presentation_safe_handoff.modules
  in
  Printf.printf "Presentation81 pending safe handoff:";
  List.iter (fun (module_name, count) -> Printf.printf " %s=%d" module_name count) counts;
  Printf.printf "; private metadata=1 remains unpromoted\n"
