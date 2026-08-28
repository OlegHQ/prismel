open Runtime_next_provider

let expect_missing target =
  match find target with
  | Error (Missing_target missing) when missing = target -> ()
  | _ -> failwith "an unrelated concrete provider was activated"

let expect_name target expected =
  match Runtime_next_concrete_provider_loader.ensure target with
  | Ok (Pack (module Provider)) when Provider.name = expected -> ()
  | _ -> failwith "the selected concrete provider was not activated"

let () =
  Private.reset ();
  expect_name Web "runtime-next-web";
  expect_missing Native;
  expect_missing Headless;
  expect_name Web "runtime-next-web";
  Private.reset ();
  expect_name Headless "runtime-next-headless";
  expect_missing Native;
  expect_missing Web;
  Private.reset ();
  expect_name Native "runtime-next-metal";
  expect_missing Headless;
  expect_missing Web;
  print_endline "runtime-next concrete loader: selected target only"
