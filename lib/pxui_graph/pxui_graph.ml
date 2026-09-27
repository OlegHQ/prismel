open Prismel
open Procedural

module Id_set = Set.Make (Int)
module Layout = Editor_core.Network_layout
module Id_map = Layout.Int_map
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
  ripple : (int * float * float) list;
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
  | Bend_changed of { node : int; slot : int }
  | Level_changed of int list
  | Set_parameter_requested of { node : int; path : string; value : Parameter.value }
  | Cut_wires_requested of Edit_graph.connection list
  | Connection_selected of Edit_graph.connection option
  | Connect_requested of Edit_graph.connection
  | Disconnect_requested of Edit_graph.connection
  | Delete_nodes_requested of int list
  | Dissolve_nodes_requested of int list
  | Bypass_requested of (int * bool) list
  | Notice of string
  | Add_requested of add_request
  | Insert_requested of insert_request
  | Paste_requested of paste_request
  | Flag_requested of int
  | Frame_camera_requested of int
  | Open_requested of int

type row = Slot of int | Field of Parameter.field_view * bool | Folder of string list | More of int

type box = {
  info : Edit_graph.node_info;
  tile_id : string;
  depth : int;
  gx : float;
  gy : float;
  width : int;
  height : int;
  level : Layout.level;
  rows : row array;
}

type edge = {
  connection : Edit_graph.connection;
  source_index : int;
  consumer_index : int;
}

type menu = {
  x : int;
  y : int;
  gx : float;
  gy : float;
  query : string;
  path : string list;
  insertion : Edit_graph.connection option;
  inputs : int list;
  compatible_input : bool;
  ripple : (int * float * float) list;
}

type hint_target = Hint_port of Edit_graph.connection | Hint_node of int
type hints = { source : int; prefix : string; targets : (string * hint_target) list }

type context_target =
  | On_canvas
  | On_tile of int
  | On_wire of Edit_graph.connection

type context = { at : int * int; target : context_target }

type box_drag = {
  start_x : int;
  start_y : int;
  current_x : int;
  current_y : int;
  additive : bool;
}

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

(* Pointer capture, press points, and cancellation belong to [Pxui.Ui];
   the canvas keeps only what a gesture means. *)
type drag =
  | Pan_canvas
  | Knife
  | Bend_wire of { node : int; slot : int; bend : int; on_canvas : bool }
  | Move_nodes of {
      node : int;
      indices : int array;
      edge_indices : int array;
      offset_x : float;
      offset_y : float;
    }
  | Box_select of { additive : bool }
  | Connect_wire of { source : int }

type edge_bound = {
  edge_id : int;
  min_x : float;
  min_y : float;
  max_x : float;
  max_y : float;
}

type edge_bvh = {
  min_x : float array;
  min_y : float array;
  max_x : float array;
  max_y : float array;
  left : int array;
  right : int array;
  edge_id : int array;
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
  edge_points : (float * float) array array;
  incident_edges : int array array;
  mutable mark_generation : int;
  mutable visible : int array;
  mutable visible_length : int;
  mutable order : int array;
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
  layout : Layout.t;
  moved_nodes : Id_set.t;
  moved_cells : Id_set.t Cell_map.t;
  spatial : spatial_index;
  selected : Id_set.t;
  primary : int option;
  selected_edge : Edit_graph.connection option;
  viewed : int;
  flagged : int option;
  flaggable : Edit_graph.node_info -> bool;
  enterable : Edit_graph.node_info -> bool;
  x : int;
  y : int;
  width : int;
  height : int;
  pan_x : float;
  pan_y : float;
  zoom : float;
  drag : drag option;
  bloom : int option;
  before_points : Layout.level Id_map.t;
  menu : menu option;
  context : context option;
  clipboard : clipboard option;
  catalog : catalog_item array;
  last_added : string option;
  hints : hints option;
  find : string option;
  namespace : string;
  visible : bool;
  theme : Pxui.theme;
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
  active : bool;
  active_bounds : (int * int * int * int) option;
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
let horizontal_gap = 60
let vertical_gap = 36
let menu_width = 286
let menu_limit = 10
let spatial_cell_size = 256.

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

(* Geometry sockets share the header trunk; additional slots are body rows. *)
let input_offset index = if index = 0 then 12. else 12. +. (24. *. float index)

let graph_output (box : box) (gx, gy) =
  gx +. (if box.level = Layout.Point then 22. else float box.width), gy +. 12.
let graph_input (box : box) (gx, gy) index = match box.level with
  | Layout.Point -> gx +. 2., gy +. 12.
  | Chip when index > 0 -> gx +. 22. +. (12. *. float (index - 1)), gy +. 24.
  | Chip | Card | Full -> gx, gy +. input_offset index

let polyline ~bottom layout connection (from_x, from_y) (to_x, to_y) =
  let bends = Option.value ~default:[]
    (Layout.Port_map.find_opt (Layout.slot connection.Edit_graph.consumer
      connection.input_index) layout.Layout.bends) in
  let stub = if bottom then to_x, to_y +. 14. else to_x -. 14., to_y in
  Array.of_list ((from_x, from_y) :: (from_x +. 14., from_y) ::
    (bends @ [stub; to_x, to_y]))

let stored_box_position positions (box : box) =
  Option.value (Id_map.find_opt box.info.Edit_graph.id positions)
    ~default:(box.gx, box.gy)

let build_edge_index boxes edges positions layout =
  let points = Array.map (fun edge ->
    let source = boxes.(edge.source_index)
    and consumer = boxes.(edge.consumer_index) in
    let source_x, source_y = stored_box_position positions source
    and consumer_x, consumer_y = stored_box_position positions consumer in
    polyline ~bottom:(consumer.level = Layout.Chip && edge.connection.input_index > 0)
      layout edge.connection
      (graph_output source (source_x, source_y))
      (graph_input consumer (consumer_x, consumer_y) edge.connection.input_index)) edges in
  (* ponytail: one BVH leaf per wire; hits scan its authored segments.
     Index segments separately only if long bend chains dominate hit time. *)
  let edge_bounds = Array.mapi (fun edge_id points ->
    let min_x = ref Float.infinity and min_y = ref Float.infinity
    and max_x = ref Float.neg_infinity and max_y = ref Float.neg_infinity in
    Array.iter (fun (x, y) -> min_x := min !min_x x; min_y := min !min_y y;
      max_x := max !max_x x; max_y := max !max_y y) points;
    { edge_id; min_x = !min_x; min_y = !min_y; max_x = !max_x; max_y = !max_y }) points in
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
  and bvh_edge_id = Array.make bvh_count (-1) in
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
      Array.unsafe_set bvh_edge_id node bound.edge_id
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
    right = bvh_right; edge_id = bvh_edge_id; root } in
  edge_bvh, points

let build_spatial_index boxes edges layout =
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
  let pending_incident = Array.make (Array.length boxes) [] in
  Array.iteri (fun index edge ->
    pending_incident.(edge.source_index) <-
      index :: pending_incident.(edge.source_index);
    if edge.consumer_index <> edge.source_index then
      pending_incident.(edge.consumer_index) <-
        index :: pending_incident.(edge.consumer_index)) edges;
  let incident_edges = Array.map (fun reversed ->
    Array.of_list (List.rev reversed)) pending_incident in
  let edge_bvh, edge_points =
    build_edge_index boxes edges Id_map.empty layout in
  { cells; edge_bvh; cell_size = spatial_cell_size;
    max_candidates = !max_candidates;
    max_edge_candidates = 1;
    marks = Array.make (Array.length boxes) 0; mark_generation = 0;
    edge_marks = Array.make (Array.length edges) 0;
    edge_points; incident_edges;
    visible = Array.make (min 16 (Array.length boxes)) 0; visible_length = 0;
    order = Array.make (min 16 (Array.length boxes)) 0;
    visible_edges = Array.make (min 16 (Array.length edges)) 0;
    visible_edge_length = 0; edge_stack = Array.make 64 0 }

let tile_text (info : Edit_graph.node_info) =
  "node###pxui-graph-node-" ^ string_of_int info.id

let shown layout id first_folder (field : Parameter.field_view) =
  match Option.bind (Id_map.find_opt id layout.Layout.rows)
      (Layout.String_map.find_opt field.name) with
  | Some pinned -> pinned
  | None -> field.current <> field.default || field.folder = first_folder

let shape layout zoom bloom (info : Edit_graph.node_info) =
  let requested = Option.value ~default:Layout.Card (Id_map.find_opt info.id layout.Layout.level) in
  let pinned = Option.value ~default:false (Id_map.find_opt info.id layout.Layout.pinned) in
  let level = if bloom = Some info.id then Layout.Full else
    if pinned then requested else if zoom < 0.34 then Layout.Point
    else if zoom < 0.50 && (requested = Card || requested = Full) then Chip else requested in
  let rows = match level with
    | Layout.Point | Chip -> [||]
    | Card | Full ->
        let fields = Node.parameter_fields info.node in
        let first_folder = match fields with f :: _ -> f.Parameter.folder | [] -> [] in
        let visible = List.filter (shown layout info.id first_folder) fields in
        let parameters = if level = Layout.Card then List.map (fun f -> Field (f, true)) visible
          else
            let _, rows = List.fold_left (fun (folder, rows) (f : Parameter.field_view) ->
              let rows = if folder = Some f.folder || f.folder = [] then rows
                else Folder f.folder :: rows in
              Some f.folder, Field (f, shown layout info.id first_folder f) :: rows) (None, []) fields in
            List.rev rows in
        let hidden = List.length fields - List.length visible in
        let more = if level = Layout.Full then [More (-1)]
          else if hidden > 0 then [More hidden] else [] in
        Array.of_list (List.init (max 0 (Array.length info.inputs - 1))
          (fun i -> Slot (i + 1)) @ parameters @ more) in
  level, rows, (if level = Layout.Point || level = Chip then 24
    else 30 + (24 * Array.length rows))

let automatic_layout document layout zoom bloom =
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
  Array.iteri (fun depth row -> rows.(depth) <-
    List.sort (fun a b -> Int.compare a.Edit_graph.id b.Edit_graph.id) row) rows;
  let boxes = ref [] in
  Array.iteri (fun depth row ->
    let y = ref 0. in
    List.iter (fun info ->
      let tile_id = tile_text info in
      let level, rows, height = shape layout zoom bloom info in
      boxes := { info; tile_id; depth;
        gx = Layout.snap (float_of_int (depth * (node_width + horizontal_gap)));
        gy = Layout.snap !y;
        width = node_width; height; level; rows } :: !boxes;
      y := Layout.snap !y +. float (height + vertical_gap)) row) rows;
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
    Array.iteri (fun input_index -> function
      | None -> ()
      | Some source ->
          (match Hashtbl.find_opt by_id source with
           | None -> ()
           | Some source_index ->
               reversed := { connection = { Edit_graph.source;
                   consumer = box.info.id; input_index };
                 source_index; consumer_index } :: !reversed))
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
    ?(theme = Pxui.default_theme) ?selected ?(catalog = [])
    ?(flaggable = fun _ -> false) ?(enterable = fun _ -> false) ?(namespace = "sop") document =
  if width <= 0 || height <= 0 then invalid_arg
      "Pxui_graph.create_document: width and height must be positive";
  let selected = match selected with
    | Some id when Edit_graph.find document ~node_id:id <> None -> Id_set.singleton id
    | _ -> Id_set.empty in
  let primary = if Id_set.is_empty selected then None else Some (Id_set.choose selected) in
  let boxes = automatic_layout document Layout.empty 1. None in
  let edges = build_edges boxes in
  let slots = build_slots boxes in
  let viewed = match Edit_graph.root document with
    | Some id -> id
    | None -> Option.value ~default:0 primary in
  { source_graph = None; document; boxes; edges; slots;
    positions = Id_map.empty; moved_nodes = Id_set.empty;
    moved_cells = Cell_map.empty;
    layout = Layout.empty;
    spatial = build_spatial_index boxes edges Layout.empty; selected; primary;
    selected_edge = None; viewed; flagged = None; flaggable; enterable; x; y; width; height;
    pan_x = 38.; pan_y = 38.; zoom = 1.; drag = None; bloom = None; before_points = Id_map.empty;
    menu = None; context = None; clipboard = None; catalog = catalog_array catalog;
    last_added = None; hints = None; find = None; namespace;
    visible = true; theme }

