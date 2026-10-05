(* The host bars of the workspace: the graph panel's toolbar (Add, Repeat, Iterate, fn, macro, defn).  Buttons only report a
   click: [Core] maps it to the one command or edit it means. *)
module Ui = Pxui.Ui

type tool = Add | Repeat | Iterate | Fn | Macro | Defn

let tools = [ Add, "Add", "A"; Repeat, "Repeat", "R"; Iterate, "Iterate", "\xe2\x87\xa7R";
              Fn, "fn", "L"; Macro, "macro", "M"; Defn, "defn", "D" ]

(* The toolbar sits in the graph panel's header, after its title and subtitle; a tool that would
   run into the collapse button is left out. *)
(* where the toolbar starts: after the focus square, a header title of this many characters and
   the hairline that separates the tools; [ponytail:] widths are estimated at 7 points a
   character so the rectangles need no font, the same for the draw and for tests *)
let tools_from title = float (24 + (7 * (String.length title + 2)) + 16)

let tool_rects ~header:(hx, hy, hw, hh) ~from =
  let hx = float hx and hy = float hy and hw = float hw and hh = float hh in
  let x = ref (hx +. from) in
  List.filter_map (fun (tool, label, hint) ->
    let w = 18. +. float (String.length label) *. 7. +. float (String.length hint) *. 6. in
    let at = !x in
    x := !x +. w +. 2.;
    (* the panel's views (Graph, List, Text) and its chevron keep the header's last 156 points *)
    if at +. w < hx +. hw -. 156. then Some (tool, label, hint, (at, hy +. 2., w, hh -. 4.)) else None) tools

let tool_rect ~header ~from tool =
  List.find_map (fun (t, _, _, r) -> if t = tool then Some r else None) (tool_rects ~header ~from)

let graph_tools ui ~header ~from ~enabled =
  let _, hy, _, hh = header in
  (* the hairline between the breadcrumb and the tools *)
  (match tool_rects ~header ~from with
   | (_, _, _, (x, _, _, _)) :: _ ->
       Ui.draw ui (Ui.box ui ~w:(Ui.Px 1.) ~h:(Ui.Px 12.) ~at:(x -. 9., float hy +. float (hh - 12) /. 2.) "workspace-tool-rule")
         (fun paint (x, y, w, h) -> Ui.Paint.fill paint ~x ~y ~w ~h (Pxui.Theme.border (Ui.theme ui)))
   | [] -> ());
  List.fold_left (fun clicked (tool, label, hint, (x, y, w, h)) ->
    if Pxui_shell.Kit.button ui ~key:("workspace-tool-" ^ label) ~at:(x, y) ~w ~h ~enabled ~hint label
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
    | Split { axis; size; a; b } ->
        let a = go (0 :: path) a in
        let b = go (1 :: path) b in
        let axis = if axis = `H then "horizontal" else "vertical" in
        bind "split" (match size with
          | `Ratio ratio -> Printf.sprintf "(ui/split-at %S %.4g %s %s)" axis ratio a b
          | `First n -> Printf.sprintf "(ui/split %S %s %s :first_size %d)" axis a b n
          | `Second n -> Printf.sprintf "(ui/split %S %s %s :second_size %d)" axis a b n)
    | Tile cells -> bind "tile" ("(ui/tile " ^ String.concat " " (List.mapi (fun i c -> go (i :: path) c) cells) ^ ")")
    | Float t -> bind "floating" ("(ui/floating " ^ go (0 :: path) t ^ ")") in
  let root = go [] tree in
  Printf.sprintf "(graph %s :context editor\n  (let* [%s]\n    (ui/workspace %s)))" name
    (String.concat "\n         " (List.rev_map (fun (n, f) -> n ^ " " ^ f) !bindings)) root,
  (fun path -> List.assoc_opt path !names)
