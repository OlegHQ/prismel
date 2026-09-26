open Prismel
open Procedural
module E = Prismel_editor.Editor3
module P = Prismel_pathtracer

let frame ?(mouse = 450., 320.) ?(delta = 0., 0.) ?(held = false) ?(events = []) count : Frame.t = {
  width = 1280; height = 820; size = 1280, 820;
  drawable_width = 1280; drawable_height = 820; drawable_size = 1280, 820;
  pixel_scale = 1., 1.; time = float_of_int count /. 60.; dt = 1. /. 60.;
  fps = 60.; count; mouse; mouse_delta = delta; keys = [];
  mouse_buttons = (if held then [Input.LeftButton] else []); events }

let () =
  let cooks = Atomic.make 0 and prepare_ms = Atomic.make 0 in
  let mode = try Sys.argv.(1) with _ -> "pt" in
  let v = Vec3.create in
  let grid = Sop_catalog.Grid.create ~label:"wall-grid" ~orientation:Pdk.Plane_generators.Grid_xy
      ~columns:35 ~rows:59 ~width:35. ~height:59. ~size:35. () in
  let cube = Sop_catalog.Box.create ~label:"cube" ~size:(v 0.86 0.86 1.) ~center:(v 0. 0. 0.5) () in
  let graph = Sop_catalog.Copy_to_points.create ~label:"copy-cubes" ~pack:true ~source:cube ~targets:grid () in
  let concrete = P.material ~roughness:0.6 ~round:0.07 (P.Linear_color.rgb 0.4 0.4 0.4) in
  let prepare _ (output : Session.output) =
    let t0 = Unix.gettimeofday () in
    Atomic.incr cooks;
    let r = match output.instances with
      | Some transforms ->
          let geometry = Result.get_ok (Pdk.Normal_ops.run ~owner:Pdk.Attribute.Vertex
              ~cusp_angle:(Float.pi /. 4.5) output.geometry) in
          if mode = "pt" then
            Result.map (fun m -> `Pt m) (P.mesh_instanced ~prototype:(geometry, concrete) transforms)
          else
            Result.map (fun mesh -> `Raster (Scene3.instances_array mesh transforms))
              (Result.map_error Pdk.Error.to_string (Pdk_prismel.Prismel_mesh.to_mesh geometry))
      | None -> Error "not packed" in
    Atomic.fetch_and_add prepare_ms (int_of_float ((Unix.gettimeofday () -. t0) *. 1000.)) |> ignore;
    r in
  let scene3 _ p = match p with `Raster node -> Scene3.create [node] | `Pt _ -> Scene3.create [] in
  let env = E.create ~graph ~factories:Sop_catalog.Editor.factories ~grain:2 ~max_entries:24
      ~max_payload_bytes:(256 * 1024 * 1024) ~prepare ~scene3 () |> Result.get_ok in
  let count = ref 0 in
  let times = ref [] in
  let step ?mouse ?delta ?held env events =
    incr count;
    let t0 = Unix.gettimeofday () in
    let env = E.update env (frame ?mouse ?delta ?held ~events !count) in
    times := (Unix.gettimeofday () -. t0) *. 1000. :: !times; env in
  let key k = Event.KeyPressed k and char c = Event.KeyPressed (Input.KeyChar c) in
  let rec settle env tries =
    let env = step env [] in
    if E.prepared env <> None && Atomic.get cooks > 0 then env
    else if tries > 0 then (Unix.sleepf 0.002; settle env (tries - 1))
    else failwith "no cook" in
  let t0 = Unix.gettimeofday () in
  let env = settle env 5000 in
  Printf.printf "first cook+prepare: %.0f ms (prepare %d ms)\n%!"
    ((Unix.gettimeofday () -. t0) *. 1000.) (Atomic.get prepare_ms);
  let panes = E.panes env (frame 0) in
  let gx, gy, _, _ = panes.graph and ix, iy, iw, ih = panes.inspector in
  let click env (x, y) = step ~mouse:(x, y) env [Event.MousePressed (Input.LeftButton, (x, y));
    Event.MouseReleased (Input.LeftButton, (x, y))] in
  let env = click env (float (gx + 40), float (gy + 400)) in
  let env = click env (float (gx + 40), float (gy + 400)) in
  let label env = Option.map Node.label (E.selected_node env) in
  let rec select name env tries =
    if label env = Some name then env
    else if tries = 0 then failwith ("no row " ^ name)
    else select name (step env [key Input.ArrowDown]) (tries - 1) in
  let stats name =
    let l = List.rev !times in
    let n = List.length l in
    let sorted = List.sort compare l in
    Printf.printf "%s: %d frames, mean %.2f ms, median %.2f, max %.2f\n%!" name n
      (List.fold_left (+.) 0. l /. float n) (List.nth sorted (n / 2)) (List.nth sorted (n - 1));
    times := [] in
  (* Drag a slider: scan the inspector bottom-up at 55% width; the first row
     whose value changes on press+move is a slider. *)
  let drag_any env ~changed ~frames =
    let x = float ix +. 0.55 *. float iw in
    let rec scan y =
      if y < float iy +. 20. then failwith "no slider found" else
      let before = env in
      let env = step ~mouse:(x, y) ~held:true env [Event.MousePressed (Input.LeftButton, (x, y))] in
      let env = step ~mouse:(x +. 4., y) ~delta:(4., 0.) ~held:true env [] in
      if changed before env then begin
        times := [];
        let rec go env i = if i = frames then env else
          go (step ~mouse:(x +. 4. +. float i, y) ~delta:(1., 0.) ~held:true env []) (i + 1) in
        let env = go env 0 in
        let env = step ~mouse:(x +. 4. +. float frames, y) env
            [Event.MouseReleased (Input.LeftButton, (x +. 4. +. float frames, y))] in
        env, y
      end else
        let env = step ~mouse:(x +. 4., y) env [Event.MouseReleased (Input.LeftButton, (x +. 4., y))] in
        ignore env; scan (y -. 8.) in
    scan (float (iy + min ih 400)) in
  (* 1. transform drag at the scene level *)
  let env = select "geo1" env 8 in
  let env = step env [] in
  let matrices e = List.map fst (E.objects e) in
  let env, y = drag_any env ~changed:(fun a b -> matrices a <> matrices b) ~frames:60 in
  Printf.printf "transform slider at y=%.0f (inspector y=%d)\n" y iy;
  stats "transform drag (held frames)";
  Printf.printf "cooks so far: %d\n%!" (Atomic.get cooks);
  (* 2. SOP parameter drag inside geo1 with live cook *)
  let env = step env [char 'i'] in
  let env = step env [] in
  let env = click env (float (gx + 40), float (gy + 400)) in
  let env = match List.find_opt (fun (t : Pxui_graph.node_view) -> t.label = "wall-grid") (E.graph_nodes env) with
    | Some tile -> let x, y, w, h = tile.bounds in
        let p = (float (x + w / 3), float (y + h / 2)) in
        let env = step ~mouse:p env [] in click env p
    | None -> select "wall-grid" env 8 in
  let env = step env [] in
  let cooks_before = Atomic.get cooks in
  let fields e = Option.map (fun n -> List.map (fun (f : Parameter.field_view) -> f.current)
      (Node.parameter_fields n)) (E.selected_node e) in
  let t0 = Unix.gettimeofday () in
  Atomic.set prepare_ms 0;
  let env, _ = drag_any env ~changed:(fun a b -> fields a <> fields b) ~frames:60 in
  stats "geometry drag (held frames)";
  let cooks_during = Atomic.get cooks - cooks_before in
  let rec settle_quiet env n = if n = 0 then env else (Unix.sleepf 0.005; settle_quiet (step env []) (n - 1)) in
  let env = settle_quiet env 100 in
  Printf.printf "cooks completed during 60-frame drag: %d, after release: %d, prepare total %d ms, wall %.0f ms\n%!"
    cooks_during (Atomic.get cooks - cooks_before - cooks_during) (Atomic.get prepare_ms)
    ((Unix.gettimeofday () -. t0) *. 1000.);
  stats "idle frames after release";
  E.close env

