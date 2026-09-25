(* Smallest check that fails if the tracer breaks: a lit sphere over a floor
   must produce a non-flat image, and two accumulations from reset must be
   byte-identical (fixed seeds, fixed camera). *)
module P = Prismel_pathtracer
let rgb = P.Linear_color.rgb

let get = function Ok v -> v | Error e -> failwith e
let live_handles = let _, live = Ogpu.Impl.create_driver () in live

let run () =
  let exact_m1 = Sys.getenv_opt "PRISMEL_PATH_TRACER_EXACT_M1" = Some "1" in
  let initial_handles = live_handles () in
  let sphere = get (Result.map_error Pdk.Error.to_string
    (Pdk.Ops.uv_sphere ~center:(Prismel.Vec3.create 0. 1. 0.) ~segments:24 ~rings:12 ~radius:1. ())) in
  let floor = get (Result.map_error Pdk.Error.to_string
    (Pdk.Ops.box ~center:(Prismel.Vec3.create 0. (-0.05) 0.) ~size:(Prismel.Vec3.create 20. 0.1 20.) ())) in
  let scene =
    { P.objects =
        [ (sphere, P.material ~roughness:0.2 ~metallic:1. (rgb 0.9 0.7 0.4))
        ; (floor, P.material ~roughness:0.8 (rgb 0.6 0.6 0.6)) ]
    ; spheres = []; strands = []
    ; environment =
        { sky = rgb 0.5 0.6 0.8; ground = rgb 0.2 0.2 0.2
        ; panels = [ P.panel ~intensity:6. ~width:0.5 ~height:0.4 (Prismel.Vec3.create 1. 2. 1.) ] }
    ; lights = [ P.rect_light ~intensity:20. ~size:(2., 2.) ~target:(Prismel.Vec3.create 0. 0. 0.)
                   (Prismel.Vec3.create (-2.) 5. 2.) ] } in
  match P.create ~spp:2 ~width:48 ~height:32 scene with
  | Error message when String.length message > 0 && Sys.getenv_opt "PRISMEL_REQUIRE_RAYTRACING" = None ->
      Printf.printf "pathtracer: skipped (%s)\n" message
  | Error message -> failwith message
  | Ok tracer ->
      let camera = Prismel.Camera.perspective ~fov_y:0.9
        ~at:(Prismel.Vec3.create 0. 2. 6.)
        ~target:(Prismel.Vec3.create 0. 0.8 0.) () in
      let unsupported = Prismel.Camera.orthographic ~height:4.
        ~at:(Prismel.Camera.position camera)
        ~target:(Prismel.Camera.target camera) () in
      (match P.render tracer unsupported with Error _ -> ()
       | Ok () -> failwith "orthographic path-tracer camera was accepted");
      assert (P.samples tracer = 0);
      let run () = P.reset tracer; get (P.render tracer camera); get (P.flush tracer); get (P.render tracer camera); get (P.flush tracer); Bytes.copy (P.pixels tracer) in
      let first = run () and second = run () in
      if exact_m1 then
        assert (Digest.to_hex (Digest.bytes first) =
          "84c5cb3002a37d05a0b2f66b49d4d6f0");
      assert (P.samples tracer = 4);
      assert (Bytes.equal first second);
      let distinct = Hashtbl.create 64 in
      Bytes.iteri (fun i c -> if i mod 4 = 0 then Hashtbl.replace distinct c ()) first;
      assert (Hashtbl.length distinct > 8);
      assert (Bytes.get first 3 = '\255');
      let moved = Prismel.Camera.with_position
        (Prismel.Vec3.create 0.4 2. 6.) camera in
      get (P.render tracer moved); get (P.flush tracer);
      assert (P.samples tracer = 0);
      let preview = Bytes.copy (P.pixels tracer) in
      let varying_block = ref false in
      for y = 0 to 15 do
        for x = 0 to 23 do
          let offset = (y * 2 * 48 + x * 2) * 4 in
          if Bytes.get preview offset <> Bytes.get preview (offset + 4)
             || Bytes.get preview offset <> Bytes.get preview (offset + 48 * 4)
          then varying_block := true
        done
      done;
      assert !varying_block;
      P.reset tracer;
      get (P.render tracer camera); get (P.flush tracer);
      P.reset tracer;
      get (P.render tracer moved); get (P.flush tracer);
      assert (not (Bytes.equal preview (P.pixels tracer)));
      let motion_run () =
        P.reset tracer;
        get (P.render tracer camera); get (P.flush tracer);
        get (P.render tracer camera); get (P.flush tracer);
        get (P.render tracer moved); get (P.flush tracer);
        Bytes.copy (P.pixels tracer) in
      assert (Bytes.equal (motion_run ()) (motion_run ()));
      get (P.render tracer moved); get (P.flush tracer);
      assert (P.samples tracer = 2);
      let matrix = Prismel.Mat4.mul
        (Prismel.Mat4.translation (Prismel.Vec3.create 0.3 0. 0.))
        (Prismel.Mat4.mul (Prismel.Mat4.rotation_y 0.23)
          (Prismel.Mat4.scaling (Prismel.Vec3.create 1.3 0.8 1.1))) in
      let instanced = get (P.mesh_instanced ~prototype:(sphere, P.material (rgb 0.7 0.5 0.3)) [|matrix|]) in
      get (P.replace_mesh tracer instanced);
      get (P.render tracer camera); get (P.flush tracer);
      get (P.render tracer camera); get (P.flush tracer);
      let instanced_pixels = Bytes.copy (P.pixels tracer) in
      if exact_m1 then
        assert (Digest.to_hex (Digest.bytes instanced_pixels) =
          "8aaf15f3d0b2f4b16e46342612ca8328");
      let transformed = Pdk.Ops.transform matrix sphere in
      get (P.replace_mesh tracer (get (P.mesh [transformed, P.material (rgb 0.7 0.5 0.3)])));
      get (P.render tracer camera); get (P.flush tracer);
      let largest_difference = ref 0 in
      Bytes.iteri (fun i value ->
        largest_difference := max !largest_difference
          (abs (Char.code value - Char.code (Bytes.get instanced_pixels i)))) (P.pixels tracer);
      assert (!largest_difference <= 2);
      let expected = Bytes.copy (P.pixels tracer) in
      get (P.queue_mesh tracer instanced);
      get (P.queue_mesh tracer (get (P.mesh [transformed, P.material (rgb 0.7 0.5 0.3)])));
      get (P.flush tracer);
      assert (P.samples tracer = 0);
      get (P.render tracer camera); get (P.flush tracer);
      assert (Bytes.equal expected (P.pixels tracer));
      let stable_handles = ref None in
      for index = 1 to 10 do
        let matrix = Prismel.Mat4.mul
          (Prismel.Mat4.translation (Prismel.Vec3.create (float index *. 0.02) 0. 0.))
          (Prismel.Mat4.scaling (Prismel.Vec3.create 1.3 0.8 1.1)) in
        get (P.queue_mesh tracer
          (get (P.mesh_instanced ~prototype:(sphere, P.material (rgb 0.7 0.5 0.3)) [|matrix|])));
        get (P.flush tracer);
        if index = 1 then stable_handles := Some (live_handles ())
      done;
      assert (live_handles () <= Option.get !stable_handles);
      P.destroy tracer;
      print_endline "pathtracer: deterministic lit render ok";
      (* Furnace: an albedo-0.8 floor under a uniform white dome reflects
         exactly 0.8 along every path, which the ACES/2.2 resolve maps to 224.
         A zero-intensity panel exercises the MIS path (panel sampling plus the
         weighted BSDF escape) and must not change the mean. *)
      let furnace panels =
        let scene = { P.objects = [ (floor, P.material ~roughness:0.8 (rgb 0.8 0.8 0.8)) ]
          ; spheres = []; strands = []; environment = { sky = rgb 1. 1. 1.; ground = rgb 1. 1. 1.; panels }; lights = [] } in
        let tracer = get (P.create ~spp:4 ~width:32 ~height:32 scene) in
        let camera = Prismel.Camera.perspective ~fov_y:0.5
          ~at:(Prismel.Vec3.create 0. 4. 0.001)
          ~target:(Prismel.Vec3.create 0. 0. 0.) () in
        for _ = 1 to 16 do get (P.render tracer camera); get (P.flush tracer) done;
        get (P.flush tracer);
        let sum = ref 0 in
        Bytes.iteri (fun i c -> if i mod 4 = 0 then sum := !sum + Char.code c) (P.pixels tracer);
        P.destroy tracer;
        float !sum /. 1024. in
      let plain = furnace [] in
      let mis = furnace [ P.panel ~intensity:0. ~width:0.9 ~height:0.6 ~softness:0.2 (Prismel.Vec3.create 0.3 1. 0.2) ] in
      Printf.printf "pathtracer: furnace mean %.1f / %.1f (expected 224)\n" plain mis;
      assert (Float.abs (plain -. 224.) < 2.);
      assert (Float.abs (mis -. 224.) < 2.);
      (* Analytic sphere in the furnace: a white bounding-box sphere resolved
         by the intersection function table must conserve energy like the
         floor, which checks sphere hits, normals, and the table binding. *)
      let sphere_furnace =
        let scene = { P.objects = []
          ; spheres = [ P.sphere ~radius:1.5 (P.material ~roughness:0.8 (rgb 0.8 0.8 0.8)) (Prismel.Vec3.create 0. 0. 0.) ]
          ; strands = []; environment = { sky = rgb 1. 1. 1.; ground = rgb 1. 1. 1.; panels = [] }; lights = [] } in
        let tracer = get (P.create ~spp:4 ~width:32 ~height:32 scene) in
        let camera = Prismel.Camera.perspective ~fov_y:0.3
          ~at:(Prismel.Vec3.create 0. 0. 6.)
          ~target:(Prismel.Vec3.create 0. 0. 0.) () in
        for _ = 1 to 16 do get (P.render tracer camera); get (P.flush tracer) done;
        get (P.flush tracer);
        let sum = ref 0 in
        Bytes.iteri (fun i c -> if i mod 4 = 0 then sum := !sum + Char.code c) (P.pixels tracer);
        P.destroy tracer;
        float !sum /. 1024. in
      Printf.printf "pathtracer: sphere furnace mean %.1f (expected 224)\n" sphere_furnace;
      assert (Float.abs (sphere_furnace -. 224.) < 2.);
      (* Per-instance materials and motion blur. Two emissive instances of one
         prototype: the left one red, the right one green, selected through the
         instance user id. With motion the right instance sweeps to the far
         right, so its rest position is only partly covered and the far
         position is hit at all, which a static build never does. *)
      let black = { P.sky = rgb 0. 0. 0.; ground = rgb 0. 0. 0.; panels = [] } in
      let scene = { P.objects = [ (sphere, P.material (rgb 0.5 0.5 0.5)) ]; spheres = []; strands = []
        ; environment = black; lights = [] } in
      let tracer = get (P.create ~spp:4 ~width:64 ~height:32 scene) in
      let camera = Prismel.Camera.perspective ~fov_y:0.8
        ~at:(Prismel.Vec3.create 0. 1. 8.) ~target:(Prismel.Vec3.create 0. 1. 0.) () in
      let place x = Prismel.Mat4.translation (Prismel.Vec3.create x 0. 0.) in
      let red = P.material ~emission:(rgb 4. 0. 0.) (rgb 0. 0. 0.)
      and green = P.material ~emission:(rgb 0. 4. 0.) (rgb 0. 0. 0.) in
      let pixel bytes x y = let o = ((y * 64) + x) * 4 in
        (Char.code (Bytes.get bytes o), Char.code (Bytes.get bytes (o + 1)), Char.code (Bytes.get bytes (o + 2))) in
      let render_twice () =
        P.reset tracer;
        get (P.render tracer camera); get (P.flush tracer);
        get (P.render tracer camera); get (P.flush tracer);
        Bytes.copy (P.pixels tracer) in
      let static_mesh = get (P.mesh_instanced ~prototype:(sphere, P.material (rgb 0.5 0.5 0.5))
        ~materials:[| red; green |] [| place (-2.); place 2. |]) in
      get (P.replace_mesh tracer static_mesh);
      let static = render_twice () in
      let r, g, _ = pixel static 20 16 in assert (r > 100 && g < 20);
      let r, g, _ = pixel static 44 16 in assert (g > 100 && r < 20);
      let r, g, b = pixel static 54 16 in assert (r = 0 && g = 0 && b = 0);
      let moving = get (P.mesh_instanced ~prototype:(sphere, P.material (rgb 0.5 0.5 0.5))
        ~materials:[| red; green |] ~motion:[| place (-2.); place 4.5 |] [| place (-2.); place 2. |]) in
      get (P.replace_mesh tracer moving);
      let blurred = render_twice () in
      let r, g, _ = pixel blurred 20 16 in assert (r > 100 && g < 20);
      let _, g_static, _ = pixel static 44 16 and _, g_blurred, _ = pixel blurred 44 16 in
      assert (g_blurred < g_static && g_blurred > 0);
      let _, g_far, _ = pixel blurred 54 16 in assert (g_far > 0);
      assert (Bytes.equal blurred (render_twice ()));
      (match P.mesh_instanced ~prototype:(sphere, red) ~materials:[| red |] [| place 0.; place 1. |] with
       | Error _ -> () | Ok _ -> failwith "mismatched instance material count was accepted");
      (match P.mesh_instanced ~prototype:(sphere, red) ~motion:[| place 0. |] [| place 0.; place 1. |] with
       | Error _ -> () | Ok _ -> failwith "mismatched motion transform count was accepted");
      (* Strands need curve intersection; devices without it get a typed
         error rather than a silent miss. Metal reports curve support per GPU
         family (Apple9 and later), so both outcomes are checked. *)
      let strands = [ P.strand ~thickness:0.3 red
        [| Prismel.Vec3.create (-2.) 1. 0.; Prismel.Vec3.create 2. 1. 0. |] ] in
      (match P.mesh ~strands [ (floor, P.material (rgb 0.5 0.5 0.5)) ] with
       | Error message -> failwith message
       | Ok strand_mesh ->
           match P.replace_mesh tracer strand_mesh with
           | Error message ->
               assert (String.length message > 0);
               Printf.printf "pathtracer: strands unsupported here (%s)\n" message
           | Ok () ->
               let hair = render_twice () in
               let r, _, _ = pixel hair 32 16 in assert (r > 100);
               print_endline "pathtracer: strands ok");
      P.destroy tracer;
      print_endline "pathtracer: spheres, instance materials, motion ok";
      (* Every kernel specialization compiles and matches its declared
         interface, including the curve variants a device may never trace. *)
      let driver, _ = Ogpu.Impl.create_driver () in
      let device = get (Result.map_error Ogpu.Error.to_string (Ogpu.Backend.create_device driver)) in
      let source = In_channel.with_open_bin "pathtrace.metal" In_channel.input_all in
      let shader = get (Result.map_error Ogpu.Error.to_string (Ogpu.Shader.create
        { backend = "metal"; label = Some "pathtrace-shapes"; bytes = Bytes.of_string source
        ; entry_points = [ { Ogpu.Shader.name = "pathtrace"; stage = Compute } ]; bindings = [] })) in
      let library = get (Result.map_error Ogpu.Error.to_string (Ogpu.Backend.create_library device shader)) in
      let binding index kind = { Ogpu.Shader.group = 0; binding = index; kind; visibility = [ Compute ] } in
      let shapes = ref 0 in
      List.iter (fun (instanced, motion, spheres, curves) ->
        if not (motion && not instanced) then begin
          let interface =
            [ binding 0 Acceleration_structure; binding 1 Uniform_buffer ]
            @ List.map (fun index -> binding index Storage_buffer)
                ([ 2; 3 ] @ (if instanced then [ 5; 6; 7; 9; 10 ] else [ 4; 5; 6; 7; 9 ]) @ [ 11; 12; 13; 14 ]
                 @ (if spheres then [ 15 ] else []) @ (if curves then [ 17; 18; 19 ] else []))
            @ (if spheres then [ binding 16 Intersection_table ] else [])
            @ [ binding 0 Storage_texture ] in
          let linked = if spheres then
            [ "sphere_hit_" ^ (if instanced then "i" else "f") ^ (if motion then "m" else "") ^ (if curves then "c" else "") ]
            else [] in
          let pipeline = get (Result.map_error Ogpu.Error.to_string
            (Ogpu.Backend.create_compute_pipeline_from library ~entry:"pathtrace"
               ~constants:[ ("INSTANCED", Bool instanced); ("MOTION", Bool motion); ("SPHERES", Bool spheres); ("CURVES", Bool curves) ]
               ~interface ~linked ())) in
          get (Result.map_error Ogpu.Error.to_string (Ogpu.Backend.destroy_pipeline pipeline));
          incr shapes
        end)
        (List.concat_map (fun i -> List.concat_map (fun m -> List.concat_map (fun s -> List.map (fun c -> (i, m, s, c)) [ false; true ]) [ false; true ]) [ false; true ]) [ false; true ]);
      assert (!shapes = 12);
      get (Result.map_error Ogpu.Error.to_string (Ogpu.Backend.destroy_library library));
      get (Result.map_error Ogpu.Error.to_string (Ogpu.Backend.destroy_device device));
      Printf.printf "pathtracer: %d kernel specializations compile\n" !shapes;
      let final_handles = live_handles () in
      Printf.printf "handle baseline %d final %d\n%!" initial_handles final_handles;
      assert (final_handles = initial_handles)
