open Prismel
open Procedural

module Id_set = Set.Make (Int)
module Id_map = Map.Make (Int)
module Cell_map = Map.Make (Int64)
module String_set = Set.Make (String)

type catalog_entry = {
  key : string;
  label : string;
  category : string list;
  arity : int;
}

let catalog_of_factories factories = List.map (fun factory -> {
    key = Edit_graph.factory_key factory;
    label = Edit_graph.factory_label factory;
    category = Edit_graph.factory_category factory;
    arity = Edit_graph.factory_arity factory;
  }) factories

type add_request = {
  factory_key : string;
  inputs : int list;
  at : float * float;
}

type insert_request = {
  factory_key : string;
  connection : Edit_graph.connection;
  at : float * float;
}

type paste_request = {
  fragment : Edit_graph.fragment;
  positions : (int * float * float) list;
}

type change =
  | Selected of int option
  | Viewed of int
  | View_changed
  | Node_moved of int
  | Nodes_moved of int list
  | Connection_selected of Edit_graph.connection option
  | Connect_requested of Edit_graph.connection
  | Disconnect_requested of Edit_graph.connection
  | Delete_nodes_requested of int list
  | Add_requested of add_request
  | Insert_requested of insert_request
  | Paste_requested of paste_request
  | Layout_optimized

type box = {
  info : Edit_graph.node_info;
  depth : int;
  gx : float;
  gy : float;
  width : int;
  height : int;
}

type edge = {
  connection : Edit_graph.connection;
  source_index : int;
  consumer_index : int;
  input_count : int;
}

type menu = {
  x : int;
  y : int;
  gx : float;
  gy : float;
  query : string;
  path : string list;
  cursor : int;
  insertion : Edit_graph.connection option;
}

type box_drag = {
  start_x : int;
  start_y : int;
  current_x : int;
  current_y : int;
  additive : bool;
}

type wire_drag = { source : int; x : int; y : int }

type clipboard = {
  fragment : Edit_graph.fragment;
  positions : (int * float * float) list;
  paste_generation : int;
}

type catalog_item = {
  entry : catalog_entry;
  lower_key : string;
  lower_label : string;
  lower_category : string;
}

type menu_row = Menu_category of string | Menu_entry of catalog_entry

type drag =
  | Pan of { button : Input.mouse_button; last_x : int; last_y : int }
  | Move_nodes of {
      indices : int array;
      edge_indices : int array;
      last_x : int;
      last_y : int;
      offset_x : float;
      offset_y : float;
    }
  | View_button of int
  | Box_select of box_drag
  | Connect_wire of wire_drag

type edge_bound = {
  edge_id : int;
  segment : int;
  min_x : float;
  min_y : float;
  max_x : float;
  max_y : float;
}

type edge_delta_tree =
  | Edge_delta_empty
  | Edge_delta_branch of {
      bound : edge_bound;
      priority : int;
      subtree_max_x : float;
      left : edge_delta_tree;
      right : edge_delta_tree;
    }

type edge_bvh = {
  min_x : float array;
  min_y : float array;
  max_x : float array;
  max_y : float array;
  left : int array;
  right : int array;
  edge_id : int array;
  segment : int array;
  root : int;
}

type spatial_index = {
  cells : (int64, int array) Hashtbl.t;
  edge_bvh : edge_bvh;
  cell_size : float;
  max_candidates : int;
  max_edge_candidates : int;
  marks : int array;
  edge_marks : int array;
  edge_x0 : float array;
  edge_y0 : float array;
  edge_x3 : float array;
  edge_y3 : float array;
  incident_edges : int array array;
  mutable mark_generation : int;
  mutable visible : int array;
  mutable visible_length : int;
  mutable visible_edges : int array;
  mutable visible_edge_length : int;
  edge_stack : int array;
}

type t = {
  source_graph : Graph.t option;
  document : Edit_graph.t;
  boxes : box array;
  edges : edge array;
  slots : (int, int) Hashtbl.t;
  positions : (float * float) Id_map.t;
  moved_nodes : Id_set.t;
  moved_cells : Id_set.t Cell_map.t;
  moved_edges : Id_set.t;
  edge_delta_bounds : edge_bound array Id_map.t;
  edge_delta_tree : edge_delta_tree;
  edge_delta_entries : int;
  spatial : spatial_index;
  selected : Id_set.t;
  primary : int option;
  selected_edge : Edit_graph.connection option;
  viewed : int;
  x : int;
  y : int;
  width : int;
  height : int;
  pan_x : float;
  pan_y : float;
  zoom : float;
  drag : drag option;
  menu : menu option;
  clipboard : clipboard option;
  catalog : catalog_item array;
  visible : bool;
  theme : Pxui.theme;
  mutable scene_cache : (t * Scene.t) option;
  mutable menu_rows_cache : (menu * menu_row array) option;
}

type node_view = {
  id : int;
  label : string;
  operation : string;
  depth : int;
  bounds : int * int * int * int;
  view_bounds : int * int * int * int;
  selected : bool;
  viewed : bool;
  has_parameters : bool;
}

type stats = {
  nodes : int;
  wires : int;
  visible_nodes : int;
  visible_wires : int;
  spatial_cells : int;
  max_spatial_candidates : int;
  spatial_edge_cells : int;
  max_spatial_edge_candidates : int;
  overflow_spatial_edges : int;
}

let node_width = 196
let node_height = 78
let horizontal_gap = 34
let vertical_gap = 74
let margin = 34
let menu_width = 286
let menu_row_height = 27
let menu_header_height = 38
let menu_limit = 10
let spatial_cell_size = 256.
let edge_bvh_segments = 8

let clamp low high value = Float.max low (Float.min high value)

let spatial_key cell_x cell_y =
  Int64.logxor (Int64.shift_left (Int64.of_int cell_x) 32)
    (Int64.logand (Int64.of_int cell_y) 0xffff_ffffL)

let spatial_cell coordinate = int_of_float (Float.floor
    (coordinate /. spatial_cell_size))

let fold_box_cells (box : box) gx gy initial visit =
  let padding = 24. in
  let first_x = spatial_cell (gx -. padding)
  and last_x = spatial_cell
      (gx +. float_of_int (max 0 (box.width - 1)) +. padding)
  and first_y = spatial_cell (gy -. padding)
  and last_y = spatial_cell
      (gy +. float_of_int (max 0 (box.height - 1)) +. padding) in
  let result = ref initial in
  for cell_y = first_y to last_y do
    for cell_x = first_x to last_x do
      result := visit !result (spatial_key cell_x cell_y)
    done
  done;
  !result

let curve_point from_x from_y to_x to_y bend t =
  let u = 1. -. t in
  let uu = u *. u and tt = t *. t in
  let a = uu *. u and b = 3. *. uu *. t
  and c = 3. *. u *. tt and d = tt *. t in
  a *. from_x +. b *. from_x +. c *. to_x +. d *. to_x,
  a *. from_y +. b *. (from_y +. bend)
  +. c *. (to_y -. bend) +. d *. to_y

let make_edge_bounds edge_id from_x from_y to_x to_y =
  let delta_y = abs_float (to_y -. from_y) in
  let low_bend = max (24. /. 3.5) (delta_y /. 2.)
  and high_bend = max 120. (delta_y /. 2.) in
  Array.init edge_bvh_segments (fun segment ->
    let t0 = float_of_int segment /. float_of_int edge_bvh_segments
    and tm = (float_of_int segment +. 0.5) /. float_of_int edge_bvh_segments
    and t1 = float_of_int (segment + 1) /.
      float_of_int edge_bvh_segments in
    let x0, y0 = curve_point from_x from_y to_x to_y low_bend t0
    and x1, y1 = curve_point from_x from_y to_x to_y low_bend t1
    and x2, y2 = curve_point from_x from_y to_x to_y high_bend t0
    and x3, y3 = curve_point from_x from_y to_x to_y high_bend t1
    and x4, y4 = curve_point from_x from_y to_x to_y low_bend tm
    and x5, y5 = curve_point from_x from_y to_x to_y high_bend tm in
    { edge_id; segment;
      min_x = min (min (min x0 x1) (min x2 x3)) (min x4 x5);
      max_x = max (max (max x0 x1) (max x2 x3)) (max x4 x5);
      min_y = min (min (min y0 y1) (min y2 y3)) (min y4 y5);
      max_y = max (max (max y0 y1) (max y2 y3)) (max y4 y5) })

let edge_bound_compare (left : edge_bound) (right : edge_bound) =
  let order = Float.compare left.min_x right.min_x in
  if order <> 0 then order else
  let order = Int.compare left.edge_id right.edge_id in
  if order <> 0 then order else Int.compare left.segment right.segment

let edge_delta_max_x = function
  | Edge_delta_empty -> Float.neg_infinity
  | Edge_delta_branch node -> node.subtree_max_x

let edge_delta_branch (bound : edge_bound) priority left right =
  Edge_delta_branch { bound; priority; left; right;
    subtree_max_x = max bound.max_x
      (max (edge_delta_max_x left) (edge_delta_max_x right)) }

let edge_delta_priority (bound : edge_bound) =
  let value = Int64.logxor (Int64.shift_left (Int64.of_int bound.edge_id) 4)
      (Int64.of_int bound.segment) in
  let value = Int64.mul (Int64.logxor value (Int64.shift_right_logical value 30))
      0xbf58476d1ce4e5b9L in
  let value = Int64.mul (Int64.logxor value (Int64.shift_right_logical value 27))
      0x94d049bb133111ebL in
  Int64.to_int (Int64.logand
      (Int64.logxor value (Int64.shift_right_logical value 31)) 0x3fff_ffffL)

let rec edge_delta_insert (bound : edge_bound) = function
  | Edge_delta_empty -> edge_delta_branch bound
      (edge_delta_priority bound) Edge_delta_empty Edge_delta_empty
  | Edge_delta_branch node ->
      let order = edge_bound_compare bound node.bound in
      if order = 0 then edge_delta_branch bound node.priority node.left node.right
      else if order < 0 then
        let left = edge_delta_insert bound node.left in
        (match left with
         | Edge_delta_branch child when child.priority < node.priority ->
             edge_delta_branch child.bound child.priority child.left
               (edge_delta_branch node.bound node.priority child.right node.right)
         | Edge_delta_empty | Edge_delta_branch _ ->
             edge_delta_branch node.bound node.priority left node.right)
      else
        let right = edge_delta_insert bound node.right in
        (match right with
         | Edge_delta_branch child when child.priority < node.priority ->
             edge_delta_branch child.bound child.priority
               (edge_delta_branch node.bound node.priority node.left child.left)
               child.right
         | Edge_delta_empty | Edge_delta_branch _ ->
             edge_delta_branch node.bound node.priority node.left right)

