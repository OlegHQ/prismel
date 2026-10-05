(* The editor's UI over a workspace file as one PNG, without a window: the picture the UI
   redesign is compared with.  usage: ui_shot FILE.rays OUTPUT.png [WIDTH HEIGHT [FRAMES]] *)
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
  Rays.Canvas.render canvas (E.scene !editor (frame frames));
  (match Rays.Canvas.save_png canvas Sys.argv.(2) with Ok () -> () | Error message -> failwith message);
  E.close !editor; Rays.Canvas.destroy canvas
