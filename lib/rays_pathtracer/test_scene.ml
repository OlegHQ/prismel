(* Several objects per trace (scene_mesh), Light.t conversion, and a flat mesh
   mixing triangles with analytic spheres (one BLAS per geometry kind). *)
module P = Rays_pathtracer
module V = Rays.Vec3
module M = Rays.Mat4
let rgb = P.Linear_color.rgb
let get = function Ok v -> v | Error e -> failwith e
let rdk r = get (Result.map_error Rdk.Error.to_string r)
let live_handles = let _, live = Ogpu.Impl.create_driver () in live
let black = { P.sky = rgb 0. 0. 0.; ground = rgb 0. 0. 0.; panels = [] }

let render ?(frames = 2) tracer camera =
  P.reset tracer;
  for _ = 1 to frames do get (P.render tracer camera); get (P.flush tracer) done;
  Bytes.copy (get (P.pixels tracer))

(* The kernel's resolve (ACES fit, gamma 2.2, exposure 1) and its inverse. *)
let resolve x =
  let c = x *. (2.51 *. x +. 0.03) /. (x *. (2.43 *. x +. 0.59) +. 0.14) in
  Float.min 1. (Float.max 0. c) ** (1. /. 2.2) *. 255.
let unresolve value =
  let rec search lo hi n = if n = 0 then (lo +. hi) /. 2. else
    let mid = (lo +. hi) /. 2. in if resolve mid < value then search mid hi (n - 1) else search lo mid (n - 1) in
  search 0. 16. 60

let run () =
  let initial_handles = live_handles () in
  let floor = rdk (Rdk.Box_generator.box ~center:(V.create 0. (-0.05) 0.) ~size:(V.create 20. 0.1 20.) ()) in
  let box = rdk (Rdk.Box_generator.box ~center:(V.create 0. 0.5 0.) ~size:(V.create 1. 1. 1.) ()) in
  let ball = rdk (Rdk.Uv_sphere.run ~center:V.zero ~segments:24 ~rings:12 ~radius:0.4 ()) in
  let scene = { P.objects = [ (floor, P.material (rgb 0.5 0.5 0.5)) ]; spheres = []; strands = []
              ; environment = { sky = rgb 0.5 0.6 0.8; ground = rgb 0.2 0.2 0.2; panels = [] }
              ; lights = [ P.rect_light ~intensity:20. ~size:(2., 2.) ~target:V.zero (V.create (-2.) 5. 2.) ] } in
  match P.create ~spp:2 ~width:64 ~height:48 scene with
  | Error message when Sys.getenv_opt "RAYS_REQUIRE_RAYTRACING" = None ->
      Printf.printf "pathtracer scene: skipped (%s)\n" message
  | Error message -> failwith message
  | Ok tracer ->
      let camera = Rays.Camera.perspective ~fov_y:0.9 ~at:(V.create 0. 2.5 6.) ~target:(V.create 0. 0.6 0.) () in
      (* 1. Two objects at world transforms, one flat and one instanced with
         per-instance materials, against the same meshes composed by hand. *)
      let red = P.material (rgb 0.8 0.2 0.2) and green = P.material (rgb 0.2 0.8 0.2)
      and blue = P.material ~roughness:0.2 (rgb 0.2 0.2 0.8) and gray = P.material (rgb 0.5 0.5 0.5) in
      let t1 = M.mul (M.translation (V.create (-1.2) 0. 0.)) (M.rotation_y 0.4)
      and t2 = M.mul (M.translation (V.create 1. 0. 0.)) (M.rotation_y (-0.3)) in
      let a = M.translation (V.create 0. 0.4 0.)
      and b = M.mul (M.translation (V.create 0.3 1.3 0.)) (M.scaling (V.create 0.8 0.8 0.8)) in
      let scene_of t1 = get (P.scene_mesh
        [ (t1, get (P.mesh [ (box, red) ]))
        ; (t2, get (P.mesh_instanced ~prototype:(ball, gray) ~materials:[| green; blue |] [| a; b |]))
        ; (M.identity, get (P.mesh [ (floor, gray) ])) ]) in
      let composed = get (P.mesh
        [ (Rdk.Transform_ops.transform t1 box, red)
        ; (Rdk.Transform_ops.transform (M.mul t2 a) ball, green)
        ; (Rdk.Transform_ops.transform (M.mul t2 b) ball, blue)
        ; (floor, gray) ]) in
      let placed = scene_of t1 in
      assert (P.triangle_count placed = P.triangle_count composed);
      get (P.replace_mesh tracer placed);
      let scene_pixels = render ~frames:4 tracer camera in
      assert (Bytes.equal scene_pixels (render ~frames:4 tracer camera));
      get (P.replace_mesh tracer composed);
      let composed_pixels = render ~frames:4 tracer camera in
      let total = ref 0 and outliers = ref 0 in
      Bytes.iteri (fun i c ->
        if i mod 4 <> 3 then begin
          let d = abs (Char.code c - Char.code (Bytes.get composed_pixels i)) in
          total := !total + d; if d > 24 then incr outliers end) scene_pixels;
      let mean = float !total /. float (64 * 48 * 3) in
      Printf.printf "pathtracer scene: vs composed mean |diff| %.3f, %d outliers\n" mean !outliers;
      assert (mean < 1.0 && !outliers < 64 * 48 * 3 / 100);
      (* A translated object moves in the image: the box's red excess
         centroid shifts right. *)
      let red_centroid pixels =
        let sum = ref 0. and weight = ref 0. in
        for y = 0 to 47 do for x = 0 to 63 do
          let o = ((y * 64) + x) * 4 in
          let excess = Char.code (Bytes.get pixels o) - Char.code (Bytes.get pixels (o + 1)) in
          if excess > 40 then (sum := !sum +. float (x * excess); weight := !weight +. float excess)
        done done;
        !sum /. !weight in
      get (P.replace_mesh tracer (scene_of (M.mul (M.translation (V.create 0.8 0. 0.)) t1)));
      let moved = render tracer camera in
      let before = red_centroid scene_pixels and after = red_centroid moved in
      Printf.printf "pathtracer scene: red centroid %.1f -> %.1f\n" before after;
      assert (after > before +. 3.);
      (match P.scene_mesh [] with Error _ -> () | Ok _ -> failwith "empty scene accepted");
      (match P.scene_mesh [ (M.identity, get (P.mesh ~spheres:[ P.sphere ~radius:1. red V.zero ] [])) ] with
       | Error _ -> () | Ok _ -> failwith "scene object with spheres accepted");
      (* Nested: a scene is itself an object. *)
      get (P.replace_mesh tracer (get (P.scene_mesh [ (M.identity, placed) ])));
      assert (Bytes.equal scene_pixels (render ~frames:4 tracer camera));
      (* move: re-placing objects over the built BLASes matches a fresh
         scene_mesh at the new transforms, directly, superseding a pending
         move, and queued behind a full build. *)
      let t1' = M.mul (M.translation (V.create 0.8 0. 0.)) t1 in
      let same name pixels =
        let total = ref 0 in
        Bytes.iteri (fun i c -> if i mod 4 <> 3 then total := !total + abs (Char.code c - Char.code (Bytes.get moved i))) pixels;
        let mean = float !total /. float (64 * 48 * 3) in
        Printf.printf "pathtracer scene: move (%s) vs scene_mesh mean |diff| %.3f\n" name mean;
        assert (mean < 0.5) in
      get (P.replace_mesh tracer placed);
      get (P.move tracer [ t1'; t2; M.identity ]); get (P.flush tracer);
      same "direct" (render tracer camera);
      get (P.move tracer [ t1; t2; M.identity ]); get (P.move tracer [ t1'; t2; M.identity ]); get (P.flush tracer);
      same "superseded" (render tracer camera);
      get (P.queue_mesh tracer placed); get (P.move tracer [ t1'; t2; M.identity ]); get (P.flush tracer);
      same "queued" (render tracer camera);
      (match P.move tracer [ t1 ] with Error _ -> () | Ok () -> failwith "move with a wrong count accepted");
      (* An edit renders like a camera move: once a queued swap installs, the
         next frame is an uncounted preview, and the one after accumulates. *)
      get (P.render tracer camera); get (P.flush tracer);
      get (P.queue_mesh tracer placed); get (P.flush tracer);
      get (P.render tracer camera); get (P.flush tracer);
      assert (P.samples tracer = 0);
      get (P.render tracer camera); get (P.flush tracer);
      assert (P.samples tracer = 2);
      (* Timing: ~2000 instances of a 12-triangle box plus a 20k-triangle
         mesh, a full scene_mesh + queue_mesh + flush against move + flush. *)
      let boxes = get (P.mesh_instanced ~prototype:(box, red)
        (Array.init 2000 (fun i -> M.translation (V.create (float (i mod 50) *. 0.3 -. 7.5) 0. (float (i / 50) *. -0.3))))) in
      let dense = get (P.mesh [ (rdk (Rdk.Uv_sphere.run ~center:V.zero ~segments:100 ~rings:101 ~radius:0.5 ()), blue) ]) in
      let at x = M.translation (V.create x 1. 0.) in
      let time f = let start = Unix.gettimeofday () in f (); (Unix.gettimeofday () -. start) *. 1000. in
      let runs = 8 in
      get (P.queue_mesh tracer (get (P.scene_mesh [ (M.identity, boxes); (at 0., dense) ]))); get (P.flush tracer);
      let full = List.init runs (fun i -> time (fun () ->
        get (P.queue_mesh tracer (get (P.scene_mesh [ (M.identity, boxes); (at (float i *. 0.1), dense) ])));
        get (P.flush tracer))) in
      let moves = List.init runs (fun i -> time (fun () ->
        get (P.move tracer [ M.identity; at (float i *. -0.1) ]); get (P.flush tracer))) in
      let median l = List.nth (List.sort compare l) (List.length l / 2) in
      Printf.printf "pathtracer scene: %d tris, %d-instance scene: scene_mesh+queue_mesh+flush %.2f ms, move+flush %.2f ms (median of %d)\n%!"
        (P.triangle_count dense) 2001 (median full) (median moves) runs;
      (* what a move saves depends on the machine and the GPU's state (both runs end in one flush), so
         the default run prints the numbers and a qualification run (RAYS_QUALIFY=1) checks them *)
      if Sys.getenv_opt "RAYS_QUALIFY" <> None then assert (median moves < median full);
      (* 2. One mesh with triangles and analytic spheres builds (one BLAS per
         kind under a TLAS) and shows both: an emissive red sphere over the
         lit floor. *)
      let glow = P.material ~emission:(rgb 4. 0. 0.) (rgb 0. 0. 0.) in
      let mixed = get (P.mesh ~spheres:[ P.sphere ~radius:0.8 glow (V.create 0. 0.8 0.) ] [ (floor, gray) ]) in
      get (P.queue_mesh tracer mixed);
      get (P.flush tracer);
      (match P.move tracer [ M.identity ] with Error _ -> () | Ok () -> failwith "move of a non-scene accepted");
      let pixels = render tracer camera in
      let pixel x y = let o = ((y * 64) + x) * 4 in
        (Char.code (Bytes.get pixels o), Char.code (Bytes.get pixels (o + 1)), Char.code (Bytes.get pixels (o + 2))) in
      let r, g, _ = pixel 32 24 in assert (r > 150 && g < 30);
      let r, g, b = pixel 8 44 in assert (r > 20 && g > 20 && b > 20 && abs (r - g) < 12);
      print_endline "pathtracer scene: mixed triangles and spheres ok";
      P.destroy tracer;
      (* 3. light_of: a white matte plane under each converted light converges
         to the raster irradiance pi I / d^2, i.e. outgoing radiance
         albedo * I / d^2 (x0.97 for the BSDF's Fresnel at normal incidence). *)
      let plane = { P.objects = [ (floor, P.material ~roughness:1. (rgb 0.8 0.8 0.8)) ]; spheres = []; strands = []
                  ; environment = black; lights = [] } in
      let tracer = get (P.create ~spp:4 ~width:32 ~height:32 plane) in
      let top = Rays.Camera.perspective ~fov_y:0.3 ~at:(V.create 0. 4. 0.001) ~target:V.zero () in
      let check name light expected =
        get (P.set_lights tracer [ P.light_of light ]);
        let pixels = render ~frames:16 tracer top in
        let sum = ref 0. in
        for y = 12 to 19 do for x = 12 to 19 do
          sum := !sum +. float (Char.code (Bytes.get pixels ((((y * 32) + x) * 4) + 1))) done done;
        let measured = unresolve (!sum /. 64.) in
        Printf.printf "pathtracer light_of %s: %.4f expected %.4f\n" name measured expected;
        assert (Float.abs (measured -. expected) < 0.06 *. expected) in
      let at = V.create 0. 2. 0. and down = V.create 0. (-1.) 0. in
      let physical = Rays.Light.attenuation ~quadratic:1. () in
      let matte intensity d2 = 0.8 *. 0.97 *. intensity /. d2 in
      check "area" (Rays.Light.area ~intensity:2. ~attenuation:physical ~at ~direction:down ~width:0.2 ~height:0.2 ()) (matte 2. 4.);
      check "point" (Rays.Light.point ~intensity:2. ~attenuation:physical ~at ()) (matte 2. 4.);
      check "spot" (Rays.Light.spot ~intensity:2. ~attenuation:physical ~at ~direction:down ~cutoff:0.5 ~concentration:1. ()) (matte 2. 4.);
      check "directional" (Rays.Light.directional ~intensity:0.5 ~direction:down ()) (matte 0.5 1.);
      P.destroy tracer;
      let final_handles = live_handles () in
      Printf.printf "pathtracer scene: handle baseline %d final %d\n%!" initial_handles final_handles;
      assert (final_handles = initial_handles)

(* Manual: frame cost at 1200x1560 on a voxel_wall-like scene (2000 rounded
   boxes, a 20k-triangle mesh, 4 bounces), a full first sample against the
   preview frame an edit now renders. Not in runtest. *)
let bench () =
  let concrete = P.material ~roughness:0.6 ~round:0.07 (rgb 0.42 0.42 0.44) in
  let box = rdk (Rdk.Box_generator.box ~size:(V.create 0.28 0.28 0.28) ()) in
  let boxes = get (P.mesh_instanced ~prototype:(box, concrete)
    (Array.init 2000 (fun i -> M.translation (V.create (float (i mod 50) *. 0.3 -. 7.5) (float (i / 50) *. 0.3) 0.)))) in
  let dense = get (P.mesh [ (rdk (Rdk.Uv_sphere.run ~center:V.zero ~segments:100 ~rings:101 ~radius:1. ()), concrete) ]) in
  let at x = M.translation (V.create x 6. 2.) in
  let scene = { P.objects = [ (box, concrete) ]; spheres = []; strands = []
              ; environment = { sky = rgb 0.006 0.007 0.009; ground = rgb 0.002 0.002 0.003; panels = [] }
              ; lights = [ P.rect_light ~intensity:9. ~size:(24., 24.) ~target:V.zero (V.create (-34.) 40. 30.) ] } in
  let tracer = get (P.create ~bounces:4 ~width:1200 ~height:1560 scene) in
  get (P.replace_mesh tracer (get (P.scene_mesh [ (M.identity, boxes); (at 0., dense) ])));
  let camera = Rays.Camera.perspective ~fov_y:0.7 ~at:(V.create 0. 6. 19.) ~target:(V.create 0. 6. 0.) () in
  let time f = let start = Unix.gettimeofday () in f (); (Unix.gettimeofday () -. start) *. 1000. in
  let frame () = time (fun () -> get (P.render tracer camera); get (P.flush tracer)) in
  ignore (frame ()); ignore (frame ());
  let full = List.init 5 (fun _ -> P.reset tracer; frame ()) in
  let preview = List.init 5 (fun i -> get (P.move tracer [ M.identity; at (float i *. 0.1) ]); get (P.flush tracer); frame ()) in
  let median l = List.nth (List.sort compare l) (List.length l / 2) in
  Printf.printf "pathtracer bench_scene 1200x1560: full first sample %.1f ms, edit preview %.1f ms (median of 5)\n%!"
    (median full) (median preview);
  P.destroy tracer