let rec edge_delta_merge left right = match left, right with
  | Edge_delta_empty, tree | tree, Edge_delta_empty -> tree
  | Edge_delta_branch left_node, Edge_delta_branch right_node ->
      if left_node.priority < right_node.priority then
        edge_delta_branch left_node.bound left_node.priority left_node.left
          (edge_delta_merge left_node.right right)
      else edge_delta_branch right_node.bound right_node.priority
          (edge_delta_merge left right_node.left) right_node.right

let rec edge_delta_remove (bound : edge_bound) = function
  | Edge_delta_empty -> Edge_delta_empty
  | Edge_delta_branch node as tree ->
      let order = edge_bound_compare bound node.bound in
      if order = 0 then edge_delta_merge node.left node.right
      else if order < 0 then
        let left = edge_delta_remove bound node.left in
        if left == node.left then tree
        else edge_delta_branch node.bound node.priority left node.right
      else
        let right = edge_delta_remove bound node.right in
        if right == node.right then tree
        else edge_delta_branch node.bound node.priority node.left right

let rec iter_edge_delta tree min_x min_y max_x max_y visit = match tree with
  | Edge_delta_empty -> ()
  | Edge_delta_branch node ->
      if edge_delta_max_x node.left >= min_x then
        iter_edge_delta node.left min_x min_y max_x max_y visit;
      if node.bound.min_x <= max_x && min_x <= node.bound.max_x
          && node.bound.min_y <= max_y && min_y <= node.bound.max_y then
        visit node.bound.edge_id node.bound.segment;
      if node.bound.min_x <= max_x then
        iter_edge_delta node.right min_x min_y max_x max_y visit

let build_spatial_index boxes edges =
  let pending = Hashtbl.create (max 16 (Array.length boxes * 2)) in
  Array.iteri (fun index (box : box) ->
    ignore (fold_box_cells box box.gx box.gy () (fun () key ->
      Hashtbl.replace pending key
        (index :: Option.value (Hashtbl.find_opt pending key) ~default:[]))))
    boxes;
  let cells = Hashtbl.create (Hashtbl.length pending) in
  let max_candidates = ref 0 in
  Hashtbl.iter (fun key reversed ->
    let candidates = Array.of_list (List.rev reversed) in
    max_candidates := max !max_candidates (Array.length candidates);
    Hashtbl.add cells key candidates) pending;
  let edge_x0 = Array.make (Array.length edges) 0.
  and edge_y0 = Array.make (Array.length edges) 0.
  and edge_x3 = Array.make (Array.length edges) 0.
  and edge_y3 = Array.make (Array.length edges) 0. in
  let pending_incident = Array.make (Array.length boxes) [] in
  Array.iteri (fun index edge ->
    pending_incident.(edge.source_index) <-
      index :: pending_incident.(edge.source_index);
    if edge.consumer_index <> edge.source_index then
      pending_incident.(edge.consumer_index) <-
        index :: pending_incident.(edge.consumer_index)) edges;
  let incident_edges = Array.map (fun reversed ->
    Array.of_list (List.rev reversed)) pending_incident in
  let edge_bounds = Array.make (Array.length edges * edge_bvh_segments)
      { edge_id = 0; segment = 0; min_x = 0.; min_y = 0.; max_x = 0.;
        max_y = 0. } in
  Array.iteri (fun index edge ->
    let source = boxes.(edge.source_index)
    and consumer = boxes.(edge.consumer_index) in
    let from_x = source.gx +. (float_of_int source.width /. 2.)
    and from_y = source.gy +. float_of_int source.height
    and to_x = consumer.gx +.
      (float_of_int (consumer.width * (edge.connection.input_index + 1)) /.
       float_of_int (edge.input_count + 1))
    and to_y = consumer.gy in
    Array.unsafe_set edge_x0 index from_x;
    Array.unsafe_set edge_y0 index from_y;
    Array.unsafe_set edge_x3 index to_x;
    Array.unsafe_set edge_y3 index to_y;
    Array.blit (make_edge_bounds index from_x from_y to_x to_y) 0 edge_bounds
      (index * edge_bvh_segments) edge_bvh_segments) edges;
  Array.sort (fun (left : edge_bound) (right : edge_bound) ->
    let by_x = Float.compare (left.min_x +. left.max_x)
        (right.min_x +. right.max_x) in
    if by_x <> 0 then by_x
    else Float.compare (left.min_y +. left.max_y)
        (right.min_y +. right.max_y)) edge_bounds;
  let leaf_count = Array.length edge_bounds in
  let bvh_count = max 0 ((2 * leaf_count) - 1) in
  let bvh_min_x = Array.make bvh_count 0.
  and bvh_min_y = Array.make bvh_count 0.
  and bvh_max_x = Array.make bvh_count 0.
  and bvh_max_y = Array.make bvh_count 0.
  and bvh_left = Array.make bvh_count (-1)
  and bvh_right = Array.make bvh_count (-1)
  and bvh_edge_id = Array.make bvh_count (-1)
  and bvh_segment = Array.make bvh_count (-1) in
  let next_node = ref 0 in
  let rec build_bvh first last =
    let node = !next_node in
    incr next_node;
    if last - first = 1 then begin
      let bound = Array.unsafe_get edge_bounds first in
      Array.unsafe_set bvh_min_x node bound.min_x;
      Array.unsafe_set bvh_min_y node bound.min_y;
      Array.unsafe_set bvh_max_x node bound.max_x;
      Array.unsafe_set bvh_max_y node bound.max_y;
      Array.unsafe_set bvh_edge_id node bound.edge_id;
      Array.unsafe_set bvh_segment node bound.segment
    end else begin
      let middle = first + ((last - first) / 2) in
      let left = build_bvh first middle and right = build_bvh middle last in
      Array.unsafe_set bvh_left node left;
      Array.unsafe_set bvh_right node right;
      Array.unsafe_set bvh_min_x node
        (min (Array.unsafe_get bvh_min_x left)
           (Array.unsafe_get bvh_min_x right));
      Array.unsafe_set bvh_min_y node
        (min (Array.unsafe_get bvh_min_y left)
           (Array.unsafe_get bvh_min_y right));
      Array.unsafe_set bvh_max_x node
        (max (Array.unsafe_get bvh_max_x left)
           (Array.unsafe_get bvh_max_x right));
      Array.unsafe_set bvh_max_y node
        (max (Array.unsafe_get bvh_max_y left)
           (Array.unsafe_get bvh_max_y right))
    end;
    node in
  let root = if leaf_count = 0 then -1 else build_bvh 0 leaf_count in
  let edge_bvh = { min_x = bvh_min_x; min_y = bvh_min_y;
    max_x = bvh_max_x; max_y = bvh_max_y; left = bvh_left;
    right = bvh_right; edge_id = bvh_edge_id; segment = bvh_segment; root } in
  { cells; edge_bvh; cell_size = spatial_cell_size;
    max_candidates = !max_candidates;
    max_edge_candidates = 1;
    marks = Array.make (Array.length boxes) 0; mark_generation = 0;
    edge_marks = Array.make (Array.length edges) 0;
    edge_x0; edge_y0; edge_x3; edge_y3; incident_edges;
    visible = Array.make (min 16 (Array.length boxes)) 0; visible_length = 0;
    visible_edges = Array.make (min 16 (Array.length edges)) 0;
    visible_edge_length = 0; edge_stack = Array.make 64 0 }

let automatic_layout document =
  let infos = Edit_graph.inspect document in
  let count = List.length infos in
  let by_id = Hashtbl.create count and depths = Hashtbl.create count in
  List.iter (fun info -> Hashtbl.add by_id info.Edit_graph.id info) infos;
  let rec depth visiting id = match Hashtbl.find_opt depths id with
    | Some depth -> depth
    | None when Id_set.mem id visiting -> 0
    | None ->
        let visiting = Id_set.add id visiting in
        let depth = match Hashtbl.find_opt by_id id with
          | None -> 0
          | Some info -> Array.fold_left (fun result -> function
              | None -> result
              | Some input_id -> max result (1 + depth visiting input_id))
              0 info.Edit_graph.inputs in
        Hashtbl.add depths id depth;
        depth in
  List.iter (fun info -> ignore (depth Id_set.empty info.Edit_graph.id)) infos;
  let max_depth = List.fold_left (fun depth info ->
    max depth (Hashtbl.find depths info.Edit_graph.id)) 0 infos in
  let rows = Array.make (max_depth + 1) [] in
  List.iter (fun info ->
    let depth = Hashtbl.find depths info.Edit_graph.id in
    rows.(depth) <- info :: rows.(depth)) infos;
  Array.iteri (fun depth row -> rows.(depth) <- List.rev row) rows;
  let boxes = ref [] in
  Array.iteri (fun depth row ->
    let count = List.length row in
    let row_width = count * node_width + max 0 (count - 1) * horizontal_gap in
    List.iteri (fun column info ->
      boxes := { info; depth;
        gx = float_of_int (margin - (row_width / 2)
          + (column * (node_width + horizontal_gap)));
        gy = float_of_int (margin + (depth * (node_height + vertical_gap)));
        width = node_width; height = node_height } :: !boxes) row) rows;
  Array.of_list (List.rev !boxes)

let preserve_positions overrides previous boxes =
  let positions = Hashtbl.create (Array.length previous) in
  Array.iter (fun (box : box) ->
    let position = Option.value (Id_map.find_opt box.info.Edit_graph.id overrides)
        ~default:(box.gx, box.gy) in
    Hashtbl.replace positions box.info.Edit_graph.id position) previous;
  Array.map (fun box -> match Hashtbl.find_opt positions box.info.Edit_graph.id with
    | None -> box
    | Some (gx, gy) -> { box with gx; gy }) boxes

