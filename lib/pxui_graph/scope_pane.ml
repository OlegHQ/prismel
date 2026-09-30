(* The graph pane of a workspace document (plan W4): draws one
   [Flow_sop.Projection.scope] with its zones, rails, iteration selectors,
   chips and output rows on the shared PXUI handle, and returns typed
   requests.  It never edits: a gesture is a [Flow_edit.op] the host reduces.
   Every interactive element is a [Ui.box]; a tile's row under the pointer is
   found from the pointer and the tile's rectangle, not from a second hit
   tree. *)
open Prismel
module P = Flow_sop.Projection
module E = Flow_sop.Flow_edit
module S = Flow.Syntax
module Ty = Flow.Ty
module Ui = Pxui.Ui

type path = P.path
module Path_set = Set.Make (struct type t = path let compare = compare end)

type change =
  | Syntax_edit of E.op
  | Probe_set of { zone : path; index : int }
  | Zone_collapsed of { zone : path; collapsed : bool }
  | Selected of path list
  | Moved of (path * float * float) list
  | Macro_requested of path list  (** the host opens the make-macro dialog over these nodes *)
  | Frames_set of { scope : path; frames : (string * (float * float) * (float * float)) list }
      (** the frames of one scope after a gesture (create, resize, retitle, delete) *)
  | Display_set of path  (** show this geometry node in the viewport (the shown one: its result) *)
  | Notice of string

type direction = Left | Down | Up | Right
type command =
  | Delete | Fold_into | Unfold | Hoist | Bypass | Wrap_repeat | Wrap_iterate | Make_fn | Make_macro
  | Collapse | Probe_step of int | Frame_all | Walk of direction
  | Edit_name  (** rename the selected node, or edit the default of a selected graph input *)
  | Item_up | Item_down  (** move the hovered list item *)
  | Make_frame  (** a titled frame around the selected nodes *)
  | Duplicate | Display
  | Frame_selection  (** [f]: pan and zoom to the selected nodes (all, with none selected) *)

type stats = {
  nodes : int; zones : int; rows : int;
  drawn_items : int; drawn_zones : int; drawn_rows : int;
}

(* ------------------------------------------------------------ geometry *)

type src = { pos : float * float; ty : Ty.t option }
type wire = { a : float * float; b : float * float; ty : Ty.t option }

