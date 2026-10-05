(* The kit's widgets (specification/pxui-kit/widgets.html) drawn by Pxui.Ui at the sheet's own
   coordinates as one PNG, without a window: compare it with widgets@2x.png (or @1x with
   WIDGETS_SCALE=1; the picture is 1440 x 1320 points either way).
   usage: widgets_shot OUTPUT.png   (WIDGETS_DO scripts the pointer first, one step a frame:
     move:X,Y  rest the pointer there     click:X,Y  press and release the left button
     hold:X,Y  press and keep the button down      tab / tabs:N  press Tab      key:NAME  press a key
     type:TEXT  typed text (no spaces; _ is a space)
     dbl:X,Y  double click      wait:N  N idle frames (a tooltip needs 24); WIDGETS_TIP=1 leaves the popups out)
   Each widget is built in a bare column box, not a panel, so that no widget's ground covers the next. *)
open Rays

let width = 1440 and height = 1320

(* 2 pixels a point, as a Retina window; WIDGETS_SCALE=1 for the sheets' @1x renders *)
let scale = Option.value ~default:2 (Option.bind (Sys.getenv_opt "WIDGETS_SCALE") int_of_string_opt)

let frame count mouse buttons events : Frame.t = {
  width; height; size = width, height;
  drawable_width = width * scale; drawable_height = height * scale;
  drawable_size = width * scale, height * scale; pixel_scale = float scale, float scale;
  time = float_of_int count /. 60.; dt = 1. /. 60.; fps = 60.; count;
  mouse; mouse_delta = 0., 0.; keys = [];
  mouse_buttons = buttons; events;
}

module Ui = Pxui.Ui

(* the widgets keep their values here, so that a click or a typed character shows *)
type state = { mutable choice : int; mutable caption : string; mutable count_text : string;
               mutable radius : float; mutable name : string }
let st = { choice = 0; caption = "Functional UI"; count_text = "12x"; radius = 48.; name = "scatter1" }

(* a column of widgets at the sheet's box: its rows start at [y] *)
let at ui ~x ~y ~w name f =
  let column = Ui.box ui ~w:(Ui.Px w) ~axis:Ui.Column ~at:(x, y) name in
  Ui.within ui column f

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
      180.5, 208., "Discard", (fun n -> ignore (Ui.button ui n));
      244., 208., "Reset", (fun n -> ignore (Ui.button ui ~bare:true n));
      290.5, 208., "<", (fun n -> ignore (Ui.button ui ~icon:true n));
      314.5, 208., "v", (fun n -> ignore (Ui.button ui ~icon:true n));
      339., 208., "+", (fun n -> ignore (Ui.button ui ~icon:true n));
      363.5, 208., "×", (fun n -> ignore (Ui.button ui ~icon:true n)) ];
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
    st.radius <- Ui.slider ui "radius" ~range:(0., 120.) st.radius;
    ignore (Ui.int_slider ui "steps" ~range:(0, 67) 8);
    Ui.label ui "";
    ignore (Ui.range_slider ui "band" ~range:(0., 1.) (0.2, 0.8)));
  at ui ~x:537. ~y:351. ~w:462. "num3" (fun () ->
    ignore (Ui.slider ui ~disabled:true "density" ~range:(0., 1.) 0.5));
  (* [07] choice, text *)
  at ui ~x:537. ~y:579. ~w:462. "txt" (fun () ->
    st.choice <- Ui.choice ui "normals" [ "Point"; "Vertex"; "Primitive" ] st.choice;
    st.name <- Ui.text_field ui "name" st.name;
    st.caption <- Ui.text_field ui "caption" st.caption;
    ignore (Ui.text_field ui ~placeholder:"all points" "group" "");
    st.count_text <- Ui.text_field ui ~invalid:"expected an integer" "count" st.count_text);
  (* [07] a vector and a colour, the kit's own functions, in rows of the control column *)
  at ui ~x:537. ~y:555. ~w:462. "vec" (fun () ->
    let row = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px 24.) "vec-row" in
    Ui.within ui row (fun () ->
      Ui.draw ui row (fun paint (x, y, _, _) ->
        Ui.Paint.text paint ~at:(x +. 12., Ui.text_top ui y 24.) ~color:(Pxui.Theme.ink_2 (Ui.theme ui)) "translate");
      ignore (Pxui_shell.Kit.vector ui row ~at:(132., 2.) ~w:318. (fun i ~x ~w ->
        ignore (Ui.value_field ui ~at:(x, 2.) ~w ~h:20. ~valid:(fun _ -> true)
          (Printf.sprintf "vec-%d" i) (List.nth [ "0"; "1.25"; "0" ] i)); []))));
  at ui ~x:537. ~y:723. ~w:462. "col" (fun () ->
    let row = Ui.box ui ~w:Ui.Grow ~h:(Ui.Px 24.) "col-row" in
    Ui.within ui row (fun () ->
      Ui.draw ui row (fun paint (x, y, _, _) ->
        Ui.Paint.text paint ~at:(x +. 12., Ui.text_top ui y 24.) ~color:(Pxui.Theme.ink_2 (Ui.theme ui)) "colour");
      ignore (Pxui_shell.Kit.colour ui ~key:"c" ~at:(132., 2.) ~w:318.
        ~swatch:(Color.rgb 0x28 0x5f 0x77) ~hex:"#285f77")));
  (* [08] messages *)
  at ui ~x:537. ~y:1023. ~w:462. "msg" (fun () ->
    Ui.message ui ~key:"info" "Select a node to edit its parameters.";
    Ui.message ui ~error:true ~key:"bad" "E_PORT_TYPE: scatter.count takes int, got vec3");
  (* [12] progress, flags *)
  let progress = Ui.box ui ~w:(Ui.Px 120.) ~h:(Ui.Px 8.) ~at:(1104.5, 756.5) "progress" in
  Ui.draw ui progress (fun paint (x, y, _, _) -> Ui.Paint.progress paint ~x ~y 0.37);
  let flags = Ui.box ui ~w:(Ui.Px 60.) ~h:(Ui.Px 14.) ~at:(1104.5, 790.) "flags" in
  Ui.draw ui flags (fun paint (x, y, _, _) ->
    Ui.Paint.flag paint ~at:(x +. 6., y +. 6.) true;
    Ui.Paint.flag paint ~at:(x +. 26., y +. 6.) ~round:true true;
    Ui.Paint.flag paint ~at:(x +. 46., y +. 6.) false);
  if Sys.getenv_opt "WIDGETS_TIP" = None then begin
  ignore (Ui.popup ui ~stroke:(Pxui.Theme.border (Ui.theme ui)) ~at:(1024., 399.) ~width:464. ~height:158. "picker" (fun () ->
    Ui.label ui "Add node";
    ignore (Ui.picker ui ~limit:4 ~off:(fun i -> i = 3)
      ~mark:(fun i -> Some (Ui.theme ui |> Pxui.Theme.ports |> fun p -> if i < 2 then p.geometry else p.float)) "Add" ~query:"sca"
      (fun _ -> [| "scatter", "sop / points"; "scale", "sop / transform"; "smooth_cap", "value / math";
                   "scene/geometry", "not in sop" |]));
    Ui.footer ui ~right:"4 of 212" [ "↑↓", "move"; "↵", "place" ]));
  ignore (Ui.context_menu ui ~at:(1024., 178.) ~width:225. ~keys:["V"; "B"; "⌘G"; ""; ""; ""; "⌫"]
    ~danger:[ 6 ]
    ~submenus:[ { Ui.row = 3; rows = [ "Point", true; "Chip", true; "Card", true; "Full", true ];
                  keys = [ "p"; ""; ""; "o" ]; current = Some 2 } ]
    "ctx" [ "View", true; "Bypass", true; "Fold into compound", true; "Level", true; "", true;
            "Set active camera", false; "Delete", true])
  end;
  Ui.tooltip ~shortcut:"B" ui ~key:"tip" ~text:"Bypass node";
  at ui ~x:644. ~y:790. ~w:368. "xy" (fun () ->
    ignore (Ui.xy ui "" ~x_range:(0., 1.) ~y_range:(0., 1.) (0.62, 0.34)))

let () =
  if Array.length Sys.argv < 2 then failwith "usage: widgets_shot OUTPUT.png";
  let canvas = Canvas.create_exn ~width:(width * scale) ~height:(height * scale) in
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
    | "type" -> step [ Event.TextInput (String.map (function '_' -> ' ' | c -> c) argument) ]
    | "key" -> step [ Event.KeyPressed (match argument with
        | "enter" -> Input.Enter | "esc" -> Input.Escape | "space" -> Input.Space
        | "backspace" -> Input.Backspace
        | name -> KeyChar name.[0]) ]
    | "" -> ()
    | other -> failwith ("widgets_shot: unknown step " ^ other))
    (String.split_on_char ' ' (Option.value ~default:"" (Sys.getenv_opt "WIDGETS_DO")));
  for _ = 1 to 6 do step [] done;
  Canvas.render ~density:scale canvas (Scene.clear (Color.rgb 0xf4 0xf5 0xf0) :: Ui.scene ui);
  (match Canvas.save_png canvas Sys.argv.(1) with Ok () -> () | Error message -> failwith message);
  Ui.destroy ui; Canvas.destroy canvas