let create ?x ?y ?width ?height ?theme ?selected ?catalog ?flaggable ?enterable graph =
  let value = create_document ?x ?y ?width ?height ?theme ?selected ?catalog ?flaggable ?enterable
      (Edit_graph.of_graph graph) in
  { value with source_graph = Some graph }

let connection_exists document connection =
  match Edit_graph.inputs document ~node_id:connection.Edit_graph.consumer with
  | Some inputs when connection.input_index >= 0
      && connection.input_index < Array.length inputs ->
      inputs.(connection.input_index) = Some connection.source
  | Some _ | None -> false

let layout_port_exists document (node, path) =
  match Edit_graph.inputs document ~node_id:node, Layout.slot_index path with
  | Some inputs, Some index -> index < Array.length inputs && inputs.(index) <> None
  | _ -> false

(* A parameter-only edit keeps every id and input slot, so positions, edges,
   the spatial index, selection, and paint cache all stay valid. *)
let same_topology (value : t) infos =
  List.compare_length_with infos (Array.length value.boxes) = 0
  && List.for_all (fun (info : Edit_graph.node_info) ->
    match Hashtbl.find_opt value.slots info.id with
    | Some index -> value.boxes.(index).info.inputs = info.inputs
    | None -> false) infos

let with_document document value =
  if document == value.document then value else
  let value = { value with hints = None } in
  let infos = Edit_graph.inspect document in
  if same_topology value infos then begin
    let boxes = Array.copy value.boxes in
    List.iter (fun (info : Edit_graph.node_info) ->
      let index = Hashtbl.find value.slots info.id in
      let tile_id = tile_text info in
      let level, rows, height = shape value.layout value.zoom value.bloom info in
      boxes.(index) <- { (boxes.(index)) with info; tile_id; level; rows; height }) infos;
    let changed_size = Array.exists (fun (box : box) ->
      box.height <> value.boxes.(Hashtbl.find value.slots box.info.id).height) boxes in
    if not changed_size then { value with source_graph = None; document; boxes } else
    let boxes = preserve_positions value.positions value.boxes boxes in
    { value with source_graph = None; document; boxes;
      positions = Id_map.empty; moved_nodes = Id_set.empty; moved_cells = Cell_map.empty;
      spatial = build_spatial_index boxes value.edges value.layout }
  end else
    let removed = Array.fold_left (fun ids (box : box) ->
      if Edit_graph.find document ~node_id:box.info.id = None then box.info.id :: ids else ids)
      [] value.boxes in
    let layout = Layout.remove_nodes removed value.layout in
    let layout = { layout with bends = Layout.Port_map.filter
      (fun port _ -> layout_port_exists document port) layout.bends } in
    let value = { value with layout } in
    let boxes = automatic_layout document value.layout value.zoom value.bloom
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
      spatial = build_spatial_index boxes edges value.layout;
      selected; primary;
      selected_edge; viewed }

let with_graph graph value = match value.source_graph with
  | Some current when current == graph -> value
  | Some _ | None ->
      let value = with_document (Edit_graph.of_graph graph) value in
      { value with source_graph = Some graph }

let with_bounds ~x ~y ~width ~height value =
  if width <= 0 || height <= 0 then invalid_arg
      "Pxui_graph.with_bounds: width and height must be positive";
  if x = value.x && y = value.y && width = value.width && height = value.height
  then value else { value with x; y; width; height;
    pan_x = value.pan_x +. (float_of_int (width - value.width) /. 2.);
    pan_y = value.pan_y +. (float_of_int (height - value.height) /. 2.);
    drag = None; menu = None; context = None }

let with_visible visible value =
  if visible = value.visible then value
  else { value with visible; drag = None; context = None }
let visible (value : t) = value.visible
let selected (value : t) = value.primary
let selected_nodes (value : t) = Id_set.elements value.selected
let selected_connection (value : t) = value.selected_edge
let viewed (value : t) = value.viewed
let flagged (value : t) = value.flagged
let with_flagged flagged (value : t) = { value with flagged }

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
    primary = (match node_ids with id :: _ -> Some id | [] -> None);
    selected_edge = None }

let clear_selection value = { value with selected = Id_set.empty; primary = None;
  selected_edge = None }

let view node_id value =
  if Edit_graph.find value.document ~node_id = None then invalid_arg
      (Printf.sprintf "Pxui_graph.view: graph has no node #%d" node_id);
  { value with viewed = node_id }

let place_nodes placements value =
  let boxes = Array.map (fun box ->
    match Id_map.find_opt box.info.Edit_graph.id value.positions with
    | None -> box
    | Some (gx, gy) -> { box with gx; gy }) value.boxes in
  List.iter (fun (node_id, x, y) -> match Hashtbl.find_opt value.slots node_id with
    | Some index -> boxes.(index) <- { (boxes.(index)) with
        gx = Layout.snap x; gy = Layout.snap y }
    | None -> ()) placements;
  let edges = build_edges boxes in
  { value with boxes; edges;
    positions = Id_map.empty; moved_nodes = Id_set.empty;
    moved_cells = Cell_map.empty;
    spatial = build_spatial_index boxes edges value.layout }

let with_layout layout value =
  let boxes = Array.map (fun (box : box) ->
    let level, rows, height = shape layout value.zoom value.bloom box.info in
    let gx, gy = Option.value (Id_map.find_opt box.info.id layout.Layout.at)
      ~default:(stored_box_position value.positions box) in
    { box with gx; gy; level; rows; height }) value.boxes in
  { value with boxes; layout; positions = Id_map.empty; moved_nodes = Id_set.empty;
    moved_cells = Cell_map.empty; spatial = build_spatial_index boxes value.edges layout }

let reshape value =
  let boxes = Array.map (fun (box : box) ->
    let level, rows, height = shape value.layout value.zoom value.bloom box.info in
    let gx, gy = stored_box_position value.positions box in
    { box with gx; gy; level; rows; height }) value.boxes in
  { value with boxes; positions = Id_map.empty; moved_nodes = Id_set.empty;
    moved_cells = Cell_map.empty;
    spatial = build_spatial_index boxes value.edges value.layout }

let set_bends ~node ~slot points value =
  let port = Layout.slot node slot in
  if not (List.for_all (fun (x, y) -> Float.is_finite x && Float.is_finite y) points) then
    invalid_arg "Pxui_graph.set_bends: nonfinite coordinates";
  if points <> [] && not (layout_port_exists value.document port) then
    invalid_arg "Pxui_graph.set_bends: missing destination slot";
  let points = List.map (fun (x, y) -> Layout.snap x, Layout.snap y) points in
  if points = Option.value ~default:[] (Layout.Port_map.find_opt port value.layout.bends)
  then value else
  let bends = if points = [] then Layout.Port_map.remove port value.layout.bends
    else Layout.Port_map.add port points value.layout.bends in
  reshape { value with layout = { value.layout with bends } }

let set_detail ids ~cards ~points value =
  let restore = points && List.for_all (fun id ->
    Id_map.find_opt id value.layout.level = Some Layout.Point) ids in
  let level, pinned, previous = List.fold_left (fun (levels, pins, previous) id ->
    if not (Hashtbl.mem value.slots id) then levels, pins, previous else
    let current = Option.value ~default:Layout.Card (Id_map.find_opt id levels) in
    let next = if cards then Layout.Card else if points then
        if restore then Option.value ~default:Layout.Card (Id_map.find_opt id previous)
        else Layout.Point
      else match current with Point -> Chip | Chip -> Card | Card | Full -> Full in
    let previous = if points && not restore && current <> Layout.Point
      then Id_map.add id current previous else previous in
    Id_map.add id next levels, Id_map.add id (not points) pins, previous)
      (value.layout.level, value.layout.pinned, value.before_points) ids in
  reshape { value with layout = { value.layout with level; pinned }; before_points = previous }

let screen_x value gx = value.x + int_of_float (value.pan_x +. (gx *. value.zoom))
let screen_y value gy = value.y + int_of_float (value.pan_y +. (gy *. value.zoom))
let screen_size value size = max 1 (int_of_float (float_of_int size *. value.zoom))
let graph_x value x = (float_of_int (x - value.x) -. value.pan_x) /. value.zoom
let graph_y value y = (float_of_int (y - value.y) -. value.pan_y) /. value.zoom

let box_graph_position (value : t) (box : box) =
  let gx, gy = stored_box_position value.positions box in
  match value.drag with
  | Some (Move_nodes { offset_x; offset_y; _ })
      when Id_set.mem box.info.Edit_graph.id value.selected ->
      gx +. offset_x, gy +. offset_y
  | Some (Move_nodes _ | Box_select _ | Connect_wire _ | Bend_wire _ | Pan_canvas | Knife) | None ->
      gx, gy

let box_bounds (value : t) (box : box) =
  let gx, gy = box_graph_position value box in
  screen_x value gx, screen_y value gy,
  screen_size value box.width, screen_size value box.height

let view_button_bounds (value : t) (box : box) =
  let x, y, width, _ = box_bounds value box in
  let button_width = screen_size value 26
  and button_height = screen_size value 12 in
  x + width - button_width - screen_size value 8,
  y + screen_size value 6, button_width, button_height

(* Tiles the host marks [flaggable] carry a flag button left of VIEW. *)
let is_flaggable (value : t) (box : box) = value.flaggable box.info

let active_button_bounds (value : t) (box : box) =
  let x, y, _, height = view_button_bounds value box in
  let width = max 40 (screen_size value 58) in
  x - width - max 4 (screen_size value 6), y, width, height

let node_views value = Array.to_list value.boxes |> List.map (fun box ->
  let info = box.info in
  { id = info.id; label = info.label; operation = info.operation;
    depth = box.depth; bounds = box_bounds value box;
    view_bounds = view_button_bounds value box;
    selected = Id_set.mem info.id value.selected; viewed = value.viewed = info.id;
    active = value.flagged = Some info.id;
    active_bounds = if is_flaggable value box then Some (active_button_bounds value box) else None;
    has_parameters = info.has_parameters })

let intersects (ax, ay, aw, ah) (bx, by, bw, bh) =
  ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah

let normalize_rect x0 y0 x1 y1 =
  min x0 x1, min y0 y1, abs (x1 - x0) + 1, abs (y1 - y0) + 1

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
        if edge_id >= 0 then visit edge_id
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

let input_port (value : t) (box : box) index =
  let gx, gy = graph_input box (box_graph_position value box) index in
  screen_x value gx, screen_y value gy

let output_port (value : t) (box : box) =
  let gx, gy = graph_output box (box_graph_position value box) in
  screen_x value gx, screen_y value gy

let hit_input value point =
  let radius = max 6 (screen_size value 6) and found = ref None in
  let visit index =
    let box = Array.unsafe_get value.boxes index in
    for input_index = 0 to Array.length box.info.Edit_graph.inputs - 1 do
      let px, py = input_port value box input_index in
      let dx = fst point - px and dy = snd point - py in
      if (dx * dx) + (dy * dy) <= radius * radius
          && Option.fold ~none:true ~some:(fun (current, _) -> index < current) !found
      then found := Some (index, input_index)
    done in
  Array.iter (fun index ->
    if not (Id_set.mem index value.moved_nodes) then visit index)
    (spatial_candidates value point);
  Option.iter (Id_set.iter visit) (moved_spatial_candidates value point);
  !found

let edge_points value edge =
  let source = value.boxes.(edge.source_index)
  and consumer = value.boxes.(edge.consumer_index) in
  let sx, sy = box_graph_position value source
  and cx, cy = box_graph_position value consumer in
  polyline ~bottom:(consumer.level = Layout.Chip && edge.connection.input_index > 0)
    value.layout edge.connection (graph_output source (sx, sy))
    (graph_input consumer (cx, cy) edge.connection.input_index)