(* ---- real Metal path tracer costs for a voxel-wall sized scene ---- *)
let () =
  if (try Sys.argv.(1) with _ -> "pt") <> "pt" then () else
  let v = Vec3.create in
  let ms f = let t0 = Unix.gettimeofday () in let r = f () in (Unix.gettimeofday () -. t0) *. 1000., r in
  let ok = function Ok x -> x | Error e -> failwith e in
  let concrete = P.material ~roughness:0.6 ~round:0.07 (P.Linear_color.rgb 0.4 0.4 0.4) in
  let wall columns rows =
    let grid = Sop_catalog.Grid.create ~orientation:Pdk.Plane_generators.Grid_xy
        ~columns ~rows ~width:35. ~height:59. ~size:35. () in
    let cube = Sop_catalog.Box.create ~size:(v 0.86 0.86 1.) ~center:(v 0. 0. 0.5) () in
    let graph = Sop_catalog.Copy_to_points.create ~pack:true ~source:cube ~targets:grid () in
    let session = ok (Session.create ~max_entries:8 ~max_payload_bytes:(256 * 1024 * 1024)) in
    let output = ok (Result.map_error Diagnostic.error_to_string
        (Session.cook session ~context:(ok (Context.create ())) graph)) in
    let geometry = ok (Result.map_error Pdk.Error.to_string (Pdk.Normal_ops.run ~owner:Pdk.Attribute.Vertex
        ~cusp_angle:(Float.pi /. 4.5) output.geometry)) in
    ok (P.mesh_instanced ~prototype:(geometry, concrete) (Option.get output.instances)) in
  let t, mesh_a = ms (fun () -> wall 35 59) in
  Printf.printf "[pt] cook+mesh_instanced 35x59: %.1f ms\n%!" t;
  let placeholder = Result.get_ok (Pdk.Box_generator.box ~size:(v 0.01 0.01 0.01) ()) in
  let t, tracer = ms (fun () -> ok (P.create ~bounces:4 ~width:560 ~height:800
    { P.objects = [ placeholder, concrete ]; spheres = []; strands = [];
      environment = { sky = P.Linear_color.rgb 0.006 0.007 0.009; ground = P.Linear_color.rgb 0.002 0.002 0.003; panels = [] };
      lights = [ P.rect_light ~intensity:9. ~size:(24., 24.) ~target:(v 0. 0. 0.) (v (-34.) 40. 30.) ] })) in
  Printf.printf "[pt] create: %.0f ms\n%!" t;
  let camera = Camera.perspective ~fov_y:0.7 ~at:(v 0. 1.5 19.) ~target:(v 0. 0. 1.) () in
  let t, scene = ms (fun () -> ok (P.scene_mesh [Mat4.identity, mesh_a])) in
  Printf.printf "[pt] scene_mesh (1 object, %d tris): %.2f ms\n%!" (P.triangle_count scene) t;
  let t, () = ms (fun () -> ok (P.queue_mesh tracer scene); ok (P.flush tracer)) in
  Printf.printf "[pt] queue_mesh + flush (BLAS+TLAS build latency): %.1f ms\n%!" t;
  let frame_ms () = let t, () = ms (fun () -> ok (P.render tracer camera); ok (P.flush tracer)) in t in
  ignore (frame_ms ());
  let l = List.init 20 (fun _ -> frame_ms ()) in
  Printf.printf "[pt] render 560x800 1spp: mean %.1f ms (min %.1f max %.1f)\n%!"
    (List.fold_left (+.) 0. l /. 20.) (List.fold_left Float.min 1e9 l) (List.fold_left Float.max 0. l);
  let l = List.init 20 (fun i ->
    let t, () = ms (fun () -> ok (P.move tracer [Mat4.translation (v (float i *. 0.1) 0. 0.)]); ok (P.flush tracer)) in t) in
  Printf.printf "[pt] move + flush (TLAS refit latency): mean %.1f ms max %.1f\n%!"
    (List.fold_left (+.) 0. l /. 20.) (List.fold_left Float.max 0. l);
  let l = List.init 10 (fun i ->
    let t, () = ms (fun () -> ok (P.move tracer [Mat4.translation (v (float i *. 0.1) 0. 0.)]); ok (P.render tracer camera); ok (P.flush tracer)) in t) in
  Printf.printf "[pt] move + render + flush per frame: mean %.1f ms\n%!" (List.fold_left (+.) 0. l /. 10.);
  let t, mesh_b = ms (fun () -> wall 36 59) in
  Printf.printf "[pt] recook+mesh_instanced 36x59: %.1f ms\n%!" t;
  let t, () = ms (fun () -> let s = ok (P.scene_mesh [Mat4.identity, mesh_b]) in ok (P.queue_mesh tracer s); ok (P.flush tracer)) in
  Printf.printf "[pt] geometry change: scene_mesh + queue_mesh + flush: %.1f ms\n%!" t;
  let t, () = ms (fun () -> ok (P.flush tracer)) in ignore t;
  let t, baked = ms (fun () -> World.bake_cached ~width:512 ~height:256 World.default) in
  Printf.printf "[world] bake 512x256: %.0f ms\n%!" t;
  let t, _ = ms (fun () -> World.bake_cached ~width:2048 ~height:1024 World.default) in
  Printf.printf "[world] bake 2048x1024: %.0f ms\n%!" t;
  let t, () = ms (fun () -> ok (P.set_world tracer (Some baked))) in
  Printf.printf "[pt] set_world: %.1f ms\n%!" t;
  P.destroy tracer

