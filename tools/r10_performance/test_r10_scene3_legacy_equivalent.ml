let require condition message = if not condition then failwith message

let digest_draws draws =
  draws
  |> List.map (fun (draw : Scene_execution.draw) ->
         Digest.to_hex (Digest.bytes draw.mesh.vertices)
         ^ Digest.to_hex (Digest.bytes draw.mesh.indices))
  |> String.concat ":" |> Digest.string |> Digest.to_hex

let signature value =
  digest_draws value.R10_scene3_legacy_equivalent.software_draws ^ ":"
  ^ digest_draws value.native_draws

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
  require (List.length value.software_batched_draws = 1) "software batch count";
  require (List.length value.native_draws = 12) "native draw count";
  require (List.length value.native_batched_draws = 1) "native batch count";
  let verify_batch label stride draws batched_draws =
    let batched=(List.hd batched_draws).Scene_execution.mesh in
    require (batched.vertex_count=value.instances*value.vertices_per_instance)
      (label^" batch vertex count");
    require (batched.index_count=value.instances*value.indices_per_instance)
      (label^" batch index count");
    List.iteri (fun instance (draw:Scene_execution.draw) ->
      let source_vertex=draw.mesh.vertex_count and source_index=draw.mesh.index_count in
      require (Bytes.sub batched.vertices (instance*source_vertex*stride)
        (source_vertex*stride)=draw.mesh.vertices) (label^" batch vertex ordering");
      for index=0 to source_index-1 do
        require (Int32.to_int(Bytes.get_int32_le batched.indices
          ((instance*source_index+index)*4))=
          Int32.to_int(Bytes.get_int32_le draw.mesh.indices(index*4))+
          instance*source_vertex) (label^" batch index rebasing")
      done) draws
  in
  verify_batch "software" 16 value.software_draws value.software_batched_draws;
  verify_batch "native" 68 value.native_draws value.native_batched_draws;
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
      (* The sphere constructor uses Prismel's shared parallel pool and is an
         initial-domain preparation boundary. Exercise only the immutable,
         independently owned packed artifact concurrently. *)
      Domain.spawn (fun () -> signature first))
  in
  Array.iter
    (fun domain -> require (Domain.join domain = expected) "domain ordering")
    domains;
  print_endline
    "R10 legacy-equivalent Scene3 artifact: sphere96x48, instances12, exact 1/4-domain"