let segment_distance_squared px py ax ay bx by =
  let dx = bx -. ax and dy = by -. ay in
  let length = (dx *. dx) +. (dy *. dy) in
  let t = if length = 0. then 0. else clamp 0. 1.
      (((px -. ax) *. dx +. (py -. ay) *. dy) /. length) in
  let x = ax +. (t *. dx) and y = ay +. (t *. dy) in
  let ex = px -. x and ey = py -. y in
  (ex *. ex) +. (ey *. ey)

let segments_cross (ax, ay) (bx, by) (cx, cy) (dx, dy) =
  let side ax ay bx by px py = (bx -. ax) *. (py -. ay) -. (by -. ay) *. (px -. ax) in
  max (min ax bx) (min cx dx) <= min (max ax bx) (max cx dx)
  && max (min ay by) (min cy dy) <= min (max ay by) (max cy dy)
  && side ax ay bx by cx cy *. side ax ay bx by dx dy <= 0.
  && side cx cy dx dy ax ay *. side cx cy dx dy bx by <= 0.

let crossed_wires value (x0, y0) (x1, y1) =
  let a = graph_x value x0, graph_y value y0
  and b = graph_x value x1, graph_y value y1 in
  let generation = next_spatial_generation value.spatial and crossed = ref [] in
  iter_edge_bvh value.spatial (min (fst a) (fst b)) (min (snd a) (snd b))
    (max (fst a) (fst b)) (max (snd a) (snd b)) (fun edge ->
      let points = value.spatial.edge_points.(edge) in
      let rec crosses i = i < Array.length points - 1
        && (segments_cross a b points.(i) points.(i + 1) || crosses (i + 1)) in
      if value.spatial.edge_marks.(edge) <> generation && crosses 0 then begin
        value.spatial.edge_marks.(edge) <- generation;
        crossed := value.edges.(edge).connection :: !crossed
      end);
  List.sort (fun (a : Edit_graph.connection) b ->
    compare (a.consumer, a.input_index) (b.consumer, b.input_index)) !crossed

let hit_edge value (px, py) =
  let graph_px = graph_x value px and graph_py = graph_y value py in
  let threshold = 6. /. value.zoom
  and best = ref None and best_distance = ref Float.infinity in
  let visit index =
    let points = Array.unsafe_get value.spatial.edge_points index in
    for segment = 0 to Array.length points - 2 do
    let ax, ay = Array.unsafe_get points segment
    and bx, by = Array.unsafe_get points (segment + 1) in
    let distance = segment_distance_squared graph_px graph_py ax ay bx by in
    if distance < !best_distance then begin
      best_distance := distance;
      best := Some index
    end
    done in
  iter_spatial_edge_candidates value (px, py) visit;
  if !best_distance <= threshold *. threshold then !best else None

let pan value dx dy =
  { value with pan_x = value.pan_x +. dx; pan_y = value.pan_y +. dy }

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

let move_nodes value node indices edge_indices (dx, dy) offset_x offset_y =
  { value with drag = Some (Move_nodes { node; indices; edge_indices;
      offset_x = offset_x +. (dx /. value.zoom);
      offset_y = offset_y +. (dy /. value.zoom) }) }

let commit_node_move value indices offset_x offset_y =
  if offset_x = 0. && offset_y = 0. then { value with drag = None } else
  let positions, moved_nodes, moved_cells = Array.fold_left
      (fun (positions, moved_nodes, moved_cells) index ->
    let box = Array.unsafe_get value.boxes index in
    let gx, gy = stored_box_position positions box in
    let moved_cells = if Id_set.mem index moved_nodes then
        fold_box_cells box gx gy moved_cells (fun cells key ->
          match Cell_map.find_opt key cells with
          | None -> cells
          | Some members ->
              let members = Id_set.remove index members in
              if Id_set.is_empty members then Cell_map.remove key cells
              else Cell_map.add key members cells)
      else moved_cells in
    let next_x = Layout.snap (gx +. offset_x)
    and next_y = Layout.snap (gy +. offset_y) in
    let moved_cells = fold_box_cells box next_x next_y moved_cells
        (fun cells key ->
          let members = Option.value (Cell_map.find_opt key cells)
              ~default:Id_set.empty in
          Cell_map.add key (Id_set.add index members) cells) in
    Id_map.add box.info.Edit_graph.id (next_x, next_y) positions,
    Id_set.add index moved_nodes, moved_cells)
      (value.positions, value.moved_nodes, value.moved_cells) indices in
  (* ponytail: full edge rebuild costs ~13 ms/22 MB for 20k wires on M1;
     refit affected BVH leaves if release latency exceeds the frame budget. *)
  let edge_bvh, edge_points =
    build_edge_index value.boxes value.edges positions value.layout in
  let spatial = { value.spatial with edge_bvh; edge_points; marks = Array.make (Array.length value.boxes) 0;
    edge_marks = Array.make (Array.length value.edges) 0;
    mark_generation = 0; visible_length = 0; visible_edge_length = 0;
    visible = Array.make (Array.length value.spatial.visible) 0;
    order = Array.make (Array.length value.spatial.order) 0;
    visible_edges = Array.make (Array.length value.spatial.visible_edges) 0;
    edge_stack = Array.make 64 0 } in
  { value with positions; moved_nodes; moved_cells; spatial; drag = None }

let zoom_at value (mouse_x, mouse_y) delta =
  let old_zoom = value.zoom in
  let zoom = clamp 0.25 2.0
      (old_zoom *. Float.pow 1.12 delta) in
  if zoom = old_zoom then value else
    let local_x = mouse_x -. float value.x -. value.pan_x
    and local_y = mouse_y -. float value.y -. value.pan_y in
    let ratio = zoom /. old_zoom in
    let next = { value with zoom;
      pan_x = mouse_x -. float value.x -. (local_x *. ratio);
      pan_y = mouse_y -. float value.y -. (local_y *. ratio) } in
    let cap z = if z < 0.34 then 0 else if z < 0.50 then 1 else 2 in
    if cap zoom = cap old_zoom then next else reshape next

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
  let zoom = clamp 0.25 2.0
      (min (available_width /. graph_width) (available_height /. graph_height)) in
  let center_x = (!min_x +. !max_x) *. 0.5
  and center_y = (!min_y +. !max_y) *. 0.5 in
  reshape { value with zoom;
    pan_x = (float_of_int value.width *. 0.5) -. (center_x *. zoom);
    pan_y = (float_of_int value.height *. 0.5) -. (center_y *. zoom);
    drag = None }

let frame_all value = frame_boxes value value.boxes

let frame_viewed (value : t) = match Hashtbl.find_opt value.slots value.viewed with
  | Some index -> frame_boxes value [| value.boxes.(index) |]
  | None -> frame_all value

let lower value = String.lowercase_ascii value

let category_text category = String.concat " / " category

let search_rank query (item : catalog_item) =
  let contains text =
    let rec at index = index + String.length query <= String.length text
      && (String.sub text index (String.length query) = query || at (index + 1)) in
    at 0 in
  if String.starts_with ~prefix:query item.lower_label then 0
  else if List.exists (String.starts_with ~prefix:query)
      (String.split_on_char ' ' item.lower_label) then 1
  else if contains item.lower_label || contains item.lower_key then 2
  else if Pxui.Ui.fuzzy_match ~query item.lower_label
      || Pxui.Ui.fuzzy_match ~query item.lower_key then 3
  else 4

let eligible menu (item : catalog_item) =
  (menu.insertion = None && not menu.compatible_input) || item.entry.arity > 0

let rec category_remainder path category = match path, category with
  | [], category -> Some category
  | expected :: path, actual :: category when expected = actual ->
      category_remainder path category
  | _ -> None

let menu_rows (value : t) menu =
  let entries = Array.to_list value.catalog |> List.filter (eligible menu) in
  if menu.query <> "" then begin
    let query = lower menu.query in
    entries |> List.filter (fun item ->
      Pxui.Ui.fuzzy_match ~query item.lower_label
      || Pxui.Ui.fuzzy_match ~query item.lower_category
      || Pxui.Ui.fuzzy_match ~query item.lower_key)
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

let open_menu (value : t) (x, y) =
  let gx, gy = graph_x value x, graph_y value y in
  let x = min (value.x + value.width - menu_width - 8) (max (value.x + 8) x) in
  let y = max (value.y + 8) y in
  { value with menu = Some { x; y; gx; gy;
    query = ""; path = []; insertion = value.selected_edge;
    inputs = selected_nodes value; compatible_input = false; ripple = [] };
    drag = None; context = None; hints = None; find = None }

let menu_request (_value : t) menu entry =
  let at = menu.gx, menu.gy in
  match menu.insertion with
  | Some connection -> Insert_requested {
      factory_key = entry.key; connection; at; ripple = menu.ripple }
  | None ->
      let rec take count values = match count, values with
        | count, _ when count <= 0 -> []
        | _, [] -> []
        | count, value :: rest -> value :: take (count - 1) rest in
      let inputs = take entry.arity menu.inputs in
      Add_requested { factory_key = entry.key; inputs; at }

let parent_path path = match List.rev path with
  | [] -> [] | _ :: rest -> List.rev rest

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

let node_positions (value : t) = Array.to_list value.boxes |> List.map (fun box ->
  let gx, gy = box_graph_position value box in box.info.Edit_graph.id, gx, gy)

let node_position (value : t) node_id = Option.map (fun index ->
  box_graph_position value (Array.unsafe_get value.boxes index))
    (Hashtbl.find_opt value.slots node_id)

let layout value =
  { value.layout with at = Id_map.of_list (List.map (fun (id, x, y) -> id, (x, y))
      (node_positions value)) }

let edit_layout ~nodes ~ports value previous =
  let at = List.fold_left (fun at id -> match node_position value id with
    | Some (x, y) -> Id_map.add id (Layout.snap x, Layout.snap y) at
    | None -> Id_map.remove id at) value.layout.at nodes in
  let source = { value.layout with at } in
  Layout.edit ~nodes ~ports ~source previous

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

let wire_bounds (value : t) points =
  let min_x = ref Float.infinity and min_y = ref Float.infinity
  and max_x = ref Float.neg_infinity and max_y = ref Float.neg_infinity in
  Array.iter (fun (x, y) ->
    min_x := min !min_x x; min_y := min !min_y y;
    max_x := max !max_x x; max_y := max !max_y y) points;
  let x = screen_x value !min_x and y = screen_y value !min_y in
  x, y, screen_x value !max_x - x + 1, screen_y value !max_y - y + 1

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
  if length > 1 then begin
    let sorted = Array.sub values 0 length in
    Array.sort Int.compare sorted;
    Array.blit sorted 0 values 0 length
  end

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
   | Some (Box_select _ | Connect_wire _ | Bend_wire _ | Pan_canvas | Knife) | None -> ());
  sort_visible_prefix spatial.visible spatial.visible_length;
  spatial.visible_edge_length <- 0;
  let graph_left = graph_x value x
  and graph_right = graph_x value (x + width - 1)
  and graph_top = graph_y value y
  and graph_bottom = graph_y value (y + height - 1) in
  let visit_edge candidate =
    if Array.unsafe_get spatial.edge_marks candidate <> generation then begin
      Array.unsafe_set spatial.edge_marks candidate generation;
      let points = edge_points value value.edges.(candidate) in
      if intersects viewport (wire_bounds value points) then begin
        ensure_visible_edge_capacity spatial
          (spatial.visible_edge_length + 1);
        Array.unsafe_set spatial.visible_edges spatial.visible_edge_length candidate;
        spatial.visible_edge_length <- spatial.visible_edge_length + 1
      end
    end in
  iter_edge_bvh spatial (min graph_left graph_right) (min graph_top graph_bottom)
    (max graph_left graph_right) (max graph_top graph_bottom)
    visit_edge;
  (match value.drag with
   | Some (Move_nodes { edge_indices; _ }) -> Array.iter visit_edge edge_indices
   | Some (Box_select _ | Connect_wire _ | Bend_wire _ | Pan_canvas | Knife) | None -> ());
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
    spatial_edge_cells = Array.length value.spatial.edge_bvh.edge_id;
    max_spatial_edge_candidates = value.spatial.max_edge_candidates;
    overflow_spatial_edges = 0 }

let stats (value : t) = let _, _, stats = visibility value in stats

