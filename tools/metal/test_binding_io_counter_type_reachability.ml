let () =
  Binding_io_counter_type_reachability.validate ();
  Printf.printf "IO/counter types: 10 exact public representations, 9 blocked; 2 runtime properties handed off\n"
