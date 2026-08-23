let () =
  Binding_mesh_tile_compile_reachability.validate ();
  List.iter
    (fun item ->
      if not (Sys.file_exists item.Binding_mesh_tile_compile_reachability.safe_fixture)
         || not (Sys.file_exists item.native_fixture)
      then failwith ("missing Mesh/tile compilation fixture for " ^ item.id))
    Binding_mesh_tile_compile_reachability.items;
  Printf.printf "Mesh/tile synchronous compilation audit: 2 pending safe/native Device selectors; no promotion\n"
