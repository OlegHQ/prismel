(* The host bars of the workspace: the top bar (title, Shell layouts, Undo, Redo, Copy Lisp)
   and the graph panel's toolbar (Add, Repeat, Iterate, λ, ◆, defn).  Buttons only report a
   click: [Core] maps it to the one command or edit it means. *)
module Ui = Pxui.Ui

type top_intent = Undo | Redo | Copy_lisp | Keys | Layout of string | Dismiss

type tool = Add | Repeat | Iterate | Fn | Macro | Defn

let height = 28

(* the four shell layouts of the study's "Shell layouts" dialog *)
let layouts = [ "default", "Default"; "code", "Graph + code"; "focus", "Focus";
                "floating", "Floating"; "restore", "Restore layout" ]

(* a bordered button; [true] on the frame a press and release land inside it *)
let button ui ~key ~at:(bx, by) ~w ?(h = 22.) ?(enabled = true) ?(active = false) ?hint label =
  let theme = Ui.theme ui in
  let box = Ui.box ui ~flags:Ui.(clickable + blocking) ~w:(Ui.Px w) ~h:(Ui.Px h) ~at:(bx, by) key in
  let signal = Ui.signal ui box in
  Ui.draw ui box (fun paint (x, y, w, h) ->
    let muted = Pxui.Theme.muted theme in
    Ui.Paint.rect paint ~x ~y ~w ~h
      ~fill:(if active then theme.foreground
             else if signal.hovered && enabled then Pxui.Theme.hover_fill theme else theme.control)
      ~stroke:(if enabled then Pxui.Theme.border theme else Pxui.Theme.faint_border theme) ~radius:2. ();
    let color = if active then theme.input else if enabled then theme.foreground else muted in
    Ui.Paint.text paint ~at:(x +. 10., y +. Float.floor ((h -. 11.) /. 2.)) ~size:11 ~color label;
    match hint with
    | None -> ()
    | Some hint ->
        let hx = x +. 10. +. Ui.Paint.text_width paint ~size:11 label +. 8. in
        let hw = Ui.Paint.text_width paint ~size:10 hint +. 8. in
        Ui.Paint.rect paint ~x:hx ~y:(y +. 4.) ~w:hw ~h:(h -. 8.) ~fill:theme.input
          ~stroke:(Pxui.Theme.faint_border theme) ~radius:2. ();
        Ui.Paint.text paint ~at:(hx +. 4., y +. Float.floor ((h -. 10.) /. 2.)) ~size:10 ~color:muted hint);
  signal.clicked && enabled

let top_labels = [ "Keys"; "Shell layouts"; "Undo"; "Redo"; "Copy Lisp" ]  (* left to right *)

(* the rectangle of a top bar button, from the right edge *)
let top_button_rect ~width label =
  let w l = 20. +. float (String.length l) *. 6.8 in
  let rec from_right x = function
    | [] -> (0., 0., 0., 0.)
    | l :: rest ->
        let at = x -. w l in
        if l = label then (at, 3., w l, 22.) else from_right (at -. 6.) rest in
  from_right (width -. 10.) (List.rev top_labels)

let top ui ~width ~title ~status ~can_undo ~can_redo =
  let theme = Ui.theme ui in
  let bar = Ui.box ui ~w:(Ui.Px width) ~h:(Ui.Px (float height)) ~at:(0., 0.) "workspace-top-bar" in
  Ui.draw ui bar (fun paint (x, y, w, h) ->
    Ui.Paint.fill paint ~x ~y ~w ~h theme.panel;
    Ui.Paint.line paint ~from_:(x, y +. h -. 0.5) ~to_:(x +. w, y +. h -. 0.5)
      (Pxui.Theme.faint_border theme);
    Ui.Paint.text paint ~at:(x +. 12., y +. 8.) ~size:11 ~color:theme.foreground "Prismel Flow";
    let bx = x +. 12. +. 13. *. 6.8 +. 14. in
    let label = title ^ "  v" in
    let bw = 20. +. float (String.length label) *. 6.8 in
    Ui.Paint.rect paint ~x:bx ~y:(y +. 3.) ~w:bw ~h:22. ~fill:theme.input
      ~stroke:(Pxui.Theme.border theme) ~radius:2. ();
    Ui.Paint.text paint ~at:(bx +. 10., y +. 9.) ~size:11 ~color:theme.foreground label;
    (* the checker's verdict on the document: Checked, or why the last edit was refused *)
    let ok, text = status in
    let sx = bx +. bw +. 16. in
    Ui.Paint.circle paint ~at:(sx, y +. 14.) ~radius:3.
      ~fill:(if ok then Prismel.Color.hex_exn "#3f8a55" else Pxui.Theme.invalid) ();
    Ui.Paint.text paint ~at:(sx +. 10., y +. 9.) ~size:11
      ~color:(if ok then Pxui.Theme.muted theme else Pxui.Theme.invalid)
      (if ok then text else text ^ "  ×"));
  let intents = ref [] in
  let emit i = intents := i :: !intents in
  (* a refusal is clicked away *)
  (match status with
   | false, text ->
       let sx = 12. +. 13. *. 6.8 +. 14. +. 20. +. float (String.length title + 3) *. 6.8 +. 16. in
       let w = 10. +. float (String.length text + 3) *. 6.8 in
       let box = Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px w) ~h:(Ui.Px 22.) ~at:(sx, 3.) "workspace-bar-dismiss" in
       if (Ui.signal ui box).clicked then emit Dismiss
   | true, _ -> ());
  List.iter (fun label ->
    let at, _, w, _ = top_button_rect ~width label in
    let key = "workspace-bar-" ^ label in
    match label with
    | "Copy Lisp" -> if button ui ~key ~at:(at, 3.) ~w label then emit Copy_lisp
    | "Keys" -> if button ui ~key ~at:(at, 3.) ~w label then emit Keys
    | "Redo" -> if button ui ~key ~at:(at, 3.) ~w ~enabled:can_redo label then emit Redo
    | "Undo" -> if button ui ~key ~at:(at, 3.) ~w ~enabled:can_undo label then emit Undo
    | _ ->
        let menu_key = key ^ "-menu" in
        let opener = Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px 0.) ~h:(Ui.Px 0.) ~at:(at, 3.) menu_key in
        let opened = Ui.state ui opener ~default:0 = 1 in
        let clicked = button ui ~key ~at:(at, 3.) ~w ~active:opened label in
        let opened = if clicked then not opened else opened in
        Ui.set_state ui opener (if opened then 1 else 0);
        if opened then
          (match Ui.context_menu ui ~at:(at, float height) (key ^ "-rows")
             (List.map (fun (_, name) -> name, true) layouts) with
           | `Open -> ()
           | `Dismiss -> Ui.set_state ui opener 0
           | `Pick i -> Ui.set_state ui opener 0; emit (Layout (fst (List.nth layouts i))))) top_labels;
  List.rev !intents

let tools = [ Add, "Add", "A"; Repeat, "Repeat", "R"; Iterate, "Iterate", "S-R";
              Fn, "\xce\xbb", "L"; Macro, "macro", "M"; Defn, "defn", "D" ]

(* The toolbar sits in the graph panel's header, after its title and subtitle; a tool that would
   run into the collapse button is left out. *)
(* where the toolbar starts: after a header title of this many characters *)
let tools_from title = float (30 + (7 * (String.length title + 2)))

let tool_rects ~header:(hx, hy, hw, hh) ~from =
  let hx = float hx and hy = float hy and hw = float hw and hh = float hh in
  let x = ref (hx +. from) in
  List.filter_map (fun (tool, label, hint) ->
    let w = 26. +. float (String.length label) *. 6.8 +. float (String.length hint) *. 6.2 in
    let at = !x in
    x := !x +. w +. 4.;
    if at +. w < hx +. hw -. hh -. 4. then Some (tool, label, hint, (at, hy +. 1., w, hh -. 2.)) else None) tools

let tool_rect ~header ~from tool =
  List.find_map (fun (t, _, _, r) -> if t = tool then Some r else None) (tool_rects ~header ~from)

let graph_tools ui ~header ~from ~enabled =
  List.fold_left (fun clicked (tool, label, hint, (x, y, w, h)) ->
    if button ui ~key:("workspace-tool-" ^ label) ~at:(x, y) ~w ~h ~enabled ~hint label
    then Some tool else clicked) None (tool_rects ~header ~from)

(* The editor graph of each layout: [graph] names the graph panel, [scene] the viewport's
   scene graph; every panel is named so the graph stays editable binding by binding. *)
let layout_text ~name ~graph ~scene layout =
  let network = match graph with Some g -> Printf.sprintf "(ui/graph %S)" g | None -> "(ui/graph)" in
  let body = match layout with
    | "code" ->
        "(let* [outline (ui/outline)\n           network " ^ network ^ "\n           preview (ui/viewport (ref " ^ scene ^ "))\n           code (ui/lisp)\n           right (ui/split-at \"vertical\" 0.45 preview code)\n           main (ui/split-at \"horizontal\" 0.58 network right)\n           panels (ui/split-at \"horizontal\" 0.13 outline main)\n           shell (ui/workspace panels)]\n      shell)"
    | "focus" ->
        "(let* [network " ^ network ^ "\n           preview (ui/viewport (ref " ^ scene ^ "))\n           panels (ui/split-at \"horizontal\" 0.68 network preview)\n           shell (ui/workspace panels)]\n      shell)"
    | "floating" ->
        "(let* [outline (ui/outline)\n           network " ^ network ^ "\n           preview (ui/viewport (ref " ^ scene ^ "))\n           inspector (ui/inspector)\n           code (ui/lisp)\n           base (ui/split-at \"horizontal\" 0.15 outline (ui/split-at \"horizontal\" 0.75 network inspector))\n           shell (ui/workspace (ui/split-at \"horizontal\" 0.5 base (ui/floating (ui/split-at \"vertical\" 0.6 preview code))))]\n      shell)"
    | _ ->
        "(let* [outline (ui/outline)\n           network " ^ network ^ "\n           preview (ui/viewport (ref " ^ scene ^ "))\n           inspector (ui/inspector)\n           code (ui/lisp)\n           lower (ui/split-at \"vertical\" 0.46 inspector code)\n           side (ui/split-at \"vertical\" 0.4 preview lower)\n           main (ui/split-at \"horizontal\" 0.66 network side)\n           panels (ui/split-at \"horizontal\" 0.13 outline main)\n           shell (ui/workspace panels)]\n      shell)" in
  Printf.sprintf "(graph %s :context editor\n  %s)" name body

(* A panel tree as an editor graph: leaves and splits are bindings, so every panel edit finds
   its binding; [ponytail:] names are kind_n, not the study's prose names. *)
let tree_text ~name ~scene tree =
  let used = Hashtbl.create 8 and bindings = ref [] and names = ref [] in
  let bind base form =
    let n = 1 + Option.value ~default:0 (Hashtbl.find_opt used base) in
    Hashtbl.replace used base n;
    let name = if n = 1 then base else Printf.sprintf "%s_%d" base n in
    bindings := (name, form) :: !bindings; name in
  let rec go path : Editor_core.Panels.t -> string = function
    | Leaf p ->
        let base, form = match p with
          | View _ -> "preview", Printf.sprintf "(ui/viewport (ref %s))" scene
          | Graph -> "network", "(ui/graph)" | List -> "list", "(ui/list)" | Lisp -> "code", "(ui/lisp)"
          | Inspector -> "inspector", "(ui/inspector)" | Outline -> "outline", "(ui/outline)"
          | Timeline -> "timeline", "(ui/timeline)" in
        let n = bind base form in
        names := (List.rev path, n) :: !names; n
    | Split { axis; ratio; a; b } ->
        let a = go (0 :: path) a in
        let b = go (1 :: path) b in
        bind "split" (Printf.sprintf "(ui/split-at %S %.2f %s %s)"
          (if axis = `H then "horizontal" else "vertical") ratio a b)
    | Tile cells -> bind "tile" ("(ui/tile " ^ String.concat " " (List.mapi (fun i c -> go (i :: path) c) cells) ^ ")")
    | Float t -> bind "floating" ("(ui/floating " ^ go (0 :: path) t ^ ")") in
  let root = go [] tree in
  Printf.sprintf "(graph %s :context editor\n  (let* [%s]\n    (ui/workspace %s)))" name
    (String.concat "\n         " (List.rev_map (fun (n, f) -> n ^ " " ^ f) !bindings)) root,
  (fun path -> List.assoc_opt path !names)
