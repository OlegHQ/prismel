let () =
  Binding_mesh_tile_compile_reachability.validate ();
  let exists path =
    Sys.file_exists path || Sys.file_exists (Filename.concat "../.." path)
  in
  List.iter
    (fun item ->
      if not (exists item.Binding_mesh_tile_compile_reachability.safe_fixture)
         || not (exists item.native_fixture)
      then failwith ("missing Mesh/tile compilation fixture for " ^ item.id))
    Binding_mesh_tile_compile_reachability.items;
  Printf.printf "Mesh/tile synchronous compilation audit: 2 promotable safe/native Device selectors\n"
