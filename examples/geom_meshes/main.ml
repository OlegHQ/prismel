open Prismel
open Geom

type model = {
  extrusion : Mesh.t;
  lathe : Mesh.t;
  sweep : Mesh.t;
  subdivision : Mesh.t;
  camera : Easy_camera.t;
  phase : float;
  frames_left : int option;
}

let result_or_fail = function
  | Ok value -> value
  | Error message -> failwith message

let make_extrusion () =
  Polygon2.star ~center:Vec2.zero ~inner_radius:0.58
    ~outer_radius:1.25 ~points:9 ()
  |> Mesh3.extrude ~depth:0.72
  |> result_or_fail

let make_lathe () =
  let profile =
    Curve2.catmull_rom ~resolution:7
      [
        Vec2.create 0.05 (-1.45);
        Vec2.create 0.82 (-1.34);
        Vec2.create 1.08 (-0.45);
        Vec2.create 0.58 0.08;
        Vec2.create 0.92 0.92;
        Vec2.create 0.12 1.5;
      ]
    |> result_or_fail
  in
  Mesh3.lathe ~segments:36 ~capped:true profile |> result_or_fail

let make_sweep () =
  let profile =
    Polygon2.regular ~center:Vec2.zero ~radius:0.26 ~sides:7 ()
  in
  let spine =
    List.init 44 (fun index ->
      let amount = float_of_int index /. 43. in
      let angle = amount *. 3.4 *. Float.pi in
      Vec3.create
        (0.95 *. cos angle)
        ((amount -. 0.5) *. 3.1)
        (0.95 *. sin angle))
  in
  Mesh3.sweep ~smooth_angle:(Float.pi /. 5.)
    ~profile ~spine () |> result_or_fail

let make_subdivision () =
  Mesh.icosahedron ~radius:1.18
  |> Mesh3.loop_subdivide ~iterations:2
  |> result_or_fail

let init _frame =
  {
    extrusion = make_extrusion ();
    lathe = make_lathe ();
    sweep = make_sweep ();
    subdivision = make_subdivision ();
    camera =
      Easy_camera.create ~target:(Vec3.create 0. 0.15 0.)
        ~distance:11.5 ~elevation:0.16 ();
    phase = 0.;
    frames_left = None;
  }

let update model (frame : Frame.t) =
  let frames_left =
    match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  {
    model with
    camera = Easy_camera.update model.camera frame;
    phase = model.phase +. frame.dt *. 0.45;
    frames_left;
  }

let material hex =
  Material.create ~diffuse:(Color.hex_exn hex)
    ~specular:(Color.rgba 255 255 255 175) ~shininess:42. ()

let lights =
  [
    Light.directional
      ~direction:(Vec3.create 0.5 (-1.) (-0.7))
      ~diffuse:(Color.hex_exn "#dbeafe")
      ~ambient:(Color.hex_exn "#172554") ();
    Light.point ~at:(Vec3.create (-2.) 4. 5.)
      ~diffuse:(Color.hex_exn "#fde68a") ();
  ]

let view model (_frame : Frame.t) =
  let spin = model.phase in
  let object_at x mesh color =
    Scene3.translate (Vec3.create x 0. 0.) [
      Scene3.rotate ~axis:Vec3.unit_y spin [
        Scene3.rotate ~axis:Vec3.unit_x (0.14 *. sin spin) [
          Scene3.mesh ~material:(material color) mesh;
        ];
      ];
    ]
  in
  let world =
    Scene3.create ~lights ~samples:4 [
      object_at (-3.45) model.extrusion "#f472b6";
      object_at (-1.15) model.lathe "#fbbf24";
      object_at 1.25 model.sweep "#22d3ee";
      object_at 3.75 model.subdivision "#a78bfa";
      Scene3.translate (Vec3.create 0. (-1.72) 0.) [
        Scene3.rotate ~axis:Vec3.unit_x (-.Float.pi /. 2.) [
          Scene3.plane ~cull:Scene3.Cull_none
            ~material:(Material.matte (Color.hex_exn "#111827"))
            ~width:12. ~height:7. ();
        ];
      ];
    ]
  in
  Scene.[
    clear (Color.hex_exn "#040714");
    view3d ~camera:(Easy_camera.camera model.camera) world;
    text ~at:(18, 16) ~size:17
      "Geom · extrusion / lathe / sweep / Loop subdivision";
    text ~at:(18, 43) ~size:12
      "2D profiles become immutable Prismel meshes";
  ]

let config = {
  Sketch.default_config with
  width = 1000;
  height = 600;
  title = "Prismel Geom meshes";
  clock = Sketch.Fixed (1. /. 60.);
}

let () =
  match Sys.getenv_opt "PRISMEL_EXPORT_DIR" with
  | Some directory ->
      ignore
        (Sketch.export_state ~config ~directory ~prefix:"geom-meshes"
           ~frames:1 ~init ~update ~view ())
  | None ->
      ignore (Sketch.run_state ~config ~init ~update ~view ())
