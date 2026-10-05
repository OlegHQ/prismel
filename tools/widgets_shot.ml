(* The kit's widgets (specification/pxui-kit/widgets.html) drawn by Pxui.Ui at the sheet's own
   coordinates as one 1440 x 1320 PNG, without a window: compare it with widgets@1x.png.
   usage: widgets_shot OUTPUT.png   (WIDGETS_DO scripts the pointer first, one step a frame:
     move:X,Y  rest the pointer there     click:X,Y  press and release the left button
     hold:X,Y  press and keep the button down      tab / tabs:N  press Tab      key:NAME  press a key
     dbl:X,Y  double click      wait:N  N idle frames (a tooltip needs 24); WIDGETS_TIP=1 leaves the popups out) *)
open Rays

let width = 1440 and height = 1320

let frame count mouse buttons events : Frame.t = {
  width; height; size = width, height;
  drawable_width = width; drawable_height = height;
  drawable_size = width, height; pixel_scale = 1., 1.;
  time = float_of_int count /. 60.; dt = 1. /. 60.; fps = 60.; count;
  mouse; mouse_delta = 0., 0.; keys = [];
  mouse_buttons = buttons; events;
}

module Ui = Pxui.Ui

(* a panel at the box of the sheet: its rows start at [y] *)
let at ui ~x ~y ~w name f = Ui.panel ui ~x ~y ~width:w name f

let sheet ui =
  (* [01] buttons: a button's box is 20 high at its row's y + 2 and starts 5 left of its text *)
  List.iteri (fun i (x, y, name, make) ->
    at ui ~x:(x -. 5.) ~y:(y -. 2.) ~w:300. (Printf.sprintf "b%d" i) (fun () -> make name))
    [ 48., 178., "Add", (fun n -> ignore (Ui.button ui ~key:"A" n));
      97., 178., "Repeat", (fun n -> ignore (Ui.button ui ~key:"R" n));
      165.5, 178., "Iterate", (fun n -> ignore (Ui.button ui ~key:"⇧R" n));
      246., 178., "fn", (fun n -> ignore (Ui.button ui ~key:"L" ~on:true n));
      288.5, 178., "defn", (fun n -> ignore (Ui.button ui ~key:"D" ~disabled:true n));
      48., 208., "Check and apply", (fun n -> ignore (Ui.button ui ~key:"⌘↵" ~primary:true n));
      180.5, 208., "Discard", (fun n -> ignore (Ui.button ui n)) ];
  (* [03] switches *)
  at ui ~x:49. ~y:415. ~w:462. "sw" (fun () ->
    ignore (Ui.toggle ui "Live update while dragging" true);
    ignore (Ui.toggle ui "Camera follows viewport" false);
    ignore (Ui.toggle ui ~disabled:true "Axis gizmo" false));
  (* [04] a section *)
  at ui ~x:49. ~y:783. ~w:462. "sec" (fun () ->
    ignore (Ui.accordion ui ~expanded:true "Shape" (fun () ->
      ignore (Ui.slider ui "rings" ~range:(0., 100.) 12.)));
    ignore (Ui.accordion ui "Transform" (fun () -> ())));
  (* [06] numbers *)
  at ui ~x:537. ~y:183. ~w:462. "num" (fun () ->
    ignore (Ui.slider ui "radius" ~range:(0., 120.) 48.);
    ignore (Ui.int_slider ui "steps" ~range:(0, 67) 8);
    Ui.label ui "";
    ignore (Ui.range_slider ui "band" ~range:(0., 1.) (0.2, 0.8)));
  at ui ~x:537. ~y:279. ~w:462. "num2" (fun () ->
    ignore (Ui.slider ui "radius " ~range:(0., 120.) 48.));
  at ui ~x:537. ~y:351. ~w:462. "num3" (fun () ->
    ignore (Ui.slider ui ~disabled:true "density" ~range:(0., 1.) 0.5));
  (* [07] choice, text *)
  at ui ~x:537. ~y:579. ~w:462. "txt" (fun () ->
    ignore (Ui.choice ui "normals" [ "Point"; "Vertex" ] 0);
    ignore (Ui.text_field ui "name" "scatter1");
    ignore (Ui.text_field ui "caption" "Functional UI");
    ignore (Ui.text_field ui "group" ""));
  if Sys.getenv_opt "WIDGETS_TIP" = None then begin
  ignore (Ui.popup ui ~stroke:(Pxui.Theme.border (Ui.theme ui)) ~at:(1024., 399.) ~width:464. ~height:158. "picker" (fun () ->
    Ui.label ui "Add node";
    Ui.picker ui ~limit:3 ~mark:(fun i -> Some (Ui.theme ui |> Pxui.Theme.ports |> fun p -> if i < 2 then p.geometry else p.float)) "Add" ~query:"sca"
      (fun _ -> [| "scatter", "sop / points"; "scale", "sop / transform"; "smooth_cap", "value / math" |])));
  ignore (Ui.context_menu ui ~at:(1024., 178.) ~width:225. ~keys:["V"; "B"; "\xe2\x8c\x98G"; ""; ""; ""] "ctx"
    ["View", true; "Bypass", true; "Fold into compound", true; "Level", true; "", true; "Set active camera", false; "Delete", true])
  end;
  Ui.tooltip ~shortcut:"B" ui ~key:"tip" ~text:"Bypass node";
  at ui ~x:644. ~y:790. ~w:368. "xy" (fun () ->
    ignore (Ui.xy ui "" ~x_range:(0., 1.) ~y_range:(0., 1.) (0.62, 0.34)))

