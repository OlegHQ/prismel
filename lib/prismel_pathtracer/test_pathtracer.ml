(* Smallest check that fails if the tracer breaks: a lit sphere over a floor
   must produce a non-flat image, and two accumulations from reset must be
   byte-identical (fixed seeds, fixed camera). *)
module P = Prismel_pathtracer
let rgb = P.Linear_color.rgb

let get = function Ok v -> v | Error e -> failwith e
let metal = function Ok v -> v | Error e -> failwith (Format.asprintf "%a" Metal.pp_error e)

let run () =
  let exact_m1 = Sys.getenv_opt "PRISMEL_PATH_TRACER_EXACT_M1" = Some "1" in
  let initial_handles = (metal (Metal.Release_queue.stats ())).live_handles in
  let sphere = get (Result.map_error Pdk.Error.to_string
    (Pdk.Ops.uv_sphere ~center:(Prismel.Vec3.create 0. 1. 0.) ~segments:24 ~rings:12 ~radius:1. ())) in
  let floor = get (Result.map_error Pdk.Error.to_string
    (Pdk.Ops.box ~center:(Prismel.Vec3.create 0. (-0.05) 0.) ~size:(Prismel.Vec3.create 20. 0.1 20.) ())) in
  let scene =
    { P.objects =
        [ (sphere, P.material ~roughness:0.2 ~metallic:1. (rgb 0.9 0.7 0.4))
        ; (floor, P.material ~roughness:0.8 (rgb 0.6 0.6 0.6)) ]
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
        if index = 1 then stable_handles := Some (metal (Metal.Release_queue.stats ())).live_handles
      done;
      ignore (metal (Metal.Release_queue.drain ()));
      assert ((metal (Metal.Release_queue.stats ())).live_handles <= Option.get !stable_handles);
      P.destroy tracer;
      print_endline "pathtracer: deterministic lit render ok";
      (* Furnace: an albedo-0.8 floor under a uniform white dome reflects
         exactly 0.8 along every path, which the ACES/2.2 resolve maps to 224.
         A zero-intensity panel exercises the MIS path (panel sampling plus the
         weighted BSDF escape) and must not change the mean. *)
      let furnace panels =
        let scene = { P.objects = [ (floor, P.material ~roughness:0.8 (rgb 0.8 0.8 0.8)) ]
          ; environment = { sky = rgb 1. 1. 1.; ground = rgb 1. 1. 1.; panels }; lights = [] } in
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
      ignore (metal (Metal.Release_queue.drain ()));
      let final_handles = (metal (Metal.Release_queue.stats ())).live_handles in
      Printf.printf "handle baseline %d final %d\n%!" initial_handles final_handles;
      assert (final_handles = initial_handles)
