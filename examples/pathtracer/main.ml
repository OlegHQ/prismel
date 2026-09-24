(* Studio table rendered by the Metal ray-tracing path tracer.
   Drag with the left mouse button to orbit, scroll to dolly.
   PRISMEL_PATHTRACER_FRAMES=N runs a finite smoke; PRISMEL_PATHTRACER_PNG=path
   saves the final frame. *)
open Prismel
module P = Prismel_pathtracer

let v = Vec3.create
let pdk = function Ok g -> g | Error e -> failwith (Pdk.Error.to_string e)

(* Seven tumbling matte cubes over a dark cyclorama. Edges are rounded by the
   render-time round-corners shader, not by geometry. *)
let cube ~at ~rotation ~size =
  pdk (Pdk.Ops.box ~center:at ~rotation ~size:(v size size size) ())

let concrete shade =
  P.material ~roughness:0.62 ~round:0.045 (shade, shade *. 1.03, shade *. 1.1)

let cubes =
  [ (v (-1.15) 6.35 0.2), (v 0.55 0.45 0.3), 0.26
  ; (v 1.05 5.65 (-0.1)), (v 0.35 (-0.6) 0.25), 0.26
  ; (v (-0.55) 4.35 0.35), (v 0.5 0.7 (-0.4)), 0.20
  ; (v 1.35 3.45 0.1), (v 0.3 0.25 0.55), 0.26
  ; (v (-0.95) 2.65 0.), (v 0.15 (-0.35) 0.1), 0.22
  ; (v 0.85 1.55 0.4), (v 0.6 0.35 (-0.5)), 0.26
  ; (v (-1.0) 0.75 0.1), (v 0.45 (-0.5) 0.35), 0.24 ]

let scene =
  { P.objects =
      List.map (fun (at, rotation, shade) -> (cube ~at ~rotation ~size:1.05, concrete shade)) cubes
      @ [ (pdk (Pdk.Ops.box ~center:(v 0. (-0.1) 0.) ~size:(v 400. 0.2 400.) ()),
           P.material ~roughness:0.8 (0.16, 0.165, 0.18)) ]
  ; environment =
      { sky = (0.008, 0.010, 0.014); ground = (0.002, 0.002, 0.003)
      ; panels = [ P.panel ~intensity:0.25 ~width:0.9 ~height:0.6 ~softness:0.3 (v 0. 0.2 1.) ] }
  ; lights =
      [ P.rect_light ~intensity:26. ~size:(4., 4.) ~target:(v 0. 3.5 0.) (v (-6.) 12. 6.)
      ; P.rect_light ~intensity:2. ~size:(3., 6.) ~target:(v 0. 3.5 0.) (v 9. 4. (-3.)) ] }

type model = { tracer : P.t; yaw : float; pitch : float; distance : float; dragging : bool }

let camera m =
  let target = v 0. 3.35 0. in
  let eye = v (target.x +. (m.distance *. cos m.pitch *. sin m.yaw))
      (target.y +. (m.distance *. sin m.pitch)) (target.z +. (m.distance *. cos m.pitch *. cos m.yaw)) in
  { P.eye; target; fov = 0.6 }

let width, height = 480, 840
let env name default of_string = Option.value ~default (Option.bind (Sys.getenv_opt name) of_string)
let frames = env "PRISMEL_PATHTRACER_FRAMES" 0 int_of_string_opt
let spp = env "PRISMEL_PATHTRACER_SPP" 1 int_of_string_opt
(* Render-resolution multiplier over the logical window: 2 fills a Retina drawable. *)
let render_scale = env "PRISMEL_PATHTRACER_SCALE" 1. float_of_string_opt
let started = Unix.gettimeofday ()

let init _ =
  match P.create ~spp ~bounces:5 ~exposure:0.9 ~width:(int_of_float (float width *. render_scale))
          ~height:(int_of_float (float height *. render_scale)) scene with
  | Error message -> failwith message
  | Ok tracer -> { tracer; yaw = 0.; pitch = -0.2; distance = 13.5; dragging = false }

let update m (frame : Frame.t) =
  let m = List.fold_left (fun m event ->
    match event with
    | Event.MousePressed (Input.LeftButton, _) -> { m with dragging = true }
    | Event.MouseReleased (Input.LeftButton, _) | Event.WindowFocusLost -> { m with dragging = false }
    | Event.MouseMoved _ when m.dragging ->
        let dx, dy = frame.mouse_delta in
        { m with yaw = m.yaw -. (float dx *. 0.006)
        ; pitch = Float.min 1.4 (Float.max (-0.6) (m.pitch +. (float dy *. 0.006))) }
    | Event.MouseScrolled (_, dy) ->
        { m with distance = Float.min 40. (Float.max 3. (m.distance *. (1. -. (dy *. 0.08)))) }
    | _ -> m) m frame.events in
  (match P.render m.tracer (camera m) with Ok () -> () | Error e -> prerr_endline e);
  if frames > 0 && frame.count + 1 >= frames then begin
    Option.iter (fun path ->
      match Canvas.save_screen_png path with
      | Ok () -> Printf.printf "saved %s\n%!" path
      | Error e -> prerr_endline e) (Sys.getenv_opt "PRISMEL_PATHTRACER_PNG");
    let w, h = P.size m.tracer in
    Printf.printf "%dx%d  %d frames  %d spp  %.1f ms/frame\n%!" w h frames (P.samples m.tracer)
      ((Unix.gettimeofday () -. started) *. 1000. /. float frames);
    Sketch.quit ()
  end;
  m

let view m (frame : Frame.t) =
  Scene.[ clear Color.black
        ; image (P.image m.tracer) ~at:(0, 0) ~scale:(1. /. render_scale) ()
        ; text ~at:(12, 12) ~color:(Color.rgb 120 120 125)
            (Printf.sprintf "%d spp  %.0f fps  drag: orbit  scroll: dolly" (P.samples m.tracer) frame.fps) ]

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width; height; title = "Prismel path tracer"; resizable = false }
    ~init ~update ~view ~on_stop:(fun m -> P.destroy m.tracer) ())
