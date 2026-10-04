open Rays

(* A 3D layer that keeps its prepared identity is rendered offscreen once and composited
   afterwards (Rays_execution retained views).  The picture must not change when that
   starts, and a changed camera must never show the old picture. *)
let run () =
  let config = { Sketch.default_config with width = 96; height = 64; title = "retained view";
                 fps = None; clock = Sketch.Fixed (1. /. 60.) } in
  let camera distance = Camera.perspective ~at:(Vec3.create 0. 0. distance) ~target:Vec3.zero () in
  let far_camera = camera 6. and near_camera = camera 2.5 in
  let sphere = Scene3.sphere ~material:(Material.matte Color.white) ~radius:1. () in
  let scene3 = Scene3.create [ sphere ] in
  let view (_ : unit) (frame : Frame.t) =
    let camera = if frame.count > 8 then near_camera else far_camera in
    (* the corner square changes every frame: only the UI layer differs between frames *)
    Scene.[ clear Color.black; view3d ~camera scene3;
            rect ~at:(0, 0) ~w:6 ~h:6 ~fill:(Color.rgb (frame.count * 20 mod 256) 0 0) () ] in
  (* an 8x8 grid of samples away from the corner square *)
  let grid canvas =
    let w = Canvas.width canvas and h = Canvas.height canvas in
    List.init 64 (fun i -> Canvas.pixel canvas ~x:((i mod 8 + 1) * w / 10 + w / 20)
      ~y:(((i / 8) + 1) * h / 10 + h / 20)) in
  let seen = ref [] in
  let after_present () (frame : Frame.t) =
    (match Canvas.capture () with
     | Ok canvas -> seen := (frame.count, grid canvas) :: !seen; Canvas.destroy canvas
     | Error message -> failwith message);
    () in
  Sketch.run_state ~config ~max_frames:12 ~init:(fun _ -> ()) ~update:(fun () _ -> ()) ~view
    ~after_present ();
  let at n = List.assoc n !seen in
  let same a b = at a = at b in
  if not (same 2 3 && same 3 5 && same 5 8) then
    failwith "retained view: the picture changed when the layer started being retained";
  if same 8 9 then failwith "retained view: a camera change showed the previous picture";
  if not (same 9 10 && same 10 12) then
    failwith "retained view: the picture changed when the new camera's layer was retained";
  print_endline "retained view: direct, retained and camera-change frames agree"