let () =
  if (try Sys.argv.(1) with _ -> "") <> "spp" then () else
  let v = Vec3.create in
  let ok = function Ok x -> x | Error e -> failwith e in
  let concrete = P.material ~roughness:0.6 ~round:0.07 (P.Linear_color.rgb 0.4 0.4 0.4) in
  let grid = Sop_catalog.Grid.create ~orientation:Pdk.Plane_generators.Grid_xy
      ~columns:35 ~rows:59 ~width:35. ~height:59. ~size:35. () in
  let cube = Sop_catalog.Box.create ~size:(v 0.86 0.86 1.) ~center:(v 0. 0. 0.5) () in
  let graph = Sop_catalog.Copy_to_points.create ~pack:true ~source:cube ~targets:grid () in
  let session = ok (Session.create ~max_entries:8 ~max_payload_bytes:(256 * 1024 * 1024)) in
  let output = ok (Result.map_error Diagnostic.error_to_string
      (Session.cook session ~context:(ok (Context.create ())) graph)) in
  let geometry = ok (Result.map_error Pdk.Error.to_string (Pdk.Normal_ops.run ~owner:Pdk.Attribute.Vertex
      ~cusp_angle:(Float.pi /. 4.5) output.geometry)) in
  let mesh = ok (P.mesh_instanced ~prototype:(geometry, concrete) (Option.get output.instances)) in
  let camera = Camera.perspective ~fov_y:0.7 ~at:(v 0. 1.5 19.) ~target:(v 0. 0. 1.) () in
  let placeholder = Result.get_ok (Pdk.Box_generator.box ~size:(v 0.01 0.01 0.01) ()) in
  List.iter (fun (width, height, spp, bounces, round_samples) ->
    let tracer = ok (P.create ~spp ~bounces ~round_samples ~width ~height
      { P.objects = [ placeholder, concrete ]; spheres = []; strands = [];
        environment = { sky = P.Linear_color.rgb 0.006 0.007 0.009; ground = P.Linear_color.rgb 0.002 0.002 0.003; panels = [] };
        lights = [ P.rect_light ~intensity:9. ~size:(24., 24.) ~target:(v 0. 0. 0.) (v (-34.) 40. 30.);
                   P.rect_light ~intensity:1.2 ~size:(30., 30.) ~target:(v 0. 0. 0.) (v 30. (-10.) 26.) ] }) in
    ok (P.queue_mesh tracer (ok (P.scene_mesh [Mat4.identity, mesh]))); ok (P.flush tracer);
    ok (P.render tracer camera); ok (P.flush tracer);
    ok (P.render tracer camera); ok (P.flush tracer);
    let t0 = Unix.gettimeofday () in
    for _ = 1 to 10 do ok (P.render tracer camera); ok (P.flush tracer) done;
    let ms = (Unix.gettimeofday () -. t0) *. 100. in
    Printf.printf "[spp] %dx%d spp=%d bounces=%d round=%d: %.1f ms/dispatch = %.1f samples/s\n%!"
      width height spp bounces round_samples ms (1000. /. ms *. float spp);
    P.destroy tracer)
    [ 800, 760, 1, 4, 4; 800, 760, 4, 4, 4; 800, 760, 8, 4, 4; 800, 760, 1, 4, 1; 800, 760, 4, 4, 1;
      800, 760, 1, 2, 1; 400, 380, 1, 4, 4; 400, 380, 4, 4, 1 ]