(* -------------------------------------------------------------- painting *)

module Ui = Pxui.Ui

let fill paint x y w h color =
  Ui.Paint.fill paint ~x:(float_of_int x) ~y:(float_of_int y)
    ~w:(float_of_int w) ~h:(float_of_int h) color
let framed paint x y w h ~fill ~stroke =
  Ui.Paint.rect paint ~x:(float_of_int x) ~y:(float_of_int y)
    ~w:(float_of_int w) ~h:(float_of_int h) ~fill ~stroke ()
let text paint ~at:(x, y) ~size ~color label =
  Ui.Paint.text paint ~at:(float_of_int x, float_of_int y) ~size ~color label
let circle paint (x, y) radius ~fill ~stroke =
  Ui.Paint.circle paint ~at:(float_of_int x, float_of_int y)
    ~radius:(float_of_int radius) ~fill ~stroke ()

let paint_wire (value : t) paint points ~width color =
  for index = 0 to Array.length points - 2 do
    let screen (x, y) = float (screen_x value x), float (screen_y value y) in
    Ui.Paint.line paint ~from_:(screen points.(index)) ~to_:(screen points.(index + 1))
      ~width color
  done

let canvas_fill (value : t) =
  if value.theme = Pxui.default_theme then Color.hex_exn "#eef2ee"
  else Color.blend value.theme.panel value.theme.accent ~pct:0.25

let paint_background (value : t) paint visible_edges visible_wires =
  let theme = value.theme in
  let spacing = max 10 (screen_size value 12) in
  let offset_x = int_of_float value.pan_x mod spacing
  and offset_y = int_of_float value.pan_y mod spacing in
  Ui.Paint.grid paint ~x:(float_of_int value.x) ~y:(float_of_int value.y)
    ~w:(float_of_int value.width) ~h:(float_of_int value.height)
    ~origin:(float_of_int (value.x + offset_x - spacing),
      float_of_int (value.y + offset_y - spacing))
    ~spacing:(float_of_int spacing) (Color.with_alpha theme.foreground 145);
  for visible_index = 0 to visible_wires - 1 do
    let edge = value.edges.(Array.unsafe_get visible_edges visible_index) in
    let points = edge_points value edge in
    if value.selected_edge = Some edge.connection then
      paint_wire value paint points ~width:8. (Color.with_alpha theme.accent 71);
    paint_wire value paint points ~width:2.4 theme.accent
  done

let field_text : Parameter.value -> string = function
  | Bool_value b -> string_of_bool b | Int_value n -> string_of_int n
  | Float_value f -> Printf.sprintf "%.5g" f | Text_value s | Choice_value s -> s

let parse_field (field : Parameter.field_view) text = match field.kind with
  | Toggle_view -> Option.map (fun x -> Parameter.Bool_value x) (bool_of_string_opt text)
  | Integer_view _ -> (match int_of_string_opt text with
      | Some n -> Some (Parameter.Int_value n)
      | None -> match float_of_string_opt text with
        | Some n when Float.is_finite n && n >= float min_int && n < float max_int ->
            Some (Parameter.Int_value (int_of_float (Float.round n)))
        | _ -> None)
  | Floating_view _ -> (match float_of_string_opt text with
      | Some x when Float.is_finite x -> Some (Parameter.Float_value x) | _ -> None)
  | Text_view -> Some (Parameter.Text_value text)
  | Choice_view choices ->
      if Array.mem text choices then Some (Parameter.Choice_value text) else None

let scrub_field (field : Parameter.field_view) =
  let numeric low high text dx shift =
    let divisor = if shift then 1500. else 150. in
    let current = Option.value ~default:0. (float_of_string_opt text) in
    let next = current +. (dx *. (high -. low) /. divisor) in
    if Float.is_finite next then Printf.sprintf "%.17g" next else text in
  match field.kind with
  | Floating_view r -> Some (numeric r.soft_min r.soft_max)
  | Integer_view r -> Some (numeric (float r.soft_min) (float r.soft_max))
  | _ -> None

let build_row_fields value ui (box : box) =
  Array.fold_left (fun (index, changes, detail, pin) row ->
    let y = 24 + (24 * index) in
    let _, gy = box_graph_position value box in
    let screen_y0 = screen_y value (gy +. float y) in
    if screen_y0 + screen_size value 24 < value.y || screen_y0 > value.y + value.height then
      index + 1, changes, detail, pin else
    let at x y = float (screen_size value x), float (screen_size value y) in
    let width = screen_size value 76 and height = screen_size value 16 in
    let emit f v = if v = f.Parameter.current then changes else
      Set_parameter_requested { node = box.info.id; path = f.name; value = v } :: changes in
    match row with
    | Field (f, _) ->
        let key = "field-" ^ f.name in
        (match f.current, f.kind with
         | Bool_value _, _ | _, Choice_view _ ->
             let field_x, field_w = match f.kind with
               | Choice_view _ -> 90, 98 | _ -> 112, 76 in
             let field = Ui.box ui ~flags:Ui.(clickable + tab_stop)
               ~at:(at field_x (y + 4)) ~w:(Ui.Px (float (screen_size value field_w)))
               ~h:(Ui.Px (float height)) key in
             let signal = Ui.signal ui field in
             let v = if not signal.clicked then f.current else match f.current, f.kind with
               | Bool_value b, _ -> Parameter.Bool_value (not b)
               | Choice_value current, Choice_view choices when Array.length choices > 0 ->
                   let i = Option.value ~default:0 (Array.find_index (( = ) current) choices) in
                   let delta = if List.mem Input.Shift (Ui.press_keys ui field) then -1 else 1 in
                   Choice_value choices.((i + delta + Array.length choices) mod Array.length choices)
               | _ -> f.current in
             Ui.draw ui field (fun paint (x, y, w, h) ->
               Ui.Paint.rect paint ~x ~y ~w ~h ~fill:value.theme.track
                 ~stroke:(Pxui.Theme.faint_border value.theme) ();
               Ui.Paint.text paint ~at:(x +. 4., y +. 2.) ~size:(max 7 (screen_size value 11))
                 ~color:value.theme.foreground (field_text v));
             index + 1, emit f v, detail, pin
         | _ ->
             let current = match f.current with
               | Float_value x -> Printf.sprintf "%.17g" x | _ -> field_text f.current in
             let fraction = match f.kind, f.current with
               | Floating_view r, Float_value x when r.soft_max > r.soft_min ->
                   Some ((x -. r.soft_min) /. (r.soft_max -. r.soft_min))
               | Integer_view r, Int_value x when r.soft_max > r.soft_min ->
                   Some ((float x -. float r.soft_min) /. (float r.soft_max -. float r.soft_min))
               | _ -> None in
             let text, editing = Ui.value_field ui ~at:(at 112 (y + 4))
               ~w:(float width) ~h:(float height) ~size:(max 7 (screen_size value 11))
               ~display:(field_text f.current)
               ?fraction ?scrub:(scrub_field f)
               ~valid:(fun text -> parse_field f text <> None) key current in
             let changes = Option.fold ~none:changes ~some:(emit f) (parse_field f text) in
             index + 1, changes, detail, pin || editing)
    | More count ->
        let button = Ui.box ui ~flags:Ui.(clickable + tab_stop) ~at:(at 0 y)
          ~w:(Ui.Px (float (screen_size value box.width)))
          ~h:(Ui.Px (float (screen_size value 24))) "more" in
        let detail = if (Ui.signal ui button).clicked
          then Some (if count < 0 then Layout.Card else Layout.Full) else detail in
        index + 1, changes, detail, pin
    | Slot _ | Folder _ -> index + 1, changes, detail, pin)
    (0, [], None, false) box.rows
  |> fun (_, changes, detail, pin) -> changes, detail, pin

let fitted_text paint size width value =
  if Ui.Paint.text_width paint ~size value <= width then value else
  let rec prefix at previous =
    if at >= String.length value then String.sub value 0 previous ^ "…" else
    let next = at + Uchar.utf_decode_length (String.get_utf_8_uchar value at) in
    if Ui.Paint.text_width paint ~size (String.sub value 0 next ^ "…") > width
    then String.sub value 0 previous ^ "…" else prefix next next in
  prefix 0 0

let paint_node (value : t) paint (box : box) =
  let theme = value.theme in
  let gx, gy = box_graph_position value box in
  let x, y, width, height = box_bounds value box in
  let selected = Id_set.mem box.info.Edit_graph.id value.selected
  and viewed = value.viewed = box.info.Edit_graph.id in
  let accent = (Pxui.Theme.ports theme).geometry in
  let stroke = if viewed || selected then accent else Pxui.Theme.border theme in
  let label_size = max 7 (screen_size value 11) in
  let label at color text_value = text paint ~at ~size:label_size ~color text_value in
  let at dx dy = screen_x value (gx +. float dx), screen_y value (gy +. float dy) in
  if box.level = Layout.Point then begin
    if viewed then begin
      let cx, cy = at 12 12 in
      for dash = 0 to 11 do
        let angle = float dash *. Float.pi /. 6. in
        Ui.Paint.arc paint ~at:(float cx, float cy) ~radius:(float (screen_size value 15))
          ~from_:angle ~to_:(angle +. Float.pi /. 12.) ~width:1. accent
      done
    end;
    if selected then circle paint (at 12 12) (screen_size value 11)
      ~fill:(Color.with_alpha accent 0) ~stroke:accent;
    circle paint (at 12 12) (screen_size value 7) ~fill:accent ~stroke:accent;
    label (at 26 5) theme.foreground box.info.label
  end else begin
    Ui.Paint.rect paint ~x:(float x) ~y:(float y) ~w:(float width) ~h:(float height)
      ~radius:(3. *. value.zoom) ~fill:theme.input ~stroke ();
    let tx, ty = at 7 7 in
    fill paint tx ty (screen_size value 10) (screen_size value 10) accent;
    let title = fitted_text paint label_size
      (float (screen_size value (if box.info.bypass then 114 else 130))) box.info.label in
    label (at 24 5) theme.foreground title;
    if box.info.bypass then label (at 150 5) accent "M";
    Array.iteri (fun index row ->
      let y = 24 + (index * 24) in
      let top = screen_y value (gy +. float y) in
      if top + screen_size value 24 >= value.y && top <= value.y + value.height then
      match row with
      | Slot slot -> label (at 14 (y + 5)) theme.foreground ("in" ^ string_of_int slot)
      | Field (f, shown) ->
          let color = if shown then theme.foreground
            else Pxui.Theme.muted theme in
          let width = match f.kind with Choice_view _ -> 68 | _ -> 90 in
          label (at 14 (y + 5)) color
            (fitted_text paint label_size (float (screen_size value width)) f.label)
      | Folder folder ->
          let name = fitted_text paint label_size (float (screen_size value 150))
            (String.uppercase_ascii (String.concat " / " folder)) in
          let fx, fy = at 10 (y + 5) in
          label (fx, fy) accent name;
          let start = float fx +. Ui.Paint.text_width paint ~size:label_size name +. 8. in
          let finish, middle = at 188 (y + 12) in
          if start < float finish then Ui.Paint.line paint ~from_:(start, float middle)
            ~to_:(float finish, float middle) ~width:1. (Pxui.Theme.faint_border theme)
      | More count -> label (at 14 (y + 5)) accent
          (if count < 0 then "− show fewer" else Printf.sprintf "+ %d more" count)) box.rows;
    let socket connected (px, py) =
      let r = screen_size value 4 in
      if py + r >= value.y && py - r <= value.y + value.height then
        framed paint (px - r) (py - r) (screen_size value 9) (screen_size value 9)
          ~fill:(if connected then accent else theme.input) ~stroke:accent in
    socket true (output_port value box);
    Array.iteri (fun i input -> socket (Option.is_some input) (input_port value box i))
      box.info.inputs;
    if viewed then begin
      let bx, by, bw, bh = view_button_bounds value box in
      fill paint bx by bw bh accent;
      text paint ~at:(bx + 2, by + 1) ~size:(max 7 (screen_size value 8))
        ~color:theme.input "VIEW"
    end;
    if is_flaggable value box then begin
      let ax, ay, aw, ah = active_button_bounds value box in
      framed paint ax ay aw ah ~fill:theme.control ~stroke:accent;
      text paint ~at:(ax + 2, ay + 1) ~size:(max 7 (screen_size value 8))
        ~color:theme.foreground (if value.flagged = Some box.info.id then "ACTIVE" else "SET")
    end
  end

