open Prismel
open Geom

type model = {
  union : Mesh.t;
  intersection : Mesh.t;
  difference : Mesh.t;
  camera : Easy_camera.t;
  phase : float;
  frames_left : int option;
}

let result_or_fail = function Ok value -> value | Error message -> failwith message

let init _frame =
  let sphere = Mesh.icosphere ~subdivisions:1 ~radius:1.25 () in
  let cutter = Mesh.box ~width:1.65 ~height:2.6 ~depth:1.65 ()
      |> Mesh.transformed (Mat4.translation (Vec3.create 0.62 0. 0.)) in
  {
    union = Csg3.union sphere cutter |> result_or_fail;
    intersection = Csg3.intersection sphere cutter |> result_or_fail;
    difference = Csg3.difference sphere cutter |> result_or_fail;
    camera = Easy_camera.create ~target:Vec3.zero ~distance:10.2 ~elevation:0.18 ();
    phase = 0.;
    frames_left = None;
  }

let update model (frame : Frame.t) =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  { model with phase = model.phase +. frame.dt *. 0.45;
               camera = Easy_camera.update model.camera frame; frames_left }

let material color = Material.create ~diffuse:(Color.hex_exn color)
    ~specular:(Color.rgba 255 255 255 190) ~shininess:46. ()

let view model _frame =
  let object_at x color mesh = Scene3.translate (Vec3.create x 0. 0.) [
    Scene3.rotate ~axis:Vec3.unit_y model.phase [
      Scene3.rotate ~axis:Vec3.unit_x (-0.18) [
        Scene3.mesh ~cull:Scene3.Cull_none ~material:(material color) mesh;
      ];
    ];
  ] in
  let world = Scene3.create ~samples:4 ~lights:[
    Light.directional ~direction:(Vec3.create 0.5 (-1.) (-0.8))
      ~diffuse:(Color.hex_exn "#e0f2fe") ~ambient:(Color.hex_exn "#172554") ();
    Light.point ~at:(Vec3.create (-2.) 4. 4.) ~diffuse:(Color.hex_exn "#fef3c7") ();
  ] [
    object_at (-3.) "#22d3ee" model.union;
    object_at 0. "#fbbf24" model.intersection;
    object_at 3. "#f472b6" model.difference;
  ] in
  Scene.[
    clear (Color.hex_exn "#040714");
    view3d ~camera:(Easy_camera.camera model.camera) world;
    text ~at:(18, 16) ~size:17 "Geom · BSP constructive solid geometry";
    text ~at:(18, 43) ~size:12 "union · intersection · difference";
  ]

let config = { Sketch.default_config with width = 960; height = 580;
  title = "Prismel Geom CSG"; clock = Sketch.Fixed (1. /. 60.) }

let () = match Sys.getenv_opt "PRISMEL_EXPORT_DIR" with
  | Some directory -> ignore (Sketch.export_state ~config ~directory
      ~prefix:"geom-csg" ~frames:1 ~init ~update ~view ())
  | None -> ignore (Sketch.run_state ~config ~init ~update ~view ())
