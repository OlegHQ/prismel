let () =
  Binding_render_pipeline93_native_closure.validate ();
  if Array.length Sys.argv = 2 && Sys.argv.(1) = "--dump" then
    List.iter print_endline Binding_render_pipeline93_native_closure.ids
  else Printf.printf "RenderPipeline93 native closure: exact93 (58 typed selectors + 30 properties + 5 classes)\n"