(* ----------------------------------------------------------- interaction *)

let optimize_layout (value : t) =
  let boxes = automatic_layout value.document value.layout value.zoom value.bloom in
  let edges = build_edges boxes in
  { value with boxes; edges;
    positions = Id_map.empty; moved_nodes = Id_set.empty;
    moved_cells = Cell_map.empty;
    spatial = build_spatial_index boxes edges value.layout } |> frame_all

let open_menu_at point value = open_menu value point

let with_last_added key value = { value with last_added = Some (value.namespace ^ "/" ^ key) }
let carry_last_added ~from value = { value with last_added = from.last_added }
let hinting value = value.hints <> None
let editing value = value.menu <> None || value.find <> None

let frame_selection value =
  let indices = indices_of_selection value in
  if Array.length indices = 0 then frame_viewed value
  else frame_boxes value (Array.map (Array.get value.boxes) indices)

let reveal_node value id = match Hashtbl.find_opt value.slots id with
  | None -> value
  | Some index ->
      let x, y, w, h = box_bounds value value.boxes.(index) in
      let shift at size origin available =
        if at < origin + 24 then float (origin + 24 - at)
        else if at + size > origin + available - 24
        then float (origin + available - 24 - at - size) else 0. in
      pan value (shift x w value.x value.width) (shift y h value.y value.height)

type direction = Left | Down | Up | Right

let walk value direction =
  let position box = box_graph_position value box in
  let compare_origin a b =
    let ax, ay = position a and bx, by = position b in
    let by_y = Float.compare ay by in
    if by_y <> 0 then by_y else let by_x = Float.compare ax bx in
    if by_x <> 0 then by_x else Int.compare a.info.id b.info.id in
  let current = Option.bind value.primary (Hashtbl.find_opt value.slots) in
  let pick = match current with
    | None -> Array.to_list value.boxes |> List.sort (fun a b ->
        let ax, _ = position a and bx, _ = position b in
        let order = Float.compare ax bx in if order = 0 then compare_origin a b else order)
        |> List.find_opt (fun _ -> true)
    | Some index ->
        let box = value.boxes.(index) in
        let connected = match direction with
          | Left -> Option.bind (Array.find_map Fun.id box.info.inputs) (fun id ->
                Option.map (Array.get value.boxes) (Hashtbl.find_opt value.slots id))
          | Right -> Array.to_list value.edges |> List.filter_map (fun edge ->
              if edge.connection.source = box.info.id
              then Some value.boxes.(edge.consumer_index) else None)
              |> List.sort compare_origin |> List.find_opt (fun _ -> true)
          | Down | Up -> None in
        (match connected with Some _ -> connected | None ->
          let x, y = position box in
          Array.to_list value.boxes |> List.filter_map (fun candidate ->
            let cx, cy = position candidate in
            let along, across = match direction with
              | Left -> x -. cx, y -. cy | Right -> cx -. x, cy -. y
              | Down -> cy -. y, cx -. x | Up -> y -. cy, x -. cx in
            if along > 10. then Some (along +. 2. *. abs_float across, candidate) else None)
          |> List.sort (fun (a, left) (b, right) ->
              let order = Float.compare a b in if order = 0 then compare_origin left right else order)
          |> List.find_opt (fun _ -> true) |> Option.map snd) in
  match pick with
  | None -> value, []
  | Some box -> select box.info.id value |> fun value -> reveal_node value box.info.id,
      [Selected (Some box.info.id)]

let arc_midpoint points =
  let distance (x, y) (xx, yy) = Float.hypot (xx -. x) (yy -. y) in
  let total = ref 0. in
  for i = 1 to Array.length points - 1 do
    total := !total +. distance points.(i - 1) points.(i)
  done;
  let rec at i remaining =
    if i >= Array.length points then points.(Array.length points - 1) else
    let length = distance points.(i - 1) points.(i) in
    if remaining > length then at (i + 1) (remaining -. length)
    else let x, y = points.(i - 1) and xx, yy = points.(i) in
      let t = if length = 0. then 0. else remaining /. length in
      x +. t *. (xx -. x), y +. t *. (yy -. y) in
  at 1 (!total /. 2.)

let downstream value source =
  let seen = Hashtbl.create 16 and pending = Queue.create () in
  Queue.add source pending;
  while not (Queue.is_empty pending) do
    let id = Queue.take pending in
    if not (Hashtbl.mem seen id) then begin
      Hashtbl.add seen id ();
      match Hashtbl.find_opt value.slots id with
      | None -> ()
      | Some index -> Array.iter (fun edge_index ->
          let edge = value.edges.(edge_index) in
          if edge.connection.source = id then Queue.add edge.connection.consumer pending)
          value.spatial.incident_edges.(index)
    end
  done;
  seen

let add_by_context ?(wire = true) value pointer =
  let opened = open_menu value pointer in
  let menu = Option.get opened.menu in
  let menu = match (if wire then value.selected_edge else None), selected_nodes value with
    | Some connection, _ ->
        (match Array.find_opt (fun edge -> edge.connection = connection) value.edges with
         | Some edge -> let gx, gy = arc_midpoint (edge_points value edge) in
             { menu with gx; gy; insertion = Some connection; inputs = []; compatible_input = true }
         | None -> { menu with insertion = None; inputs = [] })
    | None, [source] ->
        let x, gy = Option.get (node_position value source) in
        let gx = x +. float (node_width + 60) in
        let trunks = Array.to_list value.edges |> List.filter (fun edge ->
          edge.connection.source = source && edge.connection.input_index = 0)
          |> List.sort (fun a b ->
            let _, ay = box_graph_position value value.boxes.(a.consumer_index)
            and _, by = box_graph_position value value.boxes.(b.consumer_index) in
            let order = Float.compare ay by in if order = 0
            then Int.compare a.connection.consumer b.connection.consumer else order) in
        let insertion = Option.map (fun edge -> edge.connection) (List.find_opt (fun _ -> true) trunks) in
        let ripple = match insertion with None -> [] | Some connection ->
          let descendants = downstream value connection.consumer in
          node_positions value |> List.filter_map (fun (id, x, y) ->
            if Hashtbl.mem descendants id && x >= Layout.snap gx
            then Some (id, x +. float (node_width + 60), y) else None) in
        { menu with gx; gy; insertion; inputs = [source]; compatible_input = true; ripple }
    | None, _ -> { menu with insertion = None; inputs = [] } in
  { opened with menu = Some menu }

let hint_alphabet = "asdfghjklqwertyuiopzxcvbnm"

let label_hints targets =
  let two = List.length targets > String.length hint_alphabet in
  List.mapi (fun index target ->
    let label = if two then String.init 2 (function
      | 0 -> hint_alphabet.[index / 26] | _ -> hint_alphabet.[index mod 26])
      else String.make 1 hint_alphabet.[index] in label, target)
    (List.filteri (fun index _ -> index < 676) targets)

let hints_for ?node value source =
  let seen = ref Id_set.empty in
  let rec ancestors id = if not (Id_set.mem id !seen) then begin
    seen := Id_set.add id !seen;
    Option.iter (fun index -> Array.iter (Option.iter ancestors)
      value.boxes.(index).info.inputs) (Hashtbl.find_opt value.slots id)
  end in
  ancestors source;
  let sx, sy = Option.get (node_position value source) in
  Array.to_list value.boxes |> List.filter (fun box ->
    not (Id_set.mem box.info.id !seen) && Array.length box.info.inputs > 0
    && (node = None || node = Some box.info.id))
  |> List.sort (fun a b ->
    let distance box = let x, y = box_graph_position value box in
      Float.hypot (x -. sx) (y -. sy) in
    let order = Float.compare (distance a) (distance b) in
    if order = 0 then Int.compare a.info.id b.info.id else order)
  |> List.concat_map (fun box ->
    let count = Array.length box.info.inputs in
    if count = 1 || box.level = Layout.Card || box.level = Layout.Full then
      List.init count (fun input_index -> Hint_port Edit_graph.{ source;
        consumer = box.info.id; input_index })
    else [Hint_node box.info.id]) |> label_hints

let hint_letter value letter = match value.hints with
  | None -> value, []
  | Some hints ->
      let prefix = hints.prefix ^ String.make 1 letter in
      match List.assoc_opt prefix hints.targets with
      | Some (Hint_port connection) -> { value with hints = None }, [Connect_requested connection]
      | Some (Hint_node id) ->
          let layout = { value.layout with
            level = Id_map.add id Layout.Full value.layout.level;
            pinned = Id_map.add id true value.layout.pinned } in
          let value = reshape { value with layout } in
          { value with hints = Some { hints with prefix = "";
              targets = hints_for ~node:id value hints.source } }, [Level_changed [id]]
      | None when List.exists (fun (label, _) -> String.starts_with ~prefix label) hints.targets ->
          { value with hints = Some { hints with prefix } }, []
      | None -> value, []

type command = Copy | Cut | Paste | Duplicate | Delete | Frame_all
  | Open_detail | Point_detail | Open_all | Point_all
  | Walk of direction | Add | Repeat | Connect_hint | Display | Mute | Dissolve | Find
  | Frame_selection | Hint_letter of char | Hint_back | Cancel

let bindings =
  let open Editor_core.Keymap in
  let open Editor_core.Guide_context in
  let command ?(guide = []) id label action key modifiers = Editor_core.Command.make
      ~id:("graph." ^ id) ~label ~guide ~trigger:(Chord (key, modifiers)) action in
  let letter key action id = List.map (fun modifier ->
    command id id action (Input.KeyChar key) [modifier]) [Input.Meta; Input.Ctrl] in
  letter 'c' Copy "copy" @ letter 'x' Cut "cut"
  @ letter 'v' Paste "paste" @ letter 'd' Duplicate "duplicate"
  @ [command "delete" "delete" Delete Input.Delete [];
     command "delete" "delete" Delete Input.Backspace [];
     command "frame-all" "frame all" Frame_all Input.Home [];
     command "open" "Open detail" Open_detail (Input.KeyChar 'o') [];
     command "point" "Toggle points" Point_detail (Input.KeyChar 'p') [];
     command "open-all" "Open all cards" Open_all (Input.KeyChar 'o') [Input.Shift];
     command "point-all" "Toggle all points" Point_all (Input.KeyChar 'p') [Input.Shift]]
  @ List.concat_map (fun (direction, letter, arrow, name) ->
      [command ~guide:[Canvas; Node; Multi] ("walk." ^ name) ("walk " ^ name)
         (Walk direction) (Input.KeyChar letter) [];
       command ("walk." ^ name) ("walk " ^ name) (Walk direction) arrow []])
      [Left, 'h', Input.ArrowLeft, "left"; Down, 'j', Input.ArrowDown, "down";
       Up, 'k', Input.ArrowUp, "up"; Right, 'l', Input.ArrowRight, "right"]
  @ [command ~guide:[Canvas; Node; Multi; Wire] "add" "add by context" Add Input.Tab [];
     command ~guide:[Canvas; Node] "repeat" "repeat last add" Repeat (Input.KeyChar '.') [];
     command ~guide:[Node] "connect-hint" "connect by hints" Connect_hint (Input.KeyChar 'c') [];
     command ~guide:[Node] "display" "display geometry" Display (Input.KeyChar 'v') [];
     command ~guide:[Node; Multi] "mute" "toggle bypass" Mute (Input.KeyChar 'm') [];
     command ~guide:[Node; Multi; Wire] "delete" "delete" Delete (Input.KeyChar 'x') [];
     command ~guide:[Node; Multi] "dissolve" "dissolve trunk" Dissolve (Input.KeyChar 'x') [Input.Shift];
     command ~guide:[Canvas; Node; Multi] "find" "find node" Find (Input.KeyChar '/') [];
     command ~guide:[Canvas; Node; Multi] "frame-tile" "frame selection / display"
       Frame_selection (Input.KeyChar 'f') []]

