let require condition message = if not condition then failwith message

let verify value =
  require (value.R10_scene3_legacy_equivalent.instances = 12) "instance count";
  require (value.vertices_per_instance = 97 * 49) "sphere vertex count";
  require (value.indices_per_instance = 96 * 48 * 6) "sphere index count";
  require (value.triangles = 12 * 96 * 48 * 2) "triangle count";
  require (value.samples = 4) "MSAA sample count";
  require (value.diffuse_rgb = (56, 189, 248)) "material diffuse";
  require (value.ambient_rgb = (18, 22, 30)) "scene ambient";
  require
    (value.light_direction = (-0.6, -1., -1.4))
    "directional light";
  require (List.length value.software_draws = 12) "software draw count";
  require (List.length value.native_draws = 12) "native draw count";
  List.iter
    (fun (draw : Scene_execution.draw) ->
      require
        (Bytes.length draw.mesh.vertices = value.vertices_per_instance * 16)
        "software vertex layout";
      let minimum = ref max_float and maximum = ref (-.max_float) in
      for index = 0 to value.vertices_per_instance - 1 do
        let x =
          Int64.float_of_bits (Bytes.get_int64_le draw.mesh.vertices (index * 16))
        in
        minimum := min !minimum x;
        maximum := max !maximum x
      done;
      require (!minimum >= 0. && !maximum <= 64.) "projected viewport bounds";
      require (!maximum -. !minimum < 16.) "bounded sphere coverage";
      require (draw.state.cull = Ogpu.Render_pass.Cull_back) "legacy cull";
      require draw.state.depth_write "legacy depth write")
    value.software_draws;
  List.iter
    (fun (draw : Scene_execution.draw) ->
      require
        (Bytes.length draw.mesh.vertices = value.vertices_per_instance * 68)
        "native vertex layout")
    value.native_draws

let () =
  let first = R10_scene3_legacy_equivalent.create ~width:64 ~height:64 in
  verify first;
  let expected = first.signature in
  List.iter
    (fun frame ->
      let current = R10_scene3_legacy_equivalent.create ~width:64 ~height:64 in
      require (current.signature = expected)
        (Printf.sprintf "frame %d signature" frame))
    [ 2; 60; 600 ];
  let domains =
    Array.init 4 (fun _ ->
      Domain.spawn (fun () ->
        (R10_scene3_legacy_equivalent.create ~width:64 ~height:64).signature))
  in
  Array.iter
    (fun domain -> require (Domain.join domain = expected) "domain ordering")
    domains;
  print_endline
    "R10 legacy-equivalent Scene3 artifact: sphere96x48, instances12, exact 1/4-domain"
