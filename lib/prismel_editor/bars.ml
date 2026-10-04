(* The host bars of the workspace: the graph panel's toolbar (Add, Repeat, Iterate, λ, ◆, defn).  Buttons only report a
   click: [Core] maps it to the one command or edit it means. *)
module Ui = Pxui.Ui

type tool = Add | Repeat | Iterate | Fn | Macro | Defn

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
      ~stroke:(if enabled then Pxui.Theme.border theme else Pxui.Theme.faint_border theme) ();
    let color = if active then theme.input else if enabled then theme.foreground else muted in
    Ui.Paint.text paint ~at:(x +. 10., y +. Float.floor ((h -. 11.) /. 2.)) ~size:11 ~color label;
    match hint with
    | None -> ()
    | Some hint ->
        let hx = x +. 10. +. Ui.Paint.text_width paint ~size:11 label +. 8. in
        let hw = Ui.Paint.text_width paint ~size:10 hint +. 8. in
        Ui.Paint.rect paint ~x:hx ~y:(y +. 4.) ~w:hw ~h:(h -. 8.) ~fill:theme.input
          ~stroke:(Pxui.Theme.faint_border theme) ();
        Ui.Paint.text paint ~at:(hx +. 4., y +. Float.floor ((h -. 10.) /. 2.)) ~size:10 ~color:muted hint);
  signal.clicked && enabled

let tools = [ Add, "Add", "A"; Repeat, "Repeat", "R"; Iterate, "Iterate", "S-R";
              Fn, "\xce\xbb", "L"; Macro, "macro", "M"; Defn, "defn", "D" ]

(* The toolbar sits in the graph panel's header, after its title and subtitle; a tool that would
   run into the collapse button is left out. *)
(* where the toolbar starts: after a header title of this many characters *)
let tools_from title = float (42 + (7 * (String.length title + 2)))

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

(* A panel tree as an editor graph: leaves and splits are bindings, so every panel edit finds
   its binding; [ponytail:] names are kind_n, not the study's prose names. *)
let tree_text ~name ~scene tree =
  let used = Hashtbl.create 8 and bindings = ref [] and names = ref [] in
  let bind base form =
    let n = 1 + Option.value ~default:0 (Hashtbl.find_opt used base) in
    Hashtbl.replace used base n;
    let name = if n = 1 then base else Printf.sprintf "%s_%d" base n in
    bindings := (name, form) :: !bindings; name in
  let rec go path tree =
    let name = node path tree in
    names := (List.rev path, name) :: !names; name
  and node path : Editor_core.Panels.t -> string = function
    | Leaf p ->
        let base, form = match p with
          | View _ -> "preview", Printf.sprintf "(ui/viewport (ref %s))" scene
          | Graph -> "network", "(ui/graph)" | List -> "list", "(ui/list)" | Lisp -> "code", "(ui/lisp)"
          | Inspector -> "inspector", "(ui/inspector)" | Outline -> "outline", "(ui/outline)"
          | Timeline -> "timeline", "(ui/timeline)" in
        bind base form
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