let build_edges boxes =
  let by_id = Hashtbl.create (Array.length boxes) in
  Array.iteri (fun index box ->
    Hashtbl.replace by_id box.info.Edit_graph.id index) boxes;
  let reversed = ref [] in
  Array.iteri (fun consumer_index box ->
    let input_count = Array.length box.info.Edit_graph.inputs in
    Array.iteri (fun input_index -> function
      | None -> ()
      | Some source ->
          (match Hashtbl.find_opt by_id source with
           | None -> ()
           | Some source_index ->
               reversed := { connection = { Edit_graph.source;
                   consumer = box.info.id; input_index };
                 source_index; consumer_index; input_count } :: !reversed))
      box.info.inputs) boxes;
  Array.of_list (List.rev !reversed)

let build_slots boxes =
  let slots = Hashtbl.create (Array.length boxes) in
  Array.iteri (fun index box ->
    Hashtbl.replace slots box.info.Edit_graph.id index) boxes;
  slots

let catalog_array catalog =
  let seen = Hashtbl.create (List.length catalog) in
  catalog |> List.filter (fun entry ->
    if String.trim entry.key = "" || String.trim entry.label = ""
        || entry.category = []
        || List.exists (fun item -> String.trim item = "") entry.category
        || entry.arity < 0 || Hashtbl.mem seen entry.key then false
    else begin Hashtbl.add seen entry.key (); true end)
  |> List.map (fun entry -> { entry;
      lower_key = String.lowercase_ascii entry.key;
      lower_label = String.lowercase_ascii entry.label;
      lower_category = String.lowercase_ascii
          (String.concat " / " entry.category) })
  |> Array.of_list

let create_document ?(x = 0) ?(y = 0) ?(width = 640) ?(height = 360)
    ?(theme = Pxui.default_theme) ?selected ?(catalog = []) document =
  if width <= 0 || height <= 0 then invalid_arg
      "Pxui_graph.create_document: width and height must be positive";
  let selected = match selected with
    | Some id when Edit_graph.find document ~node_id:id <> None -> Id_set.singleton id
    | _ -> Id_set.empty in
  let primary = if Id_set.is_empty selected then None else Some (Id_set.choose selected) in
  let boxes = automatic_layout document in
  let edges = build_edges boxes in
  let slots = build_slots boxes in
  let viewed = match Edit_graph.root document with
    | Some id -> id
    | None -> Option.value ~default:0 primary in
  { source_graph = None; document; boxes; edges; slots;
    positions = Id_map.empty; moved_nodes = Id_set.empty;
    moved_cells = Cell_map.empty;
    moved_edges = Id_set.empty; edge_delta_bounds = Id_map.empty;
    edge_delta_tree = Edge_delta_empty; edge_delta_entries = 0;
    spatial = build_spatial_index boxes edges; selected; primary;
    selected_edge = None; viewed; x; y; width; height;
    pan_x = float_of_int (width / 2); pan_y = 18.; zoom = 1.; drag = None;
    menu = None; clipboard = None; catalog = catalog_array catalog;
    visible = true; theme; scene_cache = None; menu_rows_cache = None }

let create ?x ?y ?width ?height ?theme ?selected ?catalog graph =
  let value = create_document ?x ?y ?width ?height ?theme ?selected ?catalog
      (Edit_graph.of_graph graph) in
  { value with source_graph = Some graph }

let document (value : t) = value.document

let connection_exists document connection =
  match Edit_graph.inputs document ~node_id:connection.Edit_graph.consumer with
  | Some inputs when connection.input_index >= 0
      && connection.input_index < Array.length inputs ->
      inputs.(connection.input_index) = Some connection.source
  | Some _ | None -> false

let with_document document value =
  if document == value.document then value else
    let boxes = automatic_layout document
        |> preserve_positions value.positions value.boxes in
    let edges = build_edges boxes in
    let slots = build_slots boxes in
    let selected = Id_set.filter (fun id ->
      Edit_graph.find document ~node_id:id <> None) value.selected in
    let primary = match value.primary with
      | Some id when Id_set.mem id selected -> Some id
      | _ -> if Id_set.is_empty selected then None else Some (Id_set.max_elt selected) in
    let selected_edge = Option.bind value.selected_edge (fun connection ->
      if connection_exists document connection then Some connection else None) in
    let viewed = if Edit_graph.find document ~node_id:value.viewed <> None
      then value.viewed else Option.value ~default:0 (Edit_graph.root document) in
    { value with source_graph = None; document; boxes; edges; slots;
      positions = Id_map.empty; moved_nodes = Id_set.empty;
      moved_cells = Cell_map.empty;
      moved_edges = Id_set.empty; edge_delta_bounds = Id_map.empty;
      edge_delta_tree = Edge_delta_empty; edge_delta_entries = 0;
      spatial = build_spatial_index boxes edges;
      selected; primary;
      selected_edge; viewed }

let with_graph graph value = match value.source_graph with
  | Some current when current == graph -> value
  | Some _ | None ->
      let value = with_document (Edit_graph.of_graph graph) value in
      { value with source_graph = Some graph }
let with_catalog catalog value = { value with catalog = catalog_array catalog;
  menu_rows_cache = None }

let with_bounds ~x ~y ~width ~height value =
  if width <= 0 || height <= 0 then invalid_arg
      "Pxui_graph.with_bounds: width and height must be positive";
  if x = value.x && y = value.y && width = value.width && height = value.height
  then value else { value with x; y; width; height; drag = None; menu = None }

let with_visible visible value =
  if visible = value.visible then value
  else { value with visible; drag = None; menu = None }
let visible (value : t) = value.visible
let selected (value : t) = value.primary
let selected_nodes (value : t) = Id_set.elements value.selected
let selected_connection (value : t) = value.selected_edge
let viewed (value : t) = value.viewed

let select node_id value =
  if Edit_graph.find value.document ~node_id = None then invalid_arg
      (Printf.sprintf "Pxui_graph.select: graph has no node #%d" node_id);
  { value with selected = Id_set.singleton node_id; primary = Some node_id;
    selected_edge = None }

let select_nodes node_ids value =
  let selected = List.fold_left (fun selected node_id ->
    if Edit_graph.find value.document ~node_id = None then invalid_arg
        (Printf.sprintf "Pxui_graph.select_nodes: graph has no node #%d" node_id);
    Id_set.add node_id selected) Id_set.empty node_ids in
  { value with selected;
    primary = if Id_set.is_empty selected then None else Some (Id_set.max_elt selected);
    selected_edge = None }

let clear_selection value = { value with selected = Id_set.empty; primary = None;
  selected_edge = None }

let view node_id value =
  if Edit_graph.find value.document ~node_id = None then invalid_arg
      (Printf.sprintf "Pxui_graph.view: graph has no node #%d" node_id);
  { value with viewed = node_id }

let place_node ~node_id ~x ~y value =
  let boxes = Array.map (fun box ->
    match Id_map.find_opt box.info.Edit_graph.id value.positions with
    | None -> box
    | Some (gx, gy) -> { box with gx; gy }) value.boxes
  and found = ref false in
  Array.iteri (fun index box -> if box.info.Edit_graph.id = node_id then begin
    boxes.(index) <- { box with gx = x; gy = y }; found := true
  end) boxes;
  if not !found then invalid_arg (Printf.sprintf
      "Pxui_graph.place_node: graph has no node #%d" node_id);
  let edges = build_edges boxes in
  { value with boxes; edges;
    positions = Id_map.empty; moved_nodes = Id_set.empty;
    moved_cells = Cell_map.empty;
    moved_edges = Id_set.empty; edge_delta_bounds = Id_map.empty;
    edge_delta_tree = Edge_delta_empty; edge_delta_entries = 0;
    spatial = build_spatial_index boxes edges }

let screen_x value gx = value.x + int_of_float (value.pan_x +. (gx *. value.zoom))
let screen_y value gy = value.y + int_of_float (value.pan_y +. (gy *. value.zoom))
let screen_size value size = max 1 (int_of_float (float_of_int size *. value.zoom))
let graph_x value x = (float_of_int (x - value.x) -. value.pan_x) /. value.zoom
let graph_y value y = (float_of_int (y - value.y) -. value.pan_y) /. value.zoom

let stored_box_position positions (box : box) =
  Option.value (Id_map.find_opt box.info.Edit_graph.id positions)
    ~default:(box.gx, box.gy)

let box_graph_position (value : t) (box : box) =
  let gx, gy = stored_box_position value.positions box in
  match value.drag with
  | Some (Move_nodes { offset_x; offset_y; _ })
      when Id_set.mem box.info.Edit_graph.id value.selected ->
      gx +. offset_x, gy +. offset_y
  | Some (Move_nodes _ | Pan _ | View_button _ | Box_select _
      | Connect_wire _) | None ->
      gx, gy

let box_bounds (value : t) (box : box) =
  let gx, gy = box_graph_position value box in
  screen_x value gx, screen_y value gy,
  screen_size value box.width, screen_size value box.height

let view_button_bounds (value : t) (box : box) =
  let x, y, width, height = box_bounds value box in
  let button_width = max 30 (screen_size value 44)
  and button_height = max 15 (screen_size value 19) in
  x + width - button_width - max 5 (screen_size value 7),
  y + height - button_height - max 5 (screen_size value 7),
  button_width, button_height

let node_views value = Array.to_list value.boxes |> List.map (fun box ->
  let info = box.info in
  { id = info.id; label = info.label; operation = info.operation;
    depth = box.depth; bounds = box_bounds value box;
    view_bounds = view_button_bounds value box;
    selected = Id_set.mem info.id value.selected; viewed = value.viewed = info.id;
    has_parameters = info.has_parameters })

let contains ~x ~y ~width ~height (px, py) =
  px >= x && py >= y && px < x + width && py < y + height

let intersects (ax, ay, aw, ah) (bx, by, bw, bh) =
  ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah

let normalize_rect x0 y0 x1 y1 =
  min x0 x1, min y0 y1, abs (x1 - x0) + 1, abs (y1 - y0) + 1

let inside value point = contains ~x:value.x ~y:value.y
    ~width:value.width ~height:value.height point

let empty_candidates = [||]

let spatial_candidates value point =
  let point_x, point_y = point in
  let graph_point_x = graph_x value point_x
  and graph_point_y = graph_y value point_y in
  let cell coordinate = int_of_float (Float.floor
      (coordinate /. value.spatial.cell_size)) in
  Option.value (Hashtbl.find_opt value.spatial.cells
      (spatial_key (cell graph_point_x) (cell graph_point_y)))
    ~default:empty_candidates

