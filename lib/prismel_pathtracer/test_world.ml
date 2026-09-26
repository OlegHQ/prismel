(* The World path: CDF + MIS sampling is unbiased (furnace, and MIS matches
  | Ok t ->
      let live = let _, live = Ogpu.Impl.create_driver () in live in
      P.destroy t;
      let baseline = live () in
      checks ();
      assert (live () = baseline)
 BSDF-only sampling on a peaked map with a sun), MIS has lower variance,
   miss pixels show the background, and rect lights are hittable. *)
module P = Prismel_pathtracer
module W = Prismel.World

let rgb = P.Linear_color.rgb
let get = function Ok v -> v | Error e -> failwith e
let v3 = Prismel.Vec3.create
let white = W.rgb 1. 1. 1.
let gradient c = W.Gradient { zenith = c; horizon = c; nadir = c; sharpness = 1. }

let world ?(background = W.Environment) ?(sun = `Manual (0., 1.)) layers =
  W.bake ~domains:1 ~width:64 ~height:32
    { W.default with
      layers = List.map (fun layer -> { W.name = "layer"; layer; visible = true }) layers;
      background; exposure = 0.; sun }

let black_dome = { P.sky = rgb 0. 0. 0.; ground = rgb 0. 0. 0.; panels = [] }

(* A lone analytic sphere: convex, so every path is direct light and the
   indirect firefly clamp never applies. *)
let tracer ?(bsdf_only = false) ?(spp = 4) ?(size = 32) material =
  Unix.putenv "PRISMEL_PATHTRACER_BSDF_ONLY" (if bsdf_only then "1" else "0");
  let scene = { P.objects = []; spheres = [ P.sphere ~radius:1.5 material (v3 0. 0. 0.) ]
              ; strands = []; environment = black_dome; lights = [] } in
  let t = get (P.create ~spp ~width:size ~height:size scene) in
  Unix.putenv "PRISMEL_PATHTRACER_BSDF_ONLY" "0";
  t

let camera ?(fov = 0.3) () =
  Prismel.Camera.perspective ~fov_y:fov ~at:(v3 0. 0. 6.) ~target:(v3 0. 0. 0.) ()

let frames t cam n =
  for _ = 1 to n do get (P.render t cam); get (P.flush t) done;
  Bytes.copy (get (P.pixels t))

let mean_red bytes =
  let sum = ref 0 in
  Bytes.iteri (fun i c -> if i mod 4 = 0 then sum := !sum + Char.code c) bytes;
  float !sum /. float (Bytes.length bytes / 4)

let rmse a b =
  let sum = ref 0. in
  Bytes.iteri (fun i c -> if i mod 4 = 0 then
    let d = float (Char.code c - Char.code (Bytes.get b i)) in sum := !sum +. (d *. d)) a;
  sqrt (!sum /. float (Bytes.length a / 4))

(* The resolve's ACES fit and 2.2 gamma, for an exact background check. *)
let resolved x =
  let c = (x *. ((2.51 *. x) +. 0.03)) /. ((x *. ((2.43 *. x) +. 0.59)) +. 0.14) in
  int_of_float ((Float.pow (Float.min 1. (Float.max 0. c)) (1. /. 2.2) *. 255.) +. 0.5)

let checks () =
  let diffuse = P.material ~roughness:0.8 (rgb 0.8 0.8 0.8) in
  (* Furnace: uniform lighting radiance 1 on an albedo-0.8 sphere resolves to
     224, like the procedural furnace, with CDF sampling and MIS on. *)
  let t = tracer diffuse in
  get (P.set_world t (Some (world [ gradient white ])));
  let furnace = mean_red (frames t (camera ()) 16) in
  P.destroy t;
  Printf.printf "pathtracer world: furnace mean %.1f (expected 224)\n%!" furnace;
  assert (Float.abs (furnace -. 224.) < 2.);
  (* Peaked map plus a sun: MIS and BSDF-only sampling converge to the same
     image, and MIS is less noisy at equal samples. *)
  let peaked =
    world ~background:(W.Color (W.rgb 0. 0. 0.)) ~sun:(`Manual (-0.9, 0.4))
      [ gradient (W.rgb 0.05 0.05 0.05)
      ; W.Shape { shape = Circle; azimuth = 0.5; elevation = 0.6; width = 0.3; height = 0.
                ; softness = 0.02; color = white; intensity = 30.; emit = Dome }
      ; W.Sun { angular_radius = 0.1; intensity = 20.; tint = white } ] in
  assert (peaked.sun <> None);
  let rough = P.material ~roughness:1. (rgb 0.8 0.8 0.8) in
  let converge ~bsdf_only ~spp n =
    let t = tracer ~bsdf_only ~spp rough in
    get (P.set_world t (Some peaked));
    let image = frames t (camera ~fov:0.6 ()) n in
    P.destroy t;
    image in
  let reference = converge ~bsdf_only:false ~spp:16 128 in
  let bsdf_reference = converge ~bsdf_only:true ~spp:16 512 in
  let mis = converge ~bsdf_only:false ~spp:4 4 and bsdf = converge ~bsdf_only:true ~spp:4 4 in
  let mis_mean = mean_red reference and bsdf_mean = mean_red bsdf_reference in
  let mis_error = rmse mis reference and bsdf_error = rmse bsdf reference in
  Printf.printf "pathtracer world: peaked mean MIS %.2f BSDF-only %.2f; 16 spp rmse MIS %.2f BSDF-only %.2f\n%!"
    mis_mean bsdf_mean mis_error bsdf_error;
  assert (Float.abs (mis_mean -. bsdf_mean) < 1.5);
  assert (rmse reference bsdf_reference < 4.);
  assert (mis_error < bsdf_error);
  (* Background: a Color is the radiance of every miss pixel; Transparent
     leaves them at alpha 0. *)
  let small = P.sphere ~radius:0.5 diffuse (v3 0. 0. 0.) in
  let background bg =
    let scene = { P.objects = []; spheres = [ small ]; strands = []; environment = black_dome; lights = [] } in
    let t = get (P.create ~spp:2 ~width:32 ~height:32 scene) in
    get (P.set_world t (Some (world ~background:bg [ gradient white ])));
    let image = frames t (camera ~fov:0.6 ()) 2 in
    P.destroy t;
    image in
  let image = background (W.Color (W.rgb 0.5 0.25 0.1)) in
  let corner c = Char.code (Bytes.get image c) in
  Printf.printf "pathtracer world: background %d %d %d (expected %d %d %d)\n%!"
    (corner 0) (corner 1) (corner 2) (resolved 0.5) (resolved 0.25) (resolved 0.1);
  assert (abs (corner 0 - resolved 0.5) <= 1 && abs (corner 1 - resolved 0.25) <= 1
          && abs (corner 2 - resolved 0.1) <= 1 && corner 3 = 255);
  let image = background W.Transparent in
  let centre = ((16 * 32) + 16) * 4 in
  assert (Bytes.get image 3 = '\000' && Bytes.get image (centre + 3) = '\255');
  (* A rect light behind the camera shows in a mirror sphere: with BSDF-only
     sampling that light can only arrive by hitting the rect, and MIS agrees. *)
  let mirror = P.material ~roughness:0. ~metallic:1. (rgb 0.9 0.9 0.9) in
  let reflection ~bsdf_only =
    let t = tracer ~bsdf_only mirror in
    get (P.set_world t (Some (world ~background:(W.Color (W.rgb 0. 0. 0.)) [ gradient (W.rgb 0. 0. 0.) ])));
    get (P.set_lights t [ P.rect_light ~intensity:0.5 ~size:(6., 6.) ~target:(v3 0. 0. 0.) (v3 0. 0. 9.) ]);
    let image = frames t (camera ()) 8 in
    P.destroy t;
    let sum = ref 0 in
    for y = 12 to 19 do for x = 12 to 19 do
      sum := !sum + Char.code (Bytes.get image (((y * 32) + x) * 4))
    done done;
    float !sum /. 64. in
  let hit = reflection ~bsdf_only:true and mis = reflection ~bsdf_only:false in
  Printf.printf "pathtracer world: mirror sees rect light %.1f (MIS %.1f)\n%!" hit mis;
  assert (hit > 150. && Float.abs (hit -. mis) < 3.)

