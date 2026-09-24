open Binding_mesh_tile_pipeline_adapter

let expect_ok = function Ok () -> () | Error message -> failwith message
let expect_error = function Error _ -> () | Ok () -> failwith "expected rejection"

let () =
  let required = { width = 3; height = 1; depth = 1 } in
  let mesh =
    { label = Some "mesh"; object_function = None; mesh_function = ()
    ; fragment_function = Some (); max_total_threads_per_object_threadgroup = 1
    ; max_total_threads_per_mesh_threadgroup = 32
    ; required_threads_per_mesh_threadgroup = required; raster_sample_count = 1
    ; alpha_to_coverage_enabled = false; alpha_to_one_enabled = false
    ; rasterization_enabled = true; max_vertex_amplification_count = 1 }
  in
  expect_ok (validate_mesh mesh);
  expect_error
    (validate_mesh { mesh with required_threads_per_mesh_threadgroup =
                                { required with width = 33 } });
  let tile =
    { label = Some "tile"; tile_function = (); raster_sample_count = 1
    ; threadgroup_size_matches_tile_size = false
    ; max_total_threads_per_threadgroup = 32
    ; required_threads_per_threadgroup = { width = 1; height = 1; depth = 1 } }
  in
  expect_ok (validate_tile tile);
  expect_error (validate_tile { tile with raster_sample_count = 0 });
  print_endline "mesh/tile immutable adapter validation passed"