let hint_bindings =
  let open Editor_core.Keymap in
  let command id label key action = Editor_core.Command.make ~id:("graph.hint." ^ id)
    ~label ~trigger:(Chord (key, [])) ~guide:[Editor_core.Guide_context.Hints] action in
  List.init (String.length hint_alphabet) (fun i -> let letter = hint_alphabet.[i] in
    command (String.make 1 letter) "pick hint" (Input.KeyChar letter) (Hint_letter letter))
  @ [command "back" "erase hint letter" Input.Backspace Hint_back;
     command "cancel" "cancel hints" Input.Escape Cancel]

let run_command ?at (value : t) =
  let pointer = Option.value ~default:(value.x + value.width / 3, value.y + value.height / 3) at in
  function
  | Hint_letter letter -> hint_letter value letter
  | Hint_back -> (match value.hints with
      | Some hints when hints.prefix <> "" -> { value with hints = Some { hints with
          prefix = String.sub hints.prefix 0 (String.length hints.prefix - 1) } }, []
      | _ -> value, [])
  | Cancel -> { value with hints = None }, []
  | _ when value.menu <> None -> value, []
  | Copy -> copy_selection value, []
  | Cut -> delete_selection (copy_selection value)
  | Paste -> paste_clipboard value
  | Duplicate -> duplicate_selection value
  | Delete -> delete_selection value
  | Frame_all -> frame_all value, [View_changed]
  | Frame_selection -> frame_selection value, [View_changed]
  | Walk direction -> walk value direction
  | Add -> add_by_context value pointer, []
  | Repeat -> (match value.last_added with
      | None -> value, [Notice "Add a node first"]
      | Some kind when not (String.starts_with ~prefix:(value.namespace ^ "/") kind) ->
          value, [Notice "The last kind is unavailable in this level"]
      | Some kind ->
          let key = String.sub kind (String.length value.namespace + 1)
            (String.length kind - String.length value.namespace - 1) in
          (match Array.find_opt (fun item -> item.entry.key = key) value.catalog with
          | None -> value, [Notice "The last kind is unavailable in this level"]
          | Some item ->
              let value = add_by_context ~wire:false value pointer in
              let menu = Option.get value.menu in
              let menu = if item.entry.arity = 0 then { menu with insertion = None; ripple = [] }
                else menu in
              let request = menu_request value menu item.entry in
              { value with menu = None }, [request]))
  | Connect_hint -> (match selected_nodes value with
      | [source] -> let targets = hints_for value source in
          if targets = [] then value, [Notice "No compatible input can be connected"]
          else { value with hints = Some { source; targets; prefix = "" } }, []
      | _ -> value, [Notice "Select one source node to connect"])
  | Display -> (match value.primary with
      | Some id -> view id value, [Viewed id] | None -> value, [])
  | Mute | Dissolve when Id_set.is_empty value.selected -> value, []
  | Mute -> value, [Bypass_requested (List.filter_map (fun id ->
      Option.map (fun index -> id, not value.boxes.(index).info.bypass)
        (Hashtbl.find_opt value.slots id)) (selected_nodes value))]
  | Dissolve -> clear_selection value, [Dissolve_nodes_requested (selected_nodes value)]
  | Find -> { value with find = Some ""; hints = None; menu = None; context = None }, []
  | (Open_detail | Point_detail | Open_all | Point_all) as command ->
      let ids = if command = Open_all || command = Point_all
        then Array.to_list (Array.map (fun (box : box) -> box.info.id) value.boxes)
        else Id_set.elements value.selected in
      if ids = [] then value, [] else
      set_detail ids ~cards:(command = Open_all)
        ~points:(command = Point_detail || command = Point_all) value,
      [Level_changed ids]

let ints (x, y) = int_of_float x, int_of_float y

let picker_rows value menu query =
  menu_rows value { menu with query } |> Array.map (function
    | Menu_category category -> category, "›"
    | Menu_entry entry ->
        entry.label,
        if query = "" then Printf.sprintf "%d in" entry.arity
        else Printf.sprintf "%s · %d in" (category_text entry.category) entry.arity)

(* The node menu: a search field over the top-level column. Hovering or
   clicking a category opens its column to the right; clicking an entry adds
   it. Typing lists every matching node instead (arrows and Enter pick).
   All columns share one popup, so a press in any of them keeps it open; a
   press outside or Escape closes it. *)