let moved_spatial_candidates value point =
  let point_x, point_y = point in
  let graph_point_x = graph_x value point_x
  and graph_point_y = graph_y value point_y in
  Cell_map.find_opt
    (spatial_key (spatial_cell graph_point_x) (spatial_cell graph_point_y))
    value.moved_cells

let iter_edge_bvh spatial query_min_x query_min_y query_max_x query_max_y visit =
  let bvh = spatial.edge_bvh in
  if bvh.root >= 0 then begin
    let stack_length = ref 1 in
    Array.unsafe_set spatial.edge_stack 0 bvh.root;
    while !stack_length > 0 do
      decr stack_length;
      let node = Array.unsafe_get spatial.edge_stack !stack_length in
      if Array.unsafe_get bvh.min_x node <= query_max_x
          && query_min_x <= Array.unsafe_get bvh.max_x node
          && Array.unsafe_get bvh.min_y node <= query_max_y
          && query_min_y <= Array.unsafe_get bvh.max_y node then
        let edge_id = Array.unsafe_get bvh.edge_id node in
        if edge_id >= 0 then visit edge_id (Array.unsafe_get bvh.segment node)
        else begin
          Array.unsafe_set spatial.edge_stack !stack_length
            (Array.unsafe_get bvh.left node);
          incr stack_length;
          Array.unsafe_set spatial.edge_stack !stack_length
            (Array.unsafe_get bvh.right node);
          incr stack_length
        end
    done
  end

let iter_spatial_edge_candidates value point visit =
  let point_x, point_y = point in
  let graph_point_x = graph_x value point_x
  and graph_point_y = graph_y value point_y in
  let radius = 9. /. value.zoom in
  iter_edge_bvh value.spatial (graph_point_x -. radius)
    (graph_point_y -. radius) (graph_point_x +. radius)
    (graph_point_y +. radius) visit

let next_spatial_generation spatial =
  if spatial.mark_generation = max_int then begin
    Array.fill spatial.marks 0 (Array.length spatial.marks) 0;
    Array.fill spatial.edge_marks 0 (Array.length spatial.edge_marks) 0;
    spatial.mark_generation <- 1
  end else spatial.mark_generation <- spatial.mark_generation + 1;
  spatial.mark_generation

let hit_node value point =
  let found = ref None in
  let candidates = spatial_candidates value point in
  let index = ref (Array.length candidates - 1) in
  while !index >= 0 && !found = None do
    let candidate = Array.unsafe_get candidates !index in
    if not (Id_set.mem candidate value.moved_nodes) then begin
      let x, y, width, height = box_bounds value value.boxes.(candidate) in
      if contains ~x ~y ~width ~height point then found := Some candidate
    end;
    decr index
  done;
  Option.iter (Id_set.iter (fun candidate ->
    let x, y, width, height = box_bounds value value.boxes.(candidate) in
    if contains ~x ~y ~width ~height point
        && Option.fold ~none:true ~some:(fun current -> candidate > current) !found
    then found := Some candidate)) (moved_spatial_candidates value point);
  !found

let hit_view_button value point =
  if value.zoom < 0.45 then None else
  let found = ref None and candidates = spatial_candidates value point in
  let index = ref (Array.length candidates - 1) in
  while !index >= 0 && !found = None do
    let candidate = Array.unsafe_get candidates !index in
    if not (Id_set.mem candidate value.moved_nodes) then begin
      let x, y, width, height = view_button_bounds value value.boxes.(candidate) in
      if contains ~x ~y ~width ~height point then found := Some candidate
    end;
    decr index
  done;
  Option.iter (Id_set.iter (fun candidate ->
    let x, y, width, height = view_button_bounds value value.boxes.(candidate) in
    if contains ~x ~y ~width ~height point
        && Option.fold ~none:true ~some:(fun current -> candidate > current) !found
    then found := Some candidate)) (moved_spatial_candidates value point);
  !found

let port_x (value : t) (box : box) input_index input_count =
  let x, _, width, _ = box_bounds value box in
  x + ((width * (input_index + 1)) / (input_count + 1))

let hit_output value point =
  if value.zoom < 0.4 then None else
  let radius = max 7 (screen_size value 8) and found = ref None in
  let candidates = spatial_candidates value point and cursor = ref 0 in
  while !cursor < Array.length candidates && !found = None do
    let index = Array.unsafe_get candidates !cursor in
    if not (Id_set.mem index value.moved_nodes) then begin
      let box = Array.unsafe_get value.boxes index in
      let x, y, width, height = box_bounds value box in
      let px = x + width / 2 and py = y + height in
      let dx = fst point - px and dy = snd point - py in
      if (dx * dx) + (dy * dy) <= radius * radius then found := Some index
    end;
    incr cursor
  done;
  Option.iter (Id_set.iter (fun index ->
    let box = Array.unsafe_get value.boxes index in
    let x, y, width, height = box_bounds value box in
    let px = x + width / 2 and py = y + height in
    let dx = fst point - px and dy = snd point - py in
    if (dx * dx) + (dy * dy) <= radius * radius
        && Option.fold ~none:true ~some:(fun current -> index < current) !found
    then found := Some index)) (moved_spatial_candidates value point);
  !found

let hit_input value point =
  if value.zoom < 0.4 then None else
  let radius = max 8 (screen_size value 9) and found = ref None in
  let candidates = spatial_candidates value point and cursor = ref 0 in
  while !cursor < Array.length candidates && !found = None do
    let index = Array.unsafe_get candidates !cursor in
    if not (Id_set.mem index value.moved_nodes) then begin
      let box = Array.unsafe_get value.boxes index in
      let _, y, _, _ = box_bounds value box in
      let count = Array.length box.info.Edit_graph.inputs in
      for input_index = 0 to count - 1 do
        let px = port_x value box input_index count in
        let dx = fst point - px and dy = snd point - y in
        if !found = None && (dx * dx) + (dy * dy) <= radius * radius then
          found := Some (index, input_index)
      done
    end;
    incr cursor
  done;
  Option.iter (Id_set.iter (fun index ->
    let box = Array.unsafe_get value.boxes index in
    let _, y, _, _ = box_bounds value box in
    let count = Array.length box.info.Edit_graph.inputs in
    for input_index = 0 to count - 1 do
      let px = port_x value box input_index count in
      let dx = fst point - px and dy = snd point - y in
      if (dx * dx) + (dy * dy) <= radius * radius
          && Option.fold ~none:true
            ~some:(fun (current, _) -> index < current) !found
      then found := Some (index, input_index)
    done)) (moved_spatial_candidates value point);
  !found

let edge_points value edge =
  let source = value.boxes.(edge.source_index)
  and consumer = value.boxes.(edge.consumer_index) in
  let sx, sy, sw, sh = box_bounds value source in
  let _, cy, _, _ = box_bounds value consumer in
  let from_x = sx + (sw / 2) and from_y = sy + sh
  and to_x = port_x value consumer edge.connection.input_index edge.input_count in
  from_x, from_y, to_x, cy

let bezier_coordinate p0 p1 p2 p3 t =
  let u = 1. -. t in
  let a = u *. u *. u and b = 3. *. u *. u *. t
  and c = 3. *. u *. t *. t and d = t *. t *. t in
  (a *. p0) +. (b *. p1) +. (c *. p2) +. (d *. p3)

let segment_distance_squared px py ax ay bx by =
  let dx = bx -. ax and dy = by -. ay in
  let length = (dx *. dx) +. (dy *. dy) in
  let t = if length = 0. then 0. else clamp 0. 1.
      (((px -. ax) *. dx +. (py -. ay) *. dy) /. length) in
  let x = ax +. (t *. dx) and y = ay +. (t *. dy) in
  let ex = px -. x and ey = py -. y in
  (ex *. ex) +. (ey *. ey)

let edge_graph_points_from_positions value positions edge =
  let source = value.boxes.(edge.source_index)
  and consumer = value.boxes.(edge.consumer_index) in
  let source_x, source_y = stored_box_position positions source
  and consumer_x, consumer_y = stored_box_position positions consumer in
  source_x +. (float_of_int source.width /. 2.),
  source_y +. float_of_int source.height,
  consumer_x +.
    (float_of_int (consumer.width * (edge.connection.input_index + 1)) /.
     float_of_int (edge.input_count + 1)),
  consumer_y

let edge_graph_points value edge =
  edge_graph_points_from_positions value value.positions edge

let hit_edge value (px, py) =
  let graph_px = graph_x value px and graph_py = graph_y value py in
  let threshold = 9. /. value.zoom
  and best = ref None and best_distance = ref Float.infinity in
  let visit index segment =
    let x0, y0, x3, y3 = if Id_set.mem index value.moved_edges
      then edge_graph_points value value.edges.(index)
      else Array.unsafe_get value.spatial.edge_x0 index,
        Array.unsafe_get value.spatial.edge_y0 index,
        Array.unsafe_get value.spatial.edge_x3 index,
        Array.unsafe_get value.spatial.edge_y3 index in
    let bend = max (24. /. value.zoom) (abs_float (y3 -. y0) /. 2.) in
    let t0 = float_of_int segment /. float_of_int edge_bvh_segments
    and tm = (float_of_int segment +. 0.5) /. float_of_int edge_bvh_segments
    and t1 = float_of_int (segment + 1) /.
      float_of_int edge_bvh_segments in
    let x1 = x0 and y1 = y0 +. bend and x2 = x3 and y2 = y3 -. bend in
    let ax = bezier_coordinate x0 x1 x2 x3 t0
    and ay = bezier_coordinate y0 y1 y2 y3 t0
    and bx = bezier_coordinate x0 x1 x2 x3 tm
    and by = bezier_coordinate y0 y1 y2 y3 tm
    and cx = bezier_coordinate x0 x1 x2 x3 t1
    and cy = bezier_coordinate y0 y1 y2 y3 t1 in
    let first = segment_distance_squared graph_px graph_py ax ay bx by
    and second = segment_distance_squared graph_px graph_py bx by cx cy in
    let distance = min first second in
    if distance < !best_distance then begin
      best_distance := distance;
      best := Some index
    end in
  iter_spatial_edge_candidates value (px, py) (fun index segment ->
    if not (Id_set.mem index value.moved_edges) then visit index segment);
  iter_edge_delta value.edge_delta_tree (graph_px -. threshold)
    (graph_py -. threshold) (graph_px +. threshold) (graph_py +. threshold)
    visit;
  if !best_distance <= threshold *. threshold then !best else None

