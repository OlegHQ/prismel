(* The editor's UI over a workspace file as one PNG, without a window: the picture the UI
   redesign is compared with.  usage: ui_shot FILE.rays OUTPUT.png [WIDTH HEIGHT [FRAMES]]
   (UI_SHOT_CLICK, UI_SHOT_KEYS, UI_SHOT_MOUSE and UI_SHOT_DRAG put it in a state first). *)
let () = if Array.length Sys.argv < 3 then failwith "usage: ui_shot FILE.rays OUTPUT.png [WIDTH HEIGHT [FRAMES]]"
let arg index default = if Array.length Sys.argv > index then int_of_string Sys.argv.(index) else default
let width = arg 3 1440 and height = arg 4 900 and frames = arg 5 8

let frame count : Rays.Frame.t = {
  width; height; size = width, height;
  drawable_width = width; drawable_height = height;
  drawable_size = width, height; pixel_scale = 1., 1.;
  time = float_of_int count /. 60.; dt = 1. /. 60.; fps = 60.; count;
  mouse = -100., -100.; mouse_delta = 0., 0.; keys = [];
  mouse_buttons = []; events = [];
}

let () =
  let module E = Rays_editor.Editor3 in
  let text = In_channel.with_open_bin Sys.argv.(1) In_channel.input_all in
  let workspace = match Rays_editor.Workspace.load text with
    | Ok workspace -> workspace
    | Error diagnostics -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string diagnostics)) in
  let canvas = Rays.Canvas.create_exn ~width:(width) ~height:(height) in
  let editor = E.create ~workspace ~await:true ~presets:(Filename.temp_dir "ui-shot" "")
      ~prepare:(fun _ output -> Rdk_rays.Rays_mesh.to_mesh output.Procedural.Session.geometry
        |> Result.map_error Rdk.Error.to_string)
      ~scene3:(fun _ mesh -> Rays.Scene3.create [Rays.Scene3.mesh mesh]) () |> Result.get_ok in
  let editor = ref editor in
  for count = 0 to frames - 1 do editor := E.update !editor (frame count) done;
  (* UI_SHOT_CLICK="x,y" presses and releases the left button after the settle frames, then
     UI_SHOT_KEYS="space [ 1" presses one key a frame (a letter, a digit or a sign is itself;
     space, tab, enter, esc by name) and UI_SHOT_MOUSE="x,y" rests the pointer there *)
  let key = function
    | "space" -> Rays.Input.Space | "tab" -> Tab | "enter" -> Enter | "esc" -> Escape
    | name -> KeyChar name.[0] in
  let count = ref frames in
  let step ?(mouse = (-100., -100.)) events =
    editor := E.update !editor { (frame !count) with mouse; events }; incr count in
  let point name = Option.map (fun text -> Scanf.sscanf text "%f,%f" (fun x y -> x, y)) (Sys.getenv_opt name) in
  Option.iter (fun at ->
    step ~mouse:at [ Rays.Event.MouseMoved at ];
    step ~mouse:at [ Rays.Event.MousePressed (Rays.Input.LeftButton, at); Rays.Event.MouseReleased (Rays.Input.LeftButton, at) ];
    step ~mouse:at []) (point "UI_SHOT_CLICK");
  List.iter (fun name -> if name <> "" then step [ Rays.Event.KeyPressed (key name) ])
    (String.split_on_char ' ' (Option.value ~default:"" (Sys.getenv_opt "UI_SHOT_KEYS")));
  let mouse = point "UI_SHOT_MOUSE" in
  for _ = 1 to 30 do step ?mouse (match mouse with Some at -> [ Rays.Event.MouseMoved at ] | None -> []) done;
  (* UI_SHOT_DRAG="x0,y0,x1,y1": press at the first point and hold the button at the second, so
     the picture shows the drag in flight (a panel over its dock targets) *)
  let held = Option.map (fun text -> Scanf.sscanf text "%f,%f,%f,%f" (fun a b c d -> (a, b), (c, d)))
      (Sys.getenv_opt "UI_SHOT_DRAG") in
  let hold at events =
    editor := E.update !editor { (frame !count) with mouse = at; mouse_buttons = [ Rays.Input.LeftButton ]; events };
    incr count in
  Option.iter (fun (from, to_) ->
    step ~mouse:from [ Rays.Event.MouseMoved from ];
    hold from [ Rays.Event.MousePressed (Rays.Input.LeftButton, from) ];
    for _ = 1 to 4 do hold to_ [ Rays.Event.MouseMoved to_ ] done) held;
  let mouse = match held with Some (_, to_) -> Some to_ | None -> mouse in
  Rays.Canvas.render canvas (E.scene !editor { (frame !count) with mouse = Option.value mouse ~default:(-100., -100.) });
  (match Rays.Canvas.save_png canvas Sys.argv.(2) with Ok () -> () | Error message -> failwith message);
  E.close !editor; Rays.Canvas.destroy canvas