let build_menu (value : t) ui menu =
  let row = Ui.row_height ui in
  let searching = menu.query <> "" in
  let rows_of prefix = menu_rows value { menu with path = prefix; query = "" } in
  (* A lone top-level category (the scene's Object, the World's Layer)
     opens by itself. *)
  let base = match rows_of [] with [| Menu_category category |] -> [category] | _ -> [] in
  let menu = if menu.path = [] then { menu with path = base } else menu in
  let levels = if searching then []
    else List.init (List.length menu.path + 1 - List.length base) (fun depth ->
      List.filteri (fun index _ -> index < depth + List.length base) menu.path) in
  let shown = if searching then Array.length (menu_rows value { menu with path = [] })
    else List.fold_left (fun most prefix -> max most (Array.length (rows_of prefix))) 0 levels in
  let height = ((1 + min menu_limit shown) * row) + 6 in
  let width = max 1 (List.length levels) * menu_width in
  let x = max 0 (min menu.x (value.x + value.width - width))
  and y = max value.y (min menu.y (value.y + value.height - height)) in
  let result = Ui.popup ui ~stroke:(Ui.theme ui).accent ~at:(float_of_int x, float_of_int y)
      ~width:(float_of_int width) ~height:(float_of_int height)
      "pxui-graph-menu" (fun () ->
      let query, pick = Ui.picker ui ~limit:menu_limit "Add · type to search"
          ~query:menu.query (fun query ->
            if query = "" then [||] else picker_rows value { menu with path = [] } query) in
      let hovered = ref None and clicked = ref None in
      if query = "" then
        Ui.row ui "pxui-graph-menu-columns" (fun () ->
          List.iteri (fun depth prefix ->
            let column = Ui.box ui ~flags:Ui.(scroll + clip) ~w:(Ui.Px (float_of_int menu_width))
                ~h:Ui.Fit ~max_h:(float_of_int (menu_limit * row)) ~axis:Ui.Column
                (Printf.sprintf "column-%d" depth) in
            Ui.within ui column (fun () ->
              Array.iteri (fun index item ->
                let item_box = Ui.box ui ~flags:Ui.(clickable + tab_stop + blocking) ~w:Ui.Grow
                    ~h:(Ui.Px (float_of_int row)) (Printf.sprintf "item-%d" index) in
                let signal = Ui.signal ui item_box in
                let label, detail, opened = match item with
                  | Menu_category category ->
                      category, "›",
                      List.nth_opt menu.path (depth + List.length base) = Some category
                  | Menu_entry entry -> entry.label, Printf.sprintf "%d in" entry.arity, false in
                if signal.hovered then hovered := Some (prefix, item);
                if signal.clicked then clicked := Some (prefix, item);
                let theme = Ui.theme ui in
                Ui.draw ui item_box (fun paint (x, y, w, h) ->
                  if opened || signal.hovered then
                    Ui.Paint.fill paint ~x ~y:(y +. 1.) ~w ~h:(h -. 2.)
                      (if opened then theme.foreground else Pxui.Theme.hover_fill theme);
                  let color = if opened then theme.input else theme.foreground in
                  let text_y = y +. Float.max 4. ((h -. float_of_int (Ui.font_size ui)) /. 2.) in
                  Ui.Paint.text paint ~at:(x +. 8., text_y) ~color label;
                  Ui.Paint.text paint ~at:(x +. w -. 8. -. Ui.Paint.text_width paint detail, text_y)
                    ~color:(if opened then theme.input else Pxui.Theme.muted theme) detail))
                (rows_of prefix))) levels);
      query, pick, !hovered, !clicked) in
  let menu, requests = match result with
    | None -> None, []
    | Some (query, pick, hovered, clicked) ->
        let menu = { menu with query } in
        (match pick, clicked, hovered with
         | `Cancel, _, _ -> None, []
         | `Back, _, _ -> Some { menu with path = parent_path menu.path; query = "" }, []
         | `Pick index, _, _ ->
             (match (menu_rows value { menu with path = [] }).(index) with
              | Menu_category category -> Some { menu with path = [category]; query = "" }, []
              | Menu_entry entry -> None, [menu_request value menu entry])
         | _, Some (_, Menu_entry entry), _ -> None, [menu_request value menu entry]
         | _, Some (prefix, Menu_category category), _
         | _, None, Some (prefix, Menu_category category) ->
             Some { menu with path = prefix @ [category] }, []
         | _, None, Some (prefix, Menu_entry _)
           when List.length prefix < List.length menu.path ->
             Some { menu with path = prefix }, []
         | _ -> Some menu, []) in
  if menu = None then Ui.dismiss_popup ui;
  { value with menu }, requests

let context_items (value : t) = function
  | On_canvas -> ["Add node…", value.catalog <> [||]; "Layout", true; "Frame all", true]
  | On_tile id ->
      let flaggable = match Hashtbl.find_opt value.slots id with
        | Some index -> is_flaggable value value.boxes.(index) | None -> false in
      ["View", true; "Set active", flaggable; "Duplicate", true; "Delete", true;
       "Frame camera", true]
  | On_wire _ -> ["Insert node…", value.catalog <> [||]; "Delete", true]

(* Context-menu rows emit the same typed changes as the keyboard and pointer
   paths. *)
let apply_context (value : t) context index =
  let value = { value with context = None } in
  match context.target, index with
  | On_canvas, 0 -> open_menu value context.at, []
  | On_canvas, 1 -> optimize_layout value, [View_changed]
  | On_canvas, _ -> frame_all value, [View_changed]
  | On_tile id, 0 -> { value with viewed = id }, [Viewed id]
  | On_tile id, 1 -> { value with flagged = Some id }, [Flag_requested id]
  | On_tile id, 2 ->
      let value = select id value in
      duplicate_selection value
  | On_tile id, 4 -> value, [Frame_camera_requested id]
  | On_tile id, _ ->
      (if Id_set.mem id value.selected then clear_selection value else value),
      [Delete_nodes_requested [id]]
  | On_wire connection, 0 ->
      open_menu { value with selected_edge = Some connection;
        selected = Id_set.empty; primary = None } context.at, []
  | On_wire connection, _ ->
      { value with selected_edge = None }, [Disconnect_requested connection]

let update_canvas (value : t) ui (frame : Frame.t) =
  let value = if Frame.has_event (function Event.MousePressed _ -> true | _ -> false) frame
    then { value with hints = None } else value in
  if not value.visible then
    (* A hidden canvas (the host shows a list instead) still runs its menu. *)
    match value.menu with
    | Some menu -> let value, emitted = build_menu { value with drag = None; context = None }
          ui menu in value, List.rev emitted
    | None -> { value with drag = None; context = None }, []
  else
  let initial = value in
  let canvas = Ui.box ui ~flags:Ui.(clickable + scroll + clip + blocking)
      ~w:(Ui.Px (float_of_int value.width)) ~h:(Ui.Px (float_of_int value.height))
      ~at:(float_of_int value.x, float_of_int value.y) "pxui-graph" in
  let canvas_signal = Ui.signal ui canvas in
  (* Visible tiles become boxes keyed by node id; selected tiles on top. *)
  let visible_nodes, visible_edges, stats = visibility value in
  let is_selected index = Id_set.mem value.boxes.(index).info.Edit_graph.id value.selected in
  if Array.length value.spatial.order < stats.visible_nodes then
    value.spatial.order <- Array.make (Array.length visible_nodes) 0;
  let order = value.spatial.order in
  let next = ref 0 in
  for selected = 0 to 1 do
    for position = 0 to stats.visible_nodes - 1 do
      let index = Array.unsafe_get visible_nodes position in
      if is_selected index = (selected = 1) then begin
        Array.unsafe_set order !next index;
        incr next
      end
    done
  done;
  let local (x, y) = float_of_int (x - value.x), float_of_int (y - value.y) in
  let layer, tiles, overlay = Ui.within ui canvas (fun () ->
    let layer = Ui.box ui ~w:(Ui.Px (float_of_int value.width))
        ~h:(Ui.Px (float_of_int value.height)) ~at:(0., 0.) "wires" in
    let tiles = Array.init stats.visible_nodes (fun position ->
      let index = Array.unsafe_get order position in
      let box = value.boxes.(index) in
      let x, y, width, height = box_bounds value box in
      let tile = Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px (float_of_int width))
          ~h:(Ui.Px (float_of_int height)) ~at:(local (x, y))
          box.tile_id in
      let view, output = Ui.within ui tile (fun () ->
        let view = if box.level = Layout.Point then None else
          let bx, by, bw, bh = view_button_bounds value box in
          Some (Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px (float_of_int bw))
            ~h:(Ui.Px (float_of_int bh)) ~at:(float_of_int (bx - x), float_of_int (by - y))
            "view") in
        let output =
          let ox, oy = output_port value box in
          let radius = max 7 (screen_size value 8) in
          Some (Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px (float_of_int (2 * radius)))
            ~h:(Ui.Px (float_of_int (2 * radius)))
            ~at:(float_of_int (ox - x - radius), float_of_int (oy - y - radius))
            "output") in
        let active = if box.level = Layout.Point || not (is_flaggable value box) then None else
          let bx, by, bw, bh = active_button_bounds value box in
          Some (Ui.box ui ~flags:Ui.(clickable + tab_stop) ~w:(Ui.Px (float_of_int bw))
            ~h:(Ui.Px (float_of_int bh)) ~at:(float_of_int (bx - x), float_of_int (by - y))
            "active") in
        (view, active, build_row_fields value ui box), output) in
      (* One signal per tile per frame; every pass below reads it. *)
      index, tile, Ui.signal ui tile, view, output) in
    let overlay = Ui.box ui ~w:(Ui.Px (float_of_int value.width))
        ~h:(Ui.Px (float_of_int value.height)) ~at:(0., 0.) "overlay" in
    layer, tiles, overlay) in
  let bend_handles = Ui.within ui canvas (fun () ->
    match value.selected_edge with
    | None -> []
    | Some c ->
        let points = Option.value ~default:[]
          (Layout.Port_map.find_opt (Layout.slot c.consumer c.input_index) value.layout.bends) in
        List.mapi (fun index (gx, gy) ->
          let x = screen_x value gx and y = screen_y value gy in
          let handle = Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px 7.) ~h:(Ui.Px 7.)
            ~at:(local (x - 3, y - 3)) (Printf.sprintf "bend-%d-%d-%d"
              c.consumer c.input_index index) in
          handle, Ui.signal ui handle, c, index) points) in
  (* A right click (under the drag threshold) on a tile, wire, or blank canvas
     opens its context menu; a longer right drag only pans. *)
  let clicked_context =
    if value.menu <> None || value.context <> None then None else
    match Array.find_map (fun (index, _, signal, _, _) ->
        if Ui.context_clicked signal then
          Some { at = ints signal.release_point;
                 target = On_tile value.boxes.(index).info.Edit_graph.id }
        else None) tiles with
    | Some context -> Some context
    | None when Ui.context_clicked canvas_signal ->
        let at = ints canvas_signal.release_point in
        Some { at; target = match hit_edge value at with
          | Some edge -> On_wire value.edges.(edge).connection
          | None -> On_canvas }
    | None -> None in
  let value, changes = match value.menu, value.context with
    | Some menu, _ ->
        let value, emitted = build_menu value ui menu in
        value, List.rev emitted
    | None, Some context ->
        let x, y = context.at in
        (match Ui.context_menu ui ~at:(float_of_int x, float_of_int y)
            "pxui-graph-context" (context_items value context.target) with
         | `Open -> value, []
         | `Dismiss -> { value with context = None }, []
         | `Pick index -> let value, emitted = apply_context value context index in
             value, List.rev emitted)
    | None, None ->
    (* Right and middle drags pan from anywhere on the canvas. *)
    let panning = Array.exists (fun (_, _, (signal : Ui.signal), _, _) ->
      (signal.held || signal.released)
      && signal.button <> Some Input.LeftButton && signal.button <> None) tiles
      || ((canvas_signal.held || canvas_signal.released)
          && canvas_signal.button <> Some Input.LeftButton
          && canvas_signal.button <> None) in
    let value, changes = if not panning then value, [] else begin
        let dx, dy = if canvas_signal.held || canvas_signal.released
          then canvas_signal.drag
          else Array.fold_left (fun (dx, dy) (_, _, (signal : Ui.signal), _, _) ->
            let tx, ty = signal.drag in dx +. tx, dy +. ty) (0., 0.) tiles in
        pan value dx dy, (if dx <> 0. || dy <> 0. then [View_changed] else [])
      end in
    let scroll = snd canvas_signal.scroll in
    let value, changes = if scroll <> 0.
      then zoom_at value frame.mouse scroll, View_changed :: changes
      else value, changes in
    Array.fold_left (fun (value, changes) (index, tile, (tile_signal : Ui.signal), view, output) ->
      let id = value.boxes.(index).info.Edit_graph.id in
      let left signal = signal.Ui.button = Some Input.LeftButton in
      let view, active, (row_changes, detail, pin) = view in
      let changes = List.rev_append row_changes changes in
      let value, changes = if detail <> None || (pin &&
          not (Option.value ~default:false (Id_map.find_opt id value.layout.pinned))) then
          let layout = { value.layout with
            level = Option.fold ~none:value.layout.level
              ~some:(fun level -> Id_map.add id level value.layout.level) detail;
            pinned = Id_map.add id true value.layout.pinned } in
          reshape { value with layout }, Level_changed [id] :: changes
        else value, changes in
      let value, changes = match view with
        | Some view when (Ui.signal ui view).clicked ->
            { value with viewed = id }, Viewed id :: changes
        | Some _ | None -> value, changes in
      let value, changes = match active with
        | Some active when (Ui.signal ui active).clicked ->
            { value with flagged = Some id }, Flag_requested id :: changes
        | Some _ | None -> value, changes in
      let value, changes = match output with
        | Some output ->
            let signal = Ui.signal ui output in
            let value = if signal.pressed && left signal
              then { value with drag = Some (Connect_wire { source = id }) } else value in
            if signal.released && left signal then begin
              let value = { value with drag = None } in
              let changes = match hit_input value (ints signal.release_point) with
                | Some (consumer_index, input_index) ->
                    let consumer = value.boxes.(consumer_index).info.Edit_graph.id in
                    if consumer <> id then Connect_requested
                      { Edit_graph.source = id; consumer; input_index } :: changes
                    else changes
                | None -> changes in
              value, changes
            end else value, changes
        | None -> value, changes in
      let value, changes = if tile_signal.double_clicked && left tile_signal then
          if value.enterable value.boxes.(index).info then value, Open_requested id :: changes
          else
            let opening = value.boxes.(index).level = Layout.Chip
                || value.boxes.(index).level = Point in
            let requested = if opening then Layout.Card else Layout.Chip in
            let layout = { value.layout with
              level = Id_map.add id requested value.layout.level;
              pinned = Id_map.add id true value.layout.pinned } in
            reshape { value with layout }, Level_changed [id] :: changes
        else value, changes in
      if tile_signal.pressed && left tile_signal then begin
        let before = value.primary in
        let value = select_node value ~additive:(List.mem Input.Shift (Ui.press_keys ui tile)) index in
        let indices = indices_of_selection value in
        let changes = if before <> value.primary then
          Selected value.primary :: changes else changes in
        { value with drag = Some (Move_nodes { node = id; indices;
            edge_indices = affected_edges value.spatial indices;
            offset_x = 0.; offset_y = 0. }) }, changes
      end else value, changes)
      (value, changes) tiles
    |> fun (value, changes) ->
    (* Continue or finish the captured gesture. *)
    let value, changes = match value.drag with
      | Some (Move_nodes { node; indices; edge_indices; offset_x; offset_y }) ->
          (match Array.find_opt (fun (index, _, _, _, _) ->
              value.boxes.(index).info.Edit_graph.id = node) tiles with
           | None -> { value with drag = None }, changes
           | Some (_, _, signal, _, _) ->
               let dx, dy = signal.drag in
               let value, changes = if dx <> 0. || dy <> 0. then begin
                   let change = match indices with
                     | [|index|] -> Node_moved value.boxes.(index).info.Edit_graph.id
                     | _ -> Nodes_moved (Array.to_list (Array.map (fun index ->
                         value.boxes.(index).info.Edit_graph.id) indices)) in
                   move_nodes value node indices edge_indices (dx, dy) offset_x offset_y,
                   change :: changes
                 end else value, changes in
               if signal.released then
                 match value.drag with
                 | Some (Move_nodes moved) ->
                     commit_node_move value moved.indices
                       moved.offset_x moved.offset_y, changes
                 | _ -> value, changes
               else if signal.held then value, changes
               else { value with drag = None }, changes)
      | Some (Connect_wire _ | Box_select _ | Bend_wire _ | Pan_canvas | Knife) | None -> value, changes in
    let value, changes = List.fold_left (fun (value, changes) (handle, signal, c, index) ->
      if signal.Ui.button <> Some Input.LeftButton then value, changes else
      if (signal.pressed && List.mem Input.Alt (Ui.press_keys ui handle)) || signal.double_clicked then
        let points = Option.value ~default:[] (Layout.Port_map.find_opt
          (Layout.slot c.Edit_graph.consumer c.input_index) value.layout.bends) in
        let points = List.filteri (fun i _ -> i <> index) points in
        { (set_bends ~node:c.consumer ~slot:c.input_index points value) with drag = None },
        Bend_changed { node = c.consumer; slot = c.input_index } :: changes
      else if signal.pressed then
        { value with drag = Some (Bend_wire { node = c.consumer; slot = c.input_index;
            bend = index; on_canvas = false }) }, changes
      else value, changes) (value, changes) bend_handles in
    let value, changes = if canvas_signal.pressed && canvas_signal.button = Some Input.LeftButton then
      let modifiers = Ui.press_keys ui canvas in
      if List.mem Input.Ctrl modifiers || List.mem Input.Meta modifiers then
        { value with drag = Some Knife }, changes
      else match hit_edge value (ints canvas_signal.press_point) with
      | Some edge_index when List.mem Input.Alt modifiers ->
          let edge = value.edges.(edge_index) in
          let c = edge.connection in
          let px, py = canvas_signal.press_point in
          let gx = graph_x value (int_of_float px) and gy = graph_y value (int_of_float py) in
          let points = edge_points value edge in
          let segment = ref 0 and distance = ref Float.infinity in
          for i = 0 to Array.length points - 2 do
            let ax, ay = points.(i) and bx, by = points.(i + 1) in
            let d = segment_distance_squared gx gy ax ay bx by in
            if d < !distance then (segment := i; distance := d)
          done;
          let bends = Option.value ~default:[] (Layout.Port_map.find_opt
            (Layout.slot c.consumer c.input_index) value.layout.bends) in
          let bend = max 0 (min (List.length bends) (!segment - 1)) in
          let rec insert i = function
            | rest when i = 0 -> (gx, gy) :: rest
            | point :: rest -> point :: insert (i - 1) rest
            | [] -> [gx, gy] in
          let value = set_bends ~node:c.consumer ~slot:c.input_index (insert bend bends) value in
          { value with selected_edge = Some c;
              drag = Some (Bend_wire { node = c.consumer; slot = c.input_index;
                bend; on_canvas = true }) },
          Bend_changed { node = c.consumer; slot = c.input_index } :: changes
      | None when List.mem Input.Alt modifiers ->
          { value with drag = Some Pan_canvas }, changes
      | Some edge_index ->
          let connection = value.edges.(edge_index).connection in
          { value with selected_edge = Some connection; selected = Id_set.empty;
            primary = None; drag = None },
          Selected None :: Connection_selected (Some connection) :: changes
      | None ->
          let value = { value with selected_edge = None;
            drag = Some (Box_select { additive = List.mem Input.Shift (Ui.press_keys ui canvas) }) } in
          if canvas_signal.released then begin
            let before = value.primary in
            let (x0, y0), (x1, y1) = ints canvas_signal.press_point,
              ints canvas_signal.release_point in
            let value = apply_marquee value { start_x = x0; start_y = y0;
              current_x = x1; current_y = y1;
              additive = List.mem Input.Shift (Ui.press_keys ui canvas) } in
            value, (if before <> value.primary then
              Selected value.primary :: changes else changes)
          end else value, changes
    else match value.drag with
      | Some (Box_select { additive }) when canvas_signal.released ->
          let before = value.primary in
          let (x0, y0), (x1, y1) = ints canvas_signal.press_point,
            ints canvas_signal.release_point in
          let value = apply_marquee value { start_x = x0; start_y = y0;
            current_x = x1; current_y = y1; additive } in
          value, (if before <> value.primary then
            Selected value.primary :: changes else changes)
      | Some (Box_select _) when not canvas_signal.held ->
          { value with drag = None }, changes
      (* A cancelled or culled wire drag has no held output left. *)
      | Some (Connect_wire { source }) when not (Array.exists
          (fun (index, _, _, _, output) ->
            value.boxes.(index).info.Edit_graph.id = source
            && Option.fold ~none:false ~some:(Ui.active ui) output) tiles) ->
          { value with drag = None }, changes
      | _ -> value, changes in
    match value.drag with
    | Some Pan_canvas ->
        let dx, dy = canvas_signal.drag in
        let value = pan value dx dy in
        { value with drag = if canvas_signal.held then value.drag else None },
        (if dx <> 0. || dy <> 0. then View_changed :: changes else changes)
    | Some Knife when canvas_signal.released ->
        let crossed = crossed_wires value (ints canvas_signal.press_point)
          (ints canvas_signal.release_point) in
        { value with drag = None },
        (if crossed = [] then changes else Cut_wires_requested crossed :: changes)
    | Some Knife when not canvas_signal.held -> { value with drag = None }, changes
    | Some (Bend_wire { node; slot; bend; on_canvas }) ->
        let signal = if on_canvas then Some canvas_signal else
          List.find_map (fun (_, signal, c, index) ->
            if c.Edit_graph.consumer = node && c.input_index = slot && index = bend
            then Some signal else None) bend_handles in
        (match signal with
         | Some signal when signal.Ui.held || signal.released ->
             let px, py = if signal.released then signal.release_point else signal.pointer in
             let point = Layout.snap (graph_x value (int_of_float px)),
               Layout.snap (graph_y value (int_of_float py)) in
             let points = Option.value ~default:[]
               (Layout.Port_map.find_opt (Layout.slot node slot) value.layout.bends) in
             let changed = List.mapi (fun i p -> if i = bend then point else p) points in
             let value, changes = if changed = points then value, changes else
               set_bends ~node ~slot changed value, Bend_changed { node; slot } :: changes in
             { value with drag = if signal.held then value.drag else None }, changes
         | _ -> { value with drag = None }, changes)
    | _ -> value, changes in
  let value = match clicked_context with
    | Some context -> { value with context = Some context; drag = None }
    | None -> value in
  let bloom = match value.drag with
    | Some (Connect_wire { source }) -> Array.find_map (fun (index, _, signal, _, _) ->
        let box = value.boxes.(index) in
        if signal.Ui.hovered && box.info.id <> source && Array.length box.info.inputs > 0
        then Some box.info.id else None) tiles
    | _ -> None in
  let value = if bloom = value.bloom then value else reshape { value with bloom } in
  Ui.draw ui canvas (fun paint _ ->
    framed paint value.x value.y value.width value.height ~fill:(canvas_fill value)
      ~stroke:value.theme.foreground);
  Ui.draw ui layer (fun paint _ ->
    let edges, count =
      if value.spatial == initial.spatial && value.positions == initial.positions
          && value.drag == initial.drag && value.pan_x = initial.pan_x
          && value.pan_y = initial.pan_y && value.zoom = initial.zoom
          && value.x = initial.x && value.y = initial.y
          && value.width = initial.width && value.height = initial.height
      then visible_edges, stats.visible_wires
      else let _, edges, stats = visibility value in
        edges, stats.visible_wires in
    paint_background value paint edges count);
  Array.iter (fun (index, tile, _, _, _) ->
    let id = initial.boxes.(index).info.Edit_graph.id in
    Ui.draw ui tile (fun paint _ ->
      match Hashtbl.find_opt value.slots id with
      | Some index -> paint_node value paint value.boxes.(index)
      | None -> ())) tiles;
  List.iter (fun (handle, _, c, index) ->
    Ui.draw ui handle (fun paint (x, y, w, h) ->
      let points = Option.value ~default:[]
        (Layout.Port_map.find_opt (Layout.slot c.Edit_graph.consumer c.input_index) value.layout.bends) in
      if index < List.length points then
        Ui.Paint.rect paint ~x ~y ~w ~h ~fill:value.theme.accent ())) bend_handles;
  Ui.draw ui overlay (fun paint _ ->
    match value.drag with
    | Some (Box_select _) ->
        let (x0, y0), (x1, y1) = ints canvas_signal.press_point, ints canvas_signal.pointer in
        let x, y, width, height = normalize_rect x0 y0 x1 y1 in
        framed paint x y width height ~fill:(Color.with_alpha value.theme.accent 28)
          ~stroke:value.theme.accent
    | Some (Connect_wire { source }) ->
        (match Hashtbl.find_opt value.slots source with
         | None -> ()
         | Some index ->
             let box = value.boxes.(index) in
             let sx, sy = box_graph_position value box in
             let px, py = canvas_signal.pointer in
             let points = [|sx +. float box.width, sy +. 12.;
               graph_x value (int_of_float px), graph_y value (int_of_float py)|] in
             paint_wire value paint points ~width:2.4 value.theme.accent)
    | Some Knife -> Ui.Paint.line paint ~from_:canvas_signal.press_point
        ~to_:canvas_signal.pointer ~width:1.5 value.theme.accent
    | Some (Move_nodes _ | Bend_wire _ | Pan_canvas) | None -> ());
  Option.iter (fun hints -> Ui.draw ui overlay (fun paint _ ->
    List.iter (fun (label, target) ->
      if String.starts_with ~prefix:hints.prefix label then
        let id = match target with Hint_node id -> id | Hint_port c -> c.consumer in
        match Hashtbl.find_opt value.slots id with
        | None -> ()
        | Some index ->
            let box = value.boxes.(index) in
            let x, y = match target with
              | Hint_port c -> input_port value box c.input_index
              | Hint_node _ -> let x, y, _, _ = box_bounds value box in x + 24, y + 12 in
            let width = Ui.Paint.text_width paint ~size:11 label +. 8. in
            Ui.Paint.rect paint ~x:(float x -. 4.) ~y:(float y -. 8.)
              ~w:width ~h:18. ~radius:2. ~fill:value.theme.foreground ();
            Ui.Paint.text paint ~at:(float x, float y -. 6.) ~size:11
              ~color:(Color.hex_exn "#f5cf4f") label) hints.targets)) value.hints;
  value, List.rev changes

