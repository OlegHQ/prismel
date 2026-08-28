open Prismel

type model = {
  angle : float;
  camera : Easy_camera.t;
  frames_left : int option;
}

let headless_frame_limit =
  match Sys.getenv_opt "PRISMEL_THREE_D_FRAMES" with
  | None -> 3
  | Some value -> max 1 (int_of_string value)

let lights =
  [
    Light.directional
      ~direction:(Vec3.create 0.5 (-1.) (-0.7))
      ~diffuse:(Color.hex_exn "#dbeafe")
      ~ambient:(Color.hex_exn "#172554")
      ();
    Light.area
      ~at:(Vec3.create (-3.) 4. 4.)
      ~direction:(Vec3.create 0. (-1.) (-1.))
      ~width:2.5 ~height:1.5
      ~diffuse:(Color.hex_exn "#fef3c7")
      ~attenuation:(Light.attenuation ~constant:0.5 ~linear:0.08 ())
      ();
  ]

let cyan = Material.create ~diffuse:(Color.hex_exn "#22d3ee") ()
let coral = Material.create ~diffuse:(Color.hex_exn "#fb7185") ()
let gold = Material.create ~diffuse:(Color.hex_exn "#fbbf24") ()
let orbit_material = Material.matte Color.white
let orbit_mesh = Mesh.icosphere ~subdivisions:1 ~radius:0.16 ()
let box_mesh = Mesh.box ~width:1.8 ~height:1.8 ~depth:1.8 ()
let center_mesh = Mesh.icosphere ~radius:1.15 ()
let cylinder_mesh = Mesh.cylinder ~radius:0.85 ~height:2.2 ()
let floor_mesh = Mesh.plane ~width:12. ~height:10. ()
let floor_base_color = Color.hex_exn "#0f172a"
let floor_material = Material.unlit floor_base_color
let floor_grid_low = Color.hex_exn "#164e63"
let floor_grid_high = Color.hex_exn "#67e8f9"
let floor_grid_depth = Scene3.depth_state ~comparison:Scene3.Always ()

let floor_grid_mesh =
  let half_width = 6. and half_height = 5. and line_half_width = 0.035 in
  let vertical =
    List.init 13 (fun index ->
      let x = float_of_int (index - 6) in
      (Float.max (-.half_width) (x -. line_half_width), -.half_height,
       Float.min half_width (x +. line_half_width), half_height))
  and horizontal =
    List.init 11 (fun index ->
      let y = float_of_int (index - 5) in
      (-.half_width, Float.max (-.half_height) (y -. line_half_width),
       half_width, Float.min half_height (y +. line_half_width)))
  in
  let vertices, indices, _ =
    List.fold_left
      (fun (vertices, indices, first) (x0, y0, x1, y1) ->
        ( vertices @ [
            Vec3.create x0 y0 0.; Vec3.create x1 y0 0.;
            Vec3.create x1 y1 0.; Vec3.create x0 y1 0.;
          ],
          indices @ [first; first + 1; first + 2; first; first + 2; first + 3],
          first + 4 ))
      ([], [], 0) (vertical @ horizontal)
  in
  Mesh.create_exn ~indices
    ~normals:(List.init (List.length vertices) (fun _ -> Vec3.unit_z))
    vertices

let init _frame =
  {
    angle = 0.;
    camera =
      Easy_camera.create ~target:(Vec3.create 0. 0.2 0.)
        ~distance:8.2 ~elevation:0.22 ();
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
    angle = model.angle +. frame.dt;
    camera = Easy_camera.update model.camera frame;
    frames_left;
  }

let floor_grid_color time =
  let pulse = 0.35 +. (0.25 *. (1. +. sin time)) in
  Color.blend floor_grid_low floor_grid_high ~pct:pulse

let view model (_frame : Frame.t) =
  let orbit_instances =
    List.init 18 (fun index ->
      let angle =
        model.angle *. 0.4
        +. (float_of_int index /. 18. *. 2. *. Float.pi)
      in
      Mat4.translation
        (Vec3.create (3.5 *. cos angle) 1.1 (3.5 *. sin angle)))
  in
  let scene3 =
    Scene3.create ~lights ~samples:4 [
      Scene3.translate (Vec3.create 0. (-1.5) 0.) [
        Scene3.rotate ~axis:Vec3.unit_x (-.Float.pi /. 2.) [
          Scene3.mesh ~cull:Scene3.Cull_none
            ~material:floor_material floor_mesh;
          Scene3.with_depth floor_grid_depth [
            Scene3.mesh ~cull:Scene3.Cull_none
              ~material:(Material.unlit (floor_grid_color model.angle))
              floor_grid_mesh;
          ];
        ];
      ];
      Scene3.instances ~material:orbit_material
        orbit_mesh orbit_instances;
      Scene3.translate (Vec3.create (-2.2) 0. 0.) [
        Scene3.rotate ~axis:Vec3.unit_y model.angle [
          Scene3.mesh ~material:cyan box_mesh;
        ];
      ];
      Scene3.translate (Vec3.create 0. 0. 0.) [
        Scene3.rotate ~axis:Vec3.unit_y (-.model.angle *. 0.7) [
          Scene3.mesh ~material:coral center_mesh;
        ];
      ];
      Scene3.translate (Vec3.create 2.3 0. 0.) [
        Scene3.rotate ~axis:Vec3.unit_x (model.angle *. 0.6) [
          Scene3.mesh ~material:gold cylinder_mesh;
        ];
      ];
    ]
  in
  Scene.[
    clear (Color.hex_exn "#020617");
    view3d ~camera:(Easy_camera.camera model.camera) scene3;
    text ~at:(16, 16)
      "Left: orbit  Middle: pan  Right/scroll: zoom";
  ]

let () =
  ignore
    (Sketch.run_state
       ~config:{
         Sketch.default_config with
         width = 800;
         height = 500;
         title = "Prismel 3D";
       }
       ~init ~update ~view ())
