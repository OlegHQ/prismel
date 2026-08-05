open Prismel
open Geom

type model = {
  gyroid : Mesh.t;
  metaballs : Mesh.t;
  camera : Easy_camera.t;
  phase : float;
  frames_left : int option;
}

let result_or_fail = function
  | Ok value -> value
  | Error message -> failwith message

let symmetric_bounds radius =
  Vec3.create (-.radius) (-.radius) (-.radius),
  Vec3.create radius radius radius

let make_gyroid () =
  let minimum, maximum = symmetric_bounds 1.42 in
  let field point =
    let x = point.(0) and y = point.(1) and z = point.(2) in
    let spherical = 1.32 -. sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
    let gx = x *. 2.65 and gy = y *. 2.65 and gz = z *. 2.65 in
    let gyroid =
      (sin gx *. cos gy) +. (sin gy *. cos gz) +. (sin gz *. cos gx) in
    let sheet = 0.27 -. abs_float gyroid in
    Float.min spherical sheet
  in
  Iso3.extract_dense ~resolution:(20, 20, 20)
    ~min:minimum ~max:maximum ~iso:0. ~field:(Iso3.Field.custom field) ()
  |> result_or_fail

let make_metaballs () =
  let minimum, maximum = symmetric_bounds 1.7 in
  let balls =
    [
      Iso3.metaball ~center:(Vec3.create (-0.55) (-0.25) 0.)
        ~radius:0.72 ();
      Iso3.metaball ~center:(Vec3.create 0.48 (-0.2) 0.28)
        ~radius:0.74 ();
      Iso3.metaball ~center:(Vec3.create (-0.05) 0.62 (-0.18))
        ~radius:0.68 ();
    ]
  in
  Iso3.extract_dense ~resolution:(20, 20, 20)
    ~min:minimum ~max:maximum ~iso:1.
    ~field:(Iso3.Field.metaballs balls) ()
  |> result_or_fail

let init _frame =
  {
    gyroid = make_gyroid ();
    metaballs = make_metaballs ();
    camera =
      Easy_camera.create ~target:Vec3.zero
        ~distance:7.8 ~elevation:0.12 ();
    phase = 0.;
    frames_left = if Sketch.is_headless () then Some 3 else None;
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
    phase = model.phase +. frame.dt *. 0.4;
    frames_left;
  }

let shiny color =
  Material.create ~diffuse:(Color.hex_exn color)
    ~specular:(Color.rgba 255 255 255 210) ~shininess:52. ()

let view model (_frame : Frame.t) =
  let lights =
    [
      Light.directional
        ~direction:(Vec3.create 0.6 (-1.) (-0.8))
        ~diffuse:(Color.hex_exn "#e0f2fe")
        ~ambient:(Color.hex_exn "#172554") ();
      Light.point ~at:(Vec3.create (-2.) 3. 4.)
        ~diffuse:(Color.hex_exn "#fef3c7") ();
    ]
  in
  let object_at x material mesh =
    Scene3.translate (Vec3.create x 0. 0.) [
      Scene3.rotate ~axis:Vec3.unit_y model.phase [
        Scene3.rotate ~axis:Vec3.unit_x (-0.22) [
          Scene3.mesh ~cull:Scene3.Cull_none ~material mesh;
        ];
      ];
    ]
  in
  let world =
    Scene3.create ~lights ~samples:4 [
      object_at (-1.75) (shiny "#22d3ee") model.gyroid;
      object_at 1.65 (shiny "#f472b6") model.metaballs;
      Scene3.translate (Vec3.create 0. (-1.72) 0.) [
        Scene3.rotate ~axis:Vec3.unit_x (-.Float.pi /. 2.) [
          Scene3.plane ~cull:Scene3.Cull_none
            ~material:(Material.matte (Color.hex_exn "#111827"))
            ~width:9. ~height:6. ();
        ];
      ];
    ]
  in
  Scene.[
    clear (Color.hex_exn "#040714");
    view3d ~camera:(Easy_camera.camera model.camera) world;
    text ~at:(18, 16) ~size:17 "Geom · volumetric isosurfaces";
    text ~at:(18, 43) ~size:12
      "gyroid field · inverse-square metaballs · marching tetrahedra";
  ]

let config = {
  Sketch.default_config with
  width = 900;
  height = 600;
  title = "Prismel Geom isosurfaces";
  clock = Sketch.Fixed (1. /. 60.);
}

let () =
  match Sys.getenv_opt "PRISMEL_EXPORT_DIR" with
  | Some directory ->
      ignore
        (Sketch.export_state ~config ~directory ~prefix:"geom-isosurface"
           ~frames:1 ~init ~update ~view ())
  | None ->
      ignore (Sketch.run_state ~config ~init ~update ~view ())
