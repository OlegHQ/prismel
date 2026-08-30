open Prismel
open Procedural

module Id_set = Set.Make (Int)
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

type drag =
  | Pan of { button : Input.mouse_button; last_x : int; last_y : int }
  | Move_nodes of { indices : int array; last_x : int; last_y : int }
  | View_button of int
  | Box_select of box_drag
  | Connect_wire of wire_drag

type spatial_index = {
  cells : (int64, int array) Hashtbl.t;
  cell_size : float;
  max_candidates : int;
}

type t = {
  source_graph : Graph.t option;
  document : Edit_graph.t;
  boxes : box array;
  edges : edge array;
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
  catalog : catalog_entry array;
  visible : bool;
  theme : Pxui.theme;
  mutable scene_cache : (t * Scene.t) option;
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

let clamp low high value = Float.max low (Float.min high value)

let spatial_key cell_x cell_y =
  Int64.logxor (Int64.shift_left (Int64.of_int cell_x) 32)
    (Int64.logand (Int64.of_int cell_y) 0xffff_ffffL)

let spatial_cell coordinate = int_of_float (Float.floor
    (coordinate /. spatial_cell_size))

let build_spatial_index boxes =
  let pending = Hashtbl.create (max 16 (Array.length boxes * 2)) in
  Array.iteri (fun index (box : box) ->
    let padding = 24. in
    let first_x = spatial_cell (box.gx -. padding)
    and last_x = spatial_cell
        (box.gx +. float_of_int (max 0 (box.width - 1)) +. padding)
    and first_y = spatial_cell (box.gy -. padding)
    and last_y = spatial_cell
        (box.gy +. float_of_int (max 0 (box.height - 1)) +. padding) in
    for cell_y = first_y to last_y do
      for cell_x = first_x to last_x do
        let key = spatial_key cell_x cell_y in
        Hashtbl.replace pending key
          (index :: Option.value (Hashtbl.find_opt pending key) ~default:[])
      done
    done) boxes;
  let cells = Hashtbl.create (Hashtbl.length pending) in
  let max_candidates = ref 0 in
  Hashtbl.iter (fun key reversed ->
    let candidates = Array.of_list (List.rev reversed) in
    max_candidates := max !max_candidates (Array.length candidates);
    Hashtbl.add cells key candidates) pending;
  { cells; cell_size = spatial_cell_size; max_candidates = !max_candidates }

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

let preserve_positions previous boxes =
  let positions = Hashtbl.create (Array.length previous) in
  Array.iter (fun (box : box) ->
    Hashtbl.replace positions box.info.Edit_graph.id (box.gx, box.gy)) previous;
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

let catalog_array catalog =
  let seen = Hashtbl.create (List.length catalog) in
  catalog |> List.filter (fun entry ->
    if String.trim entry.key = "" || String.trim entry.label = ""
        || entry.category = []
        || List.exists (fun item -> String.trim item = "") entry.category
        || entry.arity < 0 || Hashtbl.mem seen entry.key then false
    else begin Hashtbl.add seen entry.key (); true end)
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
  let viewed = match Edit_graph.root document with
    | Some id -> id
    | None -> Option.value ~default:0 primary in
  { source_graph = None; document; boxes; edges = build_edges boxes;
    spatial = build_spatial_index boxes; selected; primary;
    selected_edge = None; viewed; x; y; width; height;
    pan_x = float_of_int (width / 2); pan_y = 18.; zoom = 1.; drag = None;
    menu = None; clipboard = None; catalog = catalog_array catalog;
    visible = true; theme; scene_cache = None }

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
    let boxes = automatic_layout document |> preserve_positions value.boxes in
    let selected = Id_set.filter (fun id ->
      Edit_graph.find document ~node_id:id <> None) value.selected in
    let primary = match value.primary with
      | Some id when Id_set.mem id selected -> Some id
      | _ -> if Id_set.is_empty selected then None else Some (Id_set.max_elt selected) in
    let selected_edge = Option.bind value.selected_edge (fun connection ->
      if connection_exists document connection then Some connection else None) in
    let viewed = if Edit_graph.find document ~node_id:value.viewed <> None
      then value.viewed else Option.value ~default:0 (Edit_graph.root document) in
    { value with source_graph = None; document; boxes; edges = build_edges boxes;
      spatial = build_spatial_index boxes;
      selected; primary;
      selected_edge; viewed }

let with_graph graph value = match value.source_graph with
  | Some current when current == graph -> value
  | Some _ | None ->
      let value = with_document (Edit_graph.of_graph graph) value in
      { value with source_graph = Some graph }
let with_catalog catalog value = { value with catalog = catalog_array catalog }

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
  let boxes = Array.copy value.boxes and found = ref false in
  Array.iteri (fun index box -> if box.info.Edit_graph.id = node_id then begin
    boxes.(index) <- { box with gx = x; gy = y }; found := true
  end) boxes;
  if not !found then invalid_arg (Printf.sprintf
      "Pxui_graph.place_node: graph has no node #%d" node_id);
  { value with boxes; edges = build_edges boxes;
    spatial = build_spatial_index boxes }

let screen_x value gx = value.x + int_of_float (value.pan_x +. (gx *. value.zoom))
let screen_y value gy = value.y + int_of_float (value.pan_y +. (gy *. value.zoom))
let screen_size value size = max 1 (int_of_float (float_of_int size *. value.zoom))
let graph_x value x = (float_of_int (x - value.x) -. value.pan_x) /. value.zoom
let graph_y value y = (float_of_int (y - value.y) -. value.pan_y) /. value.zoom

let box_bounds (value : t) (box : box) = screen_x value box.gx, screen_y value box.gy,
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

let hit_node value point =
  let found = ref None in
  let candidates = spatial_candidates value point in
  let index = ref (Array.length candidates - 1) in
  while !index >= 0 && !found = None do
    let candidate = Array.unsafe_get candidates !index in
    let x, y, width, height = box_bounds value value.boxes.(candidate) in
    if contains ~x ~y ~width ~height point then found := Some candidate;
    decr index
  done;
  !found

let hit_view_button value point =
  if value.zoom < 0.45 then None else
  let found = ref None and candidates = spatial_candidates value point in
  let index = ref (Array.length candidates - 1) in
  while !index >= 0 && !found = None do
    let candidate = Array.unsafe_get candidates !index in
    let x, y, width, height = view_button_bounds value value.boxes.(candidate) in
    if contains ~x ~y ~width ~height point then found := Some candidate;
    decr index
  done;
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
    let box = Array.unsafe_get value.boxes index in
    let x, y, width, height = box_bounds value box in
    let px = x + width / 2 and py = y + height in
    let dx = fst point - px and dy = snd point - py in
    if !found = None && (dx * dx) + (dy * dy) <= radius * radius then
      found := Some index;
    incr cursor
  done;
  !found

let hit_input value point =
  if value.zoom < 0.4 then None else
  let radius = max 8 (screen_size value 9) and found = ref None in
  let candidates = spatial_candidates value point and cursor = ref 0 in
  while !cursor < Array.length candidates && !found = None do
    let index = Array.unsafe_get candidates !cursor in
    let box = Array.unsafe_get value.boxes index in
    let _, y, _, _ = box_bounds value box in
    let count = Array.length box.info.Edit_graph.inputs in
    for input_index = 0 to count - 1 do
      let px = port_x value box input_index count in
      let dx = fst point - px and dy = snd point - y in
      if !found = None && (dx * dx) + (dy * dy) <= radius * radius then
        found := Some (index, input_index)
    done;
    incr cursor
  done;
  !found

let edge_points value edge =
  let source = value.boxes.(edge.source_index)
  and consumer = value.boxes.(edge.consumer_index) in
  let sx, sy, sw, sh = box_bounds value source in
  let _, cy, _, _ = box_bounds value consumer in
  let from_x = sx + (sw / 2) and from_y = sy + sh
  and to_x = port_x value consumer edge.connection.input_index edge.input_count in
  from_x, from_y, to_x, cy

let bezier_point p0 p1 p2 p3 t =
  let u = 1. -. t in
  let a = u *. u *. u and b = 3. *. u *. u *. t
  and c = 3. *. u *. t *. t and d = t *. t *. t in
  (a *. fst p0) +. (b *. fst p1) +. (c *. fst p2) +. (d *. fst p3),
  (a *. snd p0) +. (b *. snd p1) +. (c *. snd p2) +. (d *. snd p3)

let segment_distance_squared px py ax ay bx by =
  let dx = bx -. ax and dy = by -. ay in
  let length = (dx *. dx) +. (dy *. dy) in
  let t = if length = 0. then 0. else clamp 0. 1.
      (((px -. ax) *. dx +. (py -. ay) *. dy) /. length) in
  let x = ax +. (t *. dx) and y = ay +. (t *. dy) in
  let ex = px -. x and ey = py -. y in
  (ex *. ex) +. (ey *. ey)

let hit_edge value (px, py) =
  let threshold = 9. and best = ref None and best_distance = ref Float.infinity in
  Array.iteri (fun index edge ->
    let x0, y0, x3, y3 = edge_points value edge in
    let bend = float_of_int (max 24 (abs (y3 - y0) / 2)) in
    let p0 = float_of_int x0, float_of_int y0
    and p1 = float_of_int x0, float_of_int y0 +. bend
    and p2 = float_of_int x3, float_of_int y3 -. bend
    and p3 = float_of_int x3, float_of_int y3 in
    let previous = ref p0 in
    for sample = 1 to 16 do
      let point = bezier_point p0 p1 p2 p3 (float_of_int sample /. 16.) in
      let distance = segment_distance_squared (float_of_int px) (float_of_int py)
          (fst !previous) (snd !previous) (fst point) (snd point) in
      if distance < !best_distance then begin
        best_distance := distance; best := Some index
      end;
      previous := point
    done) value.edges;
  if !best_distance <= threshold *. threshold then !best else None

let pan value x y button last_x last_y =
  let dx = x - last_x and dy = y - last_y in
  { value with pan_x = value.pan_x +. float_of_int dx;
    pan_y = value.pan_y +. float_of_int dy;
    drag = Some (Pan { button; last_x = x; last_y = y }) }

let move_nodes value x y indices last_x last_y =
  let boxes = Array.copy value.boxes in
  let dx = float_of_int (x - last_x) /. value.zoom
  and dy = float_of_int (y - last_y) /. value.zoom in
  Array.iter (fun index ->
    let box = boxes.(index) in
    boxes.(index) <- { box with gx = box.gx +. dx; gy = box.gy +. dy }) indices;
  { value with boxes;
    spatial = build_spatial_index boxes;
    drag = Some (Move_nodes { indices; last_x = x; last_y = y }) }

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
    min_x := min !min_x box.gx; min_y := min !min_y box.gy;
    max_x := max !max_x (box.gx +. float_of_int box.width);
    max_y := max !max_y (box.gy +. float_of_int box.height)) boxes;
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
let contains_text text query =
  let text = lower text and query = lower query in
  let text_length = String.length text and query_length = String.length query in
  let rec search at = query_length = 0 || at + query_length <= text_length
      && (String.sub text at query_length = query || search (at + 1)) in
  search 0