let run () =
  let scene = { P.objects = []; spheres = [ P.sphere ~radius:1. (P.material (rgb 1. 1. 1.)) (v3 0. 0. 0.) ]
              ; strands = []; environment = black_dome; lights = [] } in
  match P.create ~width:4 ~height:4 scene with
  | Error message when Sys.getenv_opt "PRISMEL_REQUIRE_RAYTRACING" = None ->
      Printf.printf "pathtracer world: skipped (%s)\n" message
  | Error message -> failwith message
  | Ok t ->
      let live = let _, live = Ogpu.Impl.create_driver () in live in
      P.destroy t;
      let baseline = live () in
      checks ();
      Printf.printf "pathtracer world: handle baseline %d final %d\n" baseline (live ());
      assert (live () = baseline)

(* Convergence probe for specification/pathtracer.md (not in runtest):
   dune exec --root . lib/prismel_pathtracer/test_main.exe -- bench_world *)
let bench () =
  let floor = get (Result.map_error Pdk.Error.to_string
    (Pdk.Box_generator.box ~center:(v3 0. (-1.05) 0.) ~size:(v3 6. 0.1 6.) ())) in
  let ball = get (Result.map_error Pdk.Error.to_string
    (Pdk.Uv_sphere.run ~center:(v3 0. 0. 0.) ~segments:48 ~rings:24 ~radius:1. ())) in
  let scene = { P.objects = [ (floor, P.material ~roughness:0.7 (rgb 0.7 0.7 0.7))
                            ; (ball, P.material ~roughness:0.3 (rgb 0.8 0.5 0.3)) ]
              ; spheres = []
              ; strands = []
              ; environment = { sky = rgb 0.8 0.8 0.8; ground = rgb 0.3 0.3 0.3
                              ; panels = [ P.panel ~intensity:8. ~width:0.4 ~height:0.3 (v3 0.3 1. 0.2) ] }
              ; lights = [] } in
  let room emit = match List.assoc "white room" W.presets with
    | { W.layers = [ ({ layer = Room r; _ } as e) ]; _ } as w ->
        W.bake ~width:512 ~height:256 { w with layers = [ { e with layer = Room { r with emit } } ] }
    | _ -> failwith "white room preset changed" in
  let configs = [ "procedural dome", None; "room, panels in map", Some (room W.Dome)
                ; "room, promoted panels", Some (room W.Light) ] in
  let cam = Prismel.Camera.perspective ~fov_y:0.8 ~at:(v3 0. 0.5 5.) ~target:(v3 0. (-0.2) 0.) () in
  let render world n =
    let t = get (P.create ~spp:1 ~width:256 ~height:256 scene) in
    get (P.set_world t world);
    ignore (frames t cam 1);
    P.reset t;
    let start = Unix.gettimeofday () in
    let image = frames t cam n in
    let ms = (Unix.gettimeofday () -. start) *. 1000. /. float n in
    P.destroy t;
    image, ms in
  let references = List.map (fun (_, w) -> fst (render w 2048)) configs in
  for round = 1 to 3 do
    List.iter2 (fun (name, w) reference ->
      let image16, ms = render w 16 in
      let image64, _ = render w 64 in
      Printf.printf "round %d %-22s %.2f ms/frame  rmse@16 %.2f  rmse@64 %.2f\n%!"
        round name ms (rmse image16 reference) (rmse image64 reference))
      configs references
  done