let pan value x y button last_x last_y =
  let dx = x - last_x and dy = y - last_y in
  { value with pan_x = value.pan_x +. float_of_int dx;
    pan_y = value.pan_y +. float_of_int dy;
    drag = Some (Pan { button; last_x = x; last_y = y }) }

let affected_edges spatial indices =
  let capacity = Array.fold_left (fun count index ->
    count + Array.length spatial.incident_edges.(index)) 0 indices in
  let edges = Array.make capacity 0 and length = ref 0 in
  let generation = next_spatial_generation spatial in
  Array.iter (fun index -> Array.iter (fun edge ->
    if Array.unsafe_get spatial.edge_marks edge <> generation then begin
      Array.unsafe_set spatial.edge_marks edge generation;
      Array.unsafe_set edges !length edge;
      incr length
    end) spatial.incident_edges.(index)) indices;
  if !length = capacity then edges else Array.sub edges 0 !length

let move_nodes value x y indices edge_indices last_x last_y offset_x offset_y =
  let dx = float_of_int (x - last_x) /. value.zoom
  and dy = float_of_int (y - last_y) /. value.zoom in
  { value with drag = Some (Move_nodes { indices; edge_indices;
      last_x = x; last_y = y; offset_x = offset_x +. dx;
      offset_y = offset_y +. dy }) }

let commit_node_move value indices edge_indices offset_x offset_y =
  let positions, moved_nodes, moved_cells = Array.fold_left
      (fun (positions, moved_nodes, moved_cells) index ->
    let box = Array.unsafe_get value.boxes index in
    let gx, gy = Option.value
        (Id_map.find_opt box.info.Edit_graph.id positions)
        ~default:(box.gx, box.gy) in
    let moved_cells = if Id_set.mem index moved_nodes then
        fold_box_cells box gx gy moved_cells (fun cells key ->
          match Cell_map.find_opt key cells with
          | None -> cells
          | Some members ->
              let members = Id_set.remove index members in
              if Id_set.is_empty members then Cell_map.remove key cells
              else Cell_map.add key members cells)
      else moved_cells in
    let next_x = gx +. offset_x and next_y = gy +. offset_y in
    let moved_cells = fold_box_cells box next_x next_y moved_cells
        (fun cells key ->
          let members = Option.value (Cell_map.find_opt key cells)
              ~default:Id_set.empty in
          Cell_map.add key (Id_set.add index members) cells) in
    Id_map.add box.info.Edit_graph.id (next_x, next_y) positions,
    Id_set.add index moved_nodes, moved_cells)
      (value.positions, value.moved_nodes, value.moved_cells) indices in
  let moved_edges = Array.fold_left (fun moved index ->
    Id_set.add index moved) value.moved_edges edge_indices in
  let edge_delta_bounds, edge_delta_tree, edge_delta_entries = Array.fold_left
      (fun (all_bounds, tree, entries) index ->
    let tree = match Id_map.find_opt index all_bounds with
      | None -> tree
      | Some previous -> Array.fold_left (fun tree bound ->
          edge_delta_remove bound tree) tree previous in
    let x0, y0, x3, y3 = edge_graph_points_from_positions value positions
        value.edges.(index) in
    let bounds = make_edge_bounds index x0 y0 x3 y3 in
    let tree = Array.fold_left (fun tree bound ->
      edge_delta_insert bound tree) tree bounds in
    let entries = if Id_map.mem index all_bounds then entries
      else entries + Array.length bounds in
    Id_map.add index bounds all_bounds, tree, entries)
      (value.edge_delta_bounds, value.edge_delta_tree,
       value.edge_delta_entries) edge_indices in
  { value with positions; moved_nodes; moved_cells; moved_edges;
    edge_delta_bounds; edge_delta_tree; edge_delta_entries; drag = None }

let zoom_at value (mouse_x, mouse_y) delta =
  let old_zoom = value.zoom in
  let zoom = clamp 0.2 3.5
      (old_zoom *. Float.pow 1.12 (float_of_int delta)) in
  if zoom = old_zoom then value else
    let local_x = float_of_int (mouse_x - value.x) -. value.pan_x
    and local_y = float_of_int (mouse_y - value.y) -. value.pan_y in
    let ratio = zoom /. old_zoom in
    { value with zoom;
      pan_x = float_of_int (mouse_x - value.x) -. (local_x *. ratio);
      pan_y = float_of_int (mouse_y - value.y) -. (local_y *. ratio) }

let frame_boxes value boxes =
  if Array.length boxes = 0 then value else
  let min_x = ref Float.infinity and min_y = ref Float.infinity
  and max_x = ref Float.neg_infinity and max_y = ref Float.neg_infinity in
  Array.iter (fun (box : box) ->
    let gx, gy = box_graph_position value box in
    min_x := min !min_x gx; min_y := min !min_y gy;
    max_x := max !max_x (gx +. float_of_int box.width);
    max_y := max !max_y (gy +. float_of_int box.height)) boxes;
  let graph_width = max 1. (!max_x -. !min_x)
  and graph_height = max 1. (!max_y -. !min_y) in
  let padding = 38. in
  let available_width = max 1. (float_of_int value.width -. (2. *. padding))
  and available_height = max 1. (float_of_int value.height -. (2. *. padding)) in
  let zoom = clamp 0.2 2.5
      (min (available_width /. graph_width) (available_height /. graph_height)) in
  let center_x = (!min_x +. !max_x) *. 0.5
  and center_y = (!min_y +. !max_y) *. 0.5 in
  { value with zoom;
    pan_x = (float_of_int value.width *. 0.5) -. (center_x *. zoom);
    pan_y = (float_of_int value.height *. 0.5) -. (center_y *. zoom);
    drag = None }

let frame_all value = frame_boxes value value.boxes

let frame_selected (value : t) =
  let boxes = Array.of_list (Array.to_list value.boxes |> List.filter (fun (box : box) ->
    Id_set.mem box.info.Edit_graph.id value.selected)) in
  if Array.length boxes = 0 then frame_all value else frame_boxes value boxes

let lower value = String.lowercase_ascii value
let contains_lowered text query =
  let text_length = String.length text and query_length = String.length query in
  let rec search at = query_length = 0 || at + query_length <= text_length
      && (String.sub text at query_length = query || search (at + 1)) in
  search 0

let category_text category = String.concat " / " category

let search_rank query (item : catalog_item) =
  if String.equal query item.lower_key then 0
  else if String.equal query item.lower_label then 1
  else if String.length query <= String.length item.lower_key
      && String.sub item.lower_key 0 (String.length query) = query then 2
  else if String.length query <= String.length item.lower_label
      && String.sub item.lower_label 0 (String.length query) = query then 3
  else 4

let eligible menu (item : catalog_item) =
  menu.insertion = None || item.entry.arity = 1

let rec category_remainder path category = match path, category with
  | [], category -> Some category
  | expected :: path, actual :: category when expected = actual ->
      category_remainder path category
  | _ -> None

let menu_rows_uncached (value : t) menu =
  let entries = Array.to_list value.catalog |> List.filter (eligible menu) in
  if menu.query <> "" then begin
    let query = lower menu.query in
    entries |> List.filter (fun item ->
      contains_lowered item.lower_label query
      || contains_lowered item.lower_category query
      || contains_lowered item.lower_key query)
    |> List.sort (fun left right ->
      let order = Int.compare (search_rank query left)
          (search_rank query right) in
      if order <> 0 then order
      else String.compare left.entry.label right.entry.label)
    |> List.map (fun item -> Menu_entry item.entry) |> Array.of_list
  end else
    let categories, exact = List.fold_left
        (fun (categories, exact) item ->
      let entry = item.entry in
      match category_remainder menu.path entry.category with
      | Some (child :: _) -> String_set.add child categories, exact
      | Some [] -> categories, entry :: exact
      | None -> categories, exact) (String_set.empty, []) entries in
    let categories = String_set.elements categories
        |> List.map (fun category -> Menu_category category) in
    let exact = List.sort
        (fun (left : catalog_entry) (right : catalog_entry) ->
          String.compare left.label right.label)
        exact |> List.map (fun entry -> Menu_entry entry) in
    Array.of_list (categories @ exact)

let menu_rows (value : t) menu = match value.menu_rows_cache with
  | Some (cached_menu, rows) when cached_menu = menu -> rows
  | Some _ | None ->
      let rows = menu_rows_uncached value menu in
      value.menu_rows_cache <- Some (menu, rows);
      rows

let visible_rows rows cursor =
  let count = Array.length rows in
  let length = min menu_limit count in
  let start = if length = count then 0
    else max 0 (min (count - length) (cursor - (length / 2))) in
  start, Array.sub rows start length

let open_menu (value : t) (x, y) =
  let x = min (value.x + value.width - menu_width - 8) (max (value.x + 8) x) in
  let y = min (value.y + value.height - menu_header_height
      - (menu_row_height * 3)) (max (value.y + 8) y) in
  { value with menu = Some { x; y; gx = graph_x value x; gy = graph_y value y;
    query = ""; path = []; cursor = 0; insertion = value.selected_edge };
    drag = None }

let utf8_backspace text =
  let rec start index = if index <= 0 then 0 else
    let byte = Char.code text.[index - 1] in
    if byte land 0xc0 <> 0x80 then index - 1 else start (index - 1) in
  String.sub text 0 (start (String.length text))

let menu_request (value : t) menu entry =
  let at = menu.gx, menu.gy in
  match menu.insertion with
  | Some connection -> Insert_requested {
      factory_key = entry.key; connection; at }
  | None ->
      let rec take count values = match count, values with
        | count, _ when count <= 0 -> []
        | _, [] -> []
        | count, value :: rest -> value :: take (count - 1) rest in
      let inputs = if entry.arity = 1 then Option.to_list value.primary
        else take entry.arity (selected_nodes value) in
      Add_requested { factory_key = entry.key; inputs; at }

let menu_bounds (menu : menu) visible =
  menu.x, menu.y, menu_width,
  menu_header_height + (Array.length visible * menu_row_height) + 8

let parent_path path = match List.rev path with
  | [] -> [] | _ :: rest -> List.rev rest

let activate_menu_row value current = function
  | Menu_category category ->
      `Continue { current with path = current.path @ [category]; cursor = 0 }
  | Menu_entry entry -> `Request (menu_request value current entry)

