open Runtime_next_provider

let expect_name target expected =
  match Runtime_next_concrete_provider_loader.ensure target with
  | Ok (Pack (module Provider)) when Provider.name = expected -> ()
  | _ -> failwith "the selected concrete provider was not activated"

let () =
  Private.reset ();
  expect_name Native "runtime-next-metal";
  expect_name Native "runtime-next-metal";
  print_endline "runtime-next concrete loader: native only"