type menu_row = Menu_category of string | Menu_entry of catalog_entry

let category_text category = String.concat " / " category

let search_rank query (entry : catalog_entry) =
  let query = lower query and key = lower entry.key
  and label = lower entry.label in
  if String.equal query key then 0
  else if String.equal query label then 1
  else if String.length query <= String.length key
      && String.sub key 0 (String.length query) = query then 2
  else if String.length query <= String.length label
      && String.sub label 0 (String.length query) = query then 3
  else 4

let eligible menu (entry : catalog_entry) =
  menu.insertion = None || entry.arity = 1

let rec category_remainder path category = match path, category with
  | [], category -> Some category
  | expected :: path, actual :: category when expected = actual ->
      category_remainder path category
  | _ -> None

let menu_rows (value : t) menu =
  let entries = Array.to_list value.catalog |> List.filter (eligible menu) in
  if menu.query <> "" then
    entries |> List.filter (fun (entry : catalog_entry) ->
      contains_text entry.label menu.query
      || contains_text (category_text entry.category) menu.query
      || contains_text entry.key menu.query)
    |> List.sort (fun (left : catalog_entry) (right : catalog_entry) ->
      let order = Int.compare (search_rank menu.query left)
          (search_rank menu.query right) in
      if order <> 0 then order else String.compare left.label right.label)
    |> List.map (fun entry -> Menu_entry entry) |> Array.of_list
  else
    let categories, exact = List.fold_left
        (fun (categories, exact) (entry : catalog_entry) ->
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
  Array.to_list (Array.mapi (fun index box ->
    if Id_set.mem box.info.Edit_graph.id value.selected then Some index else None)
    value.boxes) |> List.filter_map Fun.id |> Array.of_list

let selected_positions (value : t) ids =
  let selected = List.fold_left (fun selected id -> Id_set.add id selected)
      Id_set.empty ids in
  Array.to_list value.boxes |> List.filter_map (fun box ->
    let id = box.info.Edit_graph.id in
    if Id_set.mem id selected then Some (id, box.gx, box.gy) else None)

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
  let selected = Array.fold_left (fun selected box ->
    if intersects bounds (box_bounds value box)
    then Id_set.add box.info.Edit_graph.id selected else selected)
      (if drag.additive then value.selected else Id_set.empty) value.boxes in
  let primary = if Id_set.is_empty selected then None else Some (Id_set.max_elt selected) in
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
            let value = { value with boxes; edges = build_edges boxes;
              spatial = build_spatial_index boxes } |> frame_all in
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
                           let changes = if before = value.primary then changes
                             else selection_change value :: changes in
                           { value with drag = Some (Move_nodes { indices;
                               last_x = fst point; last_y = snd point }) }, changes
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
             | Some (Move_nodes { indices; last_x; last_y }) ->
                 let ids = Array.to_list (Array.map (fun index ->
                   value.boxes.(index).info.Edit_graph.id) indices) in
                 let value = move_nodes value x y indices last_x last_y in
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
             | Some (Move_nodes _) when button = Input.LeftButton ->
                 { value with drag = None }, changes
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

let visibility (value : t) =
  let viewport = value.x, value.y, value.width, value.height in
  let visible_nodes = Array.make (Array.length value.boxes) false in
  let node_count = ref 0 in
  Array.iteri (fun index box ->
    let visible = intersects viewport (box_bounds value box) in
    visible_nodes.(index) <- visible;
    if visible then incr node_count) value.boxes;
  let wire_count = ref 0 in
  Array.iter (fun edge ->
    let from_x, from_y, to_x, to_y = edge_points value edge in
    if intersects viewport (wire_bounds from_x from_y to_x to_y)
    then incr wire_count) value.edges;
  visible_nodes, { nodes = Array.length value.boxes;
    wires = Array.length value.edges; visible_nodes = !node_count;
    visible_wires = !wire_count;
    spatial_cells = Hashtbl.length value.spatial.cells;
    max_spatial_candidates = value.spatial.max_candidates }

let stats (value : t) = snd (visibility value)

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
  let viewport = value.x, value.y, value.width, value.height in
  let visible_nodes, _ = visibility value in
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
  let wires = Array.fold_left (fun nodes edge ->
    let from_x, from_y, to_x, to_y = edge_points value edge in
    if not (intersects viewport (wire_bounds from_x from_y to_x to_y)) then nodes
    else
      let selected = value.selected_edge = Some edge.connection in
      let bend = max 24 (abs (to_y - from_y) / 2) in
      Scene.bezier [from_x, from_y; from_x, from_y + bend;
        to_x, to_y - bend; to_x, to_y] ~steps:16
        ~color:(if selected then Color.hex_exn "#fbbf24"
          else darken value.theme.accent 18) () :: nodes) [] value.edges in
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
  Array.iteri (fun index box -> if visible_nodes.(index) then
    if Id_set.mem box.info.Edit_graph.id value.selected
    then selected_nodes := render_box box :: !selected_nodes
    else ordinary := render_box box :: !ordinary) value.boxes;
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
