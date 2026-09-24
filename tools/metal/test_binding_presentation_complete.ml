let () =
  if Binding_presentation_manifest.count <> 125 then failwith "manifest count drift";
  let module I = Binding_presentation_integration in
  let zero : I.window_state =
    { attached=true; visible=true; minimized=false; pixel_width=0; pixel_height=4 }
  in
  if I.classify_nil zero ~timed_out:false <> I.Zero_sized then failwith "zero loss";
  let detached = { zero with attached=false; pixel_width=4 } in
  if I.classify_nil detached ~timed_out:false <> I.Detached then failwith "detach loss";
  (match I.validate_present_time (I.At_time nan) with Error _ -> () | Ok () -> failwith "nan");
  if List.length I.selector_contract <> 8 then failwith "typed selector contract drift";
  if List.length I.sdl3_attached_window_strategy <> 11 then failwith "SDL3 strategy drift";
  if Binding_presentation_coverage.generated_count +
       Binding_presentation_coverage.handwritten_count <> 125 then
    failwith "coverage partition drift";
  Printf.printf
    "presentation complete manifest: %d IDs (%d generated, %d lifecycle), typed SDL3 loss matrix\n"
    Binding_presentation_manifest.count Binding_presentation_coverage.generated_count
    Binding_presentation_coverage.handwritten_count
