let () =
  match Flow_sop.Manifest.generate Sop_catalog.Editor.factories with
  | Ok (text, _) -> print_string text
  | Error diagnostic -> failwith (Flow.Diagnostic.to_string diagnostic)
