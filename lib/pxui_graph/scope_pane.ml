(* The graph pane of a workspace document: draws one
   [Flow_graph.Projection.scope] with its zones, rails, iteration selectors,
   chips and output rows on the shared PXUI handle, and returns typed
   requests.  It never edits: a gesture is a [Flow_edit.op] the host reduces.
   Every interactive element is a [Ui.box]; a tile's row under the pointer is
   found from the pointer and the tile's rectangle, not from a second hit
   tree. *)
open Rays
module P = Flow_graph.Projection
module E = Flow_graph.Flow_edit
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
  | Level_set of (path * P.level option * bool) list
      (** nodes opened or pointed: their new level ([None]: back to the default, [Card]) and
          whether it is pinned (it then ignores the zoom caps) *)
  | Copy_requested of path list  (** the host puts these bindings' text on the clipboard *)
  | Paste_requested  (** the host adds the clipboard's bindings here *)
  | Menu_requested of float * float  (** a right-click on empty canvas: the host opens its add menu there *)
  | Open_import of string
  | Macro_requested of path list  (** the host opens the make-macro dialog over these nodes *)
  | Defn_requested of path list  (** the host types the outside names and writes the [defn] *)
  | Frames_set of { scope : path; frames : (string * (float * float) * (float * float)) list }
      (** the frames of one scope after a gesture (create, resize, retitle, delete) *)
  | Display_set of path  (** preview this geometry node in the viewport, or this drawing or image node in the canvas panes, at the zone selectors *)
  | Activated of path
  | Drop_over of { path : path; kind : string; value : string }
  | Dropped of { path : path; kind : string; value : string }
  | Notice of string

type direction = Left | Down | Up | Right
type command =
  | Delete | Fold_into | Unfold | Hoist | Bypass | Wrap_repeat | Wrap_iterate | Wrap_if | Add_arm | Delete_arm | Make_fn | Make_macro | Make_defn
  | Collapse | Probe_step of int | Frame_all | Walk of direction
  | Edit_name  (** rename the selected node, or edit the default of a selected graph input *)
  | Item_up | Item_down  (** move the hovered list item *)
  | Make_frame  (** a titled frame around the selected nodes *)
  | Duplicate | Display | Copy | Cut | Paste
  | Frame_selection  (** [f]: pan and zoom to the selected nodes (all, with none selected) *)
  | Open_level  (** [o]: the selection one level more detailed, pinned *)
  | Point_level  (** [p]: the selection to points, or back to its previous level *)
  | Open_all  (** [⇧O]: every node to card *)
  | Point_all  (** [⇧K]: every node to a point, or every node back *)
  | Show_hints  (** [w]: letter hints; a letter connects the selected node's output *)

type stats = {
  nodes : int; zones : int; rows : int;
  drawn_items : int; drawn_zones : int; drawn_rows : int;
}

(* ------------------------------------------------------------ geometry *)

(* tables by path: the last segment is hashed (it names the node; the ones before it its scopes),
   and segments are compared as strings, so no lookup walks a path polymorphically *)
let path_equal (a : path) (b : path) = a == b || List.equal String.equal a b
module Paths = Hashtbl.Make (struct
  type t = path
  let equal = path_equal
  let rec hash : t -> int = function [] -> 0 | [ leaf ] -> Hashtbl.hash leaf | _ :: rest -> hash rest
end)

(* a wire's route by its ends and the cards it may cross: floats and paths, compared as such *)
module Routes = Hashtbl.Make (struct
  type t = (float * float) * (float * float) * path list
  let equal (((ax, ay), (bx, by), a) : t) (((cx, cy), (dx, dy), b) : t) =
    Float.equal ax cx && Float.equal ay cy && Float.equal bx dx && Float.equal by dy && List.equal path_equal a b
  let hash (((ax, ay), (bx, by), _) : t) = Hashtbl.hash (ax, ay, bx, by)
end)

(* bucket grids are keyed by cell *)
module Cells = Hashtbl.Make (Int)

(* a cell's key: one int (cells are far fewer than 32768 high) *)
let cell_key cx cy = cx * 65536 + cy

(* ---- what is in view: a bucket grid over boxes (the tiles, the wires' bounds), built once per
   geometry, so a frame asks the cells its viewport covers and not every node of the graph ---- *)

type index = { buckets : int list Cells.t; large : int list }  (* a box over many cells is asked every time *)

let index_cell = 256.
let index_of n box =
  let buckets = Cells.create 64 and large = ref [] in
  let c v = int_of_float (Float.floor (v /. index_cell)) in
  for i = n - 1 downto 0 do
    let x0, y0, x1, y1 = box i in
    if (c x1 - c x0 + 1) * (c y1 - c y0 + 1) > 64 then large := i :: !large
    else
      for cx = c x0 to c x1 do
        for cy = c y0 to c y1 do
          let key = cell_key cx cy in
          Cells.replace buckets key (i :: Option.value ~default:[] (Cells.find_opt buckets key))
        done
      done
  done;
  { buckets; large = !large }

(* the boxes that may meet the rectangle, in index order, each once *)
let index_query ix (x0, y0, x1, y1) =
  let c v = int_of_float (Float.floor (v /. index_cell)) in
  let found = ref ix.large in
  if (c x1 - c x0 + 1) * (c y1 - c y0 + 1) >= Cells.length ix.buckets then
    Cells.iter (fun _ l -> found := List.rev_append l !found) ix.buckets
  else
    for cx = c x0 to c x1 do
      for cy = c y0 to c y1 do
        match Cells.find_opt ix.buckets (cell_key cx cy) with
        | Some l -> found := List.rev_append l !found
        | None -> ()
      done
    done;
  List.sort_uniq Int.compare !found

type src = { pos : float * float; ty : Ty.t option; owner : path option }
type wire = {
  a : float * float; b : float * float; ty : Ty.t option;
  target : (path * E.arg_key * S.t option) option;
  pts : (float * float) list;  (* the drawn polyline, [a] .. [b]: straight, or bent clear of the cards *)
  dashed : bool;  (* a loop's feedback *)
}

type obstacle = { path : path; rx : float; ry : float; rw : float; rh : float }

type geo = {
  items : (P.placed * float * float) array;  (* absolute top-left, graph units *)
  wires : wire array;
  origins : (path * (float * float)) list;  (* where each scope's own coordinates start *)
  obstacles : obstacle list;  (* what the routes were drawn around *)
  inside : (path, int list) Hashtbl.t;  (* the wires that end at a node of a zone's body, by the zone's path *)
  slot : int Paths.t;  (* an item's place in [items]: its box and its position inside its scope come from there *)
  tiles : index;  (* over the items' boxes *)
  reach : index;  (* over the wires' bounds *)
  read : (float * float, unit) Hashtbl.t;  (* the points a wire starts from: an out-port there is wired *)
  routes : (float * float) list Routes.t;
      (* each wire's route by its ends: a rebuild around the same obstacles (a number scrubbed, a
         name edited) reuses them; one entry, replaced by every rebuild *)
}

let empty_geo = { items = [||]; wires = [||]; origins = []; obstacles = [];
                  inside = Hashtbl.create 1; slot = Paths.create 1; tiles = { buckets = Cells.create 1; large = [] };
                  reach = { buckets = Cells.create 1; large = [] }; read = Hashtbl.create 1; routes = Routes.create 1 }
let root_name s = match String.index_opt s '.' with Some i -> String.sub s 0 i | None -> s
(* what a row reads once its wire is taken off: a named argument goes back to its schema default,
   written so the row stays on the card; a positional one takes a value of its type; an item of a
   variadic input goes (nothing is written in its place) *)
let fallback (r : P.row) = match r.key with
  | _ when r.kind = P.Rest -> None
  | E.Kw _ | E.Field _ ->
      Option.bind r.default (fun d -> match Flow.Syntax.parse d with Ok [ form ] -> Some form | _ -> None)
  | _ -> Option.bind r.ty (fun ty -> E.default_for ty r.label)

(* the sheet's wire ends: a header port's wire runs 1.5 points from y + 11, a row port's from the
   row's centre line (kit [.wire], measured on graph@2x.png) *)
let wire_head_y = 11.75
let wire_row_y = 12.75

let note_rows (n : P.node) = if n.note <> None then 1. else 0.
let rows_top (n : P.node) ay = ay +. P.body_top +. note_rows n *. P.row_height

(* where the rows are: the line each row of a card sits on, by row index *)
let line_of_row (lines : P.line array) =
  let tbl = Hashtbl.create 8 in
  Array.iteri (fun k -> function P.Row (i, _) -> Hashtbl.replace tbl i k | _ -> ()) lines;
  tbl

(* ---- wire routing: straight, or bent clear of every card ---- *)

(* a bucket grid over the cards: a wire asks only the cells its box crosses *)
type grid = { cell : float; cells : obstacle list Cells.t }

let grid_of obstacles =
  let cell = 128. in
  let cells = Cells.create 64 in
  List.iter (fun o ->
    for cx = int_of_float (Float.floor (o.rx /. cell)) to int_of_float (Float.floor ((o.rx +. o.rw) /. cell)) do
      for cy = int_of_float (Float.floor (o.ry /. cell)) to int_of_float (Float.floor ((o.ry +. o.rh) /. cell)) do
        Cells.replace cells (cell_key cx cy) (o :: Option.value ~default:[] (Cells.find_opt cells (cell_key cx cy)))
      done
    done) obstacles;
  { cell; cells }

(* the part of a segment inside a rectangle, as the parameters of its two ends (Liang-Barsky);
   [t0 > t1] when it misses.  The one clip of the pane: routing asks whether a wire crosses a card,
   painting and the hit boxes cut a wire to what is shown (the GPU's diagonal line ignores the
   clip of the box that paints it). *)
let clip_span x0 y0 x1 y1 ~xmin ~ymin ~xmax ~ymax =
  let dx = x1 -. x0 and dy = y1 -. y0 in
  let t0 = ref 0. and t1 = ref 1. and ok = ref true in
  let clip p q =
    if p = 0. then (if q < 0. then ok := false)
    else begin
      let r = q /. p in
      if p < 0. then (if r > !t1 then ok := false else if r > !t0 then t0 := r)
      else if r < !t0 then ok := false else if r < !t1 then t1 := r
    end in
  clip (-. dx) (x0 -. xmin); clip dx (xmax -. x0); clip (-. dy) (y0 -. ymin); clip dy (ymax -. y0);
  if !ok then !t0, !t1 else 1., 0.

let clip_segment (x0, y0) (x1, y1) (rx, ry, rw, rh) =
  let t0, t1 = clip_span x0 y0 x1 y1 ~xmin:rx ~ymin:ry ~xmax:(rx +. rw) ~ymax:(ry +. rh) in
  if t0 <= t1 then Some ((x0 +. (x1 -. x0) *. t0, y0 +. (y1 -. y0) *. t0), (x0 +. (x1 -. x0) *. t1, y0 +. (y1 -. y0) *. t1))
  else None

(* does the segment cross the rectangle grown by [margin]? *)
let crosses (x0, y0) (x1, y1) o ~margin =
  let xmin = o.rx -. margin and xmax = o.rx +. o.rw +. margin
  and ymin = o.ry -. margin and ymax = o.ry +. o.rh +. margin in
  (* the segment's box misses the rectangle: no need for the clip *)
  if Float.max x0 x1 < xmin || Float.min x0 x1 > xmax || Float.max y0 y1 < ymin || Float.min y0 y1 > ymax then false else
  let t0, t1 = clip_span x0 y0 x1 y1 ~xmin ~ymin ~xmax ~ymax in
  t0 <= t1

let blockers grid ~excl p q =
  let x0, y0 = p and x1, y1 = q in
  let c v = int_of_float (Float.floor (v /. grid.cell)) in
  let found = ref [] in
  for cx = c (Float.min x0 x1) to c (Float.max x0 x1) do
    for cy = c (Float.min y0 y1) to c (Float.max y0 y1) do
      List.iter (fun o ->
        if crosses p q o ~margin:2. && not (List.memq o !found) && not (List.mem o.path excl) then found := o :: !found)
        (Option.value ~default:[] (Cells.find_opt grid.cells (cell_key cx cy)))
    done
  done;
  !found

(* is anything in the way?  The same walk, stopping at the first card *)
exception Blocked
let is_blocked ?(margin = 2.) grid ~excl p q =
  let x0, y0 = p and x1, y1 = q in
  let c v = int_of_float (Float.floor (v /. grid.cell)) in
  try
    for cx = c (Float.min x0 x1) to c (Float.max x0 x1) do
      for cy = c (Float.min y0 y1) to c (Float.max y0 y1) do
        List.iter (fun o ->
          if crosses p q o ~margin && not (List.mem o.path excl) then raise Blocked)
          (Option.value ~default:[] (Cells.find_opt grid.cells (cell_key cx cy)))
      done
    done;
    false
  with Blocked -> true

let length pts =
  let rec go acc = function
    | (x0, y0) :: ((x1, y1) :: _ as rest) -> go (acc +. Float.hypot (x1 -. x0) (y1 -. y0)) rest
    | _ -> acc in
  go 0. pts

(* A wire is one straight segment, port to port.  One that would pass under a card gets one bend
   (a 5-point square), as box1 -> copy1.template does in the sheet: horizontal out of the source,
   then one diagonal into the port, the bend 72 points before the target; or, when that is not
   clear, the diagonal first and the horizontal into the port.  A backward wire goes round above or
   below. *)
let route grid ~excl ((ax, ay) as a) ((bx, by) as b) =
  let free ?margin pts =
    let rec go = function
      | p :: (q :: _ as rest) -> (not (is_blocked ?margin grid ~excl p q)) && go rest
      | _ -> true in
    go pts in
  let forward = bx > ax +. 8. in
  if forward && free [ a; b ] then [ a; b ]
  else if forward then begin
    let room = bx -. ax -. 24. in
    let steps = 72. :: List.filter (fun d -> d <> 72.) (List.init 12 (fun k -> 24. *. float (k + 1))) in
    let candidates = List.concat_map (fun d ->
      if d > room then [] else [ [ a; (bx -. d, ay); b ]; [ a; (ax +. d, by); b ] ]) steps in
    match List.find_opt (free ~margin:6.) candidates with
    | Some c -> c
    | None ->
        (match List.find_opt free candidates with
         | Some c -> c
         | None ->
             (* no one-bend way: round the cards above or below, 24 points clear *)
             let hit = blockers grid ~excl a b in
             let top = List.fold_left (fun m o -> Float.min m o.ry) (Float.min ay by) hit -. 24.
             and bottom = List.fold_left (fun m o -> Float.max m (o.ry +. o.rh)) (Float.max ay by) hit +. 24. in
             let round y = [ a; (ax +. 24., y); (bx -. 24., y); b ] in
             let around = [ round top; round bottom ] in
             (match List.filter free around with
              | [] -> [ a; b ]
              | c :: rest -> List.fold_left (fun best c -> if length c < length best then c else best) c rest))
  end else begin
    let hit = blockers grid ~excl (Float.min ax bx, Float.min ay by) (Float.max ax bx, Float.max ay by) in
    let top = List.fold_left (fun m o -> Float.min m o.ry) (Float.min ay by) hit -. 24.
    and bottom = List.fold_left (fun m o -> Float.max m (o.ry +. o.rh)) (Float.max ay by) hit +. 24. in
    let candidates =
      [ [ a; (ax +. 24., ay); (ax +. 24., top); (bx -. 24., top); (bx -. 24., by); b ];
        [ a; (ax +. 24., ay); (ax +. 24., bottom); (bx -. 24., bottom); (bx -. 24., by); b ] ] in
    match List.filter free candidates with
    | [] -> List.hd (List.rev candidates)
    | clear -> List.fold_left (fun best c -> if length c < length best then c else best) (List.hd clear) clear
  end

(* the old orthogonal style, kept for [:wires "rect"] *)
let rect_points (ax, ay) (bx, by) =
  let mx = if bx >= ax +. 24. then (ax +. bx) /. 2. else ax +. 12. in
  if bx >= ax +. 24. then [ (ax, ay); (mx, ay); (mx, by); (bx, by) ]
  else [ (ax, ay); (mx, ay); (mx, (ay +. by) /. 2.); (bx -. 12., (ay +. by) /. 2.); (bx -. 12., by); (bx, by) ]

(* where a card's out-port wire starts, a node's rows are read and a zone's rail rows end *)
let out_anchor (p : P.placed) ax ay =
  if p.shown = P.Point then ax +. p.w, ay +. P.point_size /. 2. else ax +. p.w, ay +. wire_head_y
let in_anchor (p : P.placed) ax ay =
  if p.shown = P.Point then ax, ay +. P.point_size /. 2. else ax, ay +. wire_head_y

(* the level a card is drawn at: the one it was given, at every zoom.  A zone, the return card
   and a frame keep their card. *)
let shown_of (p : P.placed) = match p.item with
  | P.Item { zone = Some _; _ } | P.Return -> P.Card
  | P.Item _ | P.Input _ -> p.level

(* a point's box: the disc and its name; its wires meet the disc on the left and the name's end on
   the right *)
let point_name (p : P.placed) = match p.item with
  | P.Item n -> P.point_title n | P.Input i -> i.name | P.Return -> "return"
(* [name_w] is the name's real width in graph units at the font the zoom draws it in *)
let point_box_w ~name_w name = P.point_size +. 8. +. name_w name

(* [shift] moves a placed item by its path (a drag in progress); a zone's
   children follow through the origin they are laid out from. *)
let compute ?(style = `Straight) ?(previous = empty_geo) ~name_w ~shown (scope : P.scope) (layout : P.layout) ~shift =
  let items = ref [] and count = ref 0 and slot = Paths.create 64 in
  let origins = ref [ (scope.path, (0., 0.)) ] in
  let rec walk ox oy (l : P.layout) =
    List.iter (fun (p : P.placed) ->
      let dx, dy = shift p.path in
      let ax = ox +. p.x +. dx and ay = oy +. p.y +. dy in
      (* one geometry per node at the level it is shown: the box, the ports and the wires' ends,
         the obstacles and the hit boxes all come from it *)
      let lv = shown p in
      let p, ay = match lv with
        | P.Point -> { p with shown = lv; w = point_box_w ~name_w (point_name p); h = P.point_size },
                     if p.level = P.Point && (match p.item with P.Input _ -> false | _ -> true)
                     then ay else ay +. 5.
        | P.Chip -> { p with shown = lv; h = P.head_height }, ay
        | _ -> { p with shown = lv }, ay in
      Paths.replace slot p.path !count; incr count;
      items := (p, ax, ay) :: !items;
      match p.inner, p.item with
      | Some inner, P.Item n ->
          origins := (n.path, (ax +. P.zone_pad_x, ay +. P.rail_top n)) :: !origins;
          walk (ax +. P.zone_pad_x) (ay +. P.rail_top n) inner
      | _ -> ()) l.placed in
  walk 0. 0. layout;
  let items_list = List.rev !items in
  let obstacles = List.concat_map (fun ((p : P.placed), ax, ay) -> match p.item with
    | P.Item { zone = Some _; _ } when not p.collapsed ->
        (* an expanded zone's label row is in the way, and its bottom edge (no wire runs along it);
           its inside is not *)
        [ { path = p.path; rx = ax; ry = ay; rw = p.w; rh = P.head_height };
          { path = p.path; rx = ax; ry = ay +. p.h -. 3.; rw = p.w; rh = 6. } ]
    | _ -> [ { path = p.path; rx = ax; ry = ay; rw = p.w; rh = p.h } ]) items_list in
  let grid = grid_of obstacles in
  let same (a : obstacle) (b : obstacle) =
    Float.equal a.rx b.rx && Float.equal a.ry b.ry && Float.equal a.rw b.rw && Float.equal a.rh b.rh && path_equal a.path b.path in
  let reuse = if List.equal same previous.obstacles obstacles then previous.routes else Routes.create 1 in
  let routes = Routes.create (max 16 (Routes.length reuse)) in
  let wires = ref [] in
  let wire ?target ?(dashed = false) (s : src option) b ~into =
    match s with
    | Some s ->
        let excl = (match s.owner with Some o -> [ o ] | None -> []) @ into in
        let pts = match style with
          | `Straight ->
              let key = (s.pos, b, excl) in
              let pts = match Routes.find_opt reuse key with Some pts -> pts | None -> route grid ~excl s.pos b in
              Routes.replace routes key pts; pts
          | `Rect -> rect_points s.pos b in
        wires := { a = s.pos; b; ty = s.ty; target; pts; dashed } :: !wires
    | None -> () in
  let resolve chain name =
    List.find_map (fun tbl -> match Hashtbl.find_opt tbl name with
      | Some s -> Some s | None -> Hashtbl.find_opt tbl (root_name name)) chain in
  let names_of (e : S.t option) = match e with Some e -> E.free_names e | None -> [] in
  let items = Array.of_list items_list in
  let at path : (P.placed * float * float) option = Option.map (fun i -> items.(i)) (Paths.find_opt slot path) in
  (* a plain [for] has no out-port of its own: what it yields wires from the yielded card *)
  let inner_out (n : P.node) = match n.zone with
    | Some ({ kind = P.For; _ } as z) when (match at n.path with Some (p, _, _) -> not p.collapsed | None -> true) ->
        let target = match z.scope.result with
          | P.Link l -> List.find_opt (fun (m : P.node) -> List.mem (root_name l) m.binds) z.scope.nodes
                        |> Option.map (fun (m : P.node) -> m.path)
          | P.Node p -> Some p | P.Literal _ -> None in
        Option.bind target (fun path -> Option.map (fun (p, ax, ay) -> out_anchor p ax ay, path) (at path))
    | _ -> None in
  let declared (s : P.scope) =
    let tbl = Hashtbl.create 16 in
    List.iter (fun (i : P.input) -> match at i.path with
      | Some (p, ax, ay) ->
          Hashtbl.replace tbl i.name { pos = out_anchor p ax ay; ty = Some i.ty; owner = Some i.path }
      | _ -> ()) s.inputs;
    List.iter (fun (n : P.node) -> match at n.path with
      | Some (p, ax, ay) ->
          let w = p.w in
          let lines = Array.length p.lines in
          let main, main_owner = match inner_out n with
            | Some (pos, owner) -> pos, owner
            | None -> out_anchor p ax ay, n.path in
          (* a point or a chip has the one out end; its named outputs are listed on a card *)
          let out j = if p.shown = P.Point || p.shown = P.Chip then main
            else (ax +. w, rows_top n ay +. (float (lines + j) +. 0.5) *. P.row_height +. 0.75) in
          (match n.binds with
           | [ b ] when b = n.name ->
               Hashtbl.replace tbl b { pos = main; ty = Some n.ty; owner = Some main_owner };
               List.iteri (fun j (f, ty) ->
                 Hashtbl.replace tbl (b ^ "." ^ f) { pos = out j; ty = Some ty; owner = Some n.path }) n.outputs
           | _ -> List.iteri (fun j (f, ty) ->
               Hashtbl.replace tbl f { pos = out j; ty = Some ty; owner = Some n.path }) n.outputs)
      | _ -> ()) s.nodes;
    tbl in
  let rec scope_wires chain (s : P.scope) =
    let chain = declared s :: chain in
    List.iter (fun (n : P.node) -> match at n.path with
      | Some (p, ax, ay) ->
          let w = p.w in
          (match n.zone with
           | None ->
               let lines = line_of_row p.lines in
               List.iteri (fun i (r : P.row) ->
                 let target_pos =
                   if r.head then in_anchor p ax ay
                   else match p.shown with
                     | P.Point | P.Chip -> in_anchor p ax ay
                     | _ ->
                         (match Hashtbl.find_opt lines i with
                          | Some k -> ax, rows_top n ay +. float k *. P.row_height +. wire_row_y
                          | None -> ax, ay +. wire_head_y) in
                 (* a binding cannot read itself: a name that resolves to this node is one from outside
                    its scope (a [ref] to a graph of the same name), not a wire *)
                 (match P.sources r with
                  | [] -> ()
                  | names ->
                      (* the fallback parses the row's default: only for a row that is wired *)
                      let target = Some (n.path, r.key, fallback r) in
                      List.iter (fun name -> match resolve chain name with
                        | Some { owner = Some o; _ } when o = n.path -> ()
                        | src -> wire ?target src target_pos ~into:[ n.path ]) names)) n.rows
           | Some z ->
               let collapsed = p.collapsed in
               let label = P.label_row z in
               let extras = P.extra_rails z in
               let rail_pos (r : P.rail_row) =
                 if collapsed then
                   let i = Option.value ~default:0 (List.find_index (fun x -> x == r) z.rail) in
                   ax, ay +. P.body_top +. float i *. P.row_height +. wire_row_y
                 else match label with
                   | Some l when l == r -> ax, ay +. wire_head_y
                   | _ ->
                       let i = Option.value ~default:0 (List.find_index (fun x -> x == r) extras) in
                       ax, ay +. P.head_height +. float i *. P.row_height +. wire_row_y in
               List.iter (fun (r : P.rail_row) ->
                 let plain_label = not collapsed && z.kind = P.For && (match label with Some l -> l == r | None -> false) in
                 if (collapsed || r.role <> P.Capture) && not plain_label then begin
                   let names = if r.role = P.Capture then [ r.name ] else names_of r.expr in
                   let target = match r.key with Some key -> Some (n.path, key, None) | None -> None in
                   List.iter (fun name -> wire ?target (resolve chain name) (rail_pos r) ~into:[ n.path ]) names
                 end) z.rail;
               if not collapsed then begin
                 (* the loop's variables: a port in the zone's left strip (the label's), or at the
                    right of the rail row *)
                 let rail = Hashtbl.create 8 in
                 List.iter (fun (r : P.rail_row) ->
                   if r.role <> P.Capture then begin
                     let pos = match label with
                       | Some l when l == r -> ax +. 12., ay +. 36.
                       | _ ->
                           let i = Option.value ~default:0 (List.find_index (fun x -> x == r) extras) in
                           ax +. w -. 12., ay +. P.head_height +. float i *. P.row_height +. wire_row_y in
                     let s = { pos; ty = r.ty; owner = Some n.path } in
                     List.iter (fun name -> Hashtbl.replace rail name s) r.names
                   end) z.rail;
                 let inner = rail :: chain in
                 scope_wires inner z.scope;
                 let inner_chain = declared z.scope :: inner in
                 let source = match z.scope.result with
                   | P.Link l -> resolve inner_chain l
                   | P.Node _ -> resolve inner_chain "@result"
                   | P.Literal _ -> None in
                 (* the collected result ends at the zone's own out-port; a fold or scan feeds it
                    back to its accumulator, dashed *)
                 if z.kind <> P.For then wire source (ax +. w, ay +. wire_head_y) ~into:[ n.path ];
                 (match List.find_opt (fun (r : P.rail_row) -> r.role = P.Acc) z.rail with
                  | Some acc ->
                      (match Hashtbl.find_opt rail acc.name, source with
                       | Some target, Some src -> wire ~dashed:true (Some src) target.pos ~into:[ n.path ]
                       | _ -> ())
                  | None -> ())
               end)
      | _ -> ()) s.nodes in
  scope_wires [] scope;
  (match scope.inputs with
   | [] -> ()
   | _ ->
       let chain = [ declared scope ] in
       (match at (scope.path @ [ "@return" ]) with
        | Some (_, ax, ay) ->
            let source = match scope.result with
              | P.Link l -> resolve chain l
              | P.Node _ -> resolve chain "@result"
              | P.Literal _ -> None in
            let target = (ax, ay +. P.body_top +. wire_row_y) in
            wire source target ~into:[ scope.path @ [ "@return" ] ]
        | None -> ()));
  let wires = Array.of_list (List.rev !wires) in
  let inside = Hashtbl.create 16 in
  Array.iteri (fun i w -> match w.target with
    | Some (_ :: _ :: _ :: _ as path, _, _) ->
        let zone = List.rev (List.tl (List.rev path)) in
        Hashtbl.replace inside zone (i :: Option.value ~default:[] (Hashtbl.find_opt inside zone))
    | _ -> ()) wires;
  let tiles = index_of (Array.length items) (fun i -> let (p : P.placed), ax, ay = items.(i) in ax, ay, ax +. p.w, ay +. p.h) in
  let reach = index_of (Array.length wires) (fun i ->
    List.fold_left (fun (x0, y0, x1, y1) (x, y) -> Float.min x0 x, Float.min y0 y, Float.max x1 x, Float.max y1 y)
      (infinity, infinity, neg_infinity, neg_infinity) wires.(i).pts) in
  let read = Hashtbl.create (max 16 (Array.length wires)) in
  Array.iter (fun (w : wire) -> Hashtbl.replace read w.a ()) wires;
  { items; wires; origins = !origins; obstacles; inside; slot; tiles; reach; read; routes }

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
             | Output of path  (* the name of a new output, over the [+ output] row of a [values] *)

type fr = string * (float * float) * (float * float)

(* letter hints (flow.md 7.5): [w] labels every input the selected node's output can connect to *)
type hint_target = { label : string; node : path; key : E.arg_key option; pos : float * float }
type hinting = { src : string; src_ty : Ty.t; typed : string; targets : hint_target list; stage : path option; armed : bool }

type t = {
  x : int; y : int; width : int; height : int;
  theme : Pxui.theme; guide : bool;
  key : string;
  scope : P.scope option;
  imported : path -> string option;
  at : path -> (float * float) option;
  level_at : path -> (P.level * bool) option;  (* a node's saved level and whether it is pinned *)
  pin_at : path -> string -> bool option;  (* a node's row pinned onto (or off) its card, by label *)
  collapsed : path -> bool;
  lens : (path * int) list;  (* macro calls whose expansion panel is open, and its step *)
  probe : path -> int;
  records : Flow_graph.Probe.t option;
  chains : (path, path list) Hashtbl.t;  (* the iterating zones around each node *)
  folds : (path * int, path) Hashtbl.t;  (* a wired row (node, row index) whose one source can fold into it: that node *)
  counts : (path, int) Hashtbl.t;  (* iterations each zone ran, under the probes *)
  frames : path -> (string * (float * float) * (float * float)) list;
  display : path option;  (* the node the viewport shows instead of the graph's result *)
  framed : bool;
  layout : P.layout;
  geo : geo;
  geo_fs : int;  (* the font size point names were measured at *)
  pan_x : float; pan_y : float; zoom : float;
  wires : [ `Rect | `Straight ];
  selected : Path_set.t;
  selected_wire : (path * E.arg_key * S.t option) option;
  panning_grab : bool;
  hovered_row : (path * E.arg_key) option;
  highlighted : wire list;
  drag : drag option;
  editing : editing option;
  context : ((float * float) * path) option;
  stats : stats;
  switches : (path * int) list;  (* the [ui/switch] nodes and their active layout *)
  carry_lit : (path * string) list;  (* the places a carried payload can be put, with their letters *)
  carry_hot : (path * bool) option;  (* the place under the pointer, and whether it takes the payload *)
  failed : (path * string) list;  (* nodes a cook or the checker refused, with the diagnostic's code *)
  hinting : hinting option;
  held : Input.key list * bool;  (* keys and any button held last frame: a press is a change *)
  back : (path * P.level) list;  (* the level a node had before [p] pointed it *)
  measure : int -> string -> float;  (* text width in points, from the last built frame *)
}

(* the geometry of the scope *)
let font_of zoom = max 5 (int_of_float (Float.round (13. *. zoom)))
let regeo t scope layout ~shift =
  let fs = font_of t.zoom in
  { t with geo_fs = fs;
    geo = compute ~style:t.wires ~previous:t.geo ~name_w:(fun s -> t.measure fs s /. t.zoom) ~shown:shown_of scope layout ~shift }

let no_stats = { nodes = 0; zones = 0; rows = 0; drawn_items = 0; drawn_zones = 0; drawn_rows = 0 }
let create ?(x = 0) ?(y = 0) ?(width = 640) ?(height = 360) ?(theme = Pxui.default_theme) () = {
  x; y; width; height; theme; guide = false; key = ""; scope = None; imported = (fun _ -> None);
  at = (fun _ -> None); level_at = (fun _ -> None); pin_at = (fun _ _ -> None); collapsed = (fun _ -> false); lens = []; probe = (fun _ -> 0); records = None;
  chains = Hashtbl.create 1; folds = Hashtbl.create 1; counts = Hashtbl.create 1;
  frames = (fun _ -> []); display = None; framed = true;
  layout = { P.placed = []; w = 0.; h = 0. }; geo = empty_geo; geo_fs = 13; pan_x = 12.; pan_y = 12.; zoom = 1.;
  wires = `Straight; selected = Path_set.empty; selected_wire = None; panning_grab = false;
  hovered_row = None; highlighted = []; drag = None; editing = None; context = None; stats = no_stats; switches = [];
  carry_lit = []; carry_hot = None; failed = []; hinting = None; held = [], false; back = [];
  measure = (fun size s -> 0.6 *. float (size * String.length s)) }

let with_bounds ~x ~y ~width ~height t =
  if t.x = x && t.y = y && t.width = width && t.height = height then t
  else { t with x; y; width; height }
(* the pane is not drawn this frame: nothing it began stays open, and the pointer is given back *)
let suspend t =
  if t.panning_grab then ignore (Rays.Sketch.set_relative_mouse false);
  if t.editing = None && t.hinting = None && t.drag = None && t.context = None && not t.panning_grab && t.highlighted = [] then t
  else { t with editing = None; hinting = None; drag = None; context = None; highlighted = []; panning_grab = false }
let with_guide guide t = if t.guide = guide then t else { t with guide }
let with_theme theme t = if t.theme == theme then t else { t with theme }
let with_failed failed t = if t.failed = failed then t else { t with failed }
let with_carry ~lit ~hot t =
  if t.carry_lit = lit && t.carry_hot = hot then t else { t with carry_lit = lit; carry_hot = hot }
let selected t = Path_set.elements t.selected
let editing t = t.editing <> None || t.hinting <> None
let select paths t = { t with selected = Path_set.of_list paths; selected_wire = None }
let clear_selection t =
  if Path_set.is_empty t.selected && t.selected_wire = None then t
  else { t with selected = Path_set.empty; selected_wire = None }
let stats t = t.stats
let zoom t = t.zoom
let with_wires wires t =
  if t.wires = wires then t else match t.scope with
    | None -> { t with wires }
    | Some scope -> regeo { t with wires } scope t.layout ~shift:(fun _ -> 0., 0.)

(* a screen point as a position inside [scope], snapped to the 24-point dot lattice (where a node
   added from the menu opened there goes) *)
let scope_point t ~scope (mx, my) =
  Option.map (fun (ox, oy) ->
    let snap = P.snap in
    snap ((mx -. float t.x -. t.pan_x) /. t.zoom -. ox), snap ((my -. float t.y -. t.pan_y) /. t.zoom -. oy))
    (List.assoc_opt scope t.geo.origins)

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
  (* whole points, so the hairlines of the cards land on pixels *)
  { t with zoom; pan_x = Float.round ((float t.width -. w *. zoom) /. 2.);
    pan_y = Float.round (Float.max 8. ((float t.height -. h *. zoom) /. 2.)) }

let count_of t path = Option.value ~default:0 (Hashtbl.find_opt t.counts path)

(* the iteration counts follow the scope, the probes and what was recorded *)
let refresh t = match t.scope, t.records with
  | Some scope, Some records ->
      let counts = Hashtbl.create 16 in
      List.iter (fun (p, c) -> Hashtbl.replace counts p c) (Flow_graph.Probe.counts records scope ~probe:t.probe);
      { t with counts }
  | _ -> { t with counts = Hashtbl.create 1 }

let no_shift _ = 0., 0.
let lens_of t path = List.assoc_opt path t.lens

(* the cards reserve a footer row once the host has probe records to show *)
let lay t scope ~at ~collapsed =
  P.layout ~foot:(t.records <> None) ~at ~collapsed ~lens:(lens_of t)
    ~level:(fun p -> match t.level_at p with Some (l, _) -> l | None -> P.Card) ~pin:t.pin_at scope

(* the rows a fold button is drawn on (flow.md 7.7): a row wired from one named node of its scope
   or an enclosing one, read nowhere else.  The edit checks again and says why when it refuses.
   ponytail: uses are counted by name over the whole graph, so a name shadowed in another scope
   gets no button (the context menu still folds it); count per scope if that bites. *)
let fold_sources (scope : P.scope) =
  let uses = Hashtbl.create 64 and binders = Hashtbl.create 64 and out = Hashtbl.create 16 in
  let add name =
    let k = root_name name in
    Hashtbl.replace uses k (1 + Option.value ~default:0 (Hashtbl.find_opt uses k)) in
  let rec count (s : P.scope) =
    (match s.result with P.Link target -> add target | _ -> ());
    List.iter (fun (n : P.node) ->
      if n.binds = [ n.name ] && not n.synthetic && not (E.nested n.name) then Hashtbl.replace binders n.path ();
      List.iter (fun (r : P.row) -> List.iter add (P.sources r)) n.rows;
      Option.iter (fun (z : P.zone) ->
        List.iter (fun (r : P.rail_row) -> Option.iter (fun e -> List.iter add (E.free_names e)) r.expr) z.rail;
        count z.scope) n.zone) s.nodes in
  count scope;
  let rec binder sc name = match sc with
    | [] -> None
    | _ when Hashtbl.mem binders (sc @ [ name ]) -> Some (sc @ [ name ])
    | _ -> binder (List.rev (List.tl (List.rev sc))) name in
  let rec mark (s : P.scope) =
    List.iter (fun (n : P.node) ->
      List.iteri (fun i (r : P.row) -> match r.chip, P.sources r with
        | P.Name _, [ src ] when not r.head && Hashtbl.find_opt uses src = Some 1 ->
            Option.iter (Hashtbl.replace out (n.path, i)) (binder (List.rev (List.tl (List.rev n.path))) src)
        | _ -> ()) n.rows;
      Option.iter (fun (z : P.zone) -> mark z.scope) n.zone) s.nodes in
  mark scope; out

(* a switch's rows read as the names of its layouts; [switches] are its nodes with the active input *)
let switch_nodes (scope : P.scope) = List.filter_map (fun (n : P.node) ->
  if n.head <> "ui/switch" || n.zone <> None then None else
  Some (n.path, match List.find_opt (fun (r : P.row) -> r.key = E.Kw "active") n.rows with
    | Some { expr = Some { S.node = S.Num s; _ }; _ } -> Option.value ~default:0 (int_of_string_opt s)
    | _ -> 0)) scope.nodes

let with_scope ?(at = fun _ -> None) ?(level = fun _ -> None) ?(pin = fun _ _ -> None) ?(collapsed = fun _ -> false) ?(probe = fun _ -> 0)
    ?(frames = fun _ -> []) ?(imported = fun _ -> None) ?display ?wires ?(layouts = []) ~key scope t =
  let wires = Option.value wires ~default:t.wires in
  let scope = if layouts = [] then scope else
    { scope with P.nodes = List.map (fun (n : P.node) ->
        let inputs = List.filter (fun (r : P.row) -> match r.key with E.Pos _ -> r.kind <> P.Add | _ -> false) n.rows in
        if n.head <> "ui/switch" || List.length inputs <> List.length layouts then n
        else { n with rows = List.map (fun (r : P.row) -> match r.key with
          | E.Pos i when r.kind <> P.Add -> { r with label = List.nth layouts i } | _ -> r) n.rows }) scope.P.nodes } in
  let t = { t with level_at = level; pin_at = pin } in
  (* letter hints, an open context menu and the hover name nodes and wires of the scope they were made over *)
  let t = match t.scope with
    | Some previous when previous == scope -> t
    | _ -> { t with hinting = None; context = None; highlighted = [] } in
  let layout = lay t scope ~at ~collapsed in
  let n, z, r = count_scope scope in
  let t = { t with scope = Some scope; imported; at; collapsed; probe; frames; display; layout; switches = switch_nodes scope;
    chains = Flow_graph.Probe.chains scope; folds = fold_sources scope; wires;
    stats = { t.stats with nodes = n; zones = z; rows = r } } in
  let t = regeo t scope layout ~shift:no_shift in
  (* an edit that removed or moved a node drops it from the selection *)
  let t = { (refresh t) with selected = Path_set.filter (Paths.mem t.geo.slot) t.selected } in
  let selected_wire = match t.selected_wire with
    | Some (sp, sk, _) when Array.exists (fun w -> match w.target with Some (tp, tk, _) -> sp = tp && sk = tk | None -> false) t.geo.wires ->
        t.selected_wire
    | _ -> None in
  let t = { t with selected_wire } in
  let t = match t.editing with
    | Some (Name p | Default p | Output p) when not (Paths.mem t.geo.slot p) -> { t with editing = None }
    | _ -> t in
  if key <> t.key then begin
    { (suspend t) with key; framed = false; selected = Path_set.empty; selected_wire = None }
  end else t

(* the panel of a macro call opened or stepped: its card changes size *)
let relayout t = match t.scope with
  | None -> t
  | Some scope ->
      let layout = lay t scope ~at:t.at ~collapsed:t.collapsed in
      regeo { t with layout } scope layout ~shift:no_shift

let with_display display t = if display = t.display then t else { t with display }

let with_arguments changes t = match t.scope with
  | None -> t
  | Some scope ->
      let changes = List.filter (fun (path, _, _) -> Paths.mem t.geo.slot path) changes in
      if changes = [] then t else
      let scope = P.with_arguments changes scope in
      let nodes = Paths.create (Array.length t.geo.items) in
      let rec index (scope : P.scope) = List.iter (fun (node : P.node) ->
        Paths.replace nodes node.path node; Option.iter (fun zone -> index zone.P.scope) node.zone) scope.nodes in
      index scope;
      let places = Paths.create (Array.length t.geo.items) in
      let rec patch_layout (layout : P.layout) =
        let placed = List.map (fun (placed : P.placed) ->
          let item = match placed.item with
            | Item node -> let next = Option.value ~default:node (Paths.find_opt nodes node.path) in
                if next == node then placed.item else P.Item next
            | item -> item in
          let lines = match placed.item, item with
            | P.Item old, P.Item node when old.rows != node.rows ->
                let rows = Array.of_list node.rows in Array.map (function
                | P.Row (i, _) -> P.Row (i, rows.(i))
                | line -> line) placed.lines
            | _ -> placed.lines in
          let inner = match placed.inner with
            | Some layout -> let next = patch_layout layout in
                if next == layout then placed.inner else Some next
            | None -> None in
          let placed = if item == placed.item && lines == placed.lines && inner == placed.inner then placed
            else {placed with item; lines; inner} in
          Paths.replace places placed.path placed; placed) layout.placed in
        if List.for_all2 ( == ) placed layout.placed then layout else {layout with placed} in
      let layout = patch_layout t.layout in
      let items = Array.map (fun ((placed : P.placed), x, y) ->
        Option.value ~default:placed (Paths.find_opt places placed.path), x, y) t.geo.items in
      {t with scope = Some scope; layout; geo = {t.geo with items}}

let with_records records t =
  match t.records with
  | Some previous when Flow_graph.Probe.same_eval previous records -> { t with records = Some records }
  | Some _ -> refresh { t with records = Some records }
  | None -> relayout (refresh { t with records = Some records })

(* ------------------------------------------------------------- lookups *)

let node_of t path = Option.bind t.scope (fun s -> P.find s path)
let item_at t path = Option.map (fun i -> t.geo.items.(i)) (Paths.find_opt t.geo.slot path)
(* an item's box in graph units, and where it sits inside its scope *)
let box_at t path = Option.map (fun ((p : P.placed), ax, ay) -> ax, ay, p.w, p.h) (item_at t path)
let rel_at t path = Option.map (fun ((p : P.placed), _, _) -> p.x, p.y) (item_at t path)
let selected_nodes t = List.filter_map (fun p -> node_of t p) (selected t)

let parents_removed paths =
  let set = Path_set.of_list paths in
  (* a path above this one is among them *)
  let rec under = function
    | [] | [ _ ] -> false
    | q -> let up = List.rev (List.tl (List.rev q)) in Path_set.mem up set || under up in
  List.filter (fun q -> not (under q)) paths

let first_inline (n : P.node) =
  List.find_opt (fun (r : P.row) -> match r.chip with
    | P.Inline _ -> true | P.Name leaf -> E.nested leaf | _ -> false) n.rows

let inline_rail (n : P.node) = match n.zone with
  | None -> None
  | Some z -> List.find_opt (fun (r : P.rail_row) -> match r.expr with
      | Some { S.node = S.List _; _ } -> r.key <> None | _ -> false) z.rail

let wired (r : P.row) = P.sources r <> []

(* taking a wire off a row: the nested node written there stays, as a binding of its own *)
let unwire (n : P.node) (r : P.row) =
  (match r.chip with
   | P.Name leaf when E.nested leaf -> [ E.Unfold { node = n.path; key = r.key; sub = [] } ]
   | _ -> [])
  @ [ E.Disconnect { node = n.path; key = r.key; fallback = fallback r } ]

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
  match List.filter (fun p -> Paths.mem t.geo.slot p) (selected t) with
  | [] -> None
  | first :: _ as paths ->
      let scope = scope_of_path first in
      let boxes = List.filter_map (fun p ->
        if scope_of_path p = scope then box_at t p else None) paths in
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

(* [Some hidden] when pressing b hides or shows the node: it has a :visible argument and no bypass *)
let hide_row (n : P.node) =
  if P.bypassable n then None else
  List.find_map (fun (r : P.row) -> match r.key, r.kind, r.ty with
    | E.Kw "visible", P.Arg, Some Ty.Bool ->
        Some (match r.expr with Some { S.node = S.Sym "false"; _ } -> true | _ -> false)
    | _ -> None) n.rows

let conditional_target (n : P.node) = match List.rev n.path with
  | leaf :: outer -> (match E.leaf_keys leaf with
      | Some (holder, [E.Arm index]) -> List.rev outer @ [holder], index
      | _ -> n.path, -1)
  | [] -> n.path, -1

let action_changes t command =
  let nodes = selected_nodes t in
  let paths = List.map (fun (n : P.node) -> n.path) (List.filter (fun (n : P.node) -> not n.synthetic) nodes) in
  let one f = match nodes with [ n ] -> f n | _ -> [ Notice "Select one node" ] in
  let edit op = [ Syntax_edit op ] in
  match command with
  | Delete ->
      (match t.hovered_row with
       | Some (path, key) when (match node_of t path with
           | Some n -> List.exists (fun (r : P.row) -> r.key = key && (wired r || r.kind = P.Rest)) n.rows | None -> false) ->
           (* a wire comes off; an item of a variadic input (a list's, a merge's) goes with what it holds *)
           let n = Option.get (node_of t path) in
           let r = List.find (fun (r : P.row) -> r.key = key) n.rows in
           List.map (fun op -> Syntax_edit op) (unwire n r)
       | _ -> (match t.selected_wire with
           | Some (path, key, fb) ->
               (match Option.bind (node_of t path) (fun n ->
                  Option.map (fun r -> n, r) (List.find_opt (fun (r : P.row) -> r.key = key) n.rows)) with
                | Some (n, r) -> List.map (fun op -> Syntax_edit op) (unwire n r)
                | None -> edit (E.Disconnect { node = path; key; fallback = fb }))
           | None -> if paths = [] then [] else edit (E.Delete_nodes { nodes = paths })))
  | Fold_into -> one (fun n -> edit (E.Fold_into { node = n.path }))
  | Unfold -> one (fun n ->
      let parent, arm = conditional_target n in
      if parent <> n.path then edit (E.Unfold {node = parent; key = E.Arm arm; sub = []}) else
      match t.hovered_row, first_inline n with
      | Some (p, key), _ when p = n.path -> edit (E.Unfold { node = n.path; key; sub = [] })
      | _, Some r -> edit (E.Unfold { node = n.path; key = r.key; sub = [] })
      | _ -> (match inline_rail n with
          | Some { key = Some key; _ } -> edit (E.Unfold { node = n.path; key; sub = [] })
          | _ -> [ Notice "Nothing to unfold here" ]))
  | Hoist -> one (fun n -> edit (E.Hoist { node = n.path }))
  | Bypass -> one (fun n ->
      (* a node that cannot pass an input through but has a boolean :visible (a scene object)
         takes itself out of the render without leaving the graph *)
      match hide_row n with
      | Some hidden ->
          edit (E.Set_arg { node = n.path; key = E.Kw "visible"; sub = []
                          ; value = S.make (S.Sym (if hidden then "true" else "false")) })
      | None -> edit (E.Toggle_bypass { node = n.path }))
  | Wrap_repeat -> if paths = [] then [ Notice "Select nodes to repeat" ] else edit (E.Wrap { nodes = paths; loop = E.For })
  | Wrap_iterate -> if paths = [] then [ Notice "Select nodes to iterate" ] else edit (E.Wrap { nodes = paths; loop = E.Fold })
  | Wrap_if -> if paths = [] then [Notice "Select nodes to wrap"] else edit (E.Wrap {nodes = paths; loop = E.If})
  | Add_arm -> one (fun n -> let node, after = conditional_target n in edit (E.Add_arm {node; after}))
  | Delete_arm -> one (fun n -> let node, index = conditional_target n in
      edit (E.Delete_arm {node; index = if node = n.path then 0 else index}))
  | Make_fn -> if paths = [] then [ Notice "Select nodes to make a function" ] else edit (E.Make_local_fn { nodes = paths })
  | Make_macro -> if paths = [] then [ Notice "Select nodes to make a macro" ] else [ Macro_requested paths ]
  | Make_defn -> if paths = [] then [ Notice "Select nodes to make a reusable function" ] else [ Defn_requested paths ]
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
  | Frame_all | Frame_selection | Walk _ | Edit_name | Make_frame
  | Open_level | Point_level | Open_all | Point_all | Show_hints -> []
  | Duplicate -> if paths = [] then [ Notice "Select nodes to duplicate" ] else edit (E.Duplicate { nodes = paths })
  | Copy -> if paths = [] then [ Notice "Select nodes to copy" ] else [ Copy_requested paths ]
  | Cut -> if paths = [] then [ Notice "Select nodes to cut" ]
      else Copy_requested paths :: edit (E.Delete_nodes { nodes = paths })
  | Paste -> [ Paste_requested ]
  | Display -> one (fun n ->
      if not (List.mem n.ty Flow.Ty.[ geometry; drawing; image ]) then
        [ Notice "Only a geometry, drawing or image node can be viewed" ]
      else [ Display_set n.path ])
  | Item_up | Item_down ->
      (match t.hovered_row with
       | Some (path, E.Pos i) when (match node_of t path with
           | Some n -> P.reorderable n | None -> false) ->
           edit (E.Move_item { node = path; pos = if command = Item_up then i else i + 1 })
       | _ -> [ Notice "Hover a list item to move it" ])

let frame_selection t =
  match List.filter_map (box_at t) (selected t) with
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

(* ---- levels (flow.md 6.4) ---- *)

let level_up = function P.Point -> P.Chip | Chip -> Card | Card | Full -> P.Full

(* the nodes a level applies to: cards, not zones or value cards *)
let level_of (p : P.placed) = match p.item with
  | P.Item n when n.zone = None && not (P.value_card n) -> Some p.level
  | _ -> None
let levelled t path = Option.bind (item_at t path) (fun (p, _, _) -> level_of p)

let level_command t command =
  let chosen = match command with
    | Open_all | Point_all ->
        Array.to_list t.geo.items |> List.filter_map (fun ((p : P.placed), _, _) -> Option.map (fun l -> p.path, l) (level_of p))
    | _ -> List.filter_map (fun p -> Option.map (fun l -> p, l) (levelled t p)) (selected t) in
  if chosen = [] then t, [ Notice "Select a card to change its level" ] else
  (* by path: every node may be chosen, so no list is searched per node *)
  let before = Hashtbl.create 16 and now = Hashtbl.create 16 in
  List.iter (fun (p, l) -> Hashtbl.replace before p l) (List.rev t.back);
  List.iter (fun (p, _) -> Hashtbl.replace now p ()) chosen;
  let back_of p = Option.value ~default:P.Card (Hashtbl.find_opt before p) in
  let changes, back = match command with
    | Open_level -> List.map (fun (p, l) -> p, Some (level_up l), true) chosen, t.back
    | Open_all -> List.map (fun (p, _) -> p, None, false) chosen, t.back
    | Point_level | Point_all | _ ->
        let all_points = List.for_all (fun (_, l) -> l = P.Point) chosen in
        if all_points then
          List.map (fun (p, _) -> let l = back_of p in p, (if l = P.Card then None else Some l), false) chosen, t.back
        else
          List.map (fun (p, _) -> p, Some P.Point, false) chosen,
          List.map (fun (p, l) -> p, (if l = P.Point then back_of p else l)) chosen
          @ List.filter (fun (p, _) -> not (Hashtbl.mem now p)) t.back in
  { t with back }, [ Level_set changes ]

(* ---- letter hints (flow.md 7.5): [w] labels every input the selected output can connect to ---- *)

let hint_alphabet = "asdfghjklqwertyuiopzxcvbnm"
let hint_labels n =
  if n <= 26 then List.init n (fun i -> String.make 1 hint_alphabet.[i])
  else List.init (min n 676) (fun i -> Printf.sprintf "%c%c" hint_alphabet.[i / 26] hint_alphabet.[i mod 26])

(* the nodes of [scope] that [name] depends on: connecting from [name] to them would close a cycle *)
let upstream_of t (src : P.node) =
  let nodes = match t.scope with
    | Some scope ->
        let rec all (s : P.scope) = List.concat_map (fun (n : P.node) ->
          n :: (match n.zone with Some z -> all z.scope | None -> [])) s.nodes in
        all scope
    | None -> [] in
  let binders = Hashtbl.create 64 in
  List.iter (fun (m : P.node) -> List.iter (fun b -> Hashtbl.add binders b m) m.binds) nodes;
  let seen = Hashtbl.create 16 in
  let rec visit (n : P.node) =
    if not (Hashtbl.mem seen n.path) then begin
      Hashtbl.replace seen n.path ();
      List.iter (fun (r : P.row) -> List.iter (fun name ->
        List.iter visit (Hashtbl.find_all binders (root_name name))) (P.sources r)) n.rows
    end in
  visit src; seen

let start_hints t =
  match selected_nodes t with
  | [ src ] when src.zone = None && not src.synthetic ->
      let up = upstream_of t src in
      let scope = scope_of_path src.path in
      let sx, sy = match box_at t src.path with Some (x, y, _, _) -> x, y | None -> 0., 0. in
      let candidates = Array.to_list t.geo.items |> List.filter_map (fun ((p : P.placed), ax, ay) -> match p.item with
        | P.Item n when n.zone = None && p.path <> src.path && scope_of_path p.path = scope
                        && not (Hashtbl.mem up n.path) ->
            let lines = line_of_row p.lines in
            let rows = List.filter_map (fun (i, (r : P.row)) ->
              match r.ty with
              | Some ty when r.socket && r.kind <> P.Add && Ty.fits src.ty ty
                             && (r.head || Hashtbl.mem lines i) ->
                  let y = if r.head then ay +. 12. else
                    rows_top n ay +. (float (Hashtbl.find lines i) +. 0.5) *. P.row_height in
                  Some (r, (ax, y))
              | _ -> None) (List.mapi (fun i r -> i, r) n.rows) in
            if rows = [] then None else Some (n, (ax, ay), rows)
        | _ -> None) in
      let by_distance = List.sort (fun (_, (ax, ay), _) (_, (bx, by), _) ->
        compare (Float.hypot (ax -. sx) (ay -. sy)) (Float.hypot (bx -. sx) (by -. sy))) candidates in
      let by_distance = List.filteri (fun i _ -> i < 676) by_distance in
      let labels = hint_labels (List.length by_distance) in
      let targets = List.map2 (fun label ((n : P.node), at, rows) ->
        match rows with
        | [ ((r : P.row), _) ] -> { label; node = n.path; key = Some r.key; pos = at }
        | _ -> { label; node = n.path; key = None; pos = at }) labels by_distance in
      if targets = [] then t, [ Notice "Nothing the selected output can connect to" ]
      else { t with hinting = Some { src = src.name; src_ty = src.ty; typed = ""; targets; stage = None; armed = false } }, []
  | _ -> t, [ Notice "Select one node to connect from" ]

(* a letter, Backspace or Escape while hints are up; [None] when it was not a hint key *)
let step_hints t (frame : Frame.t) =
  let pressed = List.filter (fun k -> not (List.mem k (fst t.held))) frame.keys in
  let clicked = frame.mouse_buttons <> [] && not (snd t.held) in
  let t = { t with held = (frame.keys, frame.mouse_buttons <> []) } in
  match t.hinting with
  | None -> t, []
  | Some h when not h.armed -> { t with hinting = Some { h with armed = true } }, []  (* the key that began it *)
  | Some h ->
      let h_ref = ref h and out = ref [] and cancel = ref false in
      if clicked then cancel := true;
      List.iter (function
        | Input.Escape -> cancel := true
        | Input.Backspace ->
            let h = !h_ref in
            if h.typed <> "" then h_ref := { h with typed = String.sub h.typed 0 (String.length h.typed - 1) }
            else if h.stage <> None then h_ref := { h with stage = None }
            else cancel := true
        | Input.KeyChar c when String.contains hint_alphabet (Char.lowercase_ascii c) && !out = [] ->
            let h = !h_ref in
            let typed = h.typed ^ String.make 1 (Char.lowercase_ascii c) in
            let live = List.filter (fun (tg : hint_target) -> String.starts_with ~prefix:typed tg.label) h.targets in
            (match List.find_opt (fun (tg : hint_target) -> tg.label = typed) live with
             | Some { node; key = Some key; _ } when h.stage = None ->
                 out := [ Syntax_edit (E.Connect { node; key; src = h.src; iter = false }) ]; cancel := true
             | Some { node; key = None; _ } when h.stage = None ->
                 (* a node with several inputs: its inputs get letters of their own *)
                 let rows = match node_of t node with
                   | Some n -> List.filter_map (fun (r : P.row) ->
                       match r.ty with
                       | Some ty when r.socket && r.kind <> P.Add && Ty.fits h.src_ty ty -> Some r | _ -> None) n.rows
                   | None -> [] in
                 let labels = hint_labels (List.length rows) in
                 let ax, ay = match box_at t node with Some (x, y, _, _) -> x, y | None -> 0., 0. in
                 let n = Option.get (node_of t node) in
                 let lines = match item_at t node with
                   | Some (p, _, _) -> line_of_row p.lines | None -> Hashtbl.create 1 in
                 let targets = List.map2 (fun label (r : P.row) ->
                   let i = Option.value ~default:0 (List.find_index (fun x -> x == r) n.rows) in
                   let y = if r.head then ay +. 12. else match Hashtbl.find_opt lines i with
                     | Some k -> rows_top n ay +. (float k +. 0.5) *. P.row_height | None -> ay +. 12. in
                   { label; node; key = Some r.key; pos = (ax, y) }) labels rows in
                 h_ref := { h with typed = ""; targets; stage = Some node }
             | Some { node; key = Some key; _ } ->
                 out := [ Syntax_edit (E.Connect { node; key; src = h.src; iter = false }) ]; cancel := true
             | _ -> if live = [] then () else h_ref := { h with typed })
        | _ -> ()) pressed;
      if !cancel then { t with hinting = None }, !out else { t with hinting = Some !h_ref }, !out

let run_command t = function
  | Frame_all -> frame_all t, []
  | (Open_level | Point_level | Open_all | Point_all) as command -> level_command t command
  | Show_hints -> start_hints t
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
        | path :: _ -> item_at t path
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
    make ~guide:some "conditional" "wrap conditional" Wrap_if (ch 'i') [Input.Shift];
    make ~guide:one "add-arm" "add conditional arm" Add_arm (ch 'a') [Input.Alt];
    make ~guide:one "delete-arm" "delete first arm" Delete_arm Input.Delete [Input.Alt];
    make ~guide:some "function" "make function" Make_fn (ch 'l') [];
    make ~guide:some "defn" "make reusable function (defn)" Make_defn (ch 'd') [];
    make ~guide:some "collapse" "collapse or expand zone" Collapse (ch 'c') [];
    make ~guide:one "probe-prev" "previous iteration" (Probe_step (-1)) (ch '[') [];
    make ~guide:one "probe-next" "next iteration" (Probe_step 1) (ch ']') [];
    make ~guide:any "frame-all" "frame all" Frame_all Input.Home [];
    make ~guide:any "frame-selection" "frame the selection" Frame_selection (ch 'f') [];
    make ~guide:one "hints" "letter hints: connect the selected output" Show_hints (ch 'w') [];
    make ~guide:some "open" "open one level" Open_level (ch 'o') [];
    make ~guide:some "point" "point, or back" Point_level (ch 'p') [];
    make ~guide:any "open-all" "every node to card" Open_all (ch 'o') [ Input.Shift ];
    make ~guide:any "point-all" "every node to a point, or back" Point_all (ch 'k') [ Input.Shift ];
    make ~guide:one "rename" "rename node / edit input default" Edit_name Input.F2 [];
    make ~guide:some "frame" "frame the selection (titled box)" Make_frame (ch 'g') [ Input.Shift ];
    make ~guide:some "duplicate" "duplicate" Duplicate (ch 'd') [ Input.Meta ];
    make ~guide:some "duplicate" "duplicate" Duplicate (ch 'd') [ Input.Ctrl ];
    make ~guide:some "copy" "copy as text" Copy (ch 'c') [ Input.Meta ];
    make ~guide:some "copy" "copy as text" Copy (ch 'c') [ Input.Ctrl ];
    make ~guide:some "cut" "cut" Cut (ch 'x') [ Input.Meta ];
    make ~guide:some "cut" "cut" Cut (ch 'x') [ Input.Ctrl ];
    make ~guide:any "paste" "paste bindings" Paste (ch 'v') [ Input.Meta ];
    make ~guide:any "paste" "paste bindings" Paste (ch 'v') [ Input.Ctrl ];
    make ~guide:one "display" "view in the viewport" Display (ch 'v') [];
    make ~guide:one "item-up" "move list item up" Item_up Input.ArrowUp [ Input.Alt ];
    make ~guide:one "item-down" "move list item down" Item_down Input.ArrowDown [ Input.Alt ] ]
  @ List.map (fun (direction, arrow, name) ->
      make ~guide:any ("walk." ^ name) ("walk " ^ name) (Walk direction) arrow [])
    [ Left, Input.ArrowLeft, "left"; Down, Input.ArrowDown, "down";
      Up, Input.ArrowUp, "up"; Right, Input.ArrowRight, "right" ]

(* -------------------------------------------------------------- painting *)

(* a port's colour is its type's ([Node_menu.port_color], the menu's squares too); an untyped one
   is the output's *)
let port_color theme (ty : Ty.t option) = match ty with
  | Some ty -> Node_menu.port_color theme ty
  | None -> (Pxui.Theme.ports theme).output
let colors t = Pxui.Theme.ports t.theme
let ty_color t ty = port_color t.theme ty

let fitted paint size width text =
  (* as before, the mark alone when not even it fits *)
  if Ui.Paint.text_width paint ~size text <= width then text else
  match Ui.ellipsis ~width:(Ui.Paint.text_width paint ~size) ~limit:width text with "" -> "…" | t -> t

let dashed_line paint ~width color a b = Ui.Paint.dashed paint ~from_:a ~to_:b ~width color

(* A 1-point frame inside the box, on whole points: a stroke is centred on its rectangle, so the
   box's own edge would paint half a point outside it (and blur at 1x). *)
let frame_in paint ~x ~y ~w ~h ?fill color =
  Option.iter (fun f -> Ui.Paint.fill paint ~x ~y ~w ~h f) fill;
  Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) color

(* the same, dashed (a drop target, a dashed zone) *)
let dashed_frame_in paint ~x ~y ~w ~h color =
  Ui.Paint.dashed_rect paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) color

(* crisp 1-point lines on the pixel grid: a line of width 1 centred on a whole point blurs *)
let hline paint ~x ~y ~w color = Ui.Paint.fill paint ~x ~y ~w ~h:1. color

(* the kit's chevron scaled with the zoom (the pane draws everything at [z]) *)
let draw_chevron paint ~z ~at:(cx, cy) direction color =
  let a, b, tip = match direction with
    | `Down -> (-4., -2.), (4., -2.), (0., 2.) | `Up -> (-4., 2.), (4., 2.), (0., -2.)
    | `Right -> (-2., -4.), (-2., 4.), (2., 0.) | `Left -> (2., -4.), (2., 4.), (-2., 0.) in
  let p (dx, dy) = cx +. dx *. z, cy +. dy *. z in
  Ui.Paint.line paint ~from_:(p a) ~to_:(p tip) color; Ui.Paint.line paint ~from_:(p tip) ~to_:(p b) color

let zone_style theme = function
  | P.For -> Pxui.Theme.zone_for theme | Fold | Scan | State -> Pxui.Theme.zone_fold theme
  | Sum -> Pxui.Theme.zone_sum theme | Fn -> Pxui.Theme.zone_fn theme | Let -> Pxui.Theme.zone_let theme
  | Branch -> Pxui.Theme.zone_branch theme ~taken:false

(* the tinted rectangle of an expanded zone: fill and a 1-point edge inside the box; the brackets
   of a selected zone are the frame pass's, one set *)
let paint_zone ?(taken = false) paint theme kind (x, y, w, h) =
  let s = if kind = P.Branch then Pxui.Theme.zone_branch theme ~taken else zone_style theme kind in
  Ui.Paint.fill paint ~x ~y ~w ~h s.fill;
  if s.dashed then dashed_frame_in paint ~x ~y ~w ~h s.edge
  else Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) s.edge

let sx t gx = float t.x +. t.pan_x +. gx *. t.zoom
let sy t gy = float t.y +. t.pan_y +. gy *. t.zoom

(* Kit rev 3 (specification/pxui-kit/graph.html, kit.css [.node .nh .nr .port]), in points at zoom 1
   and relative to the card's border box.  The header overlaps the 1-point border, so its type
   square is at 9, 8 and the rows start at [P.body_top]; ports are 8-point circles centred on the
   edge (a row's on x = 0 and w, the header's on 1 and w - 1, y = 13). *)
let head_pad = 9.  (* 1 border + 8 padding *)
let label_x = 13.  (* 1 border + 12 padding *)
let field_w = 76. and vec_w = 112. and field_h = 16.
let switch_w = 28. and switch_h = 14.
let value_x w = w -. head_pad -. field_w
let port_y = 13.  (* the header's ports; a row's are centred on the row *)

(* a socket: an 8-point circle (a 1-point ring in the port colour, filled once wired), a record a
   10 by 6 pill, a function the same 8-point square turned 45 degrees; a list is a plain circle *)
let paint_socket paint theme (ty : Ty.t option) ~connected ~z (cx, cy) =
  let color = port_color theme ty in
  let r = 4. *. z in
  let fill = if connected then color else theme.Pxui.input in
  let ring (cx, cy) =
    Ui.Paint.circle paint ~at:(cx, cy) ~radius:r ~fill:color ();
    if not connected then Ui.Paint.circle paint ~at:(cx, cy) ~radius:(r -. 1.) ~fill:theme.input () in
  (* a diamond of half-diagonal [half], one point of height per scan row *)
  let diamond half colour =
    let n = int_of_float (Float.ceil half) in
    for k = - n to n - 1 do
      let hw = half -. Float.abs (float k +. 0.5) in
      if hw > 0. then Ui.Paint.fill paint ~x:(cx -. hw) ~y:(cy +. float k) ~w:(2. *. hw) ~h:1. colour
    done in
  match ty with
  | Some (Ty.Fn _) ->
      let half = 4. *. Float.sqrt 2. *. z in
      diamond half color;
      if not connected then diamond (half -. Float.sqrt 2.) theme.input
  | Some (Ty.Record _) ->
      frame_in paint ~x:(cx -. 5. *. z) ~y:(cy -. 3. *. z) ~w:(10. *. z) ~h:(6. *. z) ~fill color
  | _ -> ring (cx, cy)

(* kit text centred in a row: its top is [Ui.text_top], scaled by the zoom through [h] *)
let text_in paint ui ~size ~color ~x ~y ~h text =
  Ui.Paint.text paint ~at:(x, Ui.text_top ui ~size y h) ~size ~color text

(* a label: upper case, tracked by a point; returns its width *)
let cap_in paint ui ~size ~color ~x ~y ~h label =
  let label = String.uppercase_ascii label in
  let tracking = 0.08 *. float size in  (* kit: +0.08em *)
  Ui.Paint.text paint ~at:(x, Ui.text_top ui ~size y h) ~size ~tracking ~color label;
  Ui.Paint.text_width paint ~size label +. float (String.length label) *. tracking

let kind_label = function
  | P.For -> "for" | Fold -> "fold" | Scan -> "scan" | Sum -> "sum" | Let -> "let" | Fn -> "fn" | State -> "state" | Branch -> "branch"

let note_colors theme =
  if Pxui.Theme.dark theme then Color.hex_exn "#4a4220", Color.hex_exn "#f3e6a8"
  else Color.hex_exn "#f3e6a8", Color.hex_exn "#4a3f10"

(* the marks a node or zone carries: live time, loop-invariant, macro, loop order *)
let marks ?execution (n : P.node) =
  (if n.live then [ "t" ] else [])
  @ Option.fold ~none:[] ~some:(fun (e : Flow_graph.Probe.execution) -> [e.tier]) execution
  @ (if n.macro <> None then [ "◊" ] else [])
  @ (match n.zone with Some { order = Some o; _ } -> [ o ] | _ -> [])

let marks_width paint ~size ~gap marks =
  List.fold_left (fun a m -> a +. Ui.Paint.text_width paint ~size m +. gap) 0. marks

(* marks right-aligned at [right], accent, label size *)
let paint_marks paint ui theme ~size ~gap ~right ~y ~h marks =
  ignore (List.fold_left (fun x m ->
    let w = Ui.Paint.text_width paint ~size m in
    text_in paint ui ~size ~color:theme.Pxui.accent ~x:(x -. w) ~y ~h m;
    x -. w -. gap) right marks)

(* DepartureMono has no ⟲ ◆ ◷ ↥ ▸ ▾: the pane draws ↵ ◊ t ↑ ► ▼ in their place. *)
let shown_glyph = function "⟲" -> "↵" | "◆" -> "◊" | g -> g

let strip_parens s =
  let n = String.length s in
  if n >= 2 && s.[0] = '(' && s.[n - 1] = ')' then String.sub s 1 (n - 2) else s

(* a graph input's default, what a wired name reads as live *)
let live_value t name = match t.scope with
  | Some scope ->
      List.find_map (fun (i : P.input) ->
        if i.name = name then Option.map Flow.Lisp.flat i.default else None) scope.inputs
  | None -> None

let number_words text = (* "[0 1 0]" as its numbers *)
  let n = String.length text in
  if n >= 2 && text.[0] = '[' && text.[n - 1] = ']' then
    let parts = String.split_on_char ' ' (String.sub text 1 (n - 2)) in
    if List.for_all (fun s -> float_of_string_opt s <> None) parts then Some parts else None
  else None

let fraction_of (r : P.row) text = match r.control with
  | P.Range (lo, hi) -> Editor_core.Number.fraction (lo, hi) text
  | _ -> None

(* a field painted without the live editor: a value on a line-2 hairline, label-size text *)
let all_numbers elems = List.for_all (fun (e : S.t) -> match e.node with S.Num _ -> true | _ -> false) elems

(* a number or a vector of numbers at a zoom where the live editors are built: they paint
   themselves (see [update]) *)
let live_numbers ~z (r : P.row) = z >= 0.5 && (match r.chip, r.expr with
  | P.Const, Some { S.node = S.Num _; _ } -> true
  | P.Const, Some { S.node = S.Vec elems; _ } ->
      let k = List.length elems in k >= 2 && k <= 4 && all_numbers elems
  | _ -> false)

(* a field painted without the live editor: a value on a line-2 hairline, label-size text; the
   position line of a ranged number is 2 points above the hairline (rows 13 and 14 of 16) *)
let paint_field paint ui ~z ~ls ~theme ~x ~y ~w ?(left = false) ?fraction ?(chevron = false) ~color text =
  let h = field_h *. z in
  Ui.Paint.fill paint ~x ~y:(y +. h -. 1.) ~w ~h:1. (Pxui.Theme.edge theme);
  Option.iter (fun f ->
    Ui.Paint.fill paint ~x ~y:(y +. h -. 3.) ~w:(w *. f) ~h:2. (Pxui.Theme.ink_2 theme)) fraction;
  let room = w -. 4. *. z -. (if chevron then 10. *. z else 0.) in
  let text = fitted paint ls room text in
  let tw = Ui.Paint.text_width paint ~size:ls text in
  let tx = if left || chevron then x +. 2. *. z else x +. w -. 2. *. z -. tw in
  text_in paint ui ~size:ls ~color ~x:tx ~y ~h text;
  if chevron then draw_chevron paint ~z ~at:(x +. w -. 5. *. z, y +. h /. 2. -. 1. *. z) `Down color

let paint_switch paint theme ~z ~x ~y on =
  frame_in paint ~x ~y ~w:(switch_w *. z) ~h:(switch_h *. z)
    ~fill:(if on then theme.Pxui.input else theme.Pxui.track) (Pxui.Theme.border theme);
  Ui.Paint.fill paint ~x:(x +. (if on then 17. else 3.) *. z) ~y:(y +. 3. *. z) ~w:(8. *. z) ~h:(8. *. z)
    (if on then theme.accent else Pxui.Theme.ink_3 theme)

(* the cells of a vector: each element is a field, its number right-aligned, anything else the
   expression's text *)
let paint_vector paint ui ~z ~ls ~theme ~right ~y (elems : S.t list) =
  let k = List.length elems in
  let vw = vec_w *. z and gap = 8. *. z in
  let cw = (vw -. gap *. float (k - 1)) /. float k in
  List.iteri (fun c (e : S.t) ->
    let text, left = match e.node with
      | S.Num s -> s, false | S.Str s -> s, true | _ -> Flow.Lisp.flat e, true in
    paint_field paint ui ~z ~ls ~theme ~x:(right -. vw +. float c *. (cw +. gap)) ~y ~w:cw ~left
      ~color:theme.Pxui.foreground text) elems

(* the value of a row, at the right of it (kit [.nr]).  [live]: the live editor of a number or
   vector of numbers is built over it (in [update]), so it is not painted here. *)
(* a wired row, right-aligned: [ƒ] when its source can fold into it, [←], the source and its live
   value.  Returns where the arrow starts, the room the name has, the live value and its width;
   [update] puts the fold button's box where this paints the glyph. *)
let wired_name (r : P.row) s = match r.expr with
  | Some { S.node = S.List ({ S.node = S.Sym head; _ } :: _); _ } when E.nested s -> head
  | _ -> s
let fold_glyph = "\xc6\x92"
let wired_geo ~measure t ~z ~fs ~x ~w ~fold s =
  let right = x +. w -. head_pad *. z and gap = 6. *. z in
  let live = live_value t s in
  let aw = measure fs "\xe2\x86\x90" in
  let fw = if fold then measure fs fold_glyph +. gap else 0. in
  let live_w = match live with Some v -> measure fs v +. gap | None -> 0. in
  let room = Float.max 0. (right -. x -. (label_x +. 40.) *. z -. aw -. gap -. live_w -. fw) in
  let left = right -. live_w -. Float.min (measure fs s) room -. gap -. aw in
  left, fw, room, live, live_w

(* where the name of a row that reads a binding is: its left and its width, in the card's points *)
let ref_chip_geo t ~z ~fs ~w s =
  let left, _, room, _, _ = wired_geo ~measure:t.measure t ~z ~fs ~x:0. ~w ~fold:false s in
  left, t.measure fs "\xe2\x86\x90" +. 6. *. z +. Float.min (t.measure fs s) room

let paint_value paint ui t ~z ~fs ?size ?(fold = false) ~x ~y ~w ~live (r : P.row) =
  let theme = t.theme in
  let ls = match size with Some s -> s | None -> max 4 (fs - 2) in
  let rh = P.row_height *. z in
  let right = x +. w -. head_pad *. z in
  let fx = right -. field_w *. z and fy = y +. 4. *. z in
  let dim = Pxui.Theme.ink_3 theme in
  match r.chip with
  | P.No_value ->
      (match r.default with
       | Some ("true" | "false" as d) ->
           paint_switch paint theme ~z ~x:(right -. switch_w *. z) ~y:(y +. 5. *. z) (d = "true")
       | Some d ->
           (match number_words d with
            | Some parts ->
                let k = List.length parts in
                let vw = vec_w *. z and gap = 8. *. z in
                let cw = (vw -. gap *. float (k - 1)) /. float k in
                List.iteri (fun c s ->
                  paint_field paint ui ~z ~ls ~theme ~x:(right -. vw +. float c *. (cw +. gap)) ~y:fy ~w:cw ~color:dim s) parts
            | None ->
                let numeric = float_of_string_opt d <> None in
                paint_field paint ui ~z ~ls ~theme ~x:fx ~y:fy ~w:(field_w *. z) ~left:(not numeric && r.control <> P.Choice)
                  ?fraction:(fraction_of r d) ~chevron:(r.control = P.Choice) ~color:dim d)
       | None -> ())
  | Const -> (match r.expr with
      | Some { S.node = S.Num text; _ } ->
          if not live then
            paint_field paint ui ~z ~ls ~theme ~x:fx ~y:fy ~w:(field_w *. z) ?fraction:(fraction_of r text)
              ~color:theme.foreground text
      | Some { S.node = S.Vec elems; _ } ->
          if not live then paint_vector paint ui ~z ~ls ~theme ~right ~y:fy elems
      | Some { S.node = S.Sym (("true" | "false") as b); _ } ->
          paint_switch paint theme ~z ~x:(right -. switch_w *. z) ~y:(y +. 5. *. z) (b = "true")
      | Some e ->
          let text = match e.node with S.Str s -> s | _ -> Flow.Lisp.flat e in
          paint_field paint ui ~z ~ls ~theme ~x:fx ~y:fy ~w:(field_w *. z) ~left:(r.control <> P.Choice)
            ~chevron:(r.control = P.Choice) ~color:theme.foreground text
      | None -> ())
  | Name s ->
      (* a nested node is its own card: the row names its kind; a wired row reads [← source] and
         the live value at the right *)
      let s = wired_name r s in
      let gap = 6. *. z in
      let arrow = "\xe2\x86\x90" in
      let aw = Ui.Paint.text_width paint ~size:fs arrow in
      let left, fw, room, live, live_w =
        wired_geo ~measure:(fun size s -> Ui.Paint.text_width paint ~size s) t ~z ~fs ~x ~w ~fold s in
      let s = fitted paint fs room s in
      if fold then text_in paint ui ~size:fs ~color:theme.accent ~x:(left -. fw) ~y ~h:rh fold_glyph;
      text_in paint ui ~size:fs ~color:(if fold then Pxui.Theme.ink_3 theme else theme.accent) ~x:left ~y ~h:rh arrow;
      text_in paint ui ~size:fs ~color:(Pxui.Theme.ink_2 theme) ~x:(left +. aw +. gap) ~y ~h:rh s;
      Option.iter (fun v ->
        text_in paint ui ~size:fs ~color:theme.foreground ~x:(right -. live_w +. gap) ~y ~h:rh v) live
  | Inline { glyph; text } ->
      let glyph = shown_glyph glyph in
      let gw = Ui.Paint.text_width paint ~size:ls glyph +. 6. *. z in
      text_in paint ui ~size:ls ~color:theme.accent ~x:fx ~y ~h:rh glyph;
      text_in paint ui ~size:ls ~color:(Pxui.Theme.ink_2 theme) ~x:(fx +. gw) ~y ~h:rh
        (fitted paint ls (field_w *. z -. gw) text)

(* where a row's label must stop: the control (or the wired value) takes the right of the row *)
let value_room paint t ~z ~fs ~w ?(fold = false) (r : P.row) =
  let numbers = match r.chip, r.expr with
    | P.Const, Some { S.node = S.Vec _; _ } -> true
    | P.No_value, _ -> (match Option.bind r.default number_words with Some _ -> true | None -> false)
    | _ -> false in
  match r.chip with
  | _ when r.kind = P.Add -> w -. (label_x +. head_pad) *. z
  | P.No_value when r.default = None -> w -. (label_x +. head_pad) *. z
  | P.Const when (match r.expr with Some { S.node = S.Sym ("true" | "false"); _ } -> true | _ -> false) ->
      w -. (label_x +. head_pad +. switch_w +. 6.) *. z
  | P.No_value when (match r.default with Some ("true" | "false") -> true | _ -> false) ->
      w -. (label_x +. head_pad +. switch_w +. 6.) *. z
  | P.Name s ->
      let s = match r.expr with
        | Some { S.node = S.List ({ S.node = S.Sym head; _ } :: _); _ } when E.nested s -> head | _ -> s in
      let live = live_value t s in
      let aw = Ui.Paint.text_width paint ~size:fs "\xe2\x86\x90" in
      let sw = Float.min (Ui.Paint.text_width paint ~size:fs s) (w *. 0.4) in
      let lw = match live with Some v -> Ui.Paint.text_width paint ~size:fs v +. 6. *. z | None -> 0. in
      w -. (label_x +. head_pad) *. z -. aw -. sw -. lw -. 12. *. z -. (if fold then 14. *. z else 0.)
  | _ ->
      w -. (label_x +. head_pad) *. z -. (if numbers then vec_w else field_w) *. z -. 6. *. z

let paint_rows paint ui t ~z ~fs ~x ~y ~w ?(carry = false) (n : P.node) (lines : P.line array) ~selected_row =
  let theme = t.theme in
  let ls = max 4 (fs - 2) in
  let rh = P.row_height *. z in
  Array.iteri (fun k line ->
    let ry = y +. float k *. rh in
    match line with
    | P.Folder (_, name) ->
        (* a folder's label row: its name in the foreground, 8 points in *)
        ignore (cap_in paint ui ~size:ls ~color:theme.foreground ~x:(x +. 9. *. z) ~y:ry ~h:rh name)
    | Row (i, r) ->
        let fold = Hashtbl.mem t.folds (n.path, i) in
        let target = carry && selected_row = Some i in
        if selected_row = Some i then
          Ui.Paint.fill paint ~x:(x +. 1.) ~y:ry ~w:(w -. 2.) ~h:rh
            (if target then Pxui.Theme.hover_fill theme else Pxui.Theme.faint_border theme);
        (* a carried value over a row: the row takes the hover fill, an ink label and an accent underline *)
        if target then
          hline paint ~x:(x +. value_x w *. z) ~y:(ry +. 19. *. z) ~w:(field_w *. z) theme.accent;
        let add = r.kind = P.Add in
        let color = match r.kind with
          | _ when target -> theme.foreground
          | P.Add -> Pxui.Theme.ink_2 theme | Binder | Hole -> theme.accent | _ -> Pxui.Theme.ink_2 theme in
        let size = if add then ls else fs in
        text_in paint ui ~size ~color ~x:(x +. label_x *. z) ~y:ry ~h:rh
          (fitted paint size (Float.max 0. (value_room paint t ~z ~fs ~w ~fold r)) r.label);
        if r.socket then
          paint_socket paint theme r.ty ~connected:(wired r) ~z (x, ry +. 12. *. z);
        if not add then paint_value paint ui t ~z ~fs ~fold ~x ~y:ry ~w ~live:(live_numbers ~z r) r) lines

let paint_outputs paint ui t ~z ~fs ~x ~y ~w (n : P.node) ~nlines =
  let theme = t.theme in
  let ls = max 4 (fs - 2) in
  let rh = P.row_height *. z in
  List.iteri (fun j (name, ty) ->
    let ry = y +. float (nlines + j) *. rh in
    text_in paint ui ~size:fs ~color:(colors t).record ~x:(x +. label_x *. z) ~y:ry ~h:rh ("→ " ^ name);
    let label = Ty.to_string ty in
    let lw = Ui.Paint.text_width paint ~size:ls label in
    text_in paint ui ~size:ls ~color:(Pxui.Theme.ink_2 theme) ~x:(x +. w -. head_pad *. z -. lw) ~y:ry ~h:rh label;
    paint_socket paint theme (Some ty) ~connected:true ~z (x +. w, ry +. 12. *. z)) n.outputs

(* rail rows of a zone: name, role, and what feeds it.  Under an expanded zone's label row they
   are the accumulators, further variables and parameters (the port at the right is the
   variable's); a collapsed zone's card lists every row, its captures too. *)
let paint_rail paint ui t ~z ~fs ~x ~y ~w ~expanded (rail : P.rail_row list) =
  let theme = t.theme in
  let palette = colors t in
  let ls = max 4 (fs - 2) in
  let rh = P.row_height *. z in
  List.iteri (fun i (r : P.rail_row) ->
    let ry = y +. float i *. rh in
    let color = match r.role with
      | P.Var -> theme.accent | Acc -> palette.vec3 | Param -> palette.fn | Capture -> Pxui.Theme.muted theme in
    text_in paint ui ~size:fs ~color ~x:(x +. 13. *. z) ~y:ry ~h:rh (fitted paint fs (56. *. z) r.name);
    let role = match r.role with P.Var -> "in" | Acc -> "acc" | Param -> "param" | Capture -> "from" in
    text_in paint ui ~size:ls ~color:(Pxui.Theme.ink_3 theme) ~x:(x +. 13. *. z +. 58. *. z) ~y:ry ~h:rh role;
    (match r.expr with
     | Some e ->
         let sym = (match e.node with S.Sym _ -> true | _ -> false) in
         let shown = match e.node with S.Sym s -> s | _ -> Flow.Lisp.flat e in
         let ex = x +. 92. *. z in
         let room = Float.max 0. (x +. w -. (if expanded then 24. else 8.) *. z -. ex) in
         if sym then begin
           text_in paint ui ~size:ls ~color:theme.accent ~x:ex ~y:ry ~h:rh "\xe2\x86\x90";
           let aw = Ui.Paint.text_width paint ~size:ls "\xe2\x86\x90 " in
           text_in paint ui ~size:ls ~color:(Pxui.Theme.ink_2 theme) ~x:(ex +. aw) ~y:ry ~h:rh
             (fitted paint ls (Float.max 0. (room -. aw)) shown)
         end else
           text_in paint ui ~size:ls ~color:(Pxui.Theme.ink_2 theme) ~x:ex ~y:ry ~h:rh (fitted paint ls room shown)
     | None -> ());
    if r.key <> None || r.role = P.Capture then
      paint_socket paint theme r.ty ~connected:(r.role = P.Capture || r.expr <> None) ~z (x, ry +. 12. *. z);
    if expanded then
      paint_socket paint theme r.ty ~connected:true ~z (x +. w -. 12. *. z, ry +. 12. *. z)) rail

(* the zone's label row (kit [.zone] label): [FOR] in accent, the binder in ink, "in ..." in ink-2 *)
let zone_binder (n : P.node) (zn : P.zone) =
  match P.label_row zn with
  | Some { name; expr = Some e; _ } -> name, Some (strip_parens (Flow.Lisp.flat e))
  | Some { name; _ } -> name, None
  | None -> P.title n, None

let paint_zone_label paint ui t ~z ~fs ~x ~y ~w ?execution (n : P.node) (zn : P.zone) =
  let theme = t.theme in
  let ls = max 4 (fs - 2) in
  let hh = P.head_height *. z in
  let gap = 8. *. z in
  let label = kind_label zn.kind ^ Option.fold ~none:"" ~some:(fun (e : Flow_graph.Probe.execution) -> " · " ^ e.tier) execution in
  let cw = cap_in paint ui ~size:ls ~color:theme.accent ~x ~y ~h:hh label in
  let name, in_ = zone_binder n zn in
  let nx = x +. cw +. gap in
  let room = Float.max 0. (x +. w -. 9. *. z -. nx) in
  let name = fitted paint fs room name in
  text_in paint ui ~size:fs ~color:theme.foreground ~x:nx ~y ~h:hh name;
  match in_ with
  | Some e ->
      let ix = nx +. Ui.Paint.text_width paint ~size:fs name +. gap in
      text_in paint ui ~size:fs ~color:(Pxui.Theme.ink_2 theme) ~x:ix ~y ~h:hh
        (fitted paint fs (Float.max 0. (x +. w -. 9. *. z -. ix)) ("in " ^ e))
  | None -> ()

(* the iteration selector at the zone's top right: [‹ 2 / 5 ›] on the sheet fill, 9 points in
   from the zone's edge and 3 down (inside its 1-point border), 20 high; tile-relative points *)
let selector_geo ~measure ~z ~fs ~w ~count ~probe =
  let read = if count > 0 then Printf.sprintf "%d / %d" (probe + 1) count else "no runs" in
  let tw = measure fs read in
  let chev = 6. *. z and gap = 12. *. z in
  let total = chev +. gap +. tw +. gap +. chev in
  w -. head_pad *. z -. total, 3. *. z, total, 20. *. z, read

let paint_selector paint ui t ~z ~fs ~count ~probe (x, y, w) =
  let theme = t.theme in
  let sx, sy, sw, sh, read = selector_geo ~measure:(fun size s -> Ui.text_width ui ~size s) ~z ~fs ~w ~count ~probe in
  let sx = x +. sx and sy = y +. sy in
  Ui.Paint.fill paint ~x:sx ~y:sy ~w:sw ~h:sh theme.input;
  (* the sheet's [.seg] children are ink-3 *)
  let ink = Pxui.Theme.ink_3 theme in
  draw_chevron paint ~z ~at:(sx +. 3. *. z, sy +. sh /. 2.) `Left ink;
  draw_chevron paint ~z ~at:(sx +. sw -. 3. *. z, sy +. sh /. 2.) `Right ink;
  text_in paint ui ~size:fs ~color:ink ~x:(sx +. 18. *. z) ~y:sy ~h:sh read

(* the card's header: the in-port of the first geometry slot, the type square, the name, and at
   the right the view flag, the marks and the kind (a failed node says its code instead) *)
let paint_header paint ui t ~z ~fs ~x ~y ~w (n : P.node) ?execution ?lens_open ?failed ?head ?(shown = P.Card) () =
  let theme = t.theme in
  let ls = max 4 (fs - 2) in
  let hh = P.head_height *. z in
  let viewed = t.display = Some n.path in
  let ink_3 = Pxui.Theme.ink_3 theme in
  let invalid = Pxui.Theme.invalid in
  let square =
    if failed <> None then invalid
    else if n.bypass then ink_3
    else if viewed then theme.foreground
    else ty_color t (Some n.ty) in
  Ui.Paint.fill paint ~x:(x +. head_pad *. z) ~y:(y +. 8. *. z) ~w:(8. *. z) ~h:(8. *. z) square;
  Option.iter (fun (r : P.row) ->
    paint_socket paint theme r.ty ~connected:(wired r) ~z (x +. 1. *. z, y +. port_y *. z)) head;
  let name_x = x +. 23. *. z in
  let right = x +. w -. head_pad *. z in
  let right = match lens_open with
    | Some open_ ->
        draw_chevron paint ~z ~at:(x +. w -. 14. *. z, y +. 12. *. z) (if open_ then `Down else `Right)
          (Pxui.Theme.muted theme);
        x +. w -. 24. *. z
    | None -> right in
  (* the displayed node: the 12-point view flag, a line-3 frame and the accent square inside *)
  let right = if viewed then begin
      let fx = right -. 12. *. z and fy = y +. 6. *. z in
      frame_in paint ~x:fx ~y:fy ~w:(12. *. z) ~h:(12. *. z) ~fill:theme.input (Pxui.Theme.border theme);
      Ui.Paint.fill paint ~x:(fx +. 3. *. z) ~y:(fy +. 3. *. z) ~w:(6. *. z) ~h:(6. *. z) theme.accent;
      fx -. 6. *. z
    end else right in
  let m = marks ?execution n in
  let gap = 5. *. z in
  paint_marks paint ui theme ~size:ls ~gap ~right ~y ~h:hh m;
  let right = right -. marks_width paint ~size:ls ~gap m -. (if m = [] then 0. else 1. *. z) in
  let title = P.title n in
  let name_color =
    if failed <> None then invalid
    else if n.bypass then ink_3
    else if n.synthetic || P.anonymous n then Pxui.Theme.muted theme else theme.foreground in
  let name = fitted paint fs (Float.max 0. (right -. name_x)) title in
  text_in paint ui ~size:fs ~color:name_color ~x:name_x ~y ~h:hh name;
  let name_end = name_x +. Ui.Paint.text_width paint ~size:fs name in
  (* a chip: how many rows have something written, in the kind's place at the right *)
  let right = if shown = P.Chip && P.set_count n > 0 then begin
      let text = Printf.sprintf "+%d" (P.set_count n) in
      text_in paint ui ~size:ls ~color:(Pxui.Theme.ink_2 theme) ~x:(name_end +. 9. *. z) ~y ~h:hh text;
      right end else right in
  let name_end = if shown = P.Chip && P.set_count n > 0 then
      name_end +. 9. *. z +. Ui.Paint.text_width paint ~size:ls (Printf.sprintf "+%d" (P.set_count n)) else name_end in
  (* where the name and the kind meet, the kind yields *)
  let kind_text = match failed with Some code -> Some code | None ->
    match t.imported n.path with Some file -> Some file
    | None -> if n.zone = None && n.head <> n.name then Some n.head else None in
  Option.iter (fun text ->
    let room = right -. (name_end +. 6. *. z) in
    if room >= 3. *. Ui.Paint.text_width paint ~size:ls "m" then begin
      let kind = fitted paint ls room text in
      let kw = Ui.Paint.text_width paint ~size:ls kind in
      text_in paint ui ~size:ls ~color:(Pxui.Theme.ink_2 theme) ~x:(right -. kw) ~y ~h:hh kind
    end) kind_text

(* The footer row of a node card or a collapsed zone: the value at the probe, a sparkline across
   the innermost zone, the tags; label-size ink-2 over a line-1 hairline.
   The tags use ↑ for the study's ↥ and t for ◷ (DepartureMono lacks both). *)
let paint_footer paint ui t ~z ~fs (f : Flow_graph.Probe.footer) (ty : Ty.t) ~pad (x, y, w, h) =
  let theme = t.theme in
  let ls = max 4 (fs - 2) in
  let fh = P.foot_height *. z in
  let fy = y +. h -. pad *. z -. fh in
  Ui.Paint.fill paint ~x:(x +. 1.) ~y:fy ~w:(w -. 2.) ~h:1. (Pxui.Theme.faint_border theme);
  let ink_2 = Pxui.Theme.ink_2 theme in
  let ty0 = fy +. 1. and th = fh -. 1. in
  let right = ref (x +. w -. head_pad *. z) in
  let put_right color s =
    let tw = Ui.Paint.text_width paint ~size:ls s in
    text_in paint ui ~size:ls ~color ~x:(!right -. tw) ~y:ty0 ~h:th s;
    right := !right -. tw -. 6. *. z in
  if f.live then put_right theme.accent "t";
  Option.iter (fun (e : Flow_graph.Probe.execution) -> put_right ink_2 e.tier) f.execution;
  let tags = String.concat " · " (List.filter_map Fun.id [ f.branch; f.kept; Option.map (Printf.sprintf "×%d") f.runs;
    Option.bind f.execution (fun e -> Option.map (fun seconds -> Printf.sprintf "%.3f ms" (seconds *. 1000.)) e.seconds) ]) in
  if tags <> "" then
    put_right ink_2 (fitted paint ls (Float.max 0. (!right -. x) *. 0.5) tags);
  let left = x +. label_x *. z in
  (match f.spark with
   | Some (values, at) ->
       let sw = 36. *. z and sh = 10. *. z in
       let sx0 = Float.max (left +. 30. *. z) (!right -. sw) in
       let lo = Array.fold_left Float.min infinity values and hi = Array.fold_left Float.max neg_infinity values in
       let px i = sx0 +. float i /. float (Array.length values - 1) *. sw
       (* flat runs sit on a whole point plus a half, so a 1-point line is not blurred over two rows *)
       and py v = Float.floor (if hi = lo then fy +. 7. *. z +. sh /. 2. else fy +. 7. *. z +. sh -. (v -. lo) /. (hi -. lo) *. sh) +. 0.5 in
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
  text_in paint ui ~size:ls ~color:ink_2 ~x:left ~y:ty0 ~h:th
    (fitted paint ls (Float.max 0. (!right -. left)) f.value)

(* The expansion panel under a macro call, in graph units relative to its top: step
   buttons on the first row ("call", 1, 2, ...), the printed step, and the replace
   button with the reading on the last row. *)
let lens_button_box ~len i =
  if i = 0 then (8., 2.), (36., 20.)
  else if i >= len then (8. +. 40. +. float (max 0 (len - 1)) *. 28. +. 4., 2.), (64., 20.)  (* the template *)
  else (8. +. 40. +. float (i - 1) *. 28., 2.), (24., 20.)
let lens_replace_box lh = (8., lh -. P.row_height +. 2.), (196., 20.)  (* a control is 20 high *)
(* the panel's top inside a card of height [h]: above the padding *)
let lens_top h lh = h -. lh -. P.card_pad

let paint_lens paint ui t ~z ~fs (l : P.lens) ~step (x, y, w) ~lh =
  let theme = t.theme in
  let ls = max 4 (fs - 2) in
  Ui.Paint.fill paint ~x:(x +. 1.) ~y ~w:(w -. 2.) ~h:1. (Pxui.Theme.faint_border theme);
  let len = Array.length l.steps in
  for i = 0 to len do
    let (bx, by), (bw, bh) = lens_button_box ~len i in
    let on = i = step in
    if on then Ui.Paint.fill paint ~x:(x +. (bx +. 2.) *. z) ~y:(y +. (by +. bh) *. z -. 1.) ~w:((bw -. 4.) *. z) ~h:1. theme.foreground;
    let label = if i = 0 then "call" else if i = len then "Template" else string_of_int i in
    let tw = Ui.Paint.text_width paint ~size:ls label in
    text_in paint ui ~size:ls ~color:(if on then theme.foreground else Pxui.Theme.ink_3 theme)
      ~x:(x +. (bx +. bw /. 2.) *. z -. tw /. 2.) ~y:(y +. by *. z) ~h:(bh *. z) label
  done;
  let text = if step >= len then (if l.template = "" then "(no definition)" else l.template)
    else match l.error with
      | Some message when step >= len -> message
      | _ -> l.steps.(max 0 step) in
  let lines = String.split_on_char '\n' text in
  List.iteri (fun k line ->
    if k < 16 then
      Ui.Paint.text paint ~at:(x +. 10. *. z, y +. (P.row_height +. 4. +. float k *. 20.) *. z) ~size:fs
        ~color:theme.foreground (fitted paint fs (w -. 20. *. z) (if k = 15 && List.length lines > 16 then line ^ " …" else line))) lines;
  let (rx, ry), (rw, rh) = lens_replace_box lh in
  frame_in paint ~x:(x +. rx *. z) ~y:(y +. ry *. z) ~w:(rw *. z) ~h:(rh *. z) (Pxui.Theme.border theme);
  text_in paint ui ~size:ls ~color:theme.foreground ~x:(x +. (rx +. 8.) *. z) ~y:(y +. ry *. z) ~h:(rh *. z)
    "Replace call with expansion";
  let reading = match l.error with
    | _ when step >= len -> "the macro's template"
    | Some message when step >= len - 1 && step > 0 -> message
    | _ -> if step = 0 then "as written" else Printf.sprintf "after %d expansion step%s" step (if step > 1 then "s" else "") in
  let tw = Ui.Paint.text_width paint ~size:ls reading in
  text_in paint ui ~size:ls ~color:(Pxui.Theme.muted theme) ~x:(x +. w -. head_pad *. z -. tw) ~y:(y +. ry *. z) ~h:(rh *. z)
    (fitted paint ls (w -. (rx +. rw +. 24.) *. z) reading)

(* a card's hairline: line-2, line-3 when selected, composed over the card's own fill (the sheet's
   border sits on its background) *)
let card_edge t ~fill ~selected =
  Color.blend t.theme.foreground fill ~pct:(if selected then 0.70 else 0.85)

(* the card: its fill and a 1-point border inside its box (a stroke is centred on its rectangle) *)
let paint_card paint ~x ~y ~w ~h ~fill ~edge =
  Ui.Paint.fill paint ~x ~y ~w ~h fill;
  Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) edge

(* a point: the 14-point disc in the node's colour with its name beside it (a compound is a ring
   with a dot), brackets when selected; the displayed one wears its flag below the disc *)
let paint_point paint ui t ~z ~fs (p : P.placed) ?failed ~selected (x, y, _, _) =
  let theme = t.theme in
  let c = (x +. 7. *. z, y +. 7. *. z) in
  let ty, macro, bypass, title, viewed = match p.item with
    | P.Item n -> n.ty, n.macro <> None, n.bypass, P.title n, t.display = Some n.path
    | P.Input i -> i.ty, false, false, i.name, false
    | P.Return -> Flow.Ty.geometry, false, false, "return", false in
  let color = if failed <> None then Pxui.Theme.invalid else ty_color t (Some ty) in
  if macro then begin
    Ui.Paint.circle paint ~at:c ~radius:(7. *. z) ~fill:theme.Pxui.panel ~stroke:color ();
    Ui.Paint.circle paint ~at:c ~radius:(2. *. z) ~fill:color ()
  end else Ui.Paint.circle paint ~at:c ~radius:(7. *. z) ~fill:color ();
  let name_color = if failed <> None then Pxui.Theme.invalid else if bypass then Pxui.Theme.ink_3 theme
    else theme.foreground in
  text_in paint ui ~size:fs ~color:name_color ~x:(x +. 22. *. z) ~y:(y +. 7. *. z -. 12. *. z) ~h:(24. *. z) title;
  if viewed then begin
    let fy = y +. 21. *. z in
    frame_in paint ~x ~y:fy ~w:(12. *. z) ~h:(12. *. z) ~fill:theme.input (Pxui.Theme.border theme);
    Ui.Paint.fill paint ~x:(x +. 3. *. z) ~y:(fy +. 3. *. z) ~w:(6. *. z) ~h:(6. *. z) theme.accent
  end;
  if selected then
    Ui.Paint.brackets paint ~x ~y ~w:(14. *. z) ~h:(14. *. z) ~offset:5. ~length:6. theme.accent

let paint_node paint ui t ~z ~fs ?footer ?lens_step ?(hovered = false) ?(carry = false) ?(out_wired = true) ~shown ?failed
    (p : P.placed) (n : P.node) ~selected ~row_hover (x, y, w, h) =
  if shown = P.Point then paint_point paint ui t ~z ~fs p ?failed ~selected (x, y, w, h) else
  let theme = t.theme in
  let z_ = n.zone in
  let execution = Option.bind t.records (fun records ->
    let chain = Option.value ~default:[] (Hashtbl.find_opt t.chains n.path) in
    Flow_graph.Probe.execution records n.path ~probes:(List.map t.probe chain)) in
  let execution = match execution with Some _ -> execution | None -> Option.bind footer (fun f -> f.Flow_graph.Probe.execution) in
  let ls = max 4 (fs - 2) in
  let stacked = match z_ with Some _ -> p.collapsed | None -> false in
  if stacked then
    List.iter (fun d ->
      paint_card paint ~x:(x +. d *. z) ~y:(y +. d *. z) ~w ~h ~fill:theme.input
        ~edge:(card_edge t ~fill:theme.input ~selected:false)) [ 6.; 3. ];
  (* a chip is the header of a card that is laid out larger: the zoom, not the document, shrank it *)
  let h = if shown = P.Chip && z_ = None then P.head_height *. z else h in
  let fill = if hovered && not selected then Pxui.Theme.hover_fill theme else theme.input in
  let edge = match failed with
    | Some _ -> Pxui.Theme.invalid
    | None -> card_edge t ~fill ~selected in
  paint_card paint ~x ~y ~w ~h ~fill ~edge;
  let lens = match n.lens, lens_step with Some l, Some step -> Some (l, step) | _ -> None in
  let lh = match lens with Some (l, step) -> P.lens_height l ~step | None -> 0. in
  let head = List.find_opt (fun (r : P.row) -> r.head) n.rows in
  (match z_ with
   | Some zn ->
       (* a collapsed zone: its kind as a label, the card's name, the toggle chevron *)
       paint_zone_label paint ui t ~z ~fs ~x:(x +. head_pad *. z) ~y ~w:(w -. head_pad *. z) ?execution n zn
   | None ->
       paint_header paint ui t ~z ~fs ~x ~y ~w n ~shown ?failed ?head ?execution
         ?lens_open:(if n.lens <> None && shown <> P.Chip then Some (lens <> None) else None) ());
  (* the displayed result at the end of its chain has no out-port: the view flag takes the place *)
  if out_wired || t.display <> Some n.path then
    paint_socket paint theme (Some n.ty) ~connected:out_wired ~z (x +. w -. 1. *. z, y +. port_y *. z);
  (* a literal binding is the header alone: its value in the field at the right *)
  (match n.rows with
   | [ r ] when P.value_card n -> paint_value paint ui t ~z ~fs ~size:fs ~x ~y ~w ~live:(live_numbers ~z r) r
   | _ -> ());
  let body_y = y +. P.body_top *. z in
  if shown <> P.Chip then begin
  (match n.note with
   | Some note ->
       let bg, ink = note_colors theme in
       Ui.Paint.fill paint ~x:(x +. 1.) ~y:body_y ~w:(w -. 2.) ~h:(P.row_height *. z) bg;
       let first = match String.index_opt note '\n' with Some i -> String.sub note 0 i | None -> note in
       text_in paint ui ~size:ls ~color:ink ~x:(x +. label_x *. z) ~y:body_y ~h:(P.row_height *. z)
         (fitted paint ls (w -. (label_x +. head_pad) *. z) first)
   | None -> ());
  let rows_y = body_y +. (if n.note <> None then P.row_height *. z else 0.) in
  (match z_ with
   | None ->
       paint_rows paint ui t ~z ~fs ~x ~y:rows_y ~w ~carry n p.lines ~selected_row:row_hover;
       if n.head = "list" || n.head = "str" then
         Array.iteri (fun k -> function
           | P.Row (_, ({ kind = P.Rest; key = E.Pos j; _ } : P.row)) when j >= 1 ->
               text_in paint ui ~size:fs ~color:theme.accent ~x:(x +. w -. 20. *. z) ~y:(rows_y +. float k *. P.row_height *. z)
                 ~h:(P.row_height *. z) "↑"
           | _ -> ()) p.lines;
       paint_outputs paint ui t ~z ~fs ~x ~y:rows_y ~w n ~nlines:(Array.length p.lines)
   | Some zn when p.collapsed -> paint_rail paint ui t ~z ~fs ~x ~y:body_y ~w ~expanded:false zn.rail
   | Some _ -> ());
  if shown = P.Full then
    Option.iter (fun f -> paint_footer paint ui t ~z ~fs f n.ty ~pad:(P.card_pad +. lh) (x, y, w, h)) footer;
  Option.iter (fun (l, step) -> paint_lens paint ui t ~z ~fs l ~step (x, y +. h -. (lh +. P.card_pad) *. z, w) ~lh) lens
  end;
  if selected then Ui.Paint.brackets paint ~x ~y ~w ~h ~offset:3. theme.accent

(* does anything inside the zone read this name (a loop variable shows its port only then)? *)
let zone_uses (zn : P.zone) names =
  let reads name = List.mem (root_name name) (List.map root_name names) in
  let rec scope (s : P.scope) =
    List.exists (fun (n : P.node) ->
      List.exists (fun (r : P.row) -> List.exists reads (P.sources r)) n.rows
      || (match n.zone with
          | Some z -> List.exists (fun (r : P.rail_row) ->
              match r.expr with Some e -> List.exists reads (E.free_names e) | None -> false) z.rail
              || scope z.scope
          | None -> false)) s.nodes
    || (match s.result with P.Link l -> reads l | _ -> false) in
  scope zn.scope

(* the expanded zone's label row, selector, rail rows and ports, over its tint; the cards inside
   are wired directly across its edge *)
let paint_zone_frame paint ui t ~z ~fs ?footer (n : P.node) (zn : P.zone) ~selected ~out_wired (x, y, w, h) ~probe ~count =
  let theme = t.theme in
  let execution = Option.bind t.records (fun records ->
    let chain = Option.value ~default:[] (Hashtbl.find_opt t.chains n.path) in
    Flow_graph.Probe.execution records n.path ~probes:(List.map t.probe chain)) in
  (* the zone's own footer under its body *)
  let h = match footer with
    | Some f -> paint_footer paint ui t ~z ~fs f n.ty ~pad:0. (x, y, w, h); h -. P.foot_height *. z
    | None -> h in
  (* the label clears the collection's in-port when a name feeds it *)
  let plain = zn.kind = P.For in
  let in_wired = not plain && (match P.label_row zn with
    | Some { key = Some _; expr = Some e; _ } -> E.free_names e <> [] | _ -> false) in
  let ind = if in_wired then 8. *. z else 0. in
  paint_zone_label paint ui t ~z ~fs ~x:(x +. ind) ~y ~w:(w -. ind) ?execution n zn;
  (* a plain [for] has no ports of its own on its edge: the label reads as the sheet's, and the
     yielded card wires straight to its consumer *)
  if not plain then
    paint_socket paint theme (Some n.ty) ~connected:out_wired ~z (x +. w -. 1. *. z, y +. port_y *. z);
  (match P.label_row zn with
   | Some r ->
       (* the collection's in-port when a name feeds it; the variable's out-port once something reads it *)
       (match r.expr with
        | Some e when (not plain) && r.key <> None && E.free_names e <> [] ->
            paint_socket paint theme r.ty ~connected:true ~z (x +. 1. *. z, y +. port_y *. z)
        | _ -> ());
       if zone_uses zn r.names then
         paint_socket paint theme r.ty ~connected:true ~z (x +. 12. *. z, y +. 36. *. z)
   | None -> ());
  if zn.kind <> P.Let && zn.kind <> P.State && zn.kind <> P.Branch then paint_selector paint ui t ~z ~fs ~count ~probe (x, y, w);
  paint_rail paint ui t ~z ~fs ~x ~y:(y +. P.head_height *. z) ~w ~expanded:true (P.extra_rails zn);
  if selected then Ui.Paint.brackets paint ~x ~y ~w ~h ~offset:3. theme.accent

(* a graph input is a value node: a header-only card with its value in a field at the right *)
let paint_input paint ui t ~z ~fs (i : P.input) ~selected (x, y, w, h) =
  let theme = t.theme in
  let hh = P.head_height *. z in
  paint_card paint ~x ~y ~w ~h ~fill:theme.input ~edge:(card_edge t ~fill:theme.input ~selected);
  Ui.Paint.fill paint ~x:(x +. head_pad *. z) ~y:(y +. 8. *. z) ~w:(8. *. z) ~h:(8. *. z) (ty_color t (Some i.ty));
  let fx = x +. value_x P.node_width *. z in
  text_in paint ui ~size:fs ~color:theme.foreground ~x:(x +. 23. *. z) ~y ~h:hh
    (fitted paint fs (Float.max 0. (fx -. 6. *. z -. (x +. 23. *. z))) i.name);
  (* a number is the live editor's (built in [update] at 13 points, like the sheet's header value);
     anything else is painted here *)
  (match i.default with
   | Some { S.node = S.Num _; _ } when z >= 0.5 -> ()
   | Some d ->
       let text = match d.node with S.Str s -> s | _ -> Flow.Lisp.flat d in
       let numeric = (match d.node with S.Num _ -> true | _ -> false) in
       paint_field paint ui ~z ~ls:fs ~theme ~x:fx ~y:(y +. 4. *. z) ~w:(field_w *. z) ~left:(not numeric)
         ~color:theme.foreground text
   | None ->
       paint_field paint ui ~z ~ls:fs ~theme ~x:fx ~y:(y +. 4. *. z) ~w:(field_w *. z) ~left:true
         ~color:(Pxui.Theme.ink_3 theme) (Ty.to_string i.ty));
  paint_socket paint theme (Some i.ty) ~connected:true ~z (x +. w -. 1. *. z, y +. port_y *. z);
  if selected then Ui.Paint.brackets paint ~x ~y ~w ~h ~offset:3. theme.accent

let paint_return paint ui t ~z ~fs (s : P.scope) ~selected (x, y, w, h) =
  let theme = t.theme in
  let hh = P.head_height *. z and rh = P.row_height *. z in
  paint_card paint ~x ~y ~w ~h ~fill:theme.input ~edge:(card_edge t ~fill:theme.input ~selected);
  Ui.Paint.fill paint ~x:(x +. head_pad *. z) ~y:(y +. 8. *. z) ~w:(8. *. z) ~h:(8. *. z) theme.foreground;
  text_in paint ui ~size:fs ~color:theme.foreground ~x:(x +. 23. *. z) ~y ~h:hh "return";
  let ry = y +. P.body_top *. z in
  text_in paint ui ~size:fs ~color:(Pxui.Theme.ink_2 theme) ~x:(x +. label_x *. z) ~y:ry ~h:rh "result";
  let right = x +. w -. head_pad *. z in
  (match s.result with
   | P.Link l ->
       let arrow = "\xe2\x86\x90" in
       let aw = Ui.Paint.text_width paint ~size:fs arrow and gap = 6. *. z in
       let l = fitted paint fs (w *. 0.5) l in
       let lw = Ui.Paint.text_width paint ~size:fs l in
       text_in paint ui ~size:fs ~color:theme.accent ~x:(right -. lw -. gap -. aw) ~y:ry ~h:rh arrow;
       text_in paint ui ~size:fs ~color:(Pxui.Theme.ink_2 theme) ~x:(right -. lw) ~y:ry ~h:rh l
   | Node _ -> ()
   | Literal e ->
       let text = fitted paint fs (w *. 0.5) (Flow.Lisp.flat e) in
       let tw = Ui.Paint.text_width paint ~size:fs text in
       text_in paint ui ~size:fs ~color:theme.foreground ~x:(right -. tw) ~y:ry ~h:rh text);
  paint_socket paint theme None ~connected:(s.result <> P.Literal (S.make (S.Sym "nil"))) ~z (x, ry +. 12. *. z);
  if selected then Ui.Paint.brackets paint ~x ~y ~w ~h ~offset:3. theme.accent

let paint_polyline ~clip paint ~width color pts =
  let rec go = function
    | a :: (b :: _ as rest) ->
        (match clip_segment a b clip with
         | Some (a, b) -> Ui.Paint.line paint ~from_:a ~to_:b ~width color
         | None -> ());
        go rest
    | _ -> () in
  go pts

(* the dashes of a loop's feedback or a switch's inactive wire *)
let paint_dashed_polyline paint ~width color pts =
  let rec go = function
    | a :: (b :: _ as rest) -> dashed_line paint ~width color a b; go rest
    | _ -> () in
  go pts

(* a bend: the 5-point square of the wire's colour on the line (kit [.bend]) *)
let paint_bends paint ~z color pts =
  match pts with
  | _ :: (_ :: _ as rest) ->
      let rec go = function
        | (x, y) :: (_ :: _ as more) ->
            let s = Float.max 3. (5. *. z) in
            Ui.Paint.fill paint ~x:(x -. 2. *. z) ~y:(Float.floor (y -. 2.5 *. z)) ~w:s ~h:s color; go more
        | _ -> () in
      go rest
  | _ -> ()

let paint_background paint t ~viewport ~wires (zones : (P.node * P.zone * P.placed * float * float) list) =
  let theme = t.theme in
  let vx, vy, vw, vh = viewport in
  let z = t.zoom in
  (* a dot every 24 points, thinned by powers of two so the dots stay 24 screen points apart or more *)
  let thin = if z >= 1. then 1. else 2. ** Float.ceil (Float.log2 (1. /. z) -. 1e-9) in
  let spacing = 24. *. z *. thin in
  Ui.Paint.fill paint ~x:vx ~y:vy ~w:vw ~h:vh theme.panel;
  Ui.Paint.grid paint ~x:vx ~y:vy ~w:vw ~h:vh
    ~origin:(vx +. Float.rem t.pan_x spacing -. 1., vy +. Float.rem t.pan_y spacing -. 1.) ~spacing ~dot:2.
    (Color.with_alpha theme.foreground 66);
  if z >= 0.5 then begin
    let px = 480. *. z and py = 192. *. z in
    let rem v m = let r = Float.rem v m in if r < 0. then r +. m else r in
    let x0 = vx +. rem (t.pan_x +. (84. *. z)) px and y0 = vy +. rem (t.pan_y +. (84. *. z)) py in
    let line = Pxui.Theme.border theme in
    let cx = ref x0 in
    while !cx < vx +. vw do
      let cy = ref y0 in
      while !cy < vy +. vh do
        Ui.Paint.fill paint ~x:(!cx -. 4.) ~y:!cy ~w:9. ~h:1. line;
        Ui.Paint.fill paint ~x:!cx ~y:(!cy -. 4.) ~w:1. ~h:9. line;
        cy := !cy +. py
      done;
      cx := !cx +. px
    done
  end;
  List.iter (fun ((node : P.node), (zn : P.zone), (p : P.placed), ax, ay) ->
    let taken = if zn.kind <> P.Branch then false else
      match t.records, List.rev node.path with
      | Some records, leaf :: outer ->
          (match String.rindex_opt leaf '#' with
           | None -> false
           | Some split ->
               let parent = List.rev outer @ [String.sub leaf 0 split] in
               let arm = String.sub leaf (split + 1) (String.length leaf - split - 1) in
               (match node_of t parent with
                | None -> false
                | Some parent ->
                    let index = if arm = "else" then List.length (List.filter (fun (r : P.row) ->
                      match r.key with E.Arm i -> i >= 0 | _ -> false) parent.rows)
                      else if arm = "then" then 0 else int_of_string (String.sub arm 5 (String.length arm - 5)) - 1 in
                    let chain = Option.value ~default:[] (Hashtbl.find_opt t.chains parent.path) in
                    Flow_graph.Probe.taken_arm records parent ~probes:(List.map t.probe chain) = Some index))
      | _ -> false in
    paint_zone ~taken paint theme zn.kind (sx t ax, sy t ay, p.w *. z, p.h *. z)) zones;
  (* titled frames sit under the wires *)
  List.iter (fun (scope_path, (ox, oy)) ->
    List.iter (fun (title, (fx, fy), (fw, fh)) ->
      let x = sx t (ox +. fx) and y = sy t (oy +. fy) in
      frame_in paint ~x ~y ~w:(fw *. z) ~h:(fh *. z) ~fill:(Color.with_alpha theme.foreground 8)
        (Pxui.Theme.edge theme);
      Ui.Paint.text paint ~at:(x +. 6., y +. 4.) ~size:(max 7 (int_of_float (10. *. z)))
        ~color:(Pxui.Theme.muted theme) title;
      (* delete cross top right, resize grip bottom right *)
      Ui.Paint.text paint ~at:(x +. fw *. z -. 14., y +. 4.) ~size:(max 7 (int_of_float (10. *. z)))
        ~color:(Pxui.Theme.muted theme) "x";
      let ink = Pxui.Theme.ink_3 theme in
      Ui.Paint.fill paint ~x:(x +. fw *. z -. 4.) ~y:(y +. fh *. z -. 11.) ~w:1. ~h:8. ink;
      Ui.Paint.fill paint ~x:(x +. fw *. z -. 11.) ~y:(y +. fh *. z -. 4.) ~w:8. ~h:1. ink) (frame_list t scope_path)) t.geo.origins;
  List.iter (fun i ->
    let w = t.geo.wires.(i) in
    let pts = List.map (fun (x, y) -> sx t x, sy t y) w.pts in
    let is_selected = match t.selected_wire, w.target with
      | Some (sp, sk, _), Some (tp, tk, _) -> sp = tp && sk = tk
      | _ -> false in
    let is_highlighted = List.mem w t.highlighted in
    let width = if is_highlighted then Float.max 2. (2.4 *. z) else Float.max 1. (1.5 *. z) in
    (* a switch's active wire is solid and accented, the others dashed grey *)
    let layout = match w.target with
      | Some (p, E.Pos i, _) -> Option.map (fun a -> i = a) (List.assoc_opt p t.switches)
      | _ -> None in
    let color = if is_selected then theme.foreground else if layout = Some true then theme.accent
      else if layout = Some false then Pxui.Theme.muted theme else ty_color t w.ty in
    if layout = Some false || w.dashed then paint_dashed_polyline paint ~width color pts
    else paint_polyline ~clip:viewport paint ~width color pts;
    if t.wires = `Straight then paint_bends paint ~z color pts) wires

(* ---------------------------------------------------------------- update *)

let left_button (s : Ui.signal) = s.button = Some Input.LeftButton
let contains (x, y, w, h) (px, py) = px >= x && px < x +. w && py >= y && py < y +. h

(* the number field of a row, the kit's ([Editor_core.Number], as [Pxui_shell.Kit.number]): the kind
   is the row's type, and only a literal with no typed row behind it is read by its spelling *)
let num_field ui ~at ~w ~h ?size ?kind ?range label text =
  let module N = Editor_core.Number in
  let kind = match kind with
    | Some kind -> kind
    | None -> if String.exists (fun c -> c = '.' || c = 'e') text then N.Float else N.Int in
  let valid s = match float_of_string_opt s with Some f -> Float.is_finite f | None -> false in
  let text', _ = Ui.value_field ui ~at ~w ~h ?size ?fraction:(Option.bind range (fun r -> N.fraction r text))
      ~scrub:(N.scrub kind ?range) ~valid label text in
  if text' <> text && valid text' then Some text' else None

(* what a row's field is: its type's kind (a vector's cells are floats) and its soft range *)
let kind_of (r : P.row) = match r.ty with
  | Some (Ty.Float | Ty.Vec2 | Ty.Vec3 | Ty.Vec4) -> Some Editor_core.Number.Float
  | Some Ty.Int -> Some Editor_core.Number.Int
  | _ -> None
let range_of (r : P.row) = match r.control with P.Range (lo, hi) -> Some (lo, hi) | _ -> None

(* the row of a card at a point of it ([px], [py] relative to the card, graph units): the header's
   in-port row at the top left (anywhere in the header with [header]), else the row of the line
   there; nothing for a folder label or a card drawn as a chip or point *)
let row_at ?(header = 14.) (p : P.placed) (n : P.node) ~shown ~px ~py =
  if shown = P.Point || shown = P.Chip then
    (if px < header && py < P.head_height then List.find_index (fun (r : P.row) -> r.head) n.rows else None)
  else if py < P.body_top then
    (if px < header then List.find_index (fun (r : P.row) -> r.head) n.rows else None)
  else
    let k = int_of_float (Float.floor ((py -. P.body_top -. note_rows n *. P.row_height) /. P.row_height)) in
    if k < 0 || k >= Array.length p.lines then None
    else match p.lines.(k) with P.Row (i, _) -> Some i | _ -> None

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
  match t.imported path, node_of t path with
  | Some file, _ -> ["Open " ^ file, true]
  | None, None -> []
  | None, Some n ->
      let parent, arm = conditional_target n in
      let conditional = Option.fold ~none:false ~some:(fun (n : P.node) -> List.mem n.head ["cond"; "case"]) (node_of t parent) in
      let zone = match n.zone with Some { kind = P.Let; _ } | None -> None | Some _ -> Some n in
      [ "Fold into its use", true; "Unfold a call", true; "Hoist out", n.invariant;
        (match zone with Some n -> if t.collapsed n.path then "Expand zone" else "Collapse zone"
                       | None -> "Collapse zone"), zone <> None;
        "Toggle bypass", true; "Repeat (loop)", true; "Iterate (feed back)", true;
        "Make function", true; "Make macro", true; "Make defn", true; "Delete", true;
        "Wrap conditional", true; "Add arm", conditional;
        (if parent = n.path then "Delete first arm" else "Delete arm"), conditional && (parent = n.path || arm >= 0) ]

let context_command = function
  | 0 -> Fold_into | 1 -> Unfold | 2 -> Hoist | 3 -> Collapse | 4 -> Bypass
  | 5 -> Wrap_repeat | 6 -> Wrap_iterate | 7 -> Make_fn | 8 -> Make_macro | 9 -> Make_defn
  | 11 -> Wrap_if | 12 -> Add_arm | 13 -> Delete_arm | _ -> Delete

let update t ui (frame : Frame.t) =
  (* the first view shows the whole graph, at zoom 1 when it fits (Home frames everything) *)
  let t = if t.framed then t else { (frame_all t) with framed = true } in
  let changes = ref [] in
  let emit c = changes := c :: !changes in
  let t, hint_changes = step_hints t frame in
  List.iter emit hint_changes;
  let canvas = Ui.box ui ~flags:Ui.(clickable + scroll + clip + blocking)
      ~w:(Ui.Px (float t.width)) ~h:(Ui.Px (float t.height))
      ~at:(float t.x, float t.y) "pxui-scope" in
  let canvas_signal = Ui.signal ui canvas in
  (* the grid, zones and wires paint in a child, so the canvas's clip holds them too *)
  let layer = Ui.within ui canvas (fun () ->
    Ui.box ui ~w:(Ui.Px (float t.width)) ~h:(Ui.Px (float t.height)) ~at:(0., 0.) "pxui-scope-layer") in
  let t =
    let _, wheel = canvas_signal.scroll in
    let pinch = canvas_signal.pinch in
    if (wheel = 0. && pinch = 1.) || t.context <> None then t else begin
      let mx, my = frame.mouse in
      (* the wheel steps by a tenth; a pinch carries its own factor *)
      let zoom = Float.max 0.25 (Float.min 2.5 (t.zoom *. (1. +. wheel *. 0.1) *. pinch)) in
      let k = zoom /. t.zoom in
      { t with zoom; pan_x = (mx -. float t.x) -. ((mx -. float t.x) -. t.pan_x) *. k;
        pan_y = (my -. float t.y) -. ((my -. float t.y) -. t.pan_y) *. k }
    end in
  let t = { t with measure = (fun size s -> Ui.text_width ui ~size s) } in
  let t = match t.scope with
    | Some scope when font_of t.zoom <> t.geo_fs ->
        (* a point's box is as wide as its name, drawn at the zoom's font *)
        if Array.exists (fun ((p : P.placed), _, _) -> p.shown = P.Point) t.geo.items
        then regeo t scope t.layout ~shift:no_shift else { t with geo_fs = font_of t.zoom }
    | _ -> t in
  (* a drag in progress moves its items in a fresh geometry *)
  let t = match t.drag, t.scope with
    | Some (Moving m), Some scope when m.moved ->
        let moving = Path_set.of_list m.paths in
        regeo t scope t.layout ~shift:(fun p -> if Path_set.mem p moving then m.dx, m.dy else 0., 0.)
    | Some (Carrying c), Some scope when Float.hypot c.dx c.dy > 0. ->
        let moving = Path_set.of_list c.paths in
        regeo t scope t.layout ~shift:(fun p -> if Path_set.mem p moving then c.dx, c.dy else 0., 0.)
    | _ -> t in
  let z = t.zoom in
  (* text follows the zoom down to 5 points (a 6-point row at zoom 0.25 holds it) *)
  let fs = font_of z in
  let viewport = (float t.x, float t.y, float t.width, float t.height) in
  (* what the pane shows, grown by [margin] screen points, in graph units: the indices answer it *)
  let in_view margin =
    (-. t.pan_x -. margin) /. z, (-. t.pan_y -. margin) /. z,
    (float t.width -. t.pan_x +. margin) /. z, (float t.height -. t.pan_y +. margin) /. z in
  let visible = List.filter_map (fun i ->
    let ((p : P.placed), ax, ay) as item = t.geo.items.(i) in
    let x = sx t ax -. 20. and y = sy t ay -. 20. and w = p.w *. z +. 40. and h = p.h *. z +. 40. in
    let vx, vy, vw, vh = viewport in
    if x < vx +. vw && x +. w > vx && y < vy +. vh && y +. h > vy then Some item else None)
    (index_query t.geo.tiles (in_view 20.)) in
  let wires_in_view = index_query t.geo.reach (in_view 4.) in
  let zones = List.filter_map (fun ((p : P.placed), ax, ay) -> match p.item with
    | P.Item ({ zone = Some zn; _ } as n) when not p.collapsed -> Some (n, zn, p, ax, ay)
    | _ -> None) visible in
  let local (x, y) = x -. float t.x, y -. float t.y in
  let mouse = frame.mouse in
  (* Segment rectangles live in the shared hit tree, behind the cards; ports built below take
     hover precedence.  A segment is cut to [clip] (pane points) first, so what is out of view
     costs one clip; a diagonal is then a run of 16-point boxes. *)
  let wire_hits = Cells.create 16 in
  let hits i = Option.value ~default:[] (Cells.find_opt wire_hits i) in
  let wire_boxes ?(origin = (0., 0.)) name (cx, cy, cw, ch) i =
    let w = t.geo.wires.(i) in
    let count = ref 0 in
    let prefix = name ^ ":" ^ string_of_int i ^ ":" in
    let rec segments j = function
      | (ax, ay) :: ((bx, by) :: _ as rest) ->
          (match clip_segment (sx t ax -. float t.x, sy t ay -. float t.y) (sx t bx -. float t.x, sy t by -. float t.y)
                   (cx -. 4., cy -. 4., cw +. 8., ch +. 8.) with
           | None -> ()
           | Some ((ax, ay), (bx, by)) ->
               let steps = if ax = bx || ay = by then 1 else max 1 (int_of_float (Float.hypot (bx -. ax) (by -. ay) /. 16.)) in
               let prefix = prefix ^ string_of_int j ^ "-" in
               for s = 0 to steps - 1 do
                 let u0 = float s /. float steps and u1 = float (s + 1) /. float steps in
                 let x0 = ax +. (bx -. ax) *. u0 and y0 = ay +. (by -. ay) *. u0
                 and x1 = ax +. (bx -. ax) *. u1 and y1 = ay +. (by -. ay) *. u1 in
                 incr count;
                 Cells.replace wire_hits i (Ui.box ui ~flags:Ui.clickable
                     ~at:(Float.min x0 x1 -. 4. -. fst origin, Float.min y0 y1 -. 4. -. snd origin)
                     ~w:(Ui.Px (abs_float (x1 -. x0) +. 8.)) ~h:(Ui.Px (abs_float (y1 -. y0) +. 8.))
                     (prefix ^ string_of_int !count) :: hits i)
               done);
          segments (j + 1) rest
      | _ -> () in
    if w.target <> None then segments 0 w.pts in
  Ui.within ui canvas (fun () ->
    List.iter (wire_boxes "wire" (0., 0., float t.width, float t.height)) wires_in_view);
  (* footers: only for what is in view, and not when too small to read *)
  let footers = Hashtbl.create 16 in
  (match t.records with
   | Some records when z >= 0.4 ->
       List.iter (fun ((p : P.placed), _, _) -> match p.item with
         | P.Item n when (match n.zone with Some _ -> p.collapsed | None -> true) ->
             let chain = Option.value ~default:[] (Hashtbl.find_opt t.chains n.path) in
             Hashtbl.replace footers n.path (Flow_graph.Probe.footer records n ~probes:(List.map t.probe chain))
         | _ -> ()) visible
   | _ -> ());
  let finished = ref false and opened = ref None in
  let edit_field ~at ~w ~h key current valid commit =
    let v, open_ = Ui.value_field ui ~at ~w ~h ~size:fs ~edit:true
      ~left:(float_of_string_opt current = None) ~valid key current in
    if not open_ then finished := true;
    if (not open_) && v <> current && valid v then [ commit v ] else [] in
  (* tiles *)
  let tiles = Ui.within ui canvas (fun () ->
    List.map (fun ((p : P.placed), ax, ay) ->
      let bx, by = sx t ax, sy t ay in
      let key = "t:" ^ String.concat "/" p.path in
      let w = p.w *. z and h = p.h *. z in
      let shown = p.shown in
      let tile = Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px w) ~h:(Ui.Px h) ~at:(local (bx, by)) key in
      (* an expanded zone's tile covers its body: the wires that end inside it get their boxes again
         here, over the tile and under the cards built after it *)
      (match p.item with
       | P.Item { zone = Some _; _ } when not p.collapsed ->
           let lx, ly = local (bx, by) in
           let x0 = Float.max 0. lx and y0 = Float.max 0. ly in
           let clip = x0, y0, Float.min (float t.width) (lx +. w) -. x0, Float.min (float t.height) (ly +. h) -. y0 in
           Ui.within ui tile (fun () ->
             List.iter (wire_boxes ~origin:(lx, ly) "zwire" clip)
               (Option.value ~default:[] (Hashtbl.find_opt t.geo.inside p.path)))
       | _ -> ());
      (* the live editors of a row: a number, a vector of numbers, a flag *)
      let row_fields (n : P.node) (r : P.row) ~name ~ry ~size =
        let at = value_x p.w *. z and vw = field_w *. z and h = field_h *. z in
        let ay = (ry +. 4.) *. z in
        match r.chip, r.expr with
        | P.Const, Some ({ node = S.Num text; _ }) ->
            (match num_field ui ~at:(at, ay) ~w:vw ~h ~size ?kind:(kind_of r) ?range:(range_of r) ("f" ^ name) text with
             | Some text' -> [ Syntax_edit (E.Set_arg { node = n.path; key = r.key; sub = [];
                 value = S.make (S.Num text') }) ]
             | None -> [])
        | P.Const, Some { node = S.Vec elems; _ }
          when List.length elems >= 2 && List.length elems <= 4 && all_numbers elems ->
            let k = List.length elems in
            (* a vector is its fields 8 points apart, 112 wide, at the row's right *)
            let at = (p.w -. head_pad -. vec_w) *. z and gap = 8. *. z in
            let cw = (vec_w *. z -. float (k - 1) *. gap) /. float k in
            List.concat (List.mapi (fun c (e : S.t) -> match e.node with
              | S.Num text ->
                  (match num_field ui ~at:(at +. float c *. (cw +. gap), ay) ~w:cw ~h ~size ?kind:(kind_of r)
                           (Printf.sprintf "f%s.%d" name c) text with
                   | Some text' -> [ Syntax_edit (E.Set_arg { node = n.path; key = r.key; sub = [ c ];
                       value = S.make (S.Num text') }) ]
                   | None -> [])
              | _ -> []) elems)
        | P.Const, Some { node = S.Sym (("true" | "false") as b); _ } ->
            let toggle = Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px (switch_w *. z)) ~h:(Ui.Px (switch_h *. z))
                ~at:((p.w -. head_pad -. switch_w) *. z, (ry +. 5.) *. z) ("b" ^ name) in
            if (Ui.signal ui toggle).clicked then
              [ Syntax_edit (E.Set_arg { node = n.path; key = r.key; sub = [];
                  value = S.make (S.Sym (if b = "true" then "false" else "true")) }) ]
            else []
        | _ -> [] in
      let sub = Ui.within ui tile (fun () ->
        let box ?(flags = Ui.clickable) name (dx, dy) (bw, bh) =
          Ui.box ui ~flags ~w:(Ui.Px (bw *. z)) ~h:(Ui.Px (bh *. z)) ~at:(dx *. z, dy *. z) name in
        let outs = ref [] and dels = ref [] and taps = ref [] and inputs = ref [] in
        let input name pos =
          let b = box name (fst pos -. 7., snd pos -. 7.) (14., 14.) in
          inputs := b :: !inputs; b in
        let out name src ty pos = outs := (box name (fst pos -. 7., snd pos -. 7.) (14., 14.), src, ty) :: !outs in
        let tap name pos size on = taps := (box name pos size, on) :: !taps in
        (match p.item with
         | P.Input i -> out "out" i.name (Some i.ty) (if shown = P.Point then (p.w, P.point_size /. 2.) else (p.w -. 1., port_y))
         | Return -> ignore (input "in" (0., P.body_top +. 12.))
         | Item n ->
             let node_src = if n.binds = [ n.name ] then Some n.name else None in
             let plain_for = (match n.zone with Some { kind = P.For; _ } -> not p.collapsed | _ -> false) in
             Option.iter (fun s ->
               if not plain_for then out "out" s (Some n.ty) (if shown = P.Point then (p.w, P.point_size /. 2.) else (p.w -. 1., port_y)))
               node_src;
             (* the header's in-port: the first geometry slot *)
             (match List.find_opt (fun (r : P.row) -> r.head) n.rows with
              | Some r when n.zone = None ->
                  let sink = input "d:head" (if shown = P.Point then (0., P.point_size /. 2.) else (1., port_y)) in
                  if wired r then dels := (sink, unwire n r) :: !dels
              | _ -> ());
             (match n.zone with
              | Some zn when not p.collapsed ->
                  (* the label row's variable: the collection's in-port at the edge, the variable's
                     out-port in the left strip once something reads it *)
                  Option.iter (fun (r : P.rail_row) ->
                    if r.key <> None && zn.kind <> P.For then begin
                      let sink = input "rd:label" (1., port_y) in
                      (match r.key, r.expr with
                       | Some key, Some e when E.free_names e <> [] ->
                           dels := (sink, [ E.Disconnect { node = n.path; key; fallback = None } ]) :: !dels
                       | _ -> ())
                    end;
                    if zone_uses zn r.names then out "rail:label" (List.hd r.names) r.ty (12., 36.)) (P.label_row zn);
                  List.iteri (fun i (r : P.rail_row) ->
                    let cy = P.head_height +. float i *. P.row_height +. 12. in
                    out ("rail:" ^ string_of_int i) (List.hd r.names) r.ty (p.w -. 12., cy);
                    (* wired rail rows can be disconnected from their socket *)
                    let sink = if r.key <> None then Some (input ("rd:" ^ string_of_int i) (0., cy)) else None in
                    (match r.key, r.expr, sink with
                     | Some key, Some e, Some sink when E.free_names e <> [] ->
                         dels := (sink,
                                  [ E.Disconnect { node = n.path; key; fallback = None } ]) :: !dels
                     | _ -> ())) (P.extra_rails zn);
                  if zn.kind <> P.Let && zn.kind <> P.State && zn.kind <> P.Branch then begin
                    (* the selector of the label row: a button each side of the reading *)
                    let sx, sy, sw, sh, _ = selector_geo ~measure:t.measure ~z ~fs ~w:(p.w *. z) ~count:(count_of t n.path) ~probe:(t.probe n.path) in
                    let sx = sx /. z and sy = sy /. z and sw = sw /. z and sh = sh /. z in
                    tap "prev" (sx -. 4., sy) (16., sh) (`Step (-1));
                    tap "next" (sx +. sw -. 12., sy) (16., sh) (`Step 1);
                    tap "track" (sx +. 12., sy) (sw -. 24., sh) `Track
                  end;
                  if zn.kind <> P.Let then tap "toggle" (0., 0.) (64., P.head_height) `Toggle
              | Some zn when p.collapsed ->
                  List.iteri (fun i (r : P.rail_row) ->
                    if r.key <> None || r.role = P.Capture then
                      ignore (input ("rd:" ^ string_of_int i)
                        (0., P.body_top +. (float i +. 0.5) *. P.row_height))) zn.rail;
                  if zn.kind <> P.Let then tap "toggle" (head_pad, 0.) (64., P.head_height) `Toggle
              | Some _ -> ()
              | None ->
                  (match n.lens with
                   | Some l when shown <> P.Point && shown <> P.Chip ->
                       tap "lens" (p.w -. 22., 2.) (20., 20.) `Lens;
                       (match lens_of t n.path with
                        | Some step ->
                            let lh = P.lens_height l ~step in
                            let top = lens_top p.h lh in
                            let len = Array.length l.steps in
                            for i = 0 to len do
                              let (bx, by), size = lens_button_box ~len i in
                              tap ("ls" ^ string_of_int i) (bx, top +. by) size (`Lens_step i)
                            done;
                            let (rx, ry), size = lens_replace_box lh in
                            tap "lr" (rx, top +. ry) size `Replace
                        | None -> ())
                   | _ -> ());
                  if shown = P.Card || shown = P.Full then begin
                    let top = rows_top n 0. in
                    let nlines = Array.length p.lines in
                    List.iteri (fun j (f, ty) ->
                      let src = if n.binds = [ n.name ] then n.name ^ "." ^ f else f in
                      out ("o:" ^ string_of_int j) src (Some ty)
                        (p.w, top +. (float (nlines + j) +. 0.5) *. P.row_height)) n.outputs;
                    Array.iteri (fun k -> function
                      | P.Row (i, r) ->
                          let ry = top +. float k *. P.row_height in
                          if r.socket then begin
                            let sink = input ("d:" ^ string_of_int i) (0., ry +. 12.) in
                            if wired r then dels := (sink, unwire n r) :: !dels
                          end
                      | P.Folder _ -> ()) p.lines
                  end));
        List.rev !outs, List.rev !dels, List.rev !taps, !inputs) in
      (* fields, inside the tile *)
      let fields = match p.item with
        | P.Item ({ zone = None; _ } as n) when z >= 0.5 && P.value_card n ->
            (* a literal binding: its value is the field of its header, at body size *)
            Ui.within ui tile (fun () ->
              List.concat_map (fun (r : P.row) -> row_fields n r ~name:"v" ~ry:0. ~size:fs) n.rows)
        | P.Item ({ zone = None; _ } as n) when z >= 0.5 && (shown = P.Card || shown = P.Full) ->
            Ui.within ui tile (fun () ->
              let top = rows_top n 0. in
              List.concat (List.mapi (fun k line -> match line with
                | P.Row (i, r) -> row_fields n r ~name:(string_of_int i) ~ry:(top +. float k *. P.row_height) ~size:(max 4 (fs - 2))
                | _ -> []) (Array.to_list p.lines)))
        | P.Input ({ default = Some { node = S.Num text; _ }; _ } as i) when z >= 0.5 && t.editing <> Some (Default p.path) ->
            (* a value node: its number is a field in the header, at body size *)
            Ui.within ui tile (fun () ->
              match num_field ui ~at:(value_x p.w *. z, 4. *. z) ~w:(field_w *. z) ~h:(field_h *. z) ~size:fs "default" text with
              | Some text' -> [ Syntax_edit (E.Set_input_default { form = List.hd i.path; input = i.name;
                                value = S.make (S.Num text') }) ]
              | None -> [])
        | _ -> [] in
      let add_clicks = match p.item with
        | P.Item ({ zone = None; _ } as n) when z >= 0.5 && (shown = P.Card || shown = P.Full) ->
            Ui.within ui tile (fun () ->
              let top = rows_top n 0. in
              List.concat (List.mapi (fun k line -> match line with
                | P.Row (i, r) when r.kind = P.Add || (match r.chip with P.Inline _ -> true | _ -> false) ->
                let b = Ui.box ui ~flags:Ui.(clickable + tab_stop)
                    ~w:(Ui.Px (if r.kind = P.Add then (p.w -. label_x -. head_pad) *. z else 24. *. z)) ~h:(Ui.Px (16. *. z))
                    ~at:((if r.kind = P.Add then label_x else value_x p.w) *. z, (top +. float k *. P.row_height +. 4.) *. z)
                    ("a" ^ string_of_int i) in
                if not (Ui.signal ui b).clicked then [] else
                (match r.kind, r.chip with
                 | P.Add, _ ->
                     (match r.key with
                      | E.Field _ ->
                          (* the first [fN] the record does not have *)
                          let rec free i =
                            let name = "f" ^ string_of_int i in
                            if List.exists (fun (r : P.row) -> r.key = E.Field name) n.rows then free (i + 1) else name in
                          [ Syntax_edit (E.Add_field { node = n.path; name = free 1;
                          value = S.make (S.Num "0") }) ]
                      | E.Kw "" -> opened := Some (Output n.path); []  (* a new output is named first *)
                      | _ when n.head = "list" || n.head = "str" -> [ Syntax_edit (E.Add_item { node = n.path }) ]
                      | key ->
                          (* a type with no literal (geometry, a list, a function, a scene) is wired *)
                          (match r.ty with
                           | Some (Flow.Ty.Named "geometry") -> [ Notice "Wire a node onto this row" ]
                           | Some ty ->
                               (match E.default_for ty r.label with
                                | Some value -> [ Syntax_edit (E.Set_arg { node = n.path; key; sub = []; value }) ]
                                | None -> [ Notice "Wire a node onto this row" ])
                           | None -> [ Syntax_edit (E.Set_arg { node = n.path; key; sub = []; value = S.make (S.Num "0") }) ]))
                 | _, P.Inline _ -> [ Syntax_edit (E.Unfold { node = n.path; key = r.key; sub = [] }) ]
                 | _ -> [])
                | P.Row (i, (({ chip = P.Name s; _ } : P.row) as r)) when Hashtbl.mem t.folds (n.path, i) ->
                    (* the fold button of a wired row, where [paint_value] draws its glyph *)
                    let left, fw, _, _, _ = wired_geo ~measure:t.measure t ~z ~fs ~x:0. ~w:(p.w *. z) ~fold:true (wired_name r s) in
                    let b = Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px fw) ~h:(Ui.Px (16. *. z))
                        ~at:(left -. fw -. 2. *. z, (top +. float k *. P.row_height +. 4.) *. z) ("fold" ^ string_of_int i) in
                    if (Ui.signal ui b).clicked
                    then [ Syntax_edit (E.Fold_into { node = Hashtbl.find t.folds (n.path, i) }) ] else []
                | P.Row (i, { chip = P.Name s; _ }) when not (E.nested s) ->
                    (* a row that reads a binding: a click on its name selects that binding *)
                    let root = List.hd (String.split_on_char '.' s) in
                    let rec target k =
                      if k < 0 then None else
                      let cand = List.filteri (fun j _ -> j < k) n.path @ [ root ] in
                      if node_of t cand <> None || input_of t cand <> None then Some cand else target (k - 1) in
                    (match target (List.length n.path - 1) with
                     | None -> []
                     | Some cand ->
                         let left, width = ref_chip_geo t ~z ~fs ~w:(p.w *. z) s in
                         let b = Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px width) ~h:(Ui.Px (16. *. z))
                             ~at:(left, (top +. float k *. P.row_height +. 4.) *. z) ("ref" ^ string_of_int i) in
                         if (Ui.signal ui b).clicked then [ Selected [ cand ] ] else [])
                | _ -> []) (Array.to_list p.lines)))
        | _ -> [] in
      let editors = match t.editing, p.item with
        | Some (Name path), P.Item n when path = n.path ->
            Ui.within ui tile (fun () ->
              edit_field ~at:(21. *. z, 3. *. z) ~w:((p.w -. 21. -. head_pad) *. z) ~h:(18. *. z) "name" (P.title n) valid_name
                (fun v -> Syntax_edit (E.Rename { node = n.path; to_ = v })))
        | Some (Output path), P.Item n when path = n.path ->
            (match Array.find_index (function P.Row (_, { kind = P.Add; key = E.Kw ""; _ }) -> true | _ -> false) p.lines with
             | Some k ->
                 Ui.within ui tile (fun () ->
                   edit_field ~at:(label_x *. z, (rows_top n 0. +. float k *. P.row_height +. 4.) *. z)
                     ~w:((p.w -. label_x -. head_pad) *. z) ~h:(field_h *. z) "output" "" valid_name
                     (fun v -> Syntax_edit (E.Add_field { node = n.path; name = v; value = S.make (S.Num "0") })))
             | None -> finished := true; [])
        | Some (Default path), P.Input i when path = i.path ->
            Ui.within ui tile (fun () ->
              let text = match i.default with Some d -> Flow.Lisp.flat d | None -> "" in
              edit_field ~at:(value_x p.w *. z, 4. *. z) ~w:(field_w *. z) ~h:(field_h *. z) "default" text
                (fun v -> single_form v <> None)
                (fun v -> Syntax_edit (E.Set_input_default { form = List.hd i.path; input = i.name;
                  value = Option.get (single_form v) })))
        | _ -> [] in
      let movers = match p.item with
        | P.Item n when P.reorderable n && z >= 0.5 && (shown = P.Card || shown = P.Full) ->
            Ui.within ui tile (fun () ->
              let top = rows_top n 0. in
              List.concat (List.mapi (fun k line -> match line with
                | P.Row (i, ({ kind = P.Rest; key = E.Pos j; _ } : P.row)) when j >= 1 ->
                    let b = Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px (16. *. z)) ~h:(Ui.Px (16. *. z))
                        ~at:((p.w -. 22.) *. z, (top +. float k *. P.row_height +. 4.) *. z) ("mv" ^ string_of_int i) in
                    if (Ui.signal ui b).clicked then [ Syntax_edit (E.Move_item { node = n.path; pos = j }) ] else []
                | _ -> []) (Array.to_list p.lines)))
        | _ -> [] in
      (* a switch's rows: a click on a layout's name makes it the active one *)
      let switchers = match p.item, List.assoc_opt p.path t.switches with
        | P.Item n, Some active when z >= 0.5 && (shown = P.Card || shown = P.Full) ->
            Ui.within ui tile (fun () ->
              let top = rows_top n 0. in
              List.concat (List.mapi (fun k line -> match line with
                | P.Row (i, ({ key = E.Pos j; kind; _ } : P.row)) when kind <> P.Add && j <> active ->
                    let b = Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px ((p.w -. 24.) *. z)) ~h:(Ui.Px (16. *. z))
                        ~at:(12. *. z, (top +. float k *. P.row_height +. 4.) *. z) ("sw" ^ string_of_int i) in
                    if (Ui.signal ui b).clicked then [ Syntax_edit (E.Set_layout { graph = t.key; index = j }) ] else []
                | _ -> []) (Array.to_list p.lines)))
        | _ -> [] in
      p, ax, ay, tile, Ui.signal ui tile, sub, fields @ add_clicks @ editors @ movers @ switchers) visible) in
  let t = if !finished then { t with editing = None } else t in
  (* a payload in flight: the innermost node under the pointer (a zone's tile covers its body),
     else the canvas, is where it would be put; the host decides whether it takes it *)
  (match Ui.drop_target ui canvas with
   | None -> ()
   | Some _ ->
       let area (p : P.placed) = p.w *. p.h in
       let found = List.fold_left (fun best ((p : P.placed), _, _, tile, _, _, _) ->
         match Ui.drop_target ui tile, best with
         | Some _, Some (q, _) when area q <= area p -> best
         | Some d, _ -> Some (p, d)
         | None, _ -> best) None tiles in
       let path, drop = match found, Ui.drop_target ui canvas with
         | Some ((p : P.placed), d), _ -> p.path, d
         | None, Some d -> [ t.key ], d
         | None, None -> [ t.key ], Ui.Hover { Ui.kind = ""; value = "" } in
       emit (match drop with
         | Ui.Hover { kind; value } -> Drop_over { path; kind; value }
         | Dropped { kind; value } -> Dropped { path; kind; value }));
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
          let inside path = scope_of_path path = scope && (match box_at t path with
            | Some (bx, by, bw, bh) ->
                let cx = bx +. bw /. 2. and cy = by +. bh /. 2. in
                cx >= ox +. fx && cx <= ox +. fx +. fw && cy >= oy +. fy && cy <= oy +. fy +. fh
            | None -> false) in
          let paths = Array.fold_left (fun found ((p : P.placed), _, _) -> if inside p.path then p.path :: found else found) [] t.geo.items in
          let dx = (fst ts.pointer -. fst ts.press_point) /. z and dy = (snd ts.pointer -. snd ts.press_point) /. z in
          { t with drag = Some (Carrying { scope; index = i; paths; dx; dy }) }
      | Some (Carrying c) when c.scope = scope && c.index = i && (ts.held || ts.released) ->
          let ddx, ddy = ts.drag in
          let t = { t with drag = Some (Carrying { c with dx = c.dx +. ddx /. z; dy = c.dy +. ddy /. z }) } in
          if ts.released then begin
            (match t.drag with
             | Some (Carrying c) when Float.hypot c.dx c.dy > 3. /. z ->
                 emit (Moved (List.filter_map (fun path -> match rel_at t path with
                   | Some (rx, ry) -> Some (path, P.snap (rx +. c.dx), P.snap (ry +. c.dy))
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
  let t = match !opened with Some _ as editing -> { t with editing } | None -> t in
  (* hovered row and chip expansion *)
  let hover = List.find_map (fun ((p : P.placed), ax, ay, tile, _, _, _) ->
    match p.item with
    | P.Item ({ zone = None; _ } as n) when Ui.hovered_within ui tile ->
        let px = (fst mouse -. sx t ax) /. z and py = (snd mouse -. sy t ay) /. z in
        (match row_at p n ~shown:(p.shown) ~px ~py with
         | Some i when i < List.length n.rows -> Some (n, ax, ay, i)
         | _ -> None)
    | _ -> None) tiles in
  let hovered_row = Option.map (fun ((n : P.node), _, _, i) -> n.path, (List.nth n.rows i).P.key) hover in
  let port_centre box = if Ui.hovered_within ui box then
    let x, y, w, h = Ui.rect ui box in Some (x +. w /. 2., y +. h /. 2.) else None in
  let hovered_port = List.find_map (fun (_, _, _, _, _, (outs, _, _, inputs), _) ->
    match List.find_map (fun (box, _, _) -> port_centre box) outs with
    | Some _ as port -> port
    | None -> List.find_map port_centre inputs) tiles in
  let same_port point = match hovered_port with
    | None -> false
    | Some (x, y) -> abs_float (sx t (fst point) -. x) <= 1.5 *. z +. 0.5
        && abs_float (sy t (snd point) -. y) <= 1.5 *. z +. 0.5 in
  let highlighted = ref [] in
  List.iter (fun i ->
    let w = t.geo.wires.(i) in
    if t.context = None &&
      (List.exists (Ui.hovered_within ui) (hits i) || same_port w.a || same_port w.b)
    then highlighted := w :: !highlighted) wires_in_view;
  let t = { t with hovered_row; highlighted = !highlighted } in
  (* interactions *)
  let left (s : Ui.signal) = s.button = Some Input.LeftButton in
  let non_left_pressed (s : Ui.signal) = s.pressed && s.button <> Some Input.LeftButton && s.button <> None in
  let non_left_held (s : Ui.signal) = s.held && s.button <> Some Input.LeftButton && s.button <> None in
  let non_left_released (s : Ui.signal) = s.released && s.button <> Some Input.LeftButton && s.button <> None in
  let all_signals = canvas_signal :: List.map (fun (_, _, _, _, (s : Ui.signal), _, _) -> s) tiles in
  let panning = List.exists (fun (s : Ui.signal) -> non_left_held s || non_left_released s) all_signals in
  let pan_pressed = List.exists non_left_pressed all_signals in
  let pan_released = List.exists non_left_released all_signals in
  let lost = List.exists (function Rays.Event.WindowFocusLost -> true | _ -> false) frame.events in
  let panning_grab =
    if pan_pressed || panning then true
    else if pan_released || lost || frame.mouse_buttons = [] then false
    else t.panning_grab in
  if panning_grab <> t.panning_grab then ignore (Rays.Sketch.set_relative_mouse panning_grab);
  let t = { t with panning_grab } in
  let t = if not panning then t else begin
      let dx, dy = if canvas_signal.held || canvas_signal.released then canvas_signal.drag
        else List.fold_left (fun (dx, dy) (_, _, _, _, (s : Ui.signal), _, _) -> let a, b = s.drag in dx +. a, dy +. b)
            (0., 0.) tiles in
      { t with pan_x = t.pan_x +. dx; pan_y = t.pan_y +. dy }
    end in
  let tile_pressed = List.exists (fun (_, _, _, _, (s : Ui.signal), _, _) -> s.pressed) tiles in
  let wire_pressed =
    if t.context <> None || tile_pressed || not (List.exists (function
      | Rays.Event.MousePressed (Input.LeftButton, _) -> true | _ -> false) frame.events) then None
    else List.find_map (fun i ->
      if List.exists (fun b -> let s = Ui.signal ui b in s.pressed && left s) (hits i)
      then Some i else None) wires_in_view in
  let t = match wire_pressed with
    | Some i ->
        if not (Path_set.is_empty t.selected) then emit (Selected []);
        { t with selected = Path_set.empty; selected_wire = t.geo.wires.(i).target }
    | None -> t in
  let t = if canvas_signal.pressed && left canvas_signal && t.context = None
    && not tile_pressed && Option.is_none wire_pressed
    then begin
      let additive = List.mem Input.Shift (Ui.press_keys ui canvas) in
      if (not additive) && not (Path_set.is_empty t.selected) then emit (Selected []);
      let base = if additive then t.selected else Path_set.empty in
      { t with selected = base; selected_wire = None; drag = Some (Marquee { base }) }
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
    let outs, dels, taps, _ = sub in
    List.iter emit fields;
    let t =
      if s.pressed && left s && t.context = None then begin
        let additive = List.mem Input.Shift (Ui.press_keys ui tile) in
        let selected = if additive then
            (if Path_set.mem p.path t.selected then Path_set.remove p.path t.selected else Path_set.add p.path t.selected)
          else if Path_set.mem p.path t.selected then t.selected else Path_set.singleton p.path in
        emit (Selected (Path_set.elements selected));
        { t with selected; selected_wire = None; drag = Some (Moving { paths = parents_removed (Path_set.elements selected);
                                                 dx = 0.; dy = 0.; moved = false }) }
      end else t in
    let t =
      if s.double_clicked && left s && t.context = None && t.editing = None then begin
        let _, top, _, _ = Ui.rect ui tile in
        match p.item with
        | P.Item n when (not n.synthetic) && snd s.press_point < top +. P.head_height *. z ->
            { t with editing = Some (Name p.path) }
        | P.Item n when not n.synthetic -> emit (Activated p.path); t
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
            emit (Moved (List.filter_map (fun path -> match rel_at t path with
              | Some (rx, ry) -> Some (path, P.snap (rx +. m.dx), P.snap (ry +. m.dy))
              | None -> None) m.paths));
          { t with drag = None }
      | _ -> t in
    (* zone controls *)
    let t = List.fold_left (fun t (b, on) ->
      let bs = Ui.signal ui b in
      (match p.item, on with
       | P.Item n, `Toggle when bs.clicked ->
           emit (Zone_collapsed { zone = n.path; collapsed = not p.collapsed })
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
    List.iter (fun (b, ops) -> if (Ui.signal ui b).clicked then List.iter (fun op -> emit (Syntax_edit op)) ops) dels;
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
               let lx = gx -. tax and ly = gy -. tay in
               match tp.item with
               | P.Return ->
                   Option.map (fun (s : P.scope) -> s.path @ [ "@result" ], E.Whole) t.scope
               | Input _ -> None
               | Item n ->
                   (match n.zone with
                    | None ->
                        (* anywhere on the header is the in-port of the first geometry slot *)
                        (match row_at ~header:infinity tp n ~shown:(tp.shown) ~px:lx ~py:ly with
                         | Some i when i < List.length n.rows ->
                             let r = List.nth n.rows i in
                             if r.socket then Some (n.path, r.key) else None
                         | _ -> None)
                    | Some zn when tp.collapsed ->
                        let i = int_of_float ((ly -. P.head_height) /. P.row_height) in
                        (match List.nth_opt zn.rail i with
                         | Some { key = Some key; _ } when ly >= P.head_height -> Some (n.path, key)
                         | _ -> None)
                    | Some zn ->
                        let extras = P.extra_rails zn in
                        if ly < P.head_height then
                          (match P.label_row zn with
                           | Some { key = Some key; _ } when lx < 24. -> Some (n.path, key)
                           | _ -> None)
                        else if ly < P.rail_top n -. 28. then
                          (match List.nth_opt extras (int_of_float ((ly -. P.head_height) /. P.row_height)) with
                           | Some { key = Some key; _ } when lx < 24. -> Some (n.path, key)
                           | _ -> None)
                        else if lx > tp.w -. 24. && ly >= P.rail_top n then
                          Some (zn.scope.path @ [ "@result" ], E.Whole)
                        else None)) tiles in
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
             (* the menu acts on the nodes: a wire selected before is no longer the selection *)
             let selected = if Path_set.mem path t.selected then t.selected else Path_set.singleton path in
             if not (Path_set.equal selected t.selected) then emit (Selected (Path_set.elements selected));
             { t with context = Some ((x, y), path); selected; selected_wire = None }
         | None -> t) in
  if t.context = None && Ui.context_clicked canvas_signal then (let x, y = canvas_signal.release_point in emit (Menu_requested (x, y)));
  let t = match t.context with
    | None -> t
    | Some (at, path) ->
        (match Ui.context_menu ui ~at "pxui-scope-context" (context_items t path) with
         | `Open -> t
         | `Dismiss -> { t with context = None }
         | `Pick i ->
             (match t.imported path with Some file -> emit (Open_import file)
              | None -> List.iter emit (action_changes t (context_command i)));
             { t with context = None }) in
  (* the frame's paint *)
  let selected = t.selected in
  let snapshot = t in
  let row_hover = match hover with Some (n, _, _, i) -> Some (n.path, i) | None -> None in
  (* a scene object nothing reads (taken out of its merge) is dimmed; a wire from it brings it back *)
  let read = t.geo.read in
  let dimmed (n : P.node) = not n.synthetic && n.zone = None
    && String.starts_with ~prefix:"scene/" n.head && n.head <> "scene/merge" && n.head <> "scene/root"
    && (match box_at t n.path with
        | Some (ax, ay, w, _) -> not (Hashtbl.mem read (ax +. w, ay +. wire_head_y))
        | None -> false) in
  Ui.draw ui layer (fun paint (rx, ry, rw, rh) ->
    paint_background paint snapshot ~viewport:(rx, ry, rw, rh) ~wires:wires_in_view zones);
  List.iter (fun ((p : P.placed), ax, ay, tile, _, _, _) ->
    let path = p.path in
    let isel = Path_set.mem path selected in
    let hovered = t.drag = None && t.carry_hot = None && Ui.hovered_within ui tile in
    Ui.draw ui tile (fun paint (x, y, w, h) ->
      match p.item with
      | P.Input _ when p.shown = P.Point -> paint_point paint ui snapshot ~z ~fs p ~selected:isel (x, y, w, h)
      | P.Input i -> paint_input paint ui snapshot ~z ~fs i ~selected:isel (x, y, w, h)
      | Return -> (match snapshot.scope with
          | Some s -> paint_return paint ui snapshot ~z ~fs s ~selected:isel (x, y, w, h)
          | None -> ())
      | Item n ->
          (match n.zone with
           | Some zn when not p.collapsed ->
               paint_zone_frame paint ui snapshot ~z ~fs ?footer:(Hashtbl.find_opt footers n.path) n zn ~selected:isel
                 ~out_wired:(Hashtbl.mem read (out_anchor p ax ay)) (x, y, w, h)
                 ~probe:(snapshot.probe n.path) ~count:(count_of snapshot n.path)
           | _ ->
               let rh = match row_hover with Some (rp, i) when rp = n.path -> Some i | _ -> None in
               paint_node paint ui snapshot ~z ~fs ?footer:(Hashtbl.find_opt footers n.path) ?lens_step:(lens_of snapshot n.path) ~hovered
                 ~carry:(match snapshot.carry_hot with Some (hp, _) -> hp = n.path | None -> false)
                 ~out_wired:(Hashtbl.mem read (out_anchor p ax ay)) ~shown:(p.shown)
                 ?failed:(List.assoc_opt n.path snapshot.failed) p n ~selected:isel ~row_hover:rh (x, y, w, h);
               if dimmed n then Ui.Paint.fill paint ~x ~y ~w ~h (Color.with_alpha snapshot.theme.panel 150)));
    ) tiles;
  let rows = List.fold_left (fun a ((p : P.placed), _, _, _, _, _, _) -> match p.item with
    | P.Item n -> a + List.length n.rows | _ -> a) 0 tiles in
  let drawn_items = List.length tiles in
  let drawn_zones = List.length zones in
  (* the rubber band and the expanded chip, over the tiles *)
  let band = match t.drag with
    | Some (Wiring w) -> Some w | _ -> None in
  let marks = if t.carry_lit = [] && t.carry_hot = None then [] else
    List.filter_map (fun ((p : P.placed), ax, ay, _, _, _, _) ->
      let rect = (sx t ax, sy t ay, p.w *. z, p.h *. z) in
      match List.assoc_opt p.path t.carry_lit, t.carry_hot with
      | letter, Some (hot, ok) when hot = p.path -> Some (rect, letter, Some ok)
      | Some letter, _ -> Some (rect, Some letter, None)
      | None, _ -> None) tiles in
  let canvas_hot = match t.carry_hot with Some ([ g ], ok) when g = t.key -> Some ok | _ -> None in
  (* the view flag of the displayed node: a tip below it after the pointer rests there *)
  let tip_at, tip_open = match t.display with
    | Some path ->
        (match item_at t path with
         | Some (({ item = P.Item _; _ } as p), ax, ay) when p.shown <> P.Point ->
             let fx = sx t ax +. (p.w -. head_pad -. 12.) *. z and fy = sy t ay +. 6. *. z in
             let mx, my = mouse in
             let over = mx >= fx && mx < fx +. 12. *. z && my >= fy && my < fy +. 12. *. z in
             Some (sx t ax +. 116. *. z, sy t ay +. 32. *. z), over && Ui.hover_delay ui ~key:"scope-flag"
         | _ -> None, false)
    | None -> None, false in
  let hint_chip paint ~bg (x, y) letter =
    let letter = String.uppercase_ascii letter in
    let size = max 8 (Ui.font_size ui - 2) in
    let lw = Float.max 14. (Ui.Paint.text_width paint ~size letter +. 6.) in
    Ui.Paint.fill paint ~x:(x -. 7.) ~y:(y -. 7.) ~w:lw ~h:14. bg;
    let tw = Ui.Paint.text_width paint ~size letter in
    Ui.Paint.text paint ~at:(x -. 7. +. (lw -. tw) /. 2., Ui.text_top ui ~size (y -. 7.) 14.) ~size
      ~color:snapshot.theme.foreground letter in
  Ui.draw_over ui canvas (fun paint (cx, cy, cw, ch) ->
    let refused = Pxui.Theme.invalid in
    Option.iter (fun ok -> Ui.Paint.dashed_rect paint ~x:(cx +. 1.5) ~y:(cy +. 1.5) ~w:(cw -. 3.) ~h:(ch -. 3.)
      (if ok then snapshot.theme.accent else refused)) canvas_hot;
    List.iter (fun ((x, y, w, h), letter, hot) ->
      let color = match hot with Some false -> refused | _ -> snapshot.theme.accent in
      (* a drop target: a dashed accent edge on the card *)
      if hot <> None then
        Ui.Paint.dashed_rect paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) color
      else Ui.Paint.stroke paint ~x:(x +. 0.5) ~y:(y +. 0.5) ~w:(w -. 1.) ~h:(h -. 1.) color;
      (* a letter of the key route: the hint colour under ink, at the card's top left (-7, -7) *)
      Option.iter (fun letter ->
        hint_chip paint ~bg:(if hot = Some false then refused else (Pxui.Theme.ports snapshot.theme).hint)
          (x, y) letter) letter) marks;
    (* letter hints: a chip per target still matching what was typed, the rest of its letters shown *)
    Option.iter (fun (h : hinting) ->
      List.iter (fun (tg : hint_target) ->
        if String.starts_with ~prefix:h.typed tg.label then begin
          let rest = String.sub tg.label (String.length h.typed) (String.length tg.label - String.length h.typed) in
          hint_chip paint ~bg:(Pxui.Theme.ports snapshot.theme).hint (sx snapshot (fst tg.pos), sy snapshot (snd tg.pos)) rest
        end) h.targets) snapshot.hinting;
    (* the displayed node's tip, once the pointer has rested on its flag *)
    if tip_open then Option.iter (fun (fx, fy) ->
      let size = max 4 (Ui.font_size ui - 2) in
      let label = "displayed" and key = "V" in
      let lw = Ui.Paint.text_width paint ~size label and kw = Ui.Paint.text_width paint ~size key in
      let tw = 2. +. 12. +. lw +. 6. +. kw in
      frame_in paint ~x:fx ~y:fy ~w:tw ~h:20. ~fill:snapshot.theme.input (Pxui.Theme.edge snapshot.theme);
      let ty = Ui.text_top ui ~size fy 20. in
      Ui.Paint.text paint ~at:(fx +. 7., ty) ~size ~color:snapshot.theme.foreground label;
      Ui.Paint.text paint ~at:(fx +. 7. +. lw +. 6., ty) ~size ~color:(Pxui.Theme.ink_3 snapshot.theme) key) tip_at;
    List.iter (fun w ->
      paint_polyline ~clip:(cx, cy, cw, ch) paint ~width:2. snapshot.theme.foreground
        (List.map (fun (x, y) -> sx snapshot x, sy snapshot y) w.pts);
      List.iter (fun (x, y) -> Ui.Paint.circle paint ~at:(sx snapshot x, sy snapshot y) ~radius:6.
        ~stroke:snapshot.theme.foreground ()) [w.a; w.b]) snapshot.highlighted;
    (match band with
     | Some w ->
         Option.iter (fun (a, b) -> Ui.Paint.line paint ~from_:a ~to_:b ~width:1.5 (ty_color snapshot w.ty))
           (clip_segment w.from mouse (cx, cy, cw, ch))
     | None -> ());
    (match snapshot.drag with
     | Some (Marquee _) ->
         let x0, y0 = canvas_signal.press_point and mx, my = mouse in
         frame_in paint ~x:(Float.min x0 mx) ~y:(Float.min y0 my) ~w:(abs_float (mx -. x0)) ~h:(abs_float (my -. y0))
           ~fill:(Pxui.Theme.tint snapshot.theme) snapshot.theme.accent
     | _ -> ());
    (match hover with
     | Some (n, ax, ay, i) ->
         let r = List.nth n.rows i in
         (match r.chip with
          | P.Inline { glyph; text } ->
              let size = max 4 (fs - 2) in
              let full = shown_glyph glyph ^ " " ^ text in
              let w = Ui.Paint.text_width paint ~size full +. 12. *. z in
              let k = match item_at snapshot n.path with
                | Some (q, _, _) -> Option.value ~default:0 (Hashtbl.find_opt (line_of_row q.lines) i)
                | None -> 0 in
              let x = sx snapshot (ax +. value_x P.node_width) and y = sy snapshot (rows_top n ay +. float k *. P.row_height) in
              if w > field_w *. z then begin
                frame_in paint ~x ~y:(y +. 2. *. z) ~w ~h:(20. *. z) ~fill:snapshot.theme.input
                  (Pxui.Theme.edge snapshot.theme);
                Ui.Paint.text paint ~at:(x +. 6. *. z, Ui.text_top ui ~size (y +. 2. *. z) (20. *. z)) ~size
                  ~color:snapshot.theme.foreground full
              end
          | _ -> ())
     | None -> ()));
  let t = { t with stats = { t.stats with drawn_items; drawn_zones; drawn_rows = rows } } in
  (* an opened or stepped expansion panel changes its card's size: lay out again for the next frame *)
  let t = if !lens_next == t.lens then t else relayout { t with lens = !lens_next } in
  t, List.rev !changes

(* ------------------------------------------------------------- test hooks *)

module Private = struct
  let grabbed t = t.panning_grab
  let macro_step = lens_of
  let selected_wire t = Option.map (fun (path, key, _) -> path, key) t.selected_wire
  let highlighted_connections t = List.map (fun w ->
    (sx t (fst w.a), sy t (snd w.a)), (sx t (fst w.b), sy t (snd w.b))) t.highlighted
  let box_of t path = box_at t path
    |> Option.map (fun (x, y, w, h) -> sx t x, sy t y, w *. t.zoom, h *. t.zoom)
  let selector t path =
    let visible = match node_of t path with
      | Some {zone = Some {kind = (P.Branch | Let | State); _}; _} | Some {zone = None; _} | None -> false
      | Some _ -> not (t.collapsed path) in
    if not visible then None else Option.map (fun (x, y, w, _) ->
    let z = t.zoom in
    let fs = font_of z in
    let sx, sy, sw, sh, _ = selector_geo ~measure:t.measure ~z ~fs ~w ~count:(count_of t path) ~probe:(t.probe path) in
    let x = x +. sx and y = y +. sy in
    (x -. 4. *. z, y, 16. *. z, sh), (x +. 12. *. z, y, sw -. 24. *. z, sh), (x +. sw -. 12. *. z, y, 16. *. z, sh)) (box_of t path)
  let output_socket t path =
    Option.map (fun ((p : P.placed), ax, ay) ->
      let x, y = out_anchor p ax ay in if p.shown = P.Point then sx t x, sy t y else sx t (x -. 1.), sy t (y -. wire_head_y +. port_y))
      (item_at t path)
  let row_center t path i =
    match node_of t path, item_at t path with
    | Some n, Some (p, x, y) ->
        (match List.nth_opt n.rows i with
         | Some { head = true; _ } -> Some (sx t (x +. 100.), sy t (y +. 12.))
         | Some _ ->
             Option.map (fun k -> sx t (x +. 100.), sy t (rows_top n y +. (float k +. 0.5) *. P.row_height))
               (Hashtbl.find_opt (line_of_row p.lines) i)
         | None -> None)
    | _ -> None
  let ref_chip t path i =
    match node_of t path, item_at t path with
    | Some n, Some (p, x, y) ->
        (match List.nth_opt n.rows i, Hashtbl.find_opt (line_of_row p.lines) i with
         | Some { chip = P.Name s; _ }, Some k ->
             let z = t.zoom in
             let left, width = ref_chip_geo t ~z ~fs:(font_of z) ~w:(p.w *. z) s in
             Some (sx t x +. left +. width /. 2., sy t (rows_top n y +. (float k +. 0.5) *. P.row_height))
         | _ -> None)
    | _ -> None
  let fold_button t path i =
    match node_of t path, item_at t path with
    | Some n, Some (p, x, y) when Hashtbl.mem t.folds (path, i) ->
        (match List.nth_opt n.rows i, Hashtbl.find_opt (line_of_row p.lines) i with
         | Some ({ chip = P.Name s; _ } as r), Some k ->
             let z = t.zoom in
             let left, fw, _, _, _ =
               wired_geo ~measure:t.measure t ~z ~fs:(font_of z) ~x:0. ~w:(p.w *. z) ~fold:true (wired_name r s) in
             Some (sx t x +. left -. fw /. 2. -. 2. *. z, sy t (rows_top n y +. (float k +. 0.5) *. P.row_height))
         | _ -> None)
    | _ -> None
  let tile_point t path (dx, dy) (w, h) = box_at t path
    |> Option.map (fun (x, y, _, _) -> sx t x +. (dx +. w /. 2.) *. t.zoom, sy t y +. (dy +. h /. 2.) *. t.zoom)
  let lens_toggle t path = match node_of t path, box_at t path with
    | Some { lens = Some _; _ }, Some (_, _, w, _) -> tile_point t path (w -. 22., 2.) (20., 20.)
    | _ -> None
  let lens_step_button t path i = match node_of t path, lens_of t path, box_at t path with
    | Some { lens = Some l; _ }, Some step, Some (_, _, _, h) when i <= Array.length l.steps ->
        let (bx, by), size = lens_button_box ~len:(Array.length l.steps) i in
        tile_point t path (bx, lens_top h (P.lens_height l ~step) +. by) size
    | _ -> None
  let lens_replace t path = match node_of t path, lens_of t path, box_at t path with
    | Some { lens = Some l; _ }, Some step, Some (_, _, _, h) ->
        let lh = P.lens_height l ~step in
        let (rx, ry), size = lens_replace_box lh in
        tile_point t path (rx, lens_top h lh +. ry) size
    | _ -> None
  (* every port of a plain node at the level it is shown, in screen points: the in end, the out
     end, a card's row sockets and named outputs *)
  let ports t path =
    match item_at t path with
    | Some (p, ax, ay) ->
        let s (x, y) = sx t x, sy t y in
        let rows = match p.item with
          | P.Item ({ zone = None; _ } as n) when p.shown = P.Card || p.shown = P.Full ->
              List.concat (List.mapi (fun k line -> match line with
                | P.Row (_, r) when r.socket ->
                    [ s (ax, rows_top n ay +. float k *. P.row_height +. wire_row_y) ]
                | _ -> []) (Array.to_list p.lines))
              @ List.mapi (fun j _ ->
                  s (ax +. p.w, rows_top n ay +. (float (Array.length p.lines + j) +. 0.5) *. P.row_height +. 0.75)) n.outputs
          | _ -> [] in
        s (in_anchor p ax ay) :: s (out_anchor p ax ay) :: rows
    | None -> []
  let wire_count t = Array.length t.geo.wires
  let wire_points t i =
    if i < 0 || i >= Array.length t.geo.wires then [] else List.map (fun (x, y) -> sx t x, sy t y) t.geo.wires.(i).pts
  let wire_target t i =
    if i < 0 || i >= Array.length t.geo.wires then None
    else Option.map (fun (p, k, _) -> p, k) t.geo.wires.(i).target
  let wire_midpoint t i =
    if i < 0 || i >= Array.length t.geo.wires then None else
    let w = t.geo.wires.(i) in
    let rec longest best = function
      | ((x0, y0) as p) :: ((x1, y1) :: _ as rest) ->
          let len = Float.hypot (x1 -. x0) (y1 -. y0) in
          longest (match best with Some (l, _, _) when l >= len -> best | _ -> Some (len, p, List.hd rest)) rest
      | _ -> best in
    (match longest None w.pts with
     | Some (_, (x0, y0), (x1, y1)) -> Some (sx t ((x0 +. x1) /. 2.), sy t ((y0 +. y1) /. 2.))
     | None -> None)
  let _ = contains
end