let () =
  if (try Sys.argv.(1) with _ -> "") <> "pipe" then () else
  let v = Vec3.create in
  let ok = function Ok x -> x | Error e -> failwith e in
  let concrete = P.material ~roughness:0.6 ~round:0.07 (P.Linear_color.rgb 0.4 0.4 0.4) in
  let grid = Sop_catalog.Grid.create ~orientation:Pdk.Plane_generators.Grid_xy
      ~columns:35 ~rows:59 ~width:35. ~height:59. ~size:35. () in
  let cube = Sop_catalog.Box.create ~size:(v 0.86 0.86 1.) ~center:(v 0. 0. 0.5) () in
  let graph = Sop_catalog.Copy_to_points.create ~pack:true ~source:cube ~targets:grid () in
  let session = ok (Session.create ~max_entries:8 ~max_payload_bytes:(256 * 1024 * 1024)) in
  let output = ok (Result.map_error Diagnostic.error_to_string
      (Session.cook session ~context:(ok (Context.create ())) graph)) in
  let geometry = ok (Result.map_error Pdk.Error.to_string (Pdk.Normal_ops.run ~owner:Pdk.Attribute.Vertex
      ~cusp_angle:(Float.pi /. 4.5) output.geometry)) in
  let mesh = ok (P.mesh_instanced ~prototype:(geometry, concrete) (Option.get output.instances)) in
  let camera i = Camera.perspective ~fov_y:0.7 ~at:(v (0.01 *. float i) 1.5 19.) ~target:(v 0. 0. 1.) () in
  let placeholder = Result.get_ok (Pdk.Box_generator.box ~size:(v 0.01 0.01 0.01) ()) in
  List.iter (fun preview_scale ->
    let tracer = ok (P.create ~bounces:4 ~preview_scale ~width:800 ~height:760
      { P.objects = [ placeholder, concrete ]; spheres = []; strands = [];
        environment = { sky = P.Linear_color.rgb 0.006 0.007 0.009; ground = P.Linear_color.rgb 0.002 0.002 0.003; panels = [] };
        lights = [ P.rect_light ~intensity:9. ~size:(24., 24.) ~target:(v 0. 0. 0.) (v (-34.) 40. 30.) ] }) in
    ok (P.queue_mesh tracer (ok (P.scene_mesh [Mat4.identity, mesh]))); ok (P.flush tracer);
    (* accumulation throughput with render called every 4 ms like a UI loop *)
    ok (P.render tracer (camera 0)); ok (P.flush tracer);
    let t0 = Unix.gettimeofday () in
    while Unix.gettimeofday () -. t0 < 3. do ok (P.render tracer (camera 0)); Unix.sleepf 0.004 done;
    ok (P.flush tracer);
    let seconds = Unix.gettimeofday () -. t0 in
    Printf.printf "[pipe] scale=%d accumulate: %.1f samples/s\n%!" preview_scale (float (P.samples tracer) /. seconds);
    (* preview latency: a moving camera, each frame waited for *)
    let l = List.init 10 (fun i -> let t0 = Unix.gettimeofday () in
      ok (P.render tracer (camera (i + 1))); ok (P.flush tracer); (Unix.gettimeofday () -. t0) *. 1000.) in
    Printf.printf "[pipe] scale=%d preview frame: mean %.1f ms\n%!" preview_scale (List.fold_left (+.) 0. l /. 10.);
    (* a move + set_lights while frames are in flight must not block *)
    ok (P.render tracer (camera 0)); ok (P.render tracer (camera 0));
    let t0 = Unix.gettimeofday () in
    ok (P.set_lights tracer [ P.rect_light ~intensity:8. ~size:(24., 24.) ~target:(v 0. 0. 0.) (v (-34.) 40. 30.) ]);
    ok (P.move tracer [Mat4.translation (v 0.5 0. 0.)]);
    Printf.printf "[pipe] scale=%d set_lights + move with 2 frames in flight: %.2f ms (main thread)\n%!" preview_scale
      ((Unix.gettimeofday () -. t0) *. 1000.);
    ok (P.flush tracer);
    P.destroy tracer) [1; 2; 3]