let find_matches value query = Array.to_list value.boxes |> List.filter (fun box ->
  Ui.fuzzy_match ~query box.info.label
  || Ui.fuzzy_match ~query (value.namespace ^ "/" ^ Option.value ~default:box.info.operation
    (Edit_graph.node_factory_key value.document ~node_id:box.info.id)))
  |> List.sort (fun a b -> let order = String.compare a.info.label b.info.label in
    if order = 0 then Int.compare a.info.id b.info.id else order)
  |> Array.of_list

let update value ui frame =
  let value, changes = update_canvas value ui frame in
  match value.find with
  | None -> value, changes
  | Some query ->
      let result = Ui.modal ui ~width:420. "pxui-graph-find" (fun () ->
        Ui.label ui "Find in this level";
        Ui.picker ui "Label or kind" ~query (fun query ->
          find_matches value query |> Array.map (fun box -> box.info.label,
            value.namespace ^ "/" ^ Option.value ~default:box.info.operation
              (Edit_graph.node_factory_key value.document ~node_id:box.info.id)))) in
      let value, changes = match result with
        | None | Some (_, `Cancel) -> { value with find = None }, changes
        | Some (query, `Pick index) ->
            let box = (find_matches value query).(index) in
            let value = { value with find = None } |> select box.info.id in
            frame_selection value, Selected (Some box.info.id) :: changes
        | Some (query, _) -> { value with find = Some query }, changes in
      if value.find = None then Ui.dismiss_popup ui;
      value, changes

let trunk document =
  let infos = Edit_graph.inspect document in
  let consumed = Hashtbl.create 64 and inputs = Hashtbl.create 64 in
  List.iter (fun (info : Edit_graph.node_info) ->
    Hashtbl.replace inputs info.id info.inputs;
    Array.iter (Option.iter (fun id -> Hashtbl.replace consumed id ())) info.inputs)
    infos;
  let emitted = Hashtbl.create 64 and rows = ref [] in
  let first id = match Hashtbl.find_opt inputs id with
    | Some slots when Array.length slots > 0 -> slots.(0) | _ -> None in
  let rec emit_trunk id depth =
    (* The chain up the first inputs, stopping at a node already listed. *)
    let rec chain id acc =
      if Hashtbl.mem emitted id then Some id, acc
      else match first id with
        | Some source when Hashtbl.mem inputs source -> chain source (id :: acc)
        | _ -> None, id :: acc in
    let shared, nodes = chain id [] in
    Option.iter (fun id -> rows := (id, depth, true) :: !rows) shared;
    List.iter (fun id ->
      Hashtbl.replace emitted id ();
      rows := (id, depth, false) :: !rows;
      Array.iteri (fun index slot -> match slot with
        | Some side when index > 0 && Hashtbl.mem inputs side ->
            if Hashtbl.mem emitted side then rows := (side, depth + 1, true) :: !rows
            else emit_trunk side (depth + 1)
        | _ -> ()) (Option.value ~default:[||] (Hashtbl.find_opt inputs id))) nodes in
  List.iter (fun (info : Edit_graph.node_info) ->
    if not (Hashtbl.mem consumed info.id) then emit_trunk info.id 0) infos;
  Array.of_list (List.rev !rows)

module Private = struct
  let menu_keys value ~query = match value.menu with
    | None -> [||]
    | Some menu -> menu_rows value { menu with query } |> Array.to_list
        |> List.filter_map (function Menu_entry entry -> Some entry.key | Menu_category _ -> None)
        |> Array.of_list
  let hint_labels value = match value.hints with
    | None -> []
    | Some hints -> List.map (fun (label, target) -> match target with
        | Hint_port c -> label, c.consumer, Some c.input_index
        | Hint_node id -> label, id, None) hints.targets
  let zoom value = value.zoom
  let level value node = Option.map (fun index -> value.boxes.(index).level)
    (Hashtbl.find_opt value.slots node)
  let field_bounds value ~node ~path =
    Option.bind (Hashtbl.find_opt value.slots node) (fun index ->
      let box = value.boxes.(index) in
      Option.map (fun row ->
        let gx, gy = box_graph_position value box in
        screen_x value (gx +. 112.), screen_y value (gy +. 28. +. (24. *. float row)),
        screen_size value 76, screen_size value 16)
        (Array.find_index (function Field (f, _) -> f.Parameter.name = path | _ -> false) box.rows))
  let crossed_wires = crossed_wires
  let hit_edge_id value point = Option.map (fun index ->
      value.edges.(index).connection) (hit_edge value point)
  let edge_query_points value ~limit =
    Array.init (min limit (Array.length value.edges)) (fun index ->
      let points = edge_points value value.edges.(index) in
      let ax, ay = points.(1) and bx, by = points.(2) in
      screen_x value ((ax +. bx) /. 2.), screen_y value ((ay +. by) /. 2.))
  let hit_edge_candidates value point =
    let generation = next_spatial_generation value.spatial in
    let count = ref 0 in
    iter_spatial_edge_candidates value point (fun index ->
      if Array.unsafe_get value.spatial.edge_marks index <> generation then begin
        Array.unsafe_set value.spatial.edge_marks index generation;
        incr count
      end);
    !count
end