type geo = {
  items : (P.placed * float * float) array;  (* absolute top-left, graph units *)
  wires : wire array;
  rel : (path, float * float) Hashtbl.t;  (* position inside the scope, for [at] *)
  pos : (path, float * float * float * float) Hashtbl.t;
  origins : (path * (float * float)) list;  (* where each scope's own coordinates start *)
}

let empty_geo = { items = [||]; wires = [||]; rel = Hashtbl.create 1; pos = Hashtbl.create 1; origins = [] }
let pad = 14.
let root_name s = match String.index_opt s '.' with Some i -> String.sub s 0 i | None -> s

let rail_y (n : P.node) ~collapsed ay =
  if collapsed then ay +. P.head_height else ay +. P.rail_top n
let rows_top (n : P.node) ay =
  ay +. P.head_height +. (if n.note <> None then P.row_height else 0.)

(* [shift] moves a placed item by its path (a drag in progress); a zone's
   children follow through the origin they are laid out from. *)
let compute (scope : P.scope) (layout : P.layout) ~shift =
  let items = ref [] and pos = Hashtbl.create 64 and rel = Hashtbl.create 64 in
  let origins = ref [ (scope.path, (0., 0.)) ] in
  let rec walk ox oy (l : P.layout) =
    List.iter (fun (p : P.placed) ->
      let dx, dy = shift p.path in
      let ax = ox +. p.x +. dx and ay = oy +. p.y +. dy in
      items := (p, ax, ay) :: !items;
      Hashtbl.replace pos p.path (ax, ay, p.w, p.h);
      Hashtbl.replace rel p.path (p.x, p.y);
      match p.inner, p.item with
      | Some inner, P.Item n ->
          origins := (n.path, (ax +. P.rail_width +. pad, ay +. P.rail_top n)) :: !origins;
          walk (ax +. P.rail_width +. pad) (ay +. P.rail_top n) inner
      | _ -> ()) l.placed in
  walk 0. 0. layout;
  let wires = ref [] in
  let wire (s : src option) b = match s with
    | Some s -> wires := { a = s.pos; b; ty = s.ty } :: !wires
    | None -> () in
  let resolve chain name =
    List.find_map (fun tbl -> match Hashtbl.find_opt tbl name with
      | Some s -> Some s | None -> Hashtbl.find_opt tbl (root_name name)) chain in
  let names_of (e : S.t option) = match e with Some e -> E.free_names e | None -> [] in
  let declared (s : P.scope) =
    let tbl = Hashtbl.create 16 in
    List.iter (fun (i : P.input) -> match Hashtbl.find_opt pos i.path with
      | Some (ax, ay, w, _) -> Hashtbl.replace tbl i.name { pos = (ax +. w, ay +. 12.); ty = Some i.ty }
      | None -> ()) s.inputs;
    List.iter (fun (n : P.node) -> match Hashtbl.find_opt pos n.path with
      | None -> ()
      | Some (ax, ay, w, _) ->
          let out j = (ax +. w, rows_top n ay +. (float (List.length n.rows + j) +. 0.5) *. P.row_height) in
          (match n.binds with
           | [ b ] when b = n.name ->
               Hashtbl.replace tbl b { pos = (ax +. w, ay +. 12.); ty = Some n.ty };
               List.iteri (fun j (f, ty) ->
                 Hashtbl.replace tbl (b ^ "." ^ f) { pos = out j; ty = Some ty }) n.outputs
           | _ -> List.iteri (fun j (f, ty) ->
               Hashtbl.replace tbl f { pos = out j; ty = Some ty }) n.outputs)) s.nodes;
    tbl in
  (* the second pass reads the placed items, which know their collapsed flag *)
  let placed_of = Hashtbl.create 64 in
  Array.iter (fun ((p : P.placed), _, _) -> Hashtbl.replace placed_of p.path p) (Array.of_list !items);
  let rec scope_wires chain (s : P.scope) =
    let chain = declared s :: chain in
    List.iter (fun (n : P.node) -> match Hashtbl.find_opt pos n.path, Hashtbl.find_opt placed_of n.path with
      | Some (ax, ay, w, _), Some (p : P.placed) ->
          (match n.zone with
           | None ->
               List.iteri (fun i (r : P.row) ->
                 let target = (ax, rows_top n ay +. (float i +. 0.5) *. P.row_height) in
                 List.iter (fun name -> wire (resolve chain name) target) (names_of r.expr)) n.rows
           | Some z ->
               let collapsed = p.collapsed in
               List.iteri (fun i (r : P.rail_row) ->
                 let target = (ax, rail_y n ~collapsed ay +. (float i +. 0.5) *. P.row_height) in
                 let names = if r.role = P.Capture then [ r.name ] else names_of r.expr in
                 List.iter (fun name -> wire (resolve chain name) target) names) z.rail;
               if not collapsed then begin
                 let rail = Hashtbl.create 8 in
                 List.iteri (fun i (r : P.rail_row) ->
                   let s = { pos = (ax +. P.rail_width, ay +. P.rail_top n +. (float i +. 0.5) *. P.row_height);
                             ty = r.ty } in
                   List.iter (fun name -> Hashtbl.replace rail name s) r.names) z.rail;
                 let inner = rail :: chain in
                 scope_wires inner z.scope;
                 let inner_chain = declared z.scope :: inner in
                 let source = match z.scope.result with
                   | P.Link l -> resolve inner_chain l
                   | P.Node _ -> resolve inner_chain "@result"
                   | P.Literal _ -> None in
                 let target = (ax +. w -. P.yield_width, ay +. P.rail_top n +. 12.) in
                 wire source target
               end)
      | _ -> ()) s.nodes in
  scope_wires [] scope;
  (match scope.inputs with
   | [] -> ()
   | _ ->
       let chain = [ declared scope ] in
       (match Hashtbl.find_opt pos (scope.path @ [ "@return" ]) with
        | Some (ax, ay, _, _) ->
            let source = match scope.result with
              | P.Link l -> resolve chain l
              | P.Node _ -> resolve chain "@result"
              | P.Literal _ -> None in
            let target = (ax, ay +. 36.) in
            wire source target
        | None -> ()));
  { items = Array.of_list (List.rev !items); wires = Array.of_list (List.rev !wires); rel; pos; origins = !origins }

(* ---------------------------------------------------------------- state *)

type wiring = { src : string; ty : Ty.t option; iter : bool; from : float * float }
type drag =
  | Moving of { paths : path list; dx : float; dy : float; moved : bool }
  | Wiring of wiring
  | Marquee of { base : Path_set.t }  (* from the canvas press point to the pointer, screen space *)
  | Sizing of { scope : path; index : int; dw : float; dh : float }  (* a frame's corner *)
  | Carrying of { scope : path; index : int; paths : path list; dx : float; dy : float }
      (* a frame by its title, with the nodes inside it *)

(* the text field open over the pane: a node's name, a graph input's default, a frame's title *)
type editing = Name of path | Default of path | Title of path * int

type fr = string * (float * float) * (float * float)

type t = {
  x : int; y : int; width : int; height : int;
  theme : Pxui.theme; visible : bool; guide : bool;
  key : string;
  scope : P.scope option;
  at : path -> (float * float) option;
  collapsed : path -> bool;
  lens : (path * int) list;  (* macro calls whose expansion panel is open, and its step *)
  probe : path -> int;
  records : Flow_sop.Probe.t option;
  chains : (path, path list) Hashtbl.t;  (* the iterating zones around each node *)
  counts : (path, int) Hashtbl.t;  (* iterations each zone ran, under the probes *)
  frames : path -> (string * (float * float) * (float * float)) list;
  display : path option;  (* the node the viewport shows instead of the graph's result *)
  framed : bool;
  layout : P.layout;
  geo : geo;
  pan_x : float; pan_y : float; zoom : float;
  selected : Path_set.t;
  hovered_row : (path * E.arg_key) option;
  drag : drag option;
  editing : editing option;
  context : ((float * float) * path) option;
  stats : stats;
}

let no_stats = { nodes = 0; zones = 0; rows = 0; drawn_items = 0; drawn_zones = 0; drawn_rows = 0 }
let create ?(x = 0) ?(y = 0) ?(width = 640) ?(height = 360) ?(theme = Pxui.default_theme) () = {
  x; y; width; height; theme; visible = true; guide = false; key = ""; scope = None;
  at = (fun _ -> None); collapsed = (fun _ -> false); lens = []; probe = (fun _ -> 0); records = None;
  chains = Hashtbl.create 1; counts = Hashtbl.create 1;
  frames = (fun _ -> []); display = None; framed = true;
  layout = { P.placed = []; w = 0.; h = 0. }; geo = empty_geo; pan_x = 12.; pan_y = 12.; zoom = 1.;
  selected = Path_set.empty; hovered_row = None; drag = None; editing = None; context = None; stats = no_stats }

let with_bounds ~x ~y ~width ~height t =
  if t.x = x && t.y = y && t.width = width && t.height = height then t
  else { t with x; y; width; height }
let with_visible visible t = if t.visible = visible then t else { t with visible }
let with_guide guide t = if t.guide = guide then t else { t with guide }
let selected t = Path_set.elements t.selected
let editing t = t.editing <> None
let select paths t = { t with selected = Path_set.of_list paths }
let clear_selection t = if Path_set.is_empty t.selected then t else { t with selected = Path_set.empty }
let stats t = t.stats
let zoom t = t.zoom

let count_scope (s : P.scope) =
  let rec go (s : P.scope) = List.fold_left (fun (n, z, r) (node : P.node) ->
    let n', z', r' = match node.zone with Some zn -> go zn.scope | None -> 0, 0, 0 in
    n + 1 + n', z + (if node.zone <> None then 1 else 0) + z', r + List.length node.rows + r')
    (0, 0, 0) s.nodes in
  go s

let frame_all t =
  if t.layout.placed = [] then t else
  let w = Float.max 1. t.layout.w and h = Float.max 1. t.layout.h in
  let zoom = Float.max 0.25 (Float.min 1. (Float.min (float t.width /. w) (float t.height /. h))) in
  { t with zoom; pan_x = (float t.width -. w *. zoom) /. 2.; pan_y = Float.max 8. ((float t.height -. h *. zoom) /. 2.) }

let count_of t path = Option.value ~default:0 (Hashtbl.find_opt t.counts path)

(* the iteration counts follow the scope, the probes and what was recorded *)
let refresh t = match t.scope, t.records with
  | Some scope, Some records ->
      let counts = Hashtbl.create 16 in
      List.iter (fun (p, c) -> Hashtbl.replace counts p c) (Flow_sop.Probe.counts records scope ~probe:t.probe);
      { t with counts }
  | _ -> { t with counts = Hashtbl.create 1 }

let no_shift _ = 0., 0.
let lens_of t path = List.assoc_opt path t.lens
let macro_step = lens_of

let with_scope ?(at = fun _ -> None) ?(collapsed = fun _ -> false) ?(probe = fun _ -> 0)
    ?(frames = fun _ -> []) ?display ~key scope t =
  let layout = P.layout ~at ~collapsed ~lens:(lens_of t) scope in
  let n, z, r = count_scope scope in
  let t = { t with scope = Some scope; at; collapsed; probe; frames; display; layout;
    chains = Flow_sop.Probe.chains scope;
    geo = compute scope layout ~shift:no_shift;
    stats = { t.stats with nodes = n; zones = z; rows = r } } in
  (* an edit that removed or moved a node drops it from the selection *)
  let t = { (refresh t) with selected = Path_set.filter (Hashtbl.mem t.geo.pos) t.selected } in
  let t = match t.editing with
    | Some (Name p | Default p) when not (Hashtbl.mem t.geo.pos p) -> { t with editing = None }
    | _ -> t in
  if key <> t.key then { t with key; framed = false; selected = Path_set.empty; drag = None; editing = None } else t

(* the panel of a macro call opened or stepped: its card changes size *)
let relayout t = match t.scope with
  | None -> t
  | Some scope ->
      let layout = P.layout ~at:t.at ~collapsed:t.collapsed ~lens:(lens_of t) scope in
      { t with layout; geo = compute scope layout ~shift:no_shift }

let with_records records t =
  match t.records with
  | Some previous when Flow_sop.Probe.same_eval previous records -> { t with records = Some records }
  | _ -> refresh { t with records = Some records }

(* ------------------------------------------------------------- lookups *)

let node_of t path = Option.bind t.scope (fun s -> P.find s path)
let selected_nodes t = List.filter_map (fun p -> node_of t p) (selected t)

let parents_removed paths =
  let prefix p q = List.length p < List.length q
    && List.for_all2 ( = ) p (List.filteri (fun i _ -> i < List.length p) q) in
  List.filter (fun q -> not (List.exists (fun p -> prefix p q) paths)) paths

let first_inline (n : P.node) =
  List.find_opt (fun (r : P.row) -> match r.chip with P.Inline _ -> true | _ -> false) n.rows

let inline_rail (n : P.node) = match n.zone with
  | None -> None
  | Some z -> List.find_opt (fun (r : P.rail_row) -> match r.expr with
      | Some { S.node = S.List _; _ } -> r.key <> None | _ -> false) z.rail

let fallback (r : P.row) = Option.bind r.ty (fun ty -> E.default_for ty r.label)

let wired (r : P.row) = match r.expr with
  | Some e -> E.free_names e <> [] | None -> false

(* ---------------------------------------------------------------- frames *)

let scope_of_path path = List.rev (List.tl (List.rev path))

(* a frame's size while its corner is dragged *)
let frame_list t scope : fr list = match t.drag with
  | Some (Sizing s) when s.scope = scope ->
      List.mapi (fun i ((title, at, (w, h)) : fr) ->
        if i = s.index then title, at, (Float.max 48. (w +. s.dw), Float.max 32. (h +. s.dh))
        else title, at, (w, h)) (t.frames scope)
  | Some (Carrying c) when c.scope = scope ->
      List.mapi (fun i ((title, (x, y), size) : fr) ->
        if i = c.index then title, (x +. c.dx, y +. c.dy), size else title, (x, y), size) (t.frames scope)
  | _ -> t.frames scope

(* a frame around the selected nodes of one scope, in that scope's coordinates *)
let new_frame t =
  match List.filter (fun p -> Hashtbl.mem t.geo.pos p) (selected t) with
  | [] -> None
  | first :: _ as paths ->
      let scope = scope_of_path first in
      let boxes = List.filter_map (fun p ->
        if scope_of_path p = scope then Hashtbl.find_opt t.geo.pos p else None) paths in
      let ox, oy = Option.value ~default:(0., 0.) (List.assoc_opt scope t.geo.origins) in
      let x0 = List.fold_left (fun a (x, _, _, _) -> Float.min a x) infinity boxes
      and y0 = List.fold_left (fun a (_, y, _, _) -> Float.min a y) infinity boxes
      and x1 = List.fold_left (fun a (x, _, w, _) -> Float.max a (x +. w)) neg_infinity boxes
      and y1 = List.fold_left (fun a (_, y, _, h) -> Float.max a (y +. h)) neg_infinity boxes in
      Some (scope, ("frame", (x0 -. 12. -. ox, y0 -. 24. -. oy), (x1 -. x0 +. 24., y1 -. y0 +. 36.)))

let input_of t path = match t.scope with
  | Some s -> List.find_opt (fun (i : P.input) -> i.path = path) s.inputs
  | None -> None

(* ------------------------------------------------------------- commands *)

let action_changes t command =
  let nodes = selected_nodes t in
  let paths = List.map (fun (n : P.node) -> n.path) (List.filter (fun (n : P.node) -> not n.synthetic) nodes) in
  let one f = match nodes with [ n ] -> f n | _ -> [ Notice "Select one node" ] in
  let edit op = [ Syntax_edit op ] in
  match command with
  | Delete ->
      (match t.hovered_row with
       | Some (path, key) when (match node_of t path with
           | Some n -> List.exists (fun (r : P.row) -> r.key = key && wired r) n.rows | None -> false) ->
           let n = Option.get (node_of t path) in
           let r = List.find (fun (r : P.row) -> r.key = key) n.rows in
           edit (E.Disconnect { node = path; key; fallback = fallback r })
       | _ -> if paths = [] then [] else edit (E.Delete_nodes { nodes = paths }))
  | Fold_into -> one (fun n -> edit (E.Fold_into { node = n.path }))
  | Unfold -> one (fun n ->
      match t.hovered_row, first_inline n with
      | Some (p, key), _ when p = n.path -> edit (E.Unfold { node = n.path; key; sub = [] })
      | _, Some r -> edit (E.Unfold { node = n.path; key = r.key; sub = [] })
      | _ -> (match inline_rail n with
          | Some { key = Some key; _ } -> edit (E.Unfold { node = n.path; key; sub = [] })
          | _ -> [ Notice "Nothing to unfold here" ]))
  | Hoist -> one (fun n -> edit (E.Hoist { node = n.path }))
  | Bypass -> one (fun n -> edit (E.Toggle_bypass { node = n.path }))
  | Wrap_repeat -> if paths = [] then [ Notice "Select nodes to repeat" ] else edit (E.Wrap { nodes = paths; loop = E.For })
  | Wrap_iterate -> if paths = [] then [ Notice "Select nodes to iterate" ] else edit (E.Wrap { nodes = paths; loop = E.Fold })
  | Make_fn -> if paths = [] then [ Notice "Select nodes to make a function" ] else edit (E.Make_local_fn { nodes = paths })
  | Make_macro -> if paths = [] then [ Notice "Select nodes to make a macro" ] else [ Macro_requested paths ]
  | Collapse ->
      List.filter_map (fun (n : P.node) -> match n.zone with
        | Some { kind = P.Let; _ } | None -> None
        | Some _ -> Some (Zone_collapsed { zone = n.path; collapsed = not (t.collapsed n.path) })) nodes
  | Probe_step delta ->
      List.filter_map (fun (n : P.node) -> match n.zone with
        | Some { kind = P.Let; _ } | None -> None
        | Some _ ->
            let count = count_of t n.path in
            if count <= 0 then None else
            let index = max 0 (min (count - 1) (t.probe n.path + delta)) in
            if index = t.probe n.path then None else Some (Probe_set { zone = n.path; index })) nodes
  | Frame_all | Frame_selection | Walk _ | Edit_name | Make_frame -> []
  | Duplicate -> if paths = [] then [ Notice "Select nodes to duplicate" ] else edit (E.Duplicate { nodes = paths })
  | Display -> one (fun n ->
      if n.synthetic || n.ty <> Ty.Geometry then [ Notice "Only a geometry node can be viewed" ]
      else [ Display_set n.path ])
  | Item_up | Item_down ->
      (match t.hovered_row with
       | Some (path, E.Pos i) when (match node_of t path with
           | Some n -> List.mem n.head [ "list"; "str" ] | None -> false) ->
           edit (E.Move_item { node = path; pos = if command = Item_up then i else i + 1 })
       | _ -> [ Notice "Hover a list item to move it" ])

let frame_selection t =
  match List.filter_map (Hashtbl.find_opt t.geo.pos) (selected t) with
  | [] -> frame_all t
  | boxes ->
      let x0 = List.fold_left (fun a (x, _, _, _) -> Float.min a x) infinity boxes
      and y0 = List.fold_left (fun a (_, y, _, _) -> Float.min a y) infinity boxes
      and x1 = List.fold_left (fun a (x, _, w, _) -> Float.max a (x +. w)) neg_infinity boxes
      and y1 = List.fold_left (fun a (_, y, _, h) -> Float.max a (y +. h)) neg_infinity boxes in
      let w = Float.max 1. (x1 -. x0) and h = Float.max 1. (y1 -. y0) in
      let zoom = Float.max 0.25 (Float.min 1.5
        (Float.min ((float t.width -. 40.) /. w) ((float t.height -. 40.) /. h))) in
      { t with zoom; pan_x = (float t.width -. w *. zoom) /. 2. -. x0 *. zoom;
               pan_y = (float t.height -. h *. zoom) /. 2. -. y0 *. zoom }

let run_command t = function
  | Frame_all -> frame_all t, []
  | Frame_selection -> frame_selection t, []
  | Edit_name ->
      (match selected t with
       | [ path ] when (match node_of t path with Some n -> not n.synthetic | None -> false) ->
           { t with editing = Some (Name path) }, []
       | [ path ] when input_of t path <> None -> { t with editing = Some (Default path) }, []
       | _ -> t, [ Notice "Select one node or graph input to edit" ])
  | Make_frame ->
      (match new_frame t with
       | Some (scope, frame) -> t, [ Frames_set { scope; frames = t.frames scope @ [ frame ] } ]
       | None -> t, [ Notice "Select nodes to frame" ])
  | Walk direction ->
      let center (p : P.placed) (_, ax, ay) = ax +. p.w /. 2., ay +. p.h /. 2. in
      let current = match selected t with
        | path :: _ -> Array.find_opt (fun ((p : P.placed), _, _) -> p.path = path) t.geo.items
        | [] -> None in
      (match current with
       | None -> (match Array.to_list t.geo.items with
           | ((p : P.placed), _, _) :: _ -> select [ p.path ] t, [ Selected [ p.path ] ]
           | [] -> t, [])
       | Some (cp, cx, cy) ->
           let ox, oy = center cp (cp, cx, cy) in
           let best = Array.fold_left (fun best ((p : P.placed), ax, ay) ->
             if p.path = cp.path then best else
             let x, y = center p (p, ax, ay) in
             let dx = x -. ox and dy = y -. oy in
             let along, across = match direction with
               | Right -> dx, Float.abs dy | Left -> -. dx, Float.abs dy
               | Down -> dy, Float.abs dx | Up -> -. dy, Float.abs dx in
             if along <= 1. then best else
             let cost = along +. 2. *. across in
             match best with Some (c, _) when c <= cost -> best | _ -> Some (cost, p.path)) None t.geo.items in
           (match best with
            | Some (_, path) -> select [ path ] t, [ Selected [ path ] ]
            | None -> t, []))
  | command -> t, action_changes t command

let bindings =
  let open Editor_core.Keymap in
  let open Editor_core.Guide_context in
  (* the guide strip lists a key where it does something: on the empty canvas, with one node
     selected, or with several *)
  let make ~guide id label action key modifiers =
    Editor_core.Command.make ~id:("scope." ^ id) ~label ~guide ~trigger:(Chord (key, modifiers)) action in
  let ch c = Input.KeyChar c in
  let any = [ Canvas; Node; Multi ] and some = [ Node; Multi ] and one = [ Node ] in
  [ make ~guide:some "delete" "delete" Delete Input.Delete [];
    make ~guide:some "delete" "delete" Delete Input.Backspace [];
    make ~guide:some "delete" "delete" Delete (ch 'x') [];
    make ~guide:one "fold" "fold into use" Fold_into (ch 'f') [ Input.Shift ];
    make ~guide:one "unfold" "unfold a call" Unfold (ch 'u') [ Input.Shift ];
    make ~guide:one "hoist" "hoist out" Hoist (ch 'h') [ Input.Shift ];
    make ~guide:one "bypass" "toggle bypass" Bypass (ch 'b') [];
    make ~guide:some "macro" "make macro" Make_macro (ch 'm') [];
    make ~guide:some "repeat" "repeat (loop)" Wrap_repeat (ch 'r') [];
    make ~guide:some "iterate" "iterate (feed back)" Wrap_iterate (ch 'r') [ Input.Shift ];
    make ~guide:some "function" "make function" Make_fn (ch 'l') [];
    make ~guide:some "collapse" "collapse or expand zone" Collapse (ch 'c') [];
    make ~guide:one "probe-prev" "previous iteration" (Probe_step (-1)) (ch '[') [];
    make ~guide:one "probe-next" "next iteration" (Probe_step 1) (ch ']') [];
    make ~guide:any "frame-all" "frame all" Frame_all Input.Home [];
    make ~guide:any "frame-selection" "frame the selection" Frame_selection (ch 'f') [];
    make ~guide:one "rename" "rename node / edit input default" Edit_name Input.F2 [];
    make ~guide:some "frame" "frame the selection (titled box)" Make_frame (ch 'g') [ Input.Shift ];
    make ~guide:some "duplicate" "duplicate" Duplicate (ch 'd') [ Input.Meta ];
    make ~guide:some "duplicate" "duplicate" Duplicate (ch 'd') [ Input.Ctrl ];
    make ~guide:one "display" "view in the viewport" Display (ch 'v') [];
    make ~guide:one "item-up" "move list item up" Item_up Input.ArrowUp [ Input.Alt ];
    make ~guide:one "item-down" "move list item down" Item_down Input.ArrowDown [ Input.Alt ] ]
  @ List.map (fun (direction, arrow, name) ->
      make ~guide:any ("walk." ^ name) ("walk " ^ name) (Walk direction) arrow [])
    [ Left, Input.ArrowLeft, "left"; Down, Input.ArrowDown, "down";
      Up, Input.ArrowUp, "up"; Right, Input.ArrowRight, "right" ]

(* -------------------------------------------------------------- painting *)

let colors t = Pxui.Theme.ports t.theme
let ty_color t (ty : Ty.t option) =
  let p = colors t in
  let rec go = function
    | Ty.Geometry -> p.geometry | Float -> p.float | Int -> p.int | Bool -> p.bool | Vec3 -> p.vec3
    | Text | Color -> p.text | List e -> go e | Record _ -> p.record | Fn -> p.fn
    | Any | Scene | World | Settings | Panel | Editor -> p.output in
  match ty with Some ty -> go ty | None -> p.output

let fitted paint size width text =
  if Ui.Paint.text_width paint ~size text <= width then text else
  let rec prefix at previous =
    if at >= String.length text then String.sub text 0 previous ^ "…" else
    let next = at + Uchar.utf_decode_length (String.get_utf_8_uchar text at) in
    if Ui.Paint.text_width paint ~size (String.sub text 0 next ^ "…") > width
    then String.sub text 0 previous ^ "…" else prefix next next in
  prefix 0 0

let dashed_line paint ~width color (x0, y0) (x1, y1) =
  let length = Float.hypot (x1 -. x0) (y1 -. y0) in
  if length > 0. then
    for k = 0 to int_of_float (Float.ceil (length /. 7.)) - 1 do
      let lo = float k *. 7. in
      let hi = Float.min length (lo +. 4.) in
      if lo < hi then
        let point d = x0 +. (x1 -. x0) *. d /. length, y0 +. (y1 -. y0) *. d /. length in
        Ui.Paint.line paint ~from_:(point lo) ~to_:(point hi) ~width color
    done

let zone_style theme = function
  | P.For -> Pxui.Theme.zone_for theme | Fold | Scan -> Pxui.Theme.zone_fold theme
  | Sum -> Pxui.Theme.zone_sum theme | Fn -> Pxui.Theme.zone_fn theme | Let -> Pxui.Theme.zone_let theme

let paint_zone paint theme kind ~selected (x, y, w, h) =
  let s = zone_style theme kind in
  Ui.Paint.rect paint ~x ~y ~w ~h ~radius:6. ~fill:s.fill ();
  if s.dashed then begin
    List.iter (fun (a, b) -> dashed_line paint ~width:1.2 s.edge a b)
      [ (x, y), (x +. w, y); (x +. w, y), (x +. w, y +. h);
        (x +. w, y +. h), (x, y +. h); (x, y +. h), (x, y) ]
  end else Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) ~radius:6. s.edge;
  if selected then
    Ui.Paint.stroke paint ~x:(x -. 1.) ~y:(y -. 1.) ~w:(w +. 2.) ~h:(h +. 2.) ~width:1.5 ~radius:6. theme.Pxui.accent

let sx t gx = float t.x +. t.pan_x +. gx *. t.zoom
let sy t gy = float t.y +. t.pan_y +. gy *. t.zoom

(* A socket: a square for values, a stacked pair for lists, a diamond for
   functions, a wide pill for records. *)
let paint_socket paint theme (ty : Ty.t option) ~connected ~z (cx, cy) =
  let p = Pxui.Theme.ports theme in
  let color = match ty with
    | Some ty ->
        let rec go = function
          | Ty.Geometry -> p.geometry | Float -> p.float | Int -> p.int | Bool -> p.bool | Vec3 -> p.vec3
          | Text | Color -> p.text | List e -> go e | Record _ -> p.record | Fn -> p.fn
          | Any | Scene | World | Settings | Panel | Editor -> p.output in
        go ty
    | None -> p.output in
  let r = 5. *. z in
  let fill = if connected then color else theme.Pxui.input in
  match ty with
  | Some (Ty.List _) ->
      Ui.Paint.rect paint ~x:(cx -. r +. 2. *. z) ~y:(cy -. r +. 2. *. z) ~w:(2. *. r) ~h:(2. *. r)
        ~fill:theme.input ~stroke:color ();
      Ui.Paint.rect paint ~x:(cx -. r) ~y:(cy -. r) ~w:(2. *. r) ~h:(2. *. r) ~fill ~stroke:color ()
  | Some Ty.Fn ->
      let n = 7 in
      for k = 0 to n - 1 do
        let d = float k -. float (n - 1) /. 2. in
        let half = (r +. 1.) *. (1. -. Float.abs d /. (float n /. 2.)) in
        let h = 2. *. (r +. 1.) /. float n in
        Ui.Paint.fill paint ~x:(cx -. half) ~y:(cy +. d *. h -. h /. 2.) ~w:(2. *. half) ~h:(h +. 0.3)
          (if connected then color else Color.blend color theme.input ~pct:0.5)
      done
  | Some (Ty.Record _) ->
      Ui.Paint.rect paint ~x:(cx -. r -. 2. *. z) ~y:(cy -. r) ~w:(2. *. r +. 4. *. z) ~h:(2. *. r)
        ~radius:(4. *. z) ~fill ~stroke:color ()
  | _ -> Ui.Paint.rect paint ~x:(cx -. r) ~y:(cy -. r) ~w:(2. *. r) ~h:(2. *. r) ~fill ~stroke:color ()

let glyph_of = function
  | P.For -> "for" | Fold -> "↵" | Scan -> "scan" | Sum -> "Σ" | Let -> "let" | Fn -> "λ"

let note_colors theme =
  if Pxui.Theme.dark theme then Color.hex_exn "#4a4220", Color.hex_exn "#f3e6a8"
  else Color.hex_exn "#f3e6a8", Color.hex_exn "#4a3f10"

(* the marks a node or zone carries: live time, loop-invariant, bypass, macro *)
let marks ?(viewed = false) (n : P.node) =
  (if viewed then [ "VIEW" ] else [])
  @ (if n.live then [ "t" ] else []) @ (if n.invariant then [ "↑" ] else [])
  @ (if n.macro <> None then [ "◊" ] else [])
  @ (match n.zone with Some { order = Some o; _ } -> [ o ] | _ -> [])

let paint_marks paint theme ~size ~x ~y marks =
  List.fold_left (fun x m ->
    let w = Ui.Paint.text_width paint ~size m in
    Ui.Paint.text paint ~at:(x -. w, y) ~size ~color:theme.Pxui.accent m;
    x -. w -. 5.) x marks |> ignore

(* the value cell of a row *)
let cell_x = 84.

(* DepartureMono has no ⟲ ◆ ◷ ↥ ▸ ▾: the pane draws ↵ ◊ t ↑ ► ▼ in their place. *)
let shown_glyph = function "⟲" -> "↵" | "◆" -> "◊" | g -> g

let paint_chip paint t ~size ~z ~x ~y ~w (r : P.row) =
  let theme = t.theme in
  let text_y = y +. 6. *. z in
  match r.chip with
  | P.No_value ->
      Ui.Paint.text paint ~at:(x, text_y) ~size ~color:(Pxui.Theme.muted theme)
        (fitted paint size w (Option.value ~default:"" r.default))
  | Const -> (match r.expr with
      | Some { S.node = S.Num _ | S.Vec _; _ } -> ()
      | Some e -> Ui.Paint.text paint ~at:(x, text_y) ~size ~color:theme.foreground
                    (fitted paint size w (Flow.Lisp.flat e))
      | None -> ())
  | Name s -> Ui.Paint.text paint ~at:(x, text_y) ~size ~color:(ty_color t r.ty) (fitted paint size w s)
  | Inline { glyph; text } ->
      let glyph = shown_glyph glyph in
      let gw = Ui.Paint.text_width paint ~size glyph +. 8. *. z in
      Ui.Paint.rect paint ~x ~y:(y +. 4. *. z) ~w:gw ~h:(16. *. z) ~radius:3. ~fill:theme.control
        ~stroke:(Pxui.Theme.faint_border theme) ();
      Ui.Paint.text paint ~at:(x +. 4. *. z, text_y) ~size ~color:theme.accent glyph;
      Ui.Paint.text paint ~at:(x +. gw +. 4. *. z, text_y) ~size ~color:(Pxui.Theme.muted theme)
        (fitted paint size (w -. gw -. 4. *. z) text)

let paint_rows paint t ~z ~fs ~x ~y ~w rows ~selected_row =
  let theme = t.theme in
  List.iteri (fun i (r : P.row) ->
    let ry = y +. float i *. P.row_height *. z in
    if selected_row = Some i then
      Ui.Paint.fill paint ~x:(x +. 1.) ~y:ry ~w:(w -. 2.) ~h:(P.row_height *. z)
        (Color.with_alpha theme.accent 30);
    let shown = r.kind <> P.Add in
    let label_color = match r.kind with
      | P.Add -> theme.accent | Binder | Hole -> t.theme.accent | _ -> Pxui.Theme.muted theme in
    Ui.Paint.text paint ~at:(x +. 14. *. z, ry +. 6. *. z) ~size:fs ~color:label_color
      (fitted paint fs (60. *. z) r.label);
    if r.socket then
      paint_socket paint theme r.ty ~connected:(wired r) ~z (x, ry +. 12. *. z);
    if shown then paint_chip paint t ~size:fs ~z ~x:(x +. cell_x *. z) ~y:ry
        ~w:((w /. z -. cell_x -. 8.) *. z) r) rows

let paint_outputs paint t ~z ~fs ~x ~y ~w (n : P.node) =
  let theme = t.theme in
  List.iteri (fun j (name, ty) ->
    let ry = y +. float (List.length n.rows + j) *. P.row_height *. z in
    Ui.Paint.line paint ~from_:(x +. 8. *. z, ry) ~to_:(x +. w -. 8. *. z, ry) ~width:1.
      (Pxui.Theme.faint_border theme);
    Ui.Paint.text paint ~at:(x +. 14. *. z, ry +. 6. *. z) ~size:fs ~color:(colors t).record ("→ " ^ name);
    let label = Ty.to_string ty in
    let lw = Ui.Paint.text_width paint ~size:fs label in
    Ui.Paint.text paint ~at:(x +. w -. 14. *. z -. lw, ry +. 6. *. z) ~size:fs
      ~color:(Pxui.Theme.muted theme) label;
    paint_socket paint theme (Some ty) ~connected:true ~z (x +. w, ry +. 12. *. z)) n.outputs

let paint_rail paint t ~z ~fs ~x ~y ~expanded (rail : P.rail_row list) =
  let theme = t.theme in
  let palette = colors t in
  List.iteri (fun i (r : P.rail_row) ->
    let ry = y +. float i *. P.row_height *. z in
    let color = match r.role with
      | P.Var -> theme.accent | Acc -> palette.vec3 | Param -> palette.fn | Capture -> Pxui.Theme.muted theme in
    Ui.Paint.text paint ~at:(x +. 14. *. z, ry +. 6. *. z) ~size:fs ~color (fitted paint fs (56. *. z) r.name);
    let role = match r.role with P.Var -> "in" | Acc -> "acc" | Param -> "param" | Capture -> "from" in
    Ui.Paint.text paint ~at:(x +. 14. *. z +. 58. *. z, ry +. 7. *. z) ~size:(max 6 (fs - 1))
      ~color:(Pxui.Theme.muted theme) role;
    (match r.expr with
     | Some e ->
         let shown = match e.node with S.Sym s -> s | _ -> Flow.Lisp.flat e in
         Ui.Paint.text paint ~at:(x +. 92. *. z, ry +. 6. *. z) ~size:fs
           ~color:(if (match e.node with S.Sym _ -> true | _ -> false) then ty_color t r.ty else Pxui.Theme.muted theme)
           (fitted paint fs (60. *. z) shown)
     | None -> ());
    if r.key <> None || r.role = P.Capture then
      paint_socket paint theme r.ty ~connected:(r.role = P.Capture || r.expr <> None) ~z (x, ry +. 12. *. z);
    if expanded then
      paint_socket paint theme r.ty ~connected:true ~z (x +. P.rail_width *. z, ry +. 12. *. z)) rail

let paint_header paint t ~z ~fs ~x ~y ~w (n : P.node) ~toggle ?flag ?lens_open () =
  let viewed = t.display = Some n.path in
  let theme = t.theme in
  let size = max 6 (fs - 1) in
  let head = P.head_height *. z in
  Ui.Paint.rect paint ~x:(x +. 1.) ~y:(y +. 1.) ~w:(w -. 2.) ~h:(head -. 1.) ~radius:(3. *. z)
    ~fill:theme.control ();
  let name_x = match n.zone with
    | Some z_ ->
        let g = glyph_of z_.kind in
        let gx = x +. (if toggle <> None then 22. else 8.) *. z in
        Ui.Paint.rect paint ~x:gx ~y:(y +. 4. *. z) ~w:(Ui.Paint.text_width paint ~size g +. 8. *. z) ~h:(16. *. z)
          ~radius:(3. *. z) ~fill:(zone_style theme z_.kind).edge ();
        Ui.Paint.text paint ~at:(gx +. 4. *. z, y +. 6. *. z) ~size ~color:theme.input g;
        gx +. Ui.Paint.text_width paint ~size g +. 14. *. z
    | None ->
        Ui.Paint.fill paint ~x:(x +. 7. *. z) ~y:(y +. 7. *. z) ~w:(10. *. z) ~h:(10. *. z) (ty_color t (Some n.ty));
        (match flag with
         | Some on ->
             (* the bypass flag: filled while the node is bypassed *)
             let fx = x +. 22. *. z in
             Ui.Paint.rect paint ~x:fx ~y:(y +. 4. *. z) ~w:(16. *. z) ~h:(16. *. z) ~radius:(3. *. z)
               ~fill:(if on then theme.accent else theme.input) ~stroke:(Pxui.Theme.faint_border theme) ();
             Ui.Paint.text paint ~at:(fx +. 4. *. z, y +. 6. *. z) ~size
               ~color:(if on then theme.input else Pxui.Theme.muted theme) "B";
             x +. 44. *. z
         | None -> x +. 24. *. z) in
  (match toggle with
   | Some open_ -> Ui.Paint.text paint ~at:(x +. 6. *. z, y +. 6. *. z) ~size:fs
       ~color:(Pxui.Theme.muted theme) (if open_ then "▼" else "►")
   | None -> ());
  let m = marks ~viewed n in
  let marks_w = List.fold_left (fun a s -> a +. Ui.Paint.text_width paint ~size s +. 5.) 0. m in
  let right = match lens_open with
    | Some open_ ->
        Ui.Paint.text paint ~at:(x +. w -. 18. *. z, y +. 6. *. z) ~size:fs
          ~color:(Pxui.Theme.muted theme) (if open_ then "▼" else "►");
        x +. w -. 22. *. z
    | None -> x +. w -. 10. *. z in
  paint_marks paint theme ~size ~x:right ~y:(y +. 6. *. z) m;
  let title = if n.synthetic then "result" else n.name in
  Ui.Paint.text paint ~at:(name_x, y +. 6. *. z) ~size:fs ~color:(if n.synthetic then Pxui.Theme.muted theme else theme.foreground)
    (fitted paint fs (x +. w -. name_x -. marks_w -. 12. *. z -. 40. *. z) title);
  let head_label = n.head in
  if n.zone = None && n.head <> n.name then begin
    let hw = Ui.Paint.text_width paint ~size head_label in
    let hx = right -. marks_w -. hw in
    if hx > name_x +. 40. *. z then
      Ui.Paint.text paint ~at:(hx, y +. 7. *. z) ~size ~color:(Pxui.Theme.muted theme) head_label
  end

(* The footer strip of a node card or a collapsed zone: the value at the probe,
   a sparkline across the innermost zone, the tags, and the hoist button.
   The tags use ↑ for the study's ↥ and t for ◷ (DepartureMono lacks both). *)
let hoist_x = 116.
let paint_footer paint t ~z ~fs (f : Flow_sop.Probe.footer) (ty : Ty.t) (x, y, w, h) =
  let theme = t.theme in
  let size = max 6 (fs - 1) in
  let fy = y +. h -. P.foot_height *. z in
  let text_y = fy +. 5. *. z in
  Ui.Paint.line paint ~from_:(x +. 8. *. z, fy) ~to_:(x +. w -. 8. *. z, fy) ~width:1. (Pxui.Theme.faint_border theme);
  let right = ref (x +. w -. 8. *. z) in
  let put_right color s =
    let tw = Ui.Paint.text_width paint ~size s in
    Ui.Paint.text paint ~at:(!right -. tw, text_y) ~size ~color s;
    right := !right -. tw -. 6. *. z in
  if f.invariant then begin
    let room = (hoist_x -. 8.) *. z in
    let label = fitted paint size room "↑ same each time" in
    let tw = Ui.Paint.text_width paint ~size label in
    Ui.Paint.text paint ~at:(x +. w -. 8. *. z -. tw, text_y) ~size ~color:theme.accent label;
    right := x +. w -. hoist_x *. z
  end;
  if f.live then put_right theme.accent "t";
  let tags = String.concat " · " (List.filter_map Fun.id [ f.branch; f.kept; Option.map (Printf.sprintf "×%d") f.runs ]) in
  if tags <> "" then
    put_right (Pxui.Theme.muted theme) (fitted paint size (Float.max 0. (!right -. x) *. 0.5) tags);
  let left = x +. 8. *. z in
  (match f.spark with
   | Some (values, at) ->
       let sw = 36. *. z and sh = 10. *. z in
       let sx0 = Float.max (left +. 30. *. z) (!right -. sw) in
       let lo = Array.fold_left Float.min infinity values and hi = Array.fold_left Float.max neg_infinity values in
       let px i = sx0 +. float i /. float (Array.length values - 1) *. sw
       and py v = if hi = lo then fy +. 4. *. z +. sh /. 2. else fy +. 4. *. z +. sh -. (v -. lo) /. (hi -. lo) *. sh in
       (* at most 16 segments: a 240-iteration series draws as many as a 20-iteration one *)
       let n = Array.length values in
       let step = max 1 (n / 16) in
       let i = ref 0 in
       while !i < n - 1 do
         let j = min (n - 1) (!i + step) in
         Ui.Paint.line paint ~from_:(px !i, py values.(!i)) ~to_:(px j, py values.(j)) ~width:1.
           (ty_color t (Some ty));
         i := j
       done;
       Ui.Paint.fill paint ~x:(px at -. 1.5 *. z) ~y:(py values.(at) -. 1.5 *. z) ~w:(3. *. z) ~h:(3. *. z) theme.accent;
       right := sx0 -. 6. *. z
   | None -> ());
  Ui.Paint.text paint ~at:(left, text_y) ~size ~color:(ty_color t (Some ty))
    (fitted paint size (Float.max 0. (!right -. left)) f.value)

(* The expansion panel under a macro call, in graph units relative to its top: step
   buttons on the first row ("call", 1, 2, ...), the printed step, and the replace
   button with the reading on the last row. *)
let lens_button_box ~len i =
  if i = 0 then (8., 4.), (36., 16.)
  else if i >= len then (8. +. 40. +. float (max 0 (len - 1)) *. 28. +. 4., 4.), (64., 16.)  (* the template *)
  else (8. +. 40. +. float (i - 1) *. 28., 4.), (24., 16.)
let lens_replace_box lh = (8., lh -. P.row_height +. 3.), (196., 18.)
let bypassable (n : P.node) = P.bypassable n

let paint_lens paint t ~z ~fs (l : P.lens) ~step (x, y, w) ~lh =
  let theme = t.theme in
  Ui.Paint.fill paint ~x:(x +. 1.) ~y ~w:(w -. 2.) ~h:(lh *. z -. 1.) (Color.with_alpha theme.control 140);
  Ui.Paint.line paint ~from_:(x +. 8. *. z, y) ~to_:(x +. w -. 8. *. z, y) ~width:1. (Pxui.Theme.faint_border theme);
  let len = Array.length l.steps in
  for i = 0 to len do
    let (bx, by), (bw, bh) = lens_button_box ~len i in
    let on = i = step in
    Ui.Paint.rect paint ~x:(x +. bx *. z) ~y:(y +. by *. z) ~w:(bw *. z) ~h:(bh *. z) ~radius:(3. *. z)
      ~fill:(if on then theme.accent else theme.input) ~stroke:(Pxui.Theme.faint_border theme) ();
    let label = if i = 0 then "call" else if i = len then "Template" else string_of_int i in
    let tw = Ui.Paint.text_width paint ~size:(max 6 (fs - 1)) label in
    Ui.Paint.text paint ~at:(x +. (bx +. bw /. 2.) *. z -. tw /. 2., y +. (by +. 3.) *. z) ~size:(max 6 (fs - 1))
      ~color:(if on then theme.input else theme.foreground) label
  done;
  let text = if step >= len then (if l.template = "" then "(no definition)" else l.template)
    else match l.error with
      | Some message when step >= len -> message
      | _ -> l.steps.(max 0 step) in
  let lines = String.split_on_char '\n' text in
  List.iteri (fun k line ->
    if k < 16 then
      Ui.Paint.text paint ~at:(x +. 10. *. z, y +. (P.row_height +. 6. +. float k *. 15.) *. z) ~size:fs
        ~color:theme.foreground (fitted paint fs (w -. 20. *. z) (if k = 15 && List.length lines > 16 then line ^ " …" else line))) lines;
  let (rx, ry), (rw, rh) = lens_replace_box lh in
  Ui.Paint.rect paint ~x:(x +. rx *. z) ~y:(y +. ry *. z) ~w:(rw *. z) ~h:(rh *. z) ~radius:(3. *. z)
    ~fill:theme.input ~stroke:theme.accent ();
  Ui.Paint.text paint ~at:(x +. (rx +. 8.) *. z, y +. (ry +. 4.) *. z) ~size:(max 6 (fs - 1)) ~color:theme.accent
    "Replace call with expansion";
  let reading = match l.error with
    | _ when step >= len -> "the macro's template"
    | Some message when step >= len - 1 && step > 0 -> message
    | _ -> if step = 0 then "as written" else Printf.sprintf "after %d expansion step%s" step (if step > 1 then "s" else "") in
  let size = max 6 (fs - 1) in
  let tw = Ui.Paint.text_width paint ~size reading in
  Ui.Paint.text paint ~at:(x +. w -. 8. *. z -. tw, y +. (ry +. 4.) *. z) ~size ~color:(Pxui.Theme.muted theme)
    (fitted paint size (w -. (rx +. rw +. 24.) *. z) reading)

let paint_node paint t ~z ~fs ?footer ?lens_step (p : P.placed) (n : P.node) ~selected ~row_hover (x, y, w, h) =
  let theme = t.theme in
  let z_ = n.zone in
  let stacked = match z_ with Some _ -> p.collapsed | None -> false in
  if stacked then
    List.iter (fun d ->
      Ui.Paint.rect paint ~x:(x +. d *. z) ~y:(y +. d *. z) ~w ~h ~radius:(3. *. z) ~fill:theme.input
        ~stroke:(Pxui.Theme.border theme) ()) [ 6.; 3. ];
  Ui.Paint.rect paint ~x ~y ~w ~h ~radius:(3. *. z) ~fill:theme.input ~stroke:(Pxui.Theme.border theme) ();
  (match z_ with
   | Some zn when not p.collapsed ->
       (* an expanded zone: the tint is painted under the tiles; the tile draws the frame *)
       ignore zn
   | _ -> ());
  let lens = match n.lens, lens_step with Some l, Some step -> Some (l, step) | _ -> None in
  let lh = match lens with Some (l, step) -> P.lens_height l ~step | None -> 0. in
  paint_header paint t ~z ~fs ~x ~y ~w n
    ~toggle:(match z_ with Some { kind = P.Let; _ } | None -> None | Some _ -> Some (not p.collapsed))
    ?flag:(if bypassable n then Some n.bypass else None)
    ?lens_open:(if n.lens <> None then Some (lens <> None) else None) ();
  paint_socket paint theme (Some n.ty) ~connected:true ~z (x +. w, y +. 12. *. z);
  let body_y = y +. P.head_height *. z in
  (match n.note with
   | Some note ->
       let bg, ink = note_colors theme in
       Ui.Paint.fill paint ~x:(x +. 1.) ~y:body_y ~w:(w -. 2.) ~h:(P.row_height *. z) bg;
       let first = match String.index_opt note '\n' with Some i -> String.sub note 0 i | None -> note in
       Ui.Paint.text paint ~at:(x +. 8. *. z, body_y +. 6. *. z) ~size:fs ~color:ink (fitted paint fs (w -. 16. *. z) first)
   | None -> ());
  let rows_y = body_y +. (if n.note <> None then P.row_height *. z else 0.) in
  (match z_ with
   | None ->
       paint_rows paint t ~z ~fs ~x ~y:rows_y ~w n.rows ~selected_row:row_hover;
       if n.head = "list" || n.head = "str" then
         List.iteri (fun i (r : P.row) -> match r.kind, r.key with
           | P.Rest, E.Pos k when k >= 1 ->
               Ui.Paint.text paint ~at:(x +. w -. 20. *. z, rows_y +. (float i *. P.row_height +. 6.) *. z) ~size:fs
                 ~color:theme.accent "↑"
           | _ -> ()) n.rows;
       paint_outputs paint t ~z ~fs ~x ~y:rows_y ~w n
   | Some zn when p.collapsed -> paint_rail paint t ~z ~fs ~x ~y:(y +. P.head_height *. z) ~expanded:false zn.rail
   | Some _ -> ());
  Option.iter (fun f -> paint_footer paint t ~z ~fs f n.ty (x, y, w, h -. lh *. z)) footer;
  Option.iter (fun (l, step) -> paint_lens paint t ~z ~fs l ~step (x, y +. h -. lh *. z, w) ~lh) lens;
  if selected then
    Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) ~width:2. ~radius:(3. *. z) theme.accent

(* the expanded zone's frame, rail, yield and selector, over its tint *)
let paint_zone_frame paint t ~z ~fs ?footer (n : P.node) (zn : P.zone) ~selected (x, y, w, h) ~probe ~count =
  let theme = t.theme in
  (* the zone's own footer under its body; the yield line and the feedback line end above it *)
  let h = match footer with
    | Some f -> paint_footer paint t ~z ~fs f n.ty (x, y, w, h); h -. P.foot_height *. z
    | None -> h in
  let edge = (zone_style theme zn.kind).edge in
  Ui.Paint.line paint ~from_:(x, y +. P.head_height *. z) ~to_:(x +. w, y +. P.head_height *. z) ~width:1.
    (Color.with_alpha edge 90);
  paint_header paint t ~z ~fs ~x ~y ~w n ~toggle:(if zn.kind = P.Let then None else Some true) ();
  paint_socket paint theme (Some n.ty) ~connected:true ~z (x +. w, y +. 12. *. z);
  let top = y +. P.rail_top n *. z in
  paint_rail paint t ~z ~fs ~x ~y:top ~expanded:true zn.rail;
  let yx = x +. w -. P.yield_width *. z in
  Ui.Paint.line paint ~from_:(yx, top) ~to_:(yx, y +. h -. 6. *. z) ~width:1. (Color.with_alpha edge 120);
  Ui.Paint.text paint ~at:(yx +. 14. *. z, top +. 6. *. z) ~size:fs ~color:(Pxui.Theme.muted theme) zn.yield_label;
  paint_socket paint theme (Some n.ty) ~connected:true ~z (yx, top +. 12. *. z);
  if zn.kind = P.Fold || zn.kind = P.Scan then begin
    (* the feedback line: yield back to the accumulator *)
    let acc = List.find_index (fun (r : P.rail_row) -> r.role = P.Acc) zn.rail in
    match acc with
    | Some i ->
        let by = y +. h -. 10. *. z in
        let ax = x +. P.rail_width *. z and ay = top +. (float i +. 0.5) *. P.row_height *. z in
        let color = (colors t).vec3 in
        let pts = [ (yx, top +. 12. *. z); (yx -. 8. *. z, top +. 12. *. z); (yx -. 8. *. z, by);
                    (ax +. 8. *. z, by); (ax +. 8. *. z, ay); (ax, ay) ] in
        List.iter2 (fun a b -> dashed_line paint ~width:1.2 color a b)
          (List.filteri (fun i _ -> i < List.length pts - 1) pts) (List.tl pts)
    | None -> ()
  end;
  if zn.kind <> P.Let then begin
    let sy = y +. P.head_height *. z in
    let size = max 6 (fs - 1) in
    let read = if count > 0 then Printf.sprintf "%d/%d" (probe + 1) count else "no runs" in
    let rw = Ui.Paint.text_width paint ~size read in
    Ui.Paint.line paint ~from_:(x, sy +. P.strip_height *. z) ~to_:(x +. w, sy +. P.strip_height *. z) ~width:1.
      (Color.with_alpha edge 60);
    let tx = x +. 30. *. z and tw = w -. 60. *. z -. rw -. 14. *. z in
    Ui.Paint.rect paint ~x:tx ~y:(sy +. 12. *. z) ~w:tw ~h:(10. *. z) ~radius:(2. *. z)
      ~fill:theme.track ~stroke:(Pxui.Theme.faint_border theme) ();
    if count > 0 then begin
      let cell = tw /. float count in
      if cell >= 4. *. z then
        for k = 0 to count - 1 do
          Ui.Paint.line paint ~from_:(tx +. cell *. float k, sy +. 12. *. z) ~to_:(tx +. cell *. float k, sy +. 22. *. z)
            ~width:1. (Color.with_alpha edge 60)
        done;
      Ui.Paint.fill paint ~x:(tx +. cell *. float probe) ~y:(sy +. 11. *. z) ~w:(Float.max (2. *. z) cell) ~h:(12. *. z)
        (Color.with_alpha theme.accent 210)
    end;
    Ui.Paint.text paint ~at:(x +. 8. *. z, sy +. 10. *. z) ~size:fs ~color:theme.foreground "◄";
    Ui.Paint.text paint ~at:(tx +. tw +. 6. *. z, sy +. 10. *. z) ~size:fs ~color:theme.foreground "►";
    Ui.Paint.text paint ~at:(x +. w -. 8. *. z -. rw, sy +. 11. *. z) ~size ~color:(Pxui.Theme.muted theme) read
  end;
  if selected then
    Ui.Paint.stroke paint ~x:(x -. 1.) ~y:(y -. 1.) ~w:(w +. 2.) ~h:(h +. 2.) ~width:1.5 ~radius:6. theme.accent

let paint_input paint t ~z ~fs (i : P.input) ~selected (x, y, w, h) =
  let theme = t.theme in
  Ui.Paint.rect paint ~x ~y ~w ~h ~radius:(3. *. z) ~fill:theme.input ~stroke:(Pxui.Theme.border theme) ();
  Ui.Paint.rect paint ~x:(x +. 1.) ~y:(y +. 1.) ~w:(w -. 2.) ~h:(P.head_height *. z -. 1.) ~radius:(3. *. z) ~fill:theme.control ();
  Ui.Paint.fill paint ~x:(x +. 7. *. z) ~y:(y +. 7. *. z) ~w:(10. *. z) ~h:(10. *. z) (ty_color t (Some i.ty));
  Ui.Paint.text paint ~at:(x +. 24. *. z, y +. 6. *. z) ~size:fs ~color:theme.foreground (fitted paint fs (w -. 40. *. z) i.name);
  Ui.Paint.text paint ~at:(x +. 14. *. z, y +. (P.head_height +. 6.) *. z) ~size:fs ~color:(Pxui.Theme.muted theme)
    (Ty.to_string i.ty ^ (match i.default with Some d -> " = " ^ Flow.Lisp.flat d | None -> ""));
  paint_socket paint theme (Some i.ty) ~connected:true ~z (x +. w, y +. 12. *. z);
  if selected then
    Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) ~width:2. ~radius:(3. *. z) theme.accent

let paint_return paint t ~z ~fs (s : P.scope) ~selected (x, y, w, h) =
  let theme = t.theme in
  Ui.Paint.rect paint ~x ~y ~w ~h ~radius:(3. *. z) ~fill:theme.input ~stroke:(Pxui.Theme.border theme) ();
  Ui.Paint.rect paint ~x:(x +. 1.) ~y:(y +. 1.) ~w:(w -. 2.) ~h:(P.head_height *. z -. 1.) ~radius:(3. *. z) ~fill:theme.control ();
  Ui.Paint.text paint ~at:(x +. 10. *. z, y +. 6. *. z) ~size:fs ~color:theme.foreground "return";
  let shown = match s.result with
    | P.Link l -> l | Node _ -> "result" | Literal e -> Flow.Lisp.flat e in
  Ui.Paint.text paint ~at:(x +. 14. *. z, y +. (P.head_height +. 6.) *. z) ~size:fs ~color:(Pxui.Theme.muted theme)
    (fitted paint fs (w -. 24. *. z) shown);
  paint_socket paint theme None ~connected:(s.result <> P.Literal (S.make (S.Sym "nil"))) ~z (x, y +. 36. *. z);
  if selected then
    Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) ~width:2. ~radius:(3. *. z) theme.accent

(* a wire as an orthogonal polyline with a vertical run at the midpoint *)
let wire_points (ax, ay) (bx, by) =
  let mx = if bx >= ax +. 24. then (ax +. bx) /. 2. else ax +. 12. in
  if bx >= ax +. 24. then [ (ax, ay); (mx, ay); (mx, by); (bx, by) ]
  else [ (ax, ay); (mx, ay); (mx, (ay +. by) /. 2.); (bx -. 12., (ay +. by) /. 2.); (bx -. 12., by); (bx, by) ]

let paint_polyline paint ~width color pts =
  let rec go = function
    | a :: (b :: _ as rest) -> Ui.Paint.line paint ~from_:a ~to_:b ~width color; go rest
    | _ -> () in
  go pts

let paint_background paint t ~viewport (zones : (P.node * P.zone * P.placed * float * float) list) =
  let theme = t.theme in
  let vx, vy, vw, vh = viewport in
  let z = t.zoom in
  let spacing = 24. *. z in
  Ui.Paint.fill paint ~x:vx ~y:vy ~w:vw ~h:vh
    (if theme = Pxui.default_theme then Color.hex_exn "#eaede7" else Color.blend theme.panel theme.accent ~pct:0.25);
  Ui.Paint.grid paint ~x:vx ~y:vy ~w:vw ~h:vh
    ~origin:(vx +. Float.rem t.pan_x spacing, vy +. Float.rem t.pan_y spacing) ~spacing ~dot:2.
    (Color.with_alpha theme.foreground 46);
  List.iter (fun ((n : P.node), (zn : P.zone), (p : P.placed), ax, ay) ->
    paint_zone paint theme zn.kind ~selected:(Path_set.mem n.path t.selected)
      (sx t ax, sy t ay, p.w *. z, p.h *. z)) zones;
  (* titled frames sit under the wires *)
  List.iter (fun (scope_path, (ox, oy)) ->
    List.iter (fun (title, (fx, fy), (fw, fh)) ->
      let x = sx t (ox +. fx) and y = sy t (oy +. fy) in
      Ui.Paint.rect paint ~x ~y ~w:(fw *. z) ~h:(fh *. z) ~radius:4. ~fill:(Color.with_alpha theme.foreground 10)
        ~stroke:(Pxui.Theme.faint_border theme) ();
      Ui.Paint.text paint ~at:(x +. 6., y +. 4.) ~size:(max 7 (int_of_float (10. *. z)))
        ~color:(Pxui.Theme.muted theme) title;
      (* delete cross top right, resize grip bottom right *)
      Ui.Paint.text paint ~at:(x +. fw *. z -. 14., y +. 4.) ~size:(max 7 (int_of_float (10. *. z)))
        ~color:(Pxui.Theme.muted theme) "x";
      Ui.Paint.fill paint ~x:(x +. fw *. z -. 8.) ~y:(y +. fh *. z -. 8.) ~w:6. ~h:6.
        (Color.with_alpha theme.accent 160)) (frame_list t scope_path)) t.geo.origins;
  Array.iter (fun w ->
    let pts = List.map (fun (x, y) -> sx t x, sy t y) (wire_points w.a w.b) in
    let width = Float.max 1. (1.6 *. z) in
    paint_polyline paint ~width (ty_color t w.ty) pts) t.geo.wires

(* ---------------------------------------------------------------- update *)

let left_button (s : Ui.signal) = s.button = Some Input.LeftButton
let contains (x, y, w, h) (px, py) = px >= x && px < x +. w && py >= y && py < y +. h

let num_field ui ~at ~w ~h ~size label text =
  let is_float = String.exists (fun c -> c = '.' || c = 'e') text in
  let scrub origin dx shift = match float_of_string_opt origin with
    | None -> origin
    | Some v when is_float ->
        let v = v +. dx *. (if shift then 0.005 else 0.05) in
        let s = Printf.sprintf "%.6g" v in
        if String.exists (fun c -> c = '.' || c = 'e') s then s else s ^ ".0"
    | Some v -> string_of_int (int_of_float (Float.round (v +. Float.round (dx /. 6.)))) in
  let valid s = match float_of_string_opt s with Some f -> Float.is_finite f | None -> false in
  let text', _ = Ui.value_field ui ~at ~w ~h ~size ~scrub ~valid label text in
  if text' <> text && valid text' then Some text' else None

let row_index (n : P.node) ~ay ~py =
  let top = rows_top n ay in
  if py < top then None else Some (int_of_float ((py -. top) /. P.row_height))

(* the nodes of one scope a rubber band touches (an expanded zone only when it is inside it) *)
let marquee_hits t (rx, ry, rw, rh) =
  let z = t.zoom in
  let hits = Array.fold_left (fun acc ((p : P.placed), ax, ay) -> match p.item with
    | P.Item n when not n.synthetic ->
        let x, y, w, h = sx t ax, sy t ay, p.w *. z, p.h *. z in
        let touches = x < rx +. rw && x +. w > rx && y < ry +. rh && y +. h > ry in
        let inside = x >= rx && y >= ry && x +. w <= rx +. rw && y +. h <= ry +. rh in
        if ((p.inner = None || p.collapsed) && touches) || inside then p.path :: acc else acc
    | _ -> acc) [] t.geo.items in
  match List.rev hits with
  | [] -> Path_set.empty
  | first :: _ as hits ->
      let scope = scope_of_path first in
      Path_set.of_list (List.filter (fun p -> scope_of_path p = scope) hits)

let valid_name s =
  s <> "" && not (String.exists (fun c -> List.mem c [ ' '; '('; ')'; '['; ']'; '{'; '}'; '"'; ';'; '\'' ]) s)

let single_form text = match Flow.Syntax.parse text with Ok [ form ] -> Some form | _ -> None

let context_items t path =
  match node_of t path with
  | None -> []
  | Some n ->
      let zone = match n.zone with Some { kind = P.Let; _ } | None -> None | Some _ -> Some n in
      [ "Fold into its use", true; "Unfold a call", true; "Hoist out", n.invariant;
        (match zone with Some n -> if t.collapsed n.path then "Expand zone" else "Collapse zone"
                       | None -> "Collapse zone"), zone <> None;
        "Toggle bypass", true; "Repeat (loop)", true; "Iterate (feed back)", true;
        "Make function", true; "Make macro", true; "Delete", true ]

let context_command = function
  | 0 -> Fold_into | 1 -> Unfold | 2 -> Hoist | 3 -> Collapse | 4 -> Bypass
  | 5 -> Wrap_repeat | 6 -> Wrap_iterate | 7 -> Make_fn | 8 -> Make_macro | _ -> Delete

let update t ui (frame : Frame.t) =
  if not t.visible then { t with drag = None; context = None; editing = None }, [] else
  let t = if t.framed then t else { (frame_all t) with framed = true } in
  let changes = ref [] in
  let emit c = changes := c :: !changes in
  let canvas = Ui.box ui ~flags:Ui.(clickable + scroll + clip + blocking)
      ~w:(Ui.Px (float t.width)) ~h:(Ui.Px (float t.height))
      ~at:(float t.x, float t.y) "pxui-scope" in
  let canvas_signal = Ui.signal ui canvas in
  (* the grid, zones and wires paint in a child, so the canvas's clip holds them too *)
  let layer = Ui.within ui canvas (fun () ->
    Ui.box ui ~w:(Ui.Px (float t.width)) ~h:(Ui.Px (float t.height)) ~at:(0., 0.) "pxui-scope-layer") in
  let t =
    let _, wheel = canvas_signal.scroll in
    if wheel = 0. || t.context <> None then t else begin
      let mx, my = frame.mouse in
      let zoom = Float.max 0.25 (Float.min 2.5 (t.zoom *. (1. +. wheel *. 0.1))) in
      let k = zoom /. t.zoom in
      { t with zoom; pan_x = (mx -. float t.x) -. ((mx -. float t.x) -. t.pan_x) *. k;
        pan_y = (my -. float t.y) -. ((my -. float t.y) -. t.pan_y) *. k }
    end in
  (* a drag in progress moves its items in a fresh geometry *)
  let t = match t.drag, t.scope with
    | Some (Moving m), Some scope when m.moved ->
        let paths = m.paths in
        { t with geo = compute scope t.layout ~shift:(fun p ->
            if List.mem p paths then m.dx, m.dy else 0., 0.) }
    | Some (Carrying c), Some scope when Float.hypot c.dx c.dy > 0. ->
        { t with geo = compute scope t.layout ~shift:(fun p ->
            if List.mem p c.paths then c.dx, c.dy else 0., 0.) }
    | _ -> t in
  let z = t.zoom in
  let fs = max 7 (int_of_float (Float.round (11. *. z))) in
  let viewport = (float t.x, float t.y, float t.width, float t.height) in
  let visible = Array.to_list t.geo.items |> List.filter (fun ((p : P.placed), ax, ay) ->
    let r = (sx t ax -. 20., sy t ay -. 20., p.w *. z +. 40., p.h *. z +. 40.) in
    let x, y, w, h = r and vx, vy, vw, vh = viewport in
    x < vx +. vw && x +. w > vx && y < vy +. vh && y +. h > vy) in
  let node_placed (p : P.placed) = match p.item with P.Item n -> Some n | _ -> None in
  let zones = List.filter_map (fun ((p : P.placed), ax, ay) -> match p.item with
    | P.Item ({ zone = Some zn; _ } as n) when not p.collapsed -> Some (n, zn, p, ax, ay)
    | _ -> None) visible in
  let local (x, y) = x -. float t.x, y -. float t.y in
  let mouse = frame.mouse in
  (* footers: only for what is in view, and not when too small to read *)
  let footers = Hashtbl.create 16 in
  (match t.records with
   | Some records when z >= 0.4 ->
       List.iter (fun ((p : P.placed), _, _) -> match p.item with
         | P.Item n when (match n.zone with Some { kind = P.Let; _ } -> p.collapsed | _ -> true) ->
             let chain = Option.value ~default:[] (Hashtbl.find_opt t.chains n.path) in
             Hashtbl.replace footers n.path (Flow_sop.Probe.footer records n ~probes:(List.map t.probe chain))
         | _ -> ()) visible
   | _ -> ());
  let finished = ref false in
  let edit_field ~at ~w ~h key current valid commit =
    let v, open_ = Ui.value_field ui ~at ~w ~h ~size:fs ~edit:true ~valid key current in
    if not open_ then finished := true;
    if (not open_) && v <> current && valid v then [ commit v ] else [] in
  (* tiles *)
  let tiles = Ui.within ui canvas (fun () ->
    List.map (fun ((p : P.placed), ax, ay) ->
      let bx, by = sx t ax, sy t ay in
      let key = "t:" ^ String.concat "/" p.path in
      let w = p.w *. z and h = p.h *. z in
      let tile = Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px w) ~h:(Ui.Px h) ~at:(local (bx, by)) key in
      let sub = Ui.within ui tile (fun () ->
        let box ?(flags = Ui.clickable) name (dx, dy) (bw, bh) =
          Ui.box ui ~flags ~w:(Ui.Px (bw *. z)) ~h:(Ui.Px (bh *. z)) ~at:(dx *. z, dy *. z) name in
        let outs = ref [] and dels = ref [] and taps = ref [] in
        let out name src ty pos = outs := (box name (fst pos -. 7., snd pos -. 7.) (14., 14.), src, ty) :: !outs in
        let tap name pos size on = taps := (box name pos size, on) :: !taps in
        (match p.item with
         | P.Input i -> out "out" i.name (Some i.ty) (p.w, 12.)
         | Return -> ()
         | Item n ->
             let node_src = if n.binds = [ n.name ] then Some n.name else None in
             Option.iter (fun s -> out "out" s (Some n.ty) (p.w, 12.)) node_src;
             (match Hashtbl.find_opt footers n.path with
              | Some { invariant = true; _ } -> tap "hoist" (p.w -. hoist_x, p.h -. P.foot_height +. 2.) (hoist_x -. 6., 16.) `Hoist
              | _ -> ());
             (match n.zone with
              | Some zn when not p.collapsed ->
                  let top = P.rail_top n in
                  List.iteri (fun i (r : P.rail_row) ->
                    out ("rail:" ^ string_of_int i) (List.hd r.names) r.ty
                      (P.rail_width, top +. (float i +. 0.5) *. P.row_height);
                    (* wired rail rows can be disconnected from their socket *)
                    (match r.key, r.expr with
                     | Some key, Some e when E.free_names e <> [] ->
                         dels := (box ("rd:" ^ string_of_int i) (-7., top +. float i *. P.row_height +. 5.) (14., 14.),
                                  E.Disconnect { node = n.path; key; fallback = None }) :: !dels
                     | _ -> ())) zn.rail;
                  if zn.kind <> P.Let then begin
                    let sy = P.head_height in
                    tap "prev" (2., sy +. 6.) (22., 22.) (`Step (-1));
                    tap "next" (p.w -. 24., sy +. 6.) (22., 22.) (`Step 1);
                    tap "track" (28., sy +. 6.) (p.w -. 56., 22.) `Track
                  end;
                  if zn.kind <> P.Let then tap "toggle" (2., 2.) (20., 20.) `Toggle
              | Some zn when p.collapsed ->
                  if zn.kind <> P.Let then tap "toggle" (2., 2.) (20., 20.) `Toggle
              | Some _ -> ()
              | None ->
                  if bypassable n then tap "bypass" (22., 4.) (18., 16.) `Bypass;
                  (match n.lens with
                   | Some l ->
                       tap "lens" (p.w -. 22., 2.) (20., 20.) `Lens;
                       (match lens_of t n.path with
                        | Some step ->
                            let lh = P.lens_height l ~step in
                            let top = p.h -. lh in
                            let len = Array.length l.steps in
                            for i = 0 to len do
                              let (bx, by), size = lens_button_box ~len i in
                              tap ("ls" ^ string_of_int i) (bx, top +. by) size (`Lens_step i)
                            done;
                            let (rx, ry), size = lens_replace_box lh in
                            tap "lr" (rx, top +. ry) size `Replace
                        | None -> ())
                   | None -> ());
                  let top = rows_top n 0. in
                  List.iteri (fun j (f, ty) ->
                    let src = if n.binds = [ n.name ] then n.name ^ "." ^ f else f in
                    out ("o:" ^ string_of_int j) src (Some ty)
                      (p.w, top +. (float (List.length n.rows + j) +. 0.5) *. P.row_height)) n.outputs;
                  List.iteri (fun i (r : P.row) ->
                    let ry = top +. float i *. P.row_height in
                    if wired r then
                      dels := (box ("d:" ^ string_of_int i) (-7., ry +. 5.) (14., 14.),
                               E.Disconnect { node = n.path; key = r.key; fallback = fallback r }) :: !dels
                    else ()) n.rows));
        List.rev !outs, List.rev !dels, List.rev !taps) in
      (* fields, inside the tile *)
      let fields = match p.item with
        | P.Item ({ zone = None; _ } as n) when z >= 0.5 ->
            Ui.within ui tile (fun () ->
              let top = rows_top n 0. in
              List.concat (List.mapi (fun i (r : P.row) ->
                let ry = top +. float i *. P.row_height in
                let at = cell_x *. z and vw = (p.w -. cell_x -. 8.) *. z and h = 16. *. z in
                let ay = (ry +. 4.) *. z in
                match r.chip, r.expr with
                | P.Const, Some ({ node = S.Num text; _ }) ->
                    (match num_field ui ~at:(at, ay) ~w:vw ~h ~size:fs ("f" ^ string_of_int i) text with
                     | Some text' -> [ Syntax_edit (E.Set_arg { node = n.path; key = r.key; sub = [];
                         value = S.make (S.Num text') }) ]
                     | None -> [])
                | P.Const, Some { node = S.Vec elems; _ }
                  when List.length elems >= 2 && List.length elems <= 4
                       && List.for_all (fun (e : S.t) -> match e.node with S.Num _ -> true | _ -> false) elems ->
                    let k = List.length elems in
                    let cw = (vw -. float (k - 1) *. 2.) /. float k in
                    List.concat (List.mapi (fun c (e : S.t) -> match e.node with
                      | S.Num text ->
                          (match num_field ui ~at:(at +. float c *. (cw +. 2.), ay) ~w:cw ~h ~size:(max 6 (fs - 1))
                                   (Printf.sprintf "f%d.%d" i c) text with
                           | Some text' -> [ Syntax_edit (E.Set_arg { node = n.path; key = r.key; sub = [ c ];
                               value = S.make (S.Num text') }) ]
                           | None -> [])
                      | _ -> []) elems)
                | P.Const, Some { node = S.Sym (("true" | "false") as b); _ } ->
                    let toggle = Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px vw) ~h:(Ui.Px h)
                        ~at:(at, ay) ("b" ^ string_of_int i) in
                    if (Ui.signal ui toggle).clicked then
                      [ Syntax_edit (E.Set_arg { node = n.path; key = r.key; sub = [];
                          value = S.make (S.Sym (if b = "true" then "false" else "true")) }) ]
                    else []
                | _ -> []) n.rows))
        | _ -> [] in
      let add_clicks = match p.item with
        | P.Item ({ zone = None; _ } as n) when z >= 0.5 ->
            Ui.within ui tile (fun () ->
              let top = rows_top n 0. in
              List.concat (List.mapi (fun i (r : P.row) ->
                if r.kind <> P.Add && (match r.chip with P.Inline _ -> false | _ -> true) then [] else
                let b = Ui.box ui ~flags:Ui.(clickable + tab_stop)
                    ~w:(Ui.Px (if r.kind = P.Add then (p.w -. 16.) *. z else 24. *. z)) ~h:(Ui.Px (16. *. z))
                    ~at:((if r.kind = P.Add then 8. else cell_x) *. z, (top +. float i *. P.row_height +. 4.) *. z)
                    ("a" ^ string_of_int i) in
                if not (Ui.signal ui b).clicked then [] else
                match r.kind, r.chip with
                | P.Add, _ ->
                    (match r.key with
                     | E.Field _ -> [ Syntax_edit (E.Add_field { node = n.path;
                         name = "f" ^ string_of_int (List.length n.rows);
                         value = S.make (S.Num "0") }) ]
                     | key when n.head = "list" || n.head = "str" || n.head = "concat" && false ->
                         ignore key; [ Syntax_edit (E.Add_item { node = n.path }) ]
                     | key when r.ty = Some Ty.Geometry -> ignore key; [ Notice "Wire a node onto this row" ]
                     | key ->
                         let value = match Option.bind r.ty (fun ty -> E.default_for ty r.label) with
                           | Some v -> v | None -> S.make (S.Num "0") in
                         [ Syntax_edit (E.Set_arg { node = n.path; key; sub = []; value }) ])
                | _, P.Inline _ -> [ Syntax_edit (E.Unfold { node = n.path; key = r.key; sub = [] }) ]
                | _ -> []) n.rows))
        | _ -> [] in
      let editors = match t.editing, p.item with
        | Some (Name path), P.Item n when path = n.path ->
            Ui.within ui tile (fun () ->
              edit_field ~at:(44. *. z, 3. *. z) ~w:((p.w -. 56.) *. z) ~h:(18. *. z) "name" n.name valid_name
                (fun v -> Syntax_edit (E.Rename { node = n.path; to_ = v })))
        | Some (Default path), P.Input i when path = i.path ->
            Ui.within ui tile (fun () ->
              let text = match i.default with Some d -> Flow.Lisp.flat d | None -> "" in
              edit_field ~at:(14. *. z, (P.head_height +. 2.) *. z) ~w:((p.w -. 28.) *. z) ~h:(18. *. z) "default" text
                (fun v -> single_form v <> None)
                (fun v -> Syntax_edit (E.Set_input_default { form = List.hd i.path; input = i.name;
                  value = Option.get (single_form v) })))
        | _ -> [] in
      let movers = match p.item with
        | P.Item ({ zone = None; head = ("list" | "str"); _ } as n) when z >= 0.5 ->
            Ui.within ui tile (fun () ->
              let top = rows_top n 0. in
              List.concat (List.mapi (fun i (r : P.row) -> match r.kind, r.key with
                | P.Rest, E.Pos k when k >= 1 ->
                    let b = Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px (16. *. z)) ~h:(Ui.Px (16. *. z))
                        ~at:((p.w -. 22.) *. z, (top +. float i *. P.row_height +. 4.) *. z) ("mv" ^ string_of_int i) in
                    if (Ui.signal ui b).clicked then [ Syntax_edit (E.Move_item { node = n.path; pos = k }) ] else []
                | _ -> []) n.rows))
        | _ -> [] in
      p, ax, ay, tile, Ui.signal ui tile, sub, fields @ add_clicks @ editors @ movers) visible) in
  let t = if !finished then { t with editing = None } else t in
  (* frames: a title strip, a delete cross and a resize corner, over the tiles (a zone's tile
     covers its whole body) and clear of the nodes, which keep 12 points inside the frame *)
  let frame_boxes = Ui.within ui canvas (fun () ->
    List.concat_map (fun (scope, (ox, oy)) ->
      List.mapi (fun i ((title, (fx, fy), (fw, fh)) : fr) ->
        let x = sx t (ox +. fx) and y = sy t (oy +. fy) in
        let w = fw *. z and h = fh *. z in
        let box k (bx, by) (bw, bh) =
          Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px bw) ~h:(Ui.Px bh) ~at:(local (bx, by))
            (Printf.sprintf "fr:%s:%d:%s" (String.concat "/" scope) i k) in
        (scope, i, title, (x, y, w, h)),
        (box "t" (x, y) (Float.max 8. (w -. 20.), 18. *. z), box "x" (x +. w -. 18., y +. 2.) (16., 16.),
         box "r" (x +. w -. 12., y +. h -. 12.) (12., 12.))) (t.frames scope)) t.geo.origins) in
  let t = List.fold_left (fun t ((scope, i, title, (x, y, w, _)), (tb, xb, rb)) ->
    let ts = Ui.signal ui tb and xs = Ui.signal ui xb and rs = Ui.signal ui rb in
    let all = t.frames scope in
    (match t.editing with
     | Some (Title (sp, k)) when sp = scope && k = i ->
         List.iter emit (Ui.within ui canvas (fun () ->
           edit_field ~at:(local (x +. 4., y +. 2.)) ~w:(Float.max 40. (w -. 24.)) ~h:(16. *. z)
             (Printf.sprintf "frt%d" i) title (fun s -> s <> "" && not (String.contains s '"'))
             (fun v -> Frames_set { scope; frames = List.mapi (fun j (((_, at, size) as f) : fr) ->
               if j = i then (v, at, size) else f) all })))
     | _ -> ());
    if xs.clicked then begin
      emit (Frames_set { scope; frames = List.filteri (fun j _ -> j <> i) all }); t
    end else if ts.double_clicked && t.editing = None then { t with drag = None; editing = Some (Title (scope, i)) }
    else if rs.pressed && left_button rs then
      { t with drag = Some (Sizing { scope; index = i; dw = 0.; dh = 0. }) }
    else match t.drag with
      | None when ts.held && left_button ts && t.editing = None
                  && Float.hypot (fst ts.pointer -. fst ts.press_point) (snd ts.pointer -. snd ts.press_point) > 3. ->
          (* a drag by the title (a click or a double-click stays one): the nodes of the scope
             whose centres lie inside the frame travel with it *)
          let ox, oy = Option.value ~default:(0., 0.) (List.assoc_opt scope t.geo.origins) in
          let _, (fx, fy), (fw, fh) = List.nth (t.frames scope) i in
          let inside path = scope_of_path path = scope && (match Hashtbl.find_opt t.geo.pos path with
            | Some (bx, by, bw, bh) ->
                let cx = bx +. bw /. 2. and cy = by +. bh /. 2. in
                cx >= ox +. fx && cx <= ox +. fx +. fw && cy >= oy +. fy && cy <= oy +. fy +. fh
            | None -> false) in
          let paths = Hashtbl.fold (fun path _ found -> if inside path then path :: found else found) t.geo.pos [] in
          let dx = (fst ts.pointer -. fst ts.press_point) /. z and dy = (snd ts.pointer -. snd ts.press_point) /. z in
          { t with drag = Some (Carrying { scope; index = i; paths; dx; dy }) }
      | Some (Carrying c) when c.scope = scope && c.index = i && (ts.held || ts.released) ->
          let ddx, ddy = ts.drag in
          let t = { t with drag = Some (Carrying { c with dx = c.dx +. ddx /. z; dy = c.dy +. ddy /. z }) } in
          if ts.released then begin
            (match t.drag with
             | Some (Carrying c) when Float.hypot c.dx c.dy > 3. /. z ->
                 emit (Moved (List.filter_map (fun path -> match Hashtbl.find_opt t.geo.rel path with
                   | Some (rx, ry) -> Some (path, rx +. c.dx, ry +. c.dy)
                   | None -> None) c.paths));
                 emit (Frames_set { scope; frames = frame_list t scope })
             | _ -> ());
            { t with drag = None }
          end else t
      | Some (Sizing s) when s.scope = scope && s.index = i && (rs.held || rs.released) ->
          let dx, dy = rs.drag in
          let t = { t with drag = Some (Sizing { scope; index = i; dw = s.dw +. dx /. z; dh = s.dh +. dy /. z }) } in
          if rs.released then begin
            emit (Frames_set { scope; frames = frame_list t scope });
            { t with drag = None }
          end else t
      | _ -> t) t frame_boxes in
  let t = if !finished then { t with editing = None } else t in
  let overlay = Ui.within ui canvas (fun () ->
    Ui.box ui ~w:(Ui.Px (float t.width)) ~h:(Ui.Px (float t.height)) ~at:(0., 0.) "overlay") in
  ignore overlay;
  (* hovered row and chip expansion *)
  let hover = List.find_map (fun ((p : P.placed), ax, ay, tile, _, _, _) ->
    match p.item with
    | P.Item ({ zone = None; _ } as n) when Ui.hovered_within ui tile ->
        let gy = (snd mouse -. sy t 0.) /. z in
        (match row_index n ~ay ~py:gy with
         | Some i when i < List.length n.rows -> Some (n, ax, ay, i)
         | _ -> None)
    | _ -> None) tiles in
  let hovered_row = Option.map (fun ((n : P.node), _, _, i) -> n.path, (List.nth n.rows i).P.key) hover in
  let t = { t with hovered_row } in
  (* interactions *)
  let left (s : Ui.signal) = s.button = Some Input.LeftButton in
  let panning = Array.exists (fun (s : Ui.signal) -> (s.held || s.released) && s.button <> Some Input.LeftButton && s.button <> None)
      (Array.of_list (canvas_signal :: List.map (fun (_, _, _, _, s, _, _) -> s) tiles)) in
  let t = if not panning then t else begin
      let dx, dy = if canvas_signal.held || canvas_signal.released then canvas_signal.drag
        else List.fold_left (fun (dx, dy) (_, _, _, _, (s : Ui.signal), _, _) -> let a, b = s.drag in dx +. a, dy +. b)
            (0., 0.) tiles in
      { t with pan_x = t.pan_x +. dx; pan_y = t.pan_y +. dy }
    end in
  let t = if canvas_signal.pressed && left canvas_signal && t.context = None
    && not (List.exists (fun (_, _, _, _, (s : Ui.signal), _, _) -> s.pressed) tiles)
    then begin
      let additive = List.mem Input.Shift (Ui.press_keys ui canvas) in
      if (not additive) && not (Path_set.is_empty t.selected) then emit (Selected []);
      let base = if additive then t.selected else Path_set.empty in
      { t with selected = base; drag = Some (Marquee { base }) }
    end else t in
  (* the rubber band selects the nodes of one scope it touches *)
  let t = match t.drag with
    | Some (Marquee m) when canvas_signal.held || canvas_signal.released ->
        let px, py = if canvas_signal.released then canvas_signal.release_point else canvas_signal.pointer in
        let x0, y0 = canvas_signal.press_point in
        let rw = abs_float (px -. x0) and rh = abs_float (py -. y0) in
        let selected = if rw < 3. && rh < 3. then m.base
          else Path_set.union m.base (marquee_hits t (Float.min x0 px, Float.min y0 py, rw, rh)) in
        if not (Path_set.equal selected t.selected) then emit (Selected (Path_set.elements selected));
        { t with selected; drag = (if canvas_signal.released then None else t.drag) }
    | _ -> t in
  let lens_next = ref t.lens in
  (* tile presses select and start a move; sockets start a wire *)
  let t = List.fold_left (fun t ((p : P.placed), _, _, tile, (s : Ui.signal), (sub : _), fields) ->
    let outs, dels, taps = sub in
    List.iter emit fields;
    let t =
      if s.pressed && left s && t.context = None then begin
        let additive = List.mem Input.Shift (Ui.press_keys ui tile) in
        let selected = if additive then
            (if Path_set.mem p.path t.selected then Path_set.remove p.path t.selected else Path_set.add p.path t.selected)
          else if Path_set.mem p.path t.selected then t.selected else Path_set.singleton p.path in
        emit (Selected (Path_set.elements selected));
        { t with selected; drag = Some (Moving { paths = parents_removed (Path_set.elements selected);
                                                 dx = 0.; dy = 0.; moved = false }) }
      end else t in
    let t =
      if s.double_clicked && left s && t.context = None && t.editing = None then begin
        let _, top, _, _ = Ui.rect ui tile in
        match p.item with
        | P.Item n when (not n.synthetic) && snd s.release_point < top +. P.head_height *. z ->
            { t with editing = Some (Name p.path) }
        | P.Input _ -> { t with editing = Some (Default p.path) }
        | _ -> t
      end else t in
    let t = match t.drag with
      | Some (Moving m) when s.held && left s && (Path_set.mem p.path t.selected) ->
          let ddx, ddy = s.drag in
          let dx = m.dx +. ddx /. z and dy = m.dy +. ddy /. z in
          { t with drag = Some (Moving { m with dx; dy; moved = m.moved || Float.hypot dx dy > 3. /. z }) }
      | _ -> t in
    let t = match t.drag with
      | Some (Moving m) when s.released && left s ->
          if m.moved then
            emit (Moved (List.filter_map (fun path -> match Hashtbl.find_opt t.geo.rel path with
              | Some (rx, ry) -> Some (path, rx +. m.dx, ry +. m.dy)
              | None -> None) m.paths));
          { t with drag = None }
      | _ -> t in
    (* zone controls *)
    let t = List.fold_left (fun t (b, on) ->
      let bs = Ui.signal ui b in
      (match p.item, on with
       | P.Item n, `Hoist when bs.clicked -> emit (Syntax_edit (E.Hoist { node = n.path }))
       | P.Item n, `Toggle when bs.clicked ->
           emit (Zone_collapsed { zone = n.path; collapsed = not p.collapsed })
       | P.Item n, `Bypass when bs.clicked -> emit (Syntax_edit (E.Toggle_bypass { node = n.path }))
       | P.Item n, `Replace when bs.clicked -> emit (Syntax_edit (E.Inline_macro { node = n.path }))
       | P.Item n, `Lens when bs.clicked ->
           lens_next := if List.mem_assoc n.path !lens_next then List.remove_assoc n.path !lens_next
             else (n.path, (match n.lens with Some l -> Array.length l.steps - 1 | None -> 0)) :: !lens_next
       | P.Item n, `Lens_step i when bs.clicked ->
           lens_next := (n.path, i) :: List.remove_assoc n.path !lens_next
       | P.Item n, `Step d when bs.clicked ->
           let count = count_of t n.path in
           let index = max 0 (min (count - 1) (t.probe n.path + d)) in
           if count > 0 && index <> t.probe n.path then emit (Probe_set { zone = n.path; index })
       | P.Item n, `Track when bs.pressed || bs.held ->
           let count = count_of t n.path in
           let x, _, w, _ = Ui.rect ui b in
           if count > 0 && w > 0. then begin
             let px = fst (if bs.released then bs.release_point else bs.pointer) in
             let index = max 0 (min (count - 1) (int_of_float ((px -. x) /. w *. float count))) in
             if index <> t.probe n.path then emit (Probe_set { zone = n.path; index })
           end
       | _ -> ());
      t) t taps in
    List.iter (fun (b, op) -> if (Ui.signal ui b).clicked then emit (Syntax_edit op)) dels;
    (* wires *)
    let t = List.fold_left (fun t (b, src, ty) ->
      let bs = Ui.signal ui b in
      let t = if bs.pressed && left bs then
          let iter = (match t.scope with
            | Some scope -> List.exists (fun (n : P.node) -> match n.zone with
                | Some zn -> List.exists (fun (r : P.rail_row) -> r.role = P.Var && List.mem src r.names) zn.rail
                | None -> false) (P.zones scope)
            | None -> false) in
          { t with drag = Some (Wiring { src; ty; iter; from = (let x, y, w, h = Ui.rect ui b in x +. w /. 2., y +. h /. 2.) }) }
        else t in
      if bs.released && left bs then begin
        (match t.drag with
         | Some (Wiring w) ->
             let target = List.find_map (fun ((tp : P.placed), tax, tay, ttile, _, _, _) ->
               if not (Ui.hovered_within ui ttile) then None else
               let mx, my = mouse in
               let gx = (mx -. sx t 0.) /. z and gy = (my -. sy t 0.) /. z in
               ignore tax; ignore tay;
               let _, tax, tay = (tp, tax, tay) in
               let lx = gx -. tax and ly = gy -. tay in
               match tp.item with
               | P.Return ->
                   Option.map (fun (s : P.scope) -> s.path @ [ "@result" ], E.Whole) t.scope
               | Input _ -> None
               | Item n ->
                   (match n.zone with
                    | None ->
                        (match row_index n ~ay:0. ~py:ly with
                         | Some i when i < List.length n.rows ->
                             let r = List.nth n.rows i in
                             if r.socket then Some (n.path, r.key) else None
                         | _ -> None)
                    | Some zn ->
                        let base = if tp.collapsed then P.head_height else P.rail_top n in
                        if lx > tp.w -. P.yield_width && (not tp.collapsed) && ly >= base && ly < base +. P.row_height then
                          Some (zn.scope.path @ [ "@result" ], E.Whole)
                        else if lx < P.rail_width || tp.collapsed then begin
                          let i = int_of_float ((ly -. base) /. P.row_height) in
                          match List.nth_opt zn.rail i with
                          | Some { key = Some key; _ } when ly >= base -> Some (n.path, key)
                          | _ -> None
                        end else None)) tiles in
             (match target with
              | Some (node, key) -> emit (Syntax_edit (E.Connect { node; key; src = w.src; iter = w.iter }))
              | None -> emit (Notice "Drop the wire on an input row"))
         | _ -> ());
        { t with drag = None }
      end else t) t outs in
    t) t tiles in
  (* the context menu *)
  let t = match t.context with
    | Some _ -> t
    | None ->
        (match List.find_map (fun ((p : P.placed), _, _, _, (s : Ui.signal), _, _) ->
            if Ui.context_clicked s then Some (s.release_point, p.path) else None) tiles with
         | Some ((x, y), path) ->
             let selected = if Path_set.mem path t.selected then t.selected else Path_set.singleton path in
             { t with context = Some ((x, y), path); selected }
         | None -> t) in
  let t = match t.context with
    | None -> t
    | Some (at, path) ->
        (match Ui.context_menu ui ~at "pxui-scope-context" (context_items t path) with
         | `Open -> t
         | `Dismiss -> { t with context = None }
         | `Pick i ->
             List.iter emit (action_changes t (context_command i));
             { t with context = None }) in
  (* the frame's paint *)
  let drawn_rows = ref 0 and drawn_zones = ref (List.length zones) in
  ignore drawn_zones;
  let selected = t.selected in
  let snapshot = t in
  let row_hover = match hover with Some (n, _, _, i) -> Some (n.path, i) | None -> None in
  Ui.draw ui layer (fun paint (rx, ry, rw, rh) ->
    paint_background paint snapshot ~viewport:(rx, ry, rw, rh) zones);
  List.iter (fun ((p : P.placed), ax, ay, tile, _, _, _) ->
    let path = p.path in
    let isel = Path_set.mem path selected in
    Ui.draw ui tile (fun paint (x, y, w, h) ->
      match p.item with
      | P.Input i -> paint_input paint snapshot ~z ~fs i ~selected:isel (x, y, w, h)
      | Return -> (match snapshot.scope with
          | Some s -> paint_return paint snapshot ~z ~fs s ~selected:isel (x, y, w, h)
          | None -> ())
      | Item n ->
          (match n.zone with
           | Some zn when not p.collapsed ->
               paint_zone_frame paint snapshot ~z ~fs ?footer:(Hashtbl.find_opt footers n.path) n zn ~selected:isel (x, y, w, h)
                 ~probe:(snapshot.probe n.path) ~count:(count_of snapshot n.path)
           | _ ->
               let rh = match row_hover with Some (rp, i) when rp = n.path -> Some i | _ -> None in
               paint_node paint snapshot ~z ~fs ?footer:(Hashtbl.find_opt footers n.path) ?lens_step:(lens_of snapshot n.path) p n ~selected:isel ~row_hover:rh (x, y, w, h)));
    ignore (ax, ay); ignore node_placed; drawn_rows := !drawn_rows) tiles;
  let rows = List.fold_left (fun a ((p : P.placed), _, _, _, _, _, _) -> match p.item with
    | P.Item n -> a + List.length n.rows | _ -> a) 0 tiles in
  let drawn_items = List.length tiles in
  let drawn_zones = List.length zones in
  (* the rubber band and the expanded chip, over the tiles *)
  let band = match t.drag with
    | Some (Wiring w) -> Some w | _ -> None in
  Ui.draw_over ui canvas (fun paint _ ->
    (match band with
     | Some w -> Ui.Paint.line paint ~from_:w.from ~to_:mouse ~width:1.5 (ty_color snapshot w.ty)
     | None -> ());
    (match snapshot.drag with
     | Some (Marquee _) ->
         let x0, y0 = canvas_signal.press_point and mx, my = mouse in
         Ui.Paint.rect paint ~x:(Float.min x0 mx) ~y:(Float.min y0 my) ~w:(abs_float (mx -. x0)) ~h:(abs_float (my -. y0))
           ~fill:(Color.with_alpha snapshot.theme.accent 45) ~stroke:snapshot.theme.accent ()
     | _ -> ());
    (match hover with
     | Some (n, ax, ay, i) ->
         let r = List.nth n.rows i in
         (match r.chip with
          | P.Inline { glyph; text } ->
              let size = fs in
              let full = shown_glyph glyph ^ " " ^ text in
              let w = Ui.Paint.text_width paint ~size full +. 12. *. z in
              let x = sx snapshot (ax +. cell_x) and y = sy snapshot (rows_top n ay +. float i *. P.row_height) in
              if w > (P.node_width -. cell_x -. 8.) *. z then begin
                Ui.Paint.rect paint ~x ~y:(y +. 2. *. z) ~w ~h:(20. *. z) ~radius:3. ~fill:snapshot.theme.input
                  ~stroke:snapshot.theme.accent ();
                Ui.Paint.text paint ~at:(x +. 6. *. z, y +. 6. *. z) ~size ~color:snapshot.theme.foreground full
              end
          | _ -> ())
     | None -> ()));
  let t = { t with stats = { t.stats with drawn_items; drawn_zones; drawn_rows = rows } } in
  (* an opened or stepped expansion panel changes its card's size: lay out again for the next frame *)
  let t = if !lens_next == t.lens then t else relayout { t with lens = !lens_next } in
  t, List.rev !changes

(* ------------------------------------------------------------- test hooks *)

module Private = struct
  let box_of t path = Hashtbl.find_opt t.geo.pos path
    |> Option.map (fun (x, y, w, h) -> sx t x, sy t y, w *. t.zoom, h *. t.zoom)
  let selector t path = Option.map (fun (x, y, w, _) ->
    let z = t.zoom in let top = y +. (P.head_height +. 6.) *. z in
    (x +. 2. *. z, top, 22. *. z, 22. *. z), (x +. 28. *. z, top, (w -. 56. *. z), 22. *. z),
    (x +. w -. 24. *. z, top, 22. *. z, 22. *. z)) (box_of t path)
  let output_socket t path = Hashtbl.find_opt t.geo.pos path
    |> Option.map (fun (x, y, w, _) -> sx t (x +. w), sy t (y +. 12.))
  let row_center t path i =
    match node_of t path, Hashtbl.find_opt t.geo.pos path with
    | Some n, Some (x, y, _, _) ->
        Some (sx t (x +. 100.), sy t (rows_top n y +. (float i +. 0.5) *. P.row_height))
    | _ -> None
  let tile_point t path (dx, dy) (w, h) = Hashtbl.find_opt t.geo.pos path
    |> Option.map (fun (x, y, _, _) -> sx t x +. (dx +. w /. 2.) *. t.zoom, sy t y +. (dy +. h /. 2.) *. t.zoom)
  let lens_toggle t path = match node_of t path, Hashtbl.find_opt t.geo.pos path with
    | Some { lens = Some _; _ }, Some (_, _, w, _) -> tile_point t path (w -. 22., 2.) (20., 20.)
    | _ -> None
  let lens_step_button t path i = match node_of t path, lens_of t path, Hashtbl.find_opt t.geo.pos path with
    | Some { lens = Some l; _ }, Some step, Some (_, _, _, h) when i <= Array.length l.steps ->
        let (bx, by), size = lens_button_box ~len:(Array.length l.steps) i in
        tile_point t path (bx, h -. P.lens_height l ~step +. by) size
    | _ -> None
  let lens_replace t path = match node_of t path, lens_of t path, Hashtbl.find_opt t.geo.pos path with
    | Some { lens = Some l; _ }, Some step, Some (_, _, _, h) ->
        let lh = P.lens_height l ~step in
        let (rx, ry), size = lens_replace_box lh in
        tile_point t path (rx, h -. lh +. ry) size
    | _ -> None
  let bypass_flag t path = match node_of t path with
    | Some n when bypassable n -> tile_point t path (22., 4.) (18., 16.)
    | _ -> None
  let _ = contains
end
