let () =
  Binding_io_counter_type_reachability.validate ();
  Printf.printf "IO/counter types: 5 exact public representations, 14 blocked; 2 runtime properties handed off\n"
