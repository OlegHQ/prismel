module Presenter = Runtime_sdl3_raster2_presenter.Sdl3_raster2_presenter

type error = Renderer of Raster2_renderer.error | Presenter of Presenter.error

let present session (frame : Raster2_renderer.frame) =
  Presenter.present_session session {
    rgba = frame.rgba;
    pitch = frame.pitch;
    logical_width = frame.logical_width;
    logical_height = frame.logical_height;
    drawable_width = frame.drawable_width;
    drawable_height = frame.drawable_height;
  }

let self_test () =
  let ok_renderer = function
    | Ok value -> value
    | Error _ -> failwith "Raster2 comparison renderer error"
  and ok_presenter = function
    | Ok value -> value
    | Error _ -> failwith "Raster2 comparison presenter error"
  in
  let scene2 = Scene_raster2_lowering.{
    image = (fun _ -> Error Resource_failure);
    font_text = (fun _ _ _ _ -> Error Resource_failure);
    system_text = (fun _ _ -> Error Resource_failure);
    debug_text = (fun _ -> Error Resource_failure);
  } in
  let scene3 = Scene3_raster2_lowering.{
    texture = (fun _ -> Error Texture_error);
    shadow = (fun _ -> Error Shadow_error);
  } in
  let mesh = Mesh.create_exn ~normals:[Vec3.unit_z; Vec3.unit_z; Vec3.unit_z]
      [Vec3.create (-0.6) (-0.6) 0.; Vec3.create 0.6 (-0.6) 0.;
       Vec3.create 0. 0.6 0.] in
  let camera = Camera.orthographic ~height:2. ~at:(Vec3.create 0. 0. 2.)
      ~target:Vec3.zero () in
  let view = Scene3.create [Scene3.mesh ~material:(Material.unlit Color.green)
      ~cull:Scene3.Cull_none mesh] in
  let scene = [Scene_description.Clear Color.black;
    Scene_description.Rect ((1, 1), 5, 4, None,
      { fill = Some Color.red; stroke = None });
    Scene_description.View3d (camera, view, None)] in
  let callbacks = Raster2_renderer.{ scene2; scene3 } in
  let renderer = ok_renderer (Raster2_renderer.create ~logical_width:16
      ~logical_height:16 ~drawable_width:16 ~drawable_height:16) in
  let session = ok_presenter (Presenter.create_session ~logical_width:16
      ~logical_height:16) in
  let draw frame_number =
    ignore frame_number;
    let frame = ok_renderer (Raster2_renderer.render renderer callbacks scene) in
    ok_presenter (present session frame);
    let actual = ok_presenter (Presenter.copy_session_rgba session) in
    if actual <> frame.rgba then failwith "SDL3 comparison pixel mismatch";
    actual
  in
  let expected = draw 1 in
  List.iter (fun frame -> if draw frame <> expected then
    failwith "SDL3 comparison frame drift") [2; 60; 600];
  ok_presenter (Presenter.resize_session session ~logical_width:9
      ~logical_height:7);
  ok_renderer (Raster2_renderer.resize renderer ~logical_width:9
      ~logical_height:7 ~drawable_width:9 ~drawable_height:7);
  let resized = ok_renderer (Raster2_renderer.render renderer callbacks scene) in
  ok_presenter (present session resized);
  if ok_presenter (Presenter.copy_session_rgba session) <> resized.rgba then
    failwith "SDL3 comparison resize mismatch";
  ok_renderer (Raster2_renderer.destroy renderer);
  ok_presenter (Presenter.destroy_session session)

let () =
  match Sys.getenv_opt "PRISMEL_RASTER2_SDL3_COMPARISON" with
  | Some "1" -> self_test ()
  | _ -> ()