let update_menu (value : t) frame menu =
  let changes = ref [] and menu_ref = ref menu and close = ref false in
  List.iter (fun event ->
    let current = !menu_ref in
    let rows = menu_rows value current in
    let count = Array.length rows in
    let cursor = if count = 0 then 0 else min (count - 1) current.cursor in
    let start, visible = visible_rows rows cursor in
    match event with
    | Event.TextInput text ->
        menu_ref := { current with query = current.query ^ text; cursor = 0 }
    | Event.KeyPressed Input.Backspace ->
        if current.query <> "" then
          menu_ref := { current with query = utf8_backspace current.query; cursor = 0 }
        else menu_ref := { current with path = parent_path current.path; cursor = 0 }
    | Event.KeyPressed Input.ArrowDown when count > 0 ->
        menu_ref := { current with cursor = (current.cursor + 1) mod count }
    | Event.KeyPressed Input.ArrowUp when count > 0 ->
        menu_ref := { current with cursor = (current.cursor + count - 1) mod count }
    | Event.KeyPressed Input.Enter when count > 0 ->
        (match activate_menu_row value current rows.(cursor) with
         | `Continue menu -> menu_ref := menu
         | `Request request -> changes := request :: !changes; close := true)
    | Event.KeyPressed Input.ArrowRight when count > 0 ->
        (match rows.(cursor) with
         | Menu_category category ->
             menu_ref := { current with path = current.path @ [category]; cursor = 0 }
         | Menu_entry _ -> ())
    | Event.KeyPressed Input.ArrowLeft when current.query = ""
        && current.path <> [] ->
        menu_ref := { current with path = parent_path current.path; cursor = 0 }
    | Event.KeyPressed Input.Escape -> close := true
    | Event.MousePressed (Input.LeftButton, point) ->
        let x, y, width, height = menu_bounds current visible in
        if not (contains ~x ~y ~width ~height point) then close := true
        else if snd point >= current.y + menu_header_height then
          let visible_index =
            (snd point - current.y - menu_header_height) / menu_row_height in
          if visible_index >= 0 && visible_index < Array.length visible then
            (match activate_menu_row value current
                rows.(start + visible_index) with
             | `Continue menu -> menu_ref := menu
             | `Request request ->
                 changes := request :: !changes; close := true)
    | _ -> ()) frame.Frame.events;
  { value with menu = if !close then None else Some !menu_ref }, List.rev !changes

let selection_change (value : t) = Selected value.primary

let indices_of_selection (value : t) =
  let indices = Array.make (Id_set.cardinal value.selected) 0 in
  let length = ref 0 in
  Id_set.iter (fun id -> match Hashtbl.find_opt value.slots id with
    | None -> ()
    | Some index ->
        Array.unsafe_set indices !length index;
        incr length) value.selected;
  if !length = Array.length indices then indices else Array.sub indices 0 !length

let selected_positions (value : t) ids =
  List.filter_map (fun id -> match Hashtbl.find_opt value.slots id with
    | None -> None
    | Some index ->
        let box = Array.unsafe_get value.boxes index in
        let gx, gy = box_graph_position value box in
        Some (id, gx, gy)) ids

let copy_selection (value : t) =
  let ids = selected_nodes value in
  match Edit_graph.copy_nodes ids value.document with
  | Error _ -> value
  | Ok fragment -> { value with clipboard = Some {
      fragment; positions = selected_positions value ids; paste_generation = 0 } }

let offset_positions amount positions = List.map (fun (id, x, y) ->
  id, x +. amount, y +. amount) positions

let paste_clipboard (value : t) = match value.clipboard with
  | None -> value, []
  | Some clipboard ->
      let paste_generation = clipboard.paste_generation + 1 in
      let amount = 28. *. float_of_int paste_generation in
      let request = Paste_requested {
        fragment = clipboard.fragment;
        positions = offset_positions amount clipboard.positions } in
      { value with clipboard = Some { clipboard with paste_generation } }, [request]

let duplicate_selection (value : t) =
  let ids = selected_nodes value in
  match Edit_graph.copy_nodes ids value.document with
  | Error _ -> value, []
  | Ok fragment -> value, [Paste_requested {
      fragment; positions = selected_positions value ids |> offset_positions 28. }]

let delete_selection (value : t) = match value.selected_edge with
  | Some connection ->
      { value with selected_edge = None }, [Disconnect_requested connection]
  | None when not (Id_set.is_empty value.selected) ->
      let ids = selected_nodes value in
      clear_selection value, [Delete_nodes_requested ids]
  | None -> value, []

let command_modifier frame =
  List.mem Input.Meta frame.Prismel.Frame.keys
  || List.mem Input.Ctrl frame.keys

let select_node (value : t) ~additive index =
  let id = value.boxes.(index).info.Edit_graph.id in
  if additive then
    let selected = if Id_set.mem id value.selected
      then Id_set.remove id value.selected else Id_set.add id value.selected in
    let primary = if Id_set.mem id selected then Some id
      else if Id_set.is_empty selected then None else Some (Id_set.max_elt selected) in
    { value with selected; primary; selected_edge = None }
  else if Id_set.mem id value.selected then
    { value with primary = Some id; selected_edge = None }
  else { value with selected = Id_set.singleton id; primary = Some id;
    selected_edge = None }

let apply_marquee (value : t) (drag : box_drag) =
  let bounds = normalize_rect drag.start_x drag.start_y drag.current_x drag.current_y in
  let x, y, width, height = bounds in
  let first_x = spatial_cell (graph_x value x)
  and last_x = spatial_cell (graph_x value (x + width - 1))
  and first_y = spatial_cell (graph_y value y)
  and last_y = spatial_cell (graph_y value (y + height - 1)) in
  let generation = next_spatial_generation value.spatial in
  let selected = ref (if drag.additive then value.selected else Id_set.empty) in
  let visit candidate =
    if Array.unsafe_get value.spatial.marks candidate <> generation then begin
      Array.unsafe_set value.spatial.marks candidate generation;
      let box = Array.unsafe_get value.boxes candidate in
      if intersects bounds (box_bounds value box) then
        selected := Id_set.add box.info.Edit_graph.id !selected
    end in
  for cell_y = min first_y last_y to max first_y last_y do
    for cell_x = min first_x last_x to max first_x last_x do
      let key = spatial_key cell_x cell_y in
      (match Hashtbl.find_opt value.spatial.cells key with
      | None -> ()
      | Some candidates -> Array.iter (fun candidate ->
          if not (Id_set.mem candidate value.moved_nodes)
          then visit candidate) candidates);
      Option.iter (Id_set.iter visit) (Cell_map.find_opt key value.moved_cells)
    done
  done;
  let selected = !selected in
  let primary = if Id_set.is_empty selected then None
    else Some (Id_set.max_elt selected) in
  { value with selected; primary; selected_edge = None; drag = None }

let update (value : t) frame =
  if not value.visible then { value with drag = None; menu = None }, []
  else match value.menu with
  | Some menu -> update_menu value frame menu
  | None ->
      List.fold_left (fun (value, changes) event -> match event with
        | Event.KeyPressed (Input.KeyChar character)
            when command_modifier frame ->
            (match Char.lowercase_ascii character with
             | 'c' -> copy_selection value, changes
             | 'x' ->
                 let value = copy_selection value in
                 let value, emitted = delete_selection value in
                 value, List.rev_append emitted changes
             | 'v' ->
                 let value, emitted = paste_clipboard value in
                 value, List.rev_append emitted changes
             | 'd' ->
                 let value, emitted = duplicate_selection value in
                 value, List.rev_append emitted changes
             | _ -> value, changes)
        | Event.KeyPressed Input.Space when inside value frame.Frame.mouse ->
            open_menu value frame.mouse, changes
        | Event.KeyPressed (Input.KeyChar ('o' | 'O')) ->
            let boxes = automatic_layout value.document in
            let edges = build_edges boxes in
            let value = { value with boxes; edges;
              positions = Id_map.empty; moved_nodes = Id_set.empty;
              moved_cells = Cell_map.empty;
              moved_edges = Id_set.empty; edge_delta_bounds = Id_map.empty;
              edge_delta_tree = Edge_delta_empty; edge_delta_entries = 0;
              spatial = build_spatial_index boxes edges } |> frame_all in
            value, Layout_optimized :: View_changed :: changes
        | Event.KeyPressed (Input.Delete | Input.Backspace) ->
            let value, emitted = delete_selection value in
            value, List.rev_append emitted changes
        | Event.MousePressed (Input.LeftButton, point) when inside value point ->
            (match hit_output value point with
             | Some index ->
                 let source = value.boxes.(index).info.Edit_graph.id in
                 { value with drag = Some (Connect_wire {
                     source; x = fst point; y = snd point }) }, changes
             | None ->
                 (match hit_view_button value point with
                  | Some index ->
                      { value with drag = Some (View_button index) }, changes
                  | None ->
                      (match hit_node value point with
                       | Some index ->
                           let before = value.primary in
                           let additive = List.mem Input.Shift frame.keys in
                           let value = select_node value ~additive index in
                           let indices = indices_of_selection value in
                           let edge_indices = affected_edges value.spatial indices in
                           let changes = if before = value.primary then changes
                             else selection_change value :: changes in
                           { value with drag = Some (Move_nodes { indices;
                               edge_indices; last_x = fst point; last_y = snd point;
                               offset_x = 0.; offset_y = 0. }) }, changes
                       | None ->
                           (match hit_edge value point with
                            | Some index ->
                                let connection = value.edges.(index).connection in
                                let value = { value with selected_edge = Some connection;
                                  selected = Id_set.empty; primary = None; drag = None } in
                                value, Connection_selected (Some connection)
                                  :: Selected None :: changes
                            | None ->
                                let additive = List.mem Input.Shift frame.keys in
                                { value with drag = Some (Box_select {
                                    start_x = fst point; start_y = snd point;
                                    current_x = fst point; current_y = snd point;
                                    additive });
                                  selected_edge = None }, changes))))
        | Event.MousePressed ((Input.MiddleButton | Input.RightButton as button),
            (x, y)) when inside value (x, y) ->
            { value with drag = Some (Pan { button; last_x = x; last_y = y }) }, changes
        | Event.MouseMoved (x, y) ->
            (match value.drag with
             | Some (Pan { button; last_x; last_y }) ->
                 pan value x y button last_x last_y, View_changed :: changes
             | Some (Move_nodes { indices; edge_indices; last_x; last_y;
                 offset_x; offset_y }) ->
                 let ids = Array.to_list (Array.map (fun index ->
                   value.boxes.(index).info.Edit_graph.id) indices) in
                 let value = move_nodes value x y indices edge_indices
                     last_x last_y offset_x offset_y in
                 let movement = match ids with
                   | [id] -> Node_moved id
                   | ids -> Nodes_moved ids in
                 value, movement :: changes
             | Some (Box_select drag) ->
                 { value with drag = Some (Box_select {
                     drag with current_x = x; current_y = y }) }, changes
             | Some (Connect_wire drag) ->
                 { value with drag = Some (Connect_wire { drag with x; y }) }, changes
             | Some (View_button _) | None -> value, changes)
        | Event.MouseReleased (button, point) ->
            (match value.drag with
             | Some (Pan drag) when drag.button = button ->
                 { value with drag = None }, changes
             | Some (Move_nodes { indices; edge_indices; offset_x; offset_y; _ })
                 when button = Input.LeftButton ->
                 commit_node_move value indices edge_indices offset_x offset_y,
                 changes
             | Some (Box_select drag) when button = Input.LeftButton ->
                 let before = value.primary in
                 let value = apply_marquee value drag in
                 value, if before = value.primary then changes
                   else selection_change value :: changes
             | Some (Connect_wire drag) when button = Input.LeftButton ->
                 let value = { value with drag = None } in
                 (match hit_input value point with
                  | Some (consumer_index, input_index) ->
                      let consumer = value.boxes.(consumer_index).info.Edit_graph.id in
                      if consumer = drag.source then value, changes else
                      value, Connect_requested { Edit_graph.source = drag.source;
                        consumer; input_index } :: changes
                  | None -> value, changes)
             | Some (View_button index) when button = Input.LeftButton ->
                 let x, y, width, height = view_button_bounds value value.boxes.(index) in
                 if contains ~x ~y ~width ~height point then
                   let node_id = value.boxes.(index).info.Edit_graph.id in
                   { value with viewed = node_id; drag = None },
                   Viewed node_id :: changes
                 else { value with drag = None }, changes
             | _ -> value, changes)
        | Event.PointerCancelled button ->
            (match value.drag with
             | Some (Pan drag) when drag.button = button ->
                 { value with drag = None }, changes
             | Some (Move_nodes _ | Box_select _ | Connect_wire _ | View_button _)
                 when button = Input.LeftButton ->
                 { value with drag = None }, changes
             | _ -> value, changes)
        | Event.WindowFocusLost -> { value with drag = None; menu = None }, changes
        | Event.MouseScrolled (_, delta) when delta <> 0
            && inside value frame.Frame.mouse ->
            zoom_at value frame.mouse delta, View_changed :: changes
        | Event.KeyPressed Input.Home -> frame_all value, View_changed :: changes
        | Event.KeyPressed (Input.KeyChar ('f' | 'F')) ->
            frame_selected value, View_changed :: changes
        | _ -> value, changes) (value, []) frame.Frame.events
      |> fun (value, reversed) -> value, List.rev reversed

