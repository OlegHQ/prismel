open Prismel
open Procedural

type model = {
  environment : Mesh.t Sketch_ui.Environment3.t;
  ready_frames : int;
  output : string;
}

let point_mode = match Sys.getenv_opt "PRISMEL_WORKSPACE_POINT_MODE" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false

let graph () =
  if point_mode then Sop.points ~label:"point preview" [|
      -1.2, -0.6, 0.; -0.6, 0.5, 0.; 0., 0., 0.;
      0.6, -0.5, 0.; 1.2, 0.6, 0.
    |]
  else
    let source = Sop.box ~label:"preview source"
        ~size:(Vec3.create 2.4 2.4 2.4) () in
    let moved = Sop.transform ~label:"preview transform"
        (Mat4.rotation_y 0.48) source in
    Sop.merge ~label:"preview output" [source; moved]

let material = Material.create ~diffuse:(Color.hex_exn "#f2b36d")
    ~ambient:(Color.hex_exn "#422006") ~specular:Color.white ~shininess:32. ()

let scene3 _node mesh =
  let drawing = match Mesh.mode mesh with
    | Mesh.Points -> Scene3.with_raster
        (Scene3.raster_state ~point_size:11. ()) [
          Scene3.mesh ~material:(Material.unlit (Color.hex_exn "#fbbf74")) mesh
        ]
    | Lines | Line_strip | Line_loop | Triangles | Triangle_strip
    | Triangle_fan -> Scene3.mesh ~material mesh in
  Scene3.create ~lights:[
    Light.directional ~direction:(Vec3.create (-1.) (-1.) (-2.)) ()
  ] [drawing]

let orange color = color.Color.r > 115 && color.g > 55 && color.b < 190

let verify_viewport frame panes capture =
  let scale_x, scale_y = frame.Frame.pixel_scale in
  let vx, vy, vw, vh = panes.Sketch_ui.Workspace.view in
  let left = int_of_float (float_of_int vx *. scale_x)
  and top = int_of_float (float_of_int vy *. scale_y)
  and right = int_of_float (float_of_int (vx + vw) *. scale_x)
  and bottom = int_of_float (float_of_int (vy + vh) *. scale_y) in
  let min_x = ref max_int and max_x = ref min_int
  and min_y = ref max_int and max_y = ref min_int and count = ref 0 in
  for y = max 0 top to min (Canvas.height capture - 1) (bottom - 1) do
    for x = max 0 left to min (Canvas.width capture - 1) (right - 1) do
      match Canvas.pixel capture ~x ~y with
      | Some color when orange color ->
          incr count;
          min_x := min !min_x x; max_x := max !max_x x;
          min_y := min !min_y y; max_y := max !max_y y
      | Some _ | None -> ()
    done
  done;
  if !count < 100 then failwith "workspace snapshot did not render the 3D mesh";
  let center_x = (!min_x + !max_x) / 2
  and expected_x = (left + right) / 2
  and tolerance = max 12 ((right - left) / 6) in
  if abs (center_x - expected_x) > tolerance then
    failwith (Printf.sprintf
      "native 3D viewport is not centered (%d versus %d, scale %.2f)"
      center_x expected_x scale_x);
  if !min_x < left || !max_x >= right || !min_y < top || !max_y >= bottom then
    failwith "native 3D geometry escaped its logical view column"

let init frame =
  let output = if Array.length Sys.argv > 1 then Sys.argv.(1)
    else Filename.concat (Filename.get_temp_dir_name ())
        "prismel-workspace-snapshot.png" in
  let environment = Sketch_ui.Environment3.create ~graph:(graph ())
      ~headless_frames:20
      ~camera:(Easy_camera.create ~distance:6.8 ~azimuth:0.72 ~elevation:0.42 ())
      ~prepare:(fun output -> Bridge.to_mesh output.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3
      ~overlay:(fun _ _ local_frame -> Scene.[
        text ~at:(14, 12) "Viewport-local overlay";
        text ~at:(14, local_frame.Frame.height - 28) "Overlay bottom";
      ]) () |> Result.get_ok in
  ignore frame;
  { environment; ready_frames = 0; output }

let update model frame =
  let frame = match model.ready_frames with
    | 1 | 2 ->
        let panes = Sketch_ui.Environment3.panes model.environment frame in
        let x, y, _, _ = panes.inspector in
        let point = x + 32, y + 68 in
        let event = if model.ready_frames = 1
          then Event.MousePressed (Input.LeftButton, point)
          else Event.MouseReleased (Input.LeftButton, point) in
        { frame with Frame.mouse = point; events = [event] }
    | 3 -> { frame with Frame.mouse = 10, 100;
        events = [Event.MouseMoved (10, 100)] }
    | _ -> frame in
  let environment = Sketch_ui.Environment3.update model.environment frame in
  let ready_frames = if Sketch_ui.Environment3.prepared environment = None
    then 0 else model.ready_frames + 1 in
  (* Native framebuffer capture observes the previously presented frame. Give
     the cross-frame accordion release one additional presentation before
     reading pixels so native and headless snapshots show the same state. *)
  if ready_frames = 5 then begin
    let capture = Canvas.capture () |> Result.get_ok in
    let panes = Sketch_ui.Environment3.panes environment frame in
    verify_viewport frame panes capture;
    Canvas.save_png capture model.output |> Result.get_ok;
    Canvas.destroy capture;
    Sketch.quit ()
  end;
  { model with environment; ready_frames }

let view model frame = Sketch_ui.Environment3.scene model.environment frame
let stop model = Sketch_ui.Environment3.close model.environment

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 1200; height = 760;
      title = "Prismel workspace snapshot"; domains = Some 1 }
    ~init ~update ~view ~on_stop:stop ())
