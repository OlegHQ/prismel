open Prismel
open Geom

type model = {
  meshes : (string * string * Mesh.t) list;
  camera : Easy_camera.t;
  phase : float;
  frames_left : int option;
}

let result_or_fail = function Ok value -> value | Error message -> failwith message

let init _frame =
  let source = Mesh.icosahedron ~radius:1.15 in
  {
    meshes = [
      "Loop", "#22d3ee", Mesh3.loop_subdivide ~iterations:2 source |> result_or_fail;
      "Butterfly", "#fbbf24", Mesh3.butterfly_subdivide ~iterations:2 source |> result_or_fail;
      "Catmull-Clark", "#f472b6", Mesh3.catmull_clark ~iterations:2 source |> result_or_fail;
      "Doo-Sabin", "#a78bfa", Mesh3.doo_sabin source |> result_or_fail;
    ];
    camera = Easy_camera.create ~target:Vec3.zero ~distance:11.8 ~elevation:0.12 ();
    phase = 0.; frames_left = if Sketch.is_headless () then Some 3 else None;
  }

let update model (frame : Frame.t) =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0 | Some count -> Some (count - 1) | None -> None in
  { model with phase = model.phase +. frame.dt *. 0.4;
               camera = Easy_camera.update model.camera frame; frames_left }

let view model _frame =
  let positions = [-3.75; -1.25; 1.25; 3.75] in
  let nodes = List.map2 (fun x (_name, color, mesh) ->
    Scene3.translate (Vec3.create x 0. 0.) [
      Scene3.rotate ~axis:Vec3.unit_y model.phase [
        Scene3.mesh ~cull:Scene3.Cull_none
          ~material:(Material.create ~diffuse:(Color.hex_exn color)
            ~specular:(Color.rgba 255 255 255 170) ~shininess:38. ()) mesh;
      ];
    ]) positions model.meshes in
  let world = Scene3.create ~samples:4 ~lights:[
    Light.directional ~direction:(Vec3.create 0.4 (-1.) (-0.7))
      ~diffuse:(Color.hex_exn "#e0f2fe") ~ambient:(Color.hex_exn "#172554") ();
  ] nodes in
  let labels = List.map2 (fun x (name, _, _) ->
    Scene.text ~at:(int_of_float (480. +. (x *. 85.)) - 38, 520) ~size:11 name)
    positions model.meshes in
  Scene.clear (Color.hex_exn "#040714")
  :: Scene.view3d ~camera:(Easy_camera.camera model.camera) world
  :: Scene.text ~at:(18, 16) ~size:17 "Geom · subdivision families"
  :: labels

let config = { Sketch.default_config with width = 960; height = 560;
  title = "Prismel Geom subdivision"; clock = Sketch.Fixed (1. /. 60.) }

let () = match Sys.getenv_opt "PRISMEL_EXPORT_DIR" with
  | Some directory -> ignore (Sketch.export_state ~config ~directory
      ~prefix:"geom-subdivision" ~frames:1 ~init ~update ~view ())
  | None -> ignore (Sketch.run_state ~config ~init ~update ~view ())