let darken color amount = Color.rgba
    (max 0 (color.Color.r - amount))
    (max 0 (color.g - amount))
    (max 0 (color.b - amount)) color.a

let wire_bounds from_x from_y to_x to_y =
  min from_x to_x, min from_y to_y,
  abs (to_x - from_x) + 1, abs (to_y - from_y) + 1

let ensure_visible_capacity (spatial : spatial_index) needed =
  if needed > Array.length spatial.visible then begin
    let capacity = ref (max 16 (Array.length spatial.visible)) in
    while !capacity < needed do capacity := !capacity * 2 done;
    let grown = Array.make !capacity 0 in
    Array.blit spatial.visible 0 grown 0 spatial.visible_length;
    spatial.visible <- grown
  end

let ensure_visible_edge_capacity (spatial : spatial_index) needed =
  if needed > Array.length spatial.visible_edges then begin
    let capacity = ref (max 16 (Array.length spatial.visible_edges)) in
    while !capacity < needed do capacity := !capacity * 2 done;
    let grown = Array.make !capacity 0 in
    Array.blit spatial.visible_edges 0 grown 0 spatial.visible_edge_length;
    spatial.visible_edges <- grown
  end

let sort_visible_prefix values length =
  let swap left right =
    let value = Array.unsafe_get values left in
    Array.unsafe_set values left (Array.unsafe_get values right);
    Array.unsafe_set values right value in
  let rec sift root limit =
    let child = (root * 2) + 1 in
    if child < limit then begin
      let child = if child + 1 < limit
          && Array.unsafe_get values child < Array.unsafe_get values (child + 1)
        then child + 1 else child in
      if Array.unsafe_get values root < Array.unsafe_get values child then begin
        swap root child;
        sift child limit
      end
    end in
  for root = (length / 2) - 1 downto 0 do sift root length done;
  for limit = length - 1 downto 1 do
    swap 0 limit;
    sift 0 limit
  done

let visible_node_indices (value : t) viewport =
  let spatial = value.spatial in
  let generation = next_spatial_generation spatial in
  spatial.visible_length <- 0;
  let x, y, width, height = viewport in
  let first_x = spatial_cell (graph_x value x)
  and last_x = spatial_cell (graph_x value (x + width - 1))
  and first_y = spatial_cell (graph_y value y)
  and last_y = spatial_cell (graph_y value (y + height - 1)) in
  let visit_node candidate =
    if Array.unsafe_get spatial.marks candidate <> generation then begin
      Array.unsafe_set spatial.marks candidate generation;
      if intersects viewport (box_bounds value value.boxes.(candidate)) then begin
        ensure_visible_capacity spatial (spatial.visible_length + 1);
        Array.unsafe_set spatial.visible spatial.visible_length candidate;
        spatial.visible_length <- spatial.visible_length + 1
      end
    end in
  for cell_y = min first_y last_y to max first_y last_y do
    for cell_x = min first_x last_x to max first_x last_x do
      let key = spatial_key cell_x cell_y in
      (match Hashtbl.find_opt spatial.cells key with
      | None -> ()
      | Some candidates -> Array.iter (fun candidate ->
          if not (Id_set.mem candidate value.moved_nodes)
          then visit_node candidate) candidates);
      Option.iter (Id_set.iter visit_node)
        (Cell_map.find_opt key value.moved_cells)
    done
  done;
  (match value.drag with
   | Some (Move_nodes { indices; _ }) -> Array.iter visit_node indices
   | Some (Pan _ | View_button _ | Box_select _ | Connect_wire _) | None -> ());
  sort_visible_prefix spatial.visible spatial.visible_length;
  spatial.visible_edge_length <- 0;
  let graph_left = graph_x value x
  and graph_right = graph_x value (x + width - 1)
  and graph_top = graph_y value y
  and graph_bottom = graph_y value (y + height - 1) in
  let visit_edge candidate =
    if Array.unsafe_get spatial.edge_marks candidate <> generation then begin
      Array.unsafe_set spatial.edge_marks candidate generation;
      let from_x, from_y, to_x, to_y = edge_points value
          value.edges.(candidate) in
      if intersects viewport (wire_bounds from_x from_y to_x to_y) then begin
        ensure_visible_edge_capacity spatial
          (spatial.visible_edge_length + 1);
        Array.unsafe_set spatial.visible_edges spatial.visible_edge_length candidate;
        spatial.visible_edge_length <- spatial.visible_edge_length + 1
      end
    end in
  iter_edge_bvh spatial (min graph_left graph_right) (min graph_top graph_bottom)
    (max graph_left graph_right) (max graph_top graph_bottom)
    (fun candidate _segment ->
      if not (Id_set.mem candidate value.moved_edges) then visit_edge candidate);
  iter_edge_delta value.edge_delta_tree (min graph_left graph_right)
    (min graph_top graph_bottom) (max graph_left graph_right)
    (max graph_top graph_bottom) (fun candidate _segment ->
      visit_edge candidate);
  (match value.drag with
   | Some (Move_nodes { edge_indices; _ }) -> Array.iter visit_edge edge_indices
   | Some (Pan _ | View_button _ | Box_select _ | Connect_wire _) | None -> ());
  sort_visible_prefix spatial.visible_edges spatial.visible_edge_length;
  spatial.visible, spatial.visible_length,
  spatial.visible_edges, spatial.visible_edge_length

let visibility (value : t) =
  let viewport = value.x, value.y, value.width, value.height in
  let visible_nodes, visible_length, visible_edges, visible_edge_length =
    visible_node_indices value viewport in
  visible_nodes, visible_edges, { nodes = Array.length value.boxes;
    wires = Array.length value.edges; visible_nodes = visible_length;
    visible_wires = visible_edge_length;
    spatial_cells = Hashtbl.length value.spatial.cells;
    max_spatial_candidates = value.spatial.max_candidates;
    spatial_edge_cells = Array.length value.spatial.edge_bvh.edge_id
      + value.edge_delta_entries;
    max_spatial_edge_candidates = value.spatial.max_edge_candidates;
    overflow_spatial_edges = 0 }

let stats (value : t) = let _, _, stats = visibility value in stats

let menu_scene (value : t) menu =
  let rows = menu_rows value menu in
  let count = Array.length rows in
  let cursor = if count = 0 then 0 else min (count - 1) menu.cursor in
  let start, visible = visible_rows rows cursor in
  let x, y, width, height = menu_bounds menu visible in
  let theme = value.theme in
  let row_scenes = Array.to_list (Array.mapi (fun visible_index row ->
    let index = start + visible_index in
    let row_y = y + menu_header_height + (visible_index * menu_row_height) in
    let label, detail, color = match row with
      | Menu_category category -> category, "›", theme.accent
      | Menu_entry entry ->
          let detail = if menu.query = "" then Printf.sprintf "%d in" entry.arity
            else Printf.sprintf "%s · %d in"
                (category_text entry.category) entry.arity in
          entry.label, detail, theme.foreground in
    [Scene.rect ~at:(x + 6, row_y) ~w:(width - 12) ~h:menu_row_height
       ~fill:(if index = cursor then darken theme.accent 105
         else theme.input) ();
     Scene.text ~at:(x + 14, row_y + 7) ~size:12
       ~color label;
     Scene.text ~at:(x + width - 94, row_y + 8) ~size:9
       ~color:(darken theme.foreground 65)
       detail]) visible)
    |> List.concat in
  let breadcrumb = match menu.path with
    | [] -> "SOPs" | path -> "SOPs / " ^ category_text path in
  [Scene.rect ~at:(x, y) ~w:width ~h:height ~fill:theme.panel
     ~stroke:theme.accent ();
   Scene.rect ~at:(x + 7, y + 7) ~w:(width - 14) ~h:27
     ~fill:theme.input ~stroke:theme.control ();
   Scene.text ~at:(x + 15, y + 14) ~size:12 ~color:theme.foreground
     ((if menu.query = "" then breadcrumb else menu.query) ^ "│");
   Scene.text_input_region ~at:(x + 7, y + 7) ~w:(width - 14) ~h:27
     ~focused:true ()] @ row_scenes