let () =
  if Array.length Sys.argv < 2 then failwith "usage: widgets_shot OUTPUT.png";
  let canvas = Canvas.create_exn ~width ~height in
  let ui = Ui.create () in
  let mouse = ref (-100., -100.) and buttons = ref [] and count = ref 0 in
  let step events =
    Ui.frame ui (frame !count !mouse !buttons events) sheet; incr count in
  for _ = 1 to 4 do step [] done;
  let point text = Scanf.sscanf text "%f,%f" (fun x y -> x, y) in
  List.iter (fun word ->
    let name, argument = match String.index_opt word ':' with
      | Some i -> String.sub word 0 i, String.sub word (i + 1) (String.length word - i - 1)
      | None -> word, "" in
    match name with
    | "move" -> mouse := point argument; step [ Event.MouseMoved !mouse ]
    | "click" ->
        mouse := point argument; step [ Event.MouseMoved !mouse ];
        step [ Event.MousePressed (Input.LeftButton, !mouse); Event.MouseReleased (Input.LeftButton, !mouse) ]
    | "dbl" ->
        mouse := point argument; step [ Event.MouseMoved !mouse ];
        for _ = 1 to 2 do
          step [ Event.MousePressed (Input.LeftButton, !mouse); Event.MouseReleased (Input.LeftButton, !mouse) ]
        done
    | "hold" ->
        mouse := point argument; step [ Event.MouseMoved !mouse ];
        buttons := [ Input.LeftButton ];
        step [ Event.MousePressed (Input.LeftButton, !mouse) ]; step []
    | "wait" -> for _ = 1 to int_of_string argument do step [] done
    | "tabs" -> for _ = 1 to int_of_string argument do step [ Event.KeyPressed Input.Tab ] done
    | "tab" -> step [ Event.KeyPressed Input.Tab ]
    | "key" -> step [ Event.KeyPressed (match argument with
        | "enter" -> Input.Enter | "esc" -> Input.Escape | "space" -> Input.Space
        | name -> KeyChar name.[0]) ]
    | "" -> ()
    | other -> failwith ("widgets_shot: unknown step " ^ other))
    (String.split_on_char ' ' (Option.value ~default:"" (Sys.getenv_opt "WIDGETS_DO")));
  for _ = 1 to 6 do step [] done;
  Canvas.render canvas (Scene.clear (Color.rgb 0xf4 0xf5 0xf0) :: Ui.scene ui);
  (match Canvas.save_png canvas Sys.argv.(1) with Ok () -> () | Error message -> failwith message);
  Ui.destroy ui; Canvas.destroy canvas
