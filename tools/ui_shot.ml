(* The editor's UI over a workspace file as one PNG, without a window: the picture the UI
   redesign is compared with.  usage: ui_shot FILE.rays OUTPUT.png [WIDTH HEIGHT [FRAMES]]
   (UI_SHOT_DO is a script of keys, clicks and drags that puts it in a state first). *)
let () = if Array.length Sys.argv < 3 then failwith "usage: ui_shot FILE.rays OUTPUT.png [WIDTH HEIGHT [FRAMES]]"
let arg index default = if Array.length Sys.argv > index then int_of_string Sys.argv.(index) else default
let width = arg 3 1440 and height = arg 4 900 and frames = arg 5 8
(* UI_SHOT_SCALE=2: the picture a Retina window shows, two pixels a point (glyphs at their 2x
   advances), for comparing with the sheets' @2x renders *)
let scale = Option.value ~default:1 (Option.bind (Sys.getenv_opt "UI_SHOT_SCALE") int_of_string_opt)

let frame count : Rays.Frame.t = {
  width; height; size = width, height;
  drawable_width = width * scale; drawable_height = height * scale;
  drawable_size = width * scale, height * scale; pixel_scale = float scale, float scale;
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
  let canvas = Rays.Canvas.create_exn ~width:(width * scale) ~height:(height * scale) in
  let editor = E.create ~workspace ~await:true ~presets:(Filename.temp_dir "ui-shot" "")
      ~prepare:(fun _ output -> Rdk_rays.Rays_mesh.to_mesh output.Procedural.Session.geometry
        |> Result.map_error Rdk.Error.to_string)
      ~scene3:(fun _ mesh -> Rays.Scene3.create [Rays.Scene3.mesh mesh]) () |> Result.get_ok in
  let editor = ref editor in
  for count = 0 to frames - 1 do editor := E.update !editor (frame count) done;
  (* UI_SHOT_DO is a script run after the settle frames, one step a frame, in order:
       key:NAME        a key press (a letter, a digit or a sign is itself; space tab enter esc)
       click:X,Y       move there, press and release the left button
       move:X,Y        rest the pointer there (it stays for the picture)
       pinch:X,Y,F     a trackpad pinch of factor F at that point (above 1 zooms in)
       hold:X0,Y0,X1,Y1  press at the first point and keep the button down at the second, so
                       the picture shows the drag in flight
     e.g. UI_SHOT_DO="key:space key:[ key:1 click:490,95" *)
  let key = function
    | "space" -> Rays.Input.Space | "tab" -> Tab | "enter" -> Enter | "esc" -> Escape
    | name -> KeyChar name.[0] in
  let count = ref frames and mouse = ref (-100., -100.) and buttons = ref [] in
  let step events =
    editor := E.update !editor { (frame !count) with mouse = !mouse; mouse_buttons = !buttons; events };
    incr count in
  let point text = Scanf.sscanf text "%f,%f" (fun x y -> x, y) in
  List.iter (fun word -> match String.index_opt word ':' with
    | None -> ()
    | Some colon ->
        let argument = String.sub word (colon + 1) (String.length word - colon - 1) in
        (match String.sub word 0 colon with
         | "key" -> step [ Rays.Event.KeyPressed (key argument) ]
         | "click" ->
             mouse := point argument;
             step [ Rays.Event.MouseMoved !mouse ];
             step [ Rays.Event.MousePressed (Rays.Input.LeftButton, !mouse); Rays.Event.MouseReleased (Rays.Input.LeftButton, !mouse) ]
         | "move" -> mouse := point argument; step [ Rays.Event.MouseMoved !mouse ]
         | "pinch" ->
             let (x, y), factor = Scanf.sscanf argument "%f,%f,%f" (fun x y f -> (x, y), f) in
             mouse := (x, y); step [ Rays.Event.MouseMoved !mouse ];
             step [ Rays.Event.MousePinched factor ]
         | "hold" ->
             let from, to_ = Scanf.sscanf argument "%f,%f,%f,%f" (fun a b c d -> (a, b), (c, d)) in
             mouse := from; step [ Rays.Event.MouseMoved from ];
             buttons := [ Rays.Input.LeftButton ];
             step [ Rays.Event.MousePressed (Rays.Input.LeftButton, from) ];
             mouse := to_;
             for _ = 1 to 4 do step [ Rays.Event.MouseMoved to_ ] done
         | other -> failwith ("ui_shot: unknown step " ^ other)))
    (String.split_on_char ' ' (Option.value ~default:"" (Sys.getenv_opt "UI_SHOT_DO")));
  (* let hover delays and cooks settle; a held button stays down *)
  for _ = 1 to 30 do step [] done;
  let scene = E.scene !editor { (frame !count) with mouse = !mouse; mouse_buttons = !buttons } in
  Rays.Canvas.render ~density:scale canvas scene;
  (match Rays.Canvas.save_png canvas Sys.argv.(2) with Ok () -> () | Error message -> failwith message);
  E.close !editor; Rays.Canvas.destroy canvas