let scene_uncached (value : t) =
  if not value.visible then Scene.empty else
  let visible_nodes, visible_edges, visibility_stats = visibility value in
  let grid =
    let spacing = max 18 (screen_size value 32) in
    let color = darken value.theme.control 20 in
    let offset_x = int_of_float value.pan_x mod spacing
    and offset_y = int_of_float value.pan_y mod spacing in
    let start_x = value.x + offset_x - spacing
    and start_y = value.y + offset_y - spacing in
    let rec vertical x nodes = if x >= value.x + value.width then nodes else
      vertical (x + spacing) (Scene.line ~from_:(x, value.y)
        ~to_:(x, value.y + value.height) ~color () :: nodes) in
    let rec horizontal y nodes = if y >= value.y + value.height then nodes else
      horizontal (y + spacing) (Scene.line ~from_:(value.x, y)
        ~to_:(value.x + value.width, y) ~color () :: nodes) in
    horizontal start_y (vertical start_x []) in
  let wires = ref [] in
  for visible_index = 0 to visibility_stats.visible_wires - 1 do
    let edge = value.edges.(Array.unsafe_get visible_edges visible_index) in
    let from_x, from_y, to_x, to_y = edge_points value edge in
    let selected = value.selected_edge = Some edge.connection in
    let bend = max 24 (abs (to_y - from_y) / 2) in
    wires := Scene.bezier [from_x, from_y; from_x, from_y + bend;
        to_x, to_y - bend; to_x, to_y] ~steps:16
        ~color:(if selected then Color.hex_exn "#fbbf24"
          else darken value.theme.accent 18) () :: !wires
  done;
  let wires = !wires in
  let connector_radius = max 2 (screen_size value 4) in
  let render_box box =
    let x, y, width, height = box_bounds value box in
    let selected = Id_set.mem box.info.Edit_graph.id value.selected
    and viewed = value.viewed = box.info.Edit_graph.id in
    let view_color = Color.hex_exn "#fbbf24" in
    let stroke = if viewed then view_color
      else if selected then value.theme.accent else value.theme.control in
    let fill = if selected then darken value.theme.accent 82 else value.theme.input in
    let font_size = max 9 (min 14 (screen_size value 13)) in
    let detail_size = max 8 (min 11 (screen_size value 10)) in
    let parameter_badge = if box.info.has_parameters then [
      Scene.text ~at:(x + width - 20, y + 8) ~size:9
        ~color:value.theme.accent "P"] else [] in
    let connectors = if value.zoom < 0.45 then [] else
      let inputs = Array.to_list (Array.mapi (fun input_index connected ->
        let px = port_x value box input_index (Array.length box.info.inputs) in
        Scene.circle ~at:(px, y) ~radius:connector_radius
          ~fill:(if Option.is_some connected then value.theme.accent
            else darken value.theme.foreground 85)
          ~stroke:value.theme.panel ()) box.info.inputs) in
      Scene.circle ~at:(x + width / 2, y + height) ~radius:connector_radius
        ~fill:value.theme.accent ~stroke:value.theme.panel () :: inputs in
    let dependency = Context.Dependencies.to_string box.info.dependencies in
    let input_labels =
      let count = Array.length box.info.inputs in
      if value.zoom < 0.75 || count < 2 then [] else
        Array.to_list (Array.init count (fun input_index ->
          let px = port_x value box input_index count in
          Scene.text ~at:(px - 3, y + 4) ~size:8
            ~color:(darken value.theme.foreground 44)
            (string_of_int input_index))) in
    let bx, by, bw, bh = view_button_bounds value box in
    let view_button = if value.zoom < 0.45 then [] else [
      Scene.rounded_rect ~at:(bx, by) ~w:bw ~h:bh ~radius:4
        ~fill:(if viewed then darken view_color 85 else value.theme.control)
        ~stroke:(if viewed then view_color else darken value.theme.foreground 80) ();
      Scene.text ~at:(bx + max 4 (screen_size value 7), by + 3)
        ~size:(max 8 (min 10 (screen_size value 9)))
        ~color:(if viewed then view_color else value.theme.foreground) "VIEW"] in
    let shell = [Scene.rounded_rect ~at:(x, y) ~w:width ~h:height ~radius:7
      ~fill ~stroke ()] in
    let content = if value.zoom < 0.4 then [] else [
      Scene.rect ~at:(x + 1, y + 1) ~w:(max 1 (width - 2))
        ~h:(max 1 (screen_size value 27))
        ~fill:(if selected then darken value.theme.accent 94
          else darken value.theme.control 8) ();
      Scene.text ~at:(x + 10, y + 9) ~size:font_size
        ~color:value.theme.foreground box.info.label;
      Scene.text ~at:(x + 10, y + height - max 23 (screen_size value 25))
        ~size:detail_size ~color:(darken value.theme.foreground 55)
        (box.info.operation ^ " · " ^ dependency)]
      @ connectors @ input_labels @ parameter_badge @ view_button in
    shell @ content in
  let ordinary = ref [] and selected_nodes = ref [] in
  for visible_index = 0 to visibility_stats.visible_nodes - 1 do
    let index = Array.unsafe_get visible_nodes visible_index in
    let box = Array.unsafe_get value.boxes index in
    if Id_set.mem box.info.Edit_graph.id value.selected
    then selected_nodes := render_box box :: !selected_nodes
    else ordinary := render_box box :: !ordinary
  done;
  let drag_scene = match value.drag with
    | Some (Box_select drag) ->
        let x, y, width, height = normalize_rect drag.start_x drag.start_y
            drag.current_x drag.current_y in
        [Scene.rect ~at:(x, y) ~w:width ~h:height
           ~fill:(Color.with_alpha value.theme.accent 28)
           ~stroke:value.theme.accent ()]
    | Some (Connect_wire drag) ->
        (match Array.find_opt (fun box -> box.info.Edit_graph.id = drag.source)
              value.boxes with
           | None -> []
           | Some source ->
               let sx, sy, sw, sh = box_bounds value source in
               [Scene.bezier [sx + sw / 2, sy + sh;
                  sx + sw / 2, sy + sh + 30; drag.x, drag.y - 30;
                  drag.x, drag.y] ~steps:12
                  ~color:value.theme.accent ()])
    | Some (Pan _ | Move_nodes _ | View_button _) | None -> [] in
  let base = [Scene.rect ~at:(value.x, value.y) ~w:value.width ~h:value.height
      ~fill:value.theme.panel ~stroke:value.theme.control ();
    Scene.clip ~at:(value.x, value.y) ~w:value.width ~h:value.height
      (grid @ wires @ List.concat (List.rev !ordinary)
        @ List.concat (List.rev !selected_nodes) @ drag_scene)] in
  base @ Option.fold ~none:[] ~some:(menu_scene value) value.menu

let same_scene_state (left : t) (right : t) =
  left.boxes == right.boxes && left.edges == right.edges
  && left.positions == right.positions
  && left.moved_nodes == right.moved_nodes
  && left.moved_cells == right.moved_cells
  && left.moved_edges == right.moved_edges
  && left.edge_delta_bounds == right.edge_delta_bounds
  && left.edge_delta_tree == right.edge_delta_tree
  && left.edge_delta_entries = right.edge_delta_entries
  && left.selected = right.selected && left.primary = right.primary
  && left.selected_edge = right.selected_edge && left.viewed = right.viewed
  && left.x = right.x && left.y = right.y && left.width = right.width
  && left.height = right.height && left.pan_x = right.pan_x
  && left.pan_y = right.pan_y && left.zoom = right.zoom
  && left.drag = right.drag && left.menu = right.menu
  && left.catalog == right.catalog && left.visible = right.visible
  && left.theme = right.theme

let scene (value : t) = match value.scene_cache with
  | Some (snapshot, scene) when same_scene_state snapshot value -> scene
  | _ ->
      let scene = scene_uncached value in
      value.scene_cache <- Some ({ value with scene_cache = None }, scene);
      scene

module Private = struct
  let hit_node_id value point = Option.map (fun index ->
      value.boxes.(index).info.Edit_graph.id) (hit_node value point)
  let hit_edge_id value point = Option.map (fun index ->
      value.edges.(index).connection) (hit_edge value point)
  let edge_query_points value ~limit =
    Array.init (min limit (Array.length value.edges)) (fun index ->
      let x0, y0, x3, y3 = edge_points value value.edges.(index) in
      (x0 + x3) / 2, (y0 + y3) / 2)
  let hit_candidates value point =
    let count = ref 0 in
    Array.iter (fun index ->
      if not (Id_set.mem index value.moved_nodes) then incr count)
      (spatial_candidates value point);
    Option.iter (fun members -> count := !count + Id_set.cardinal members)
      (moved_spatial_candidates value point);
    !count
  let hit_edge_candidates value point =
    let generation = next_spatial_generation value.spatial in
    let count = ref 0 in
    iter_spatial_edge_candidates value point (fun index _segment ->
      if not (Id_set.mem index value.moved_edges)
          && Array.unsafe_get value.spatial.edge_marks index <> generation then begin
        Array.unsafe_set value.spatial.edge_marks index generation;
        incr count
      end);
    let px, py = point in
    let graph_x = graph_x value px and graph_y = graph_y value py in
    let radius = 9. /. value.zoom in
    iter_edge_delta value.edge_delta_tree (graph_x -. radius)
      (graph_y -. radius) (graph_x +. radius) (graph_y +. radius)
      (fun index _segment ->
        if Array.unsafe_get value.spatial.edge_marks index <> generation then begin
          Array.unsafe_set value.spatial.edge_marks index generation;
          incr count
        end);
    !count
end
