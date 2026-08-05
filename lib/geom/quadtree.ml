open Prismel

type 'a entry = { point : Vec2.t; value : 'a }
type 'a node = Leaf of 'a entry list | Branch of 'a node array
type 'a t = { bounds : Bounds2.t; capacity : int; max_depth : int; size : int; root : 'a node }
type 'a mutable_entry = { entry : 'a entry; nx : float; ny : float }
type 'a mutable_node = Mutable_leaf of 'a mutable_entry list | Mutable_branch of 'a mutable_node array

let create ?(capacity = 8) ?(max_depth = 20) bounds =
  if capacity <= 0 then invalid_arg "Quadtree.create: capacity must be positive";
  if max_depth < 0 then invalid_arg "Quadtree.create: max_depth must be non-negative";
  { bounds; capacity; max_depth; size = 0; root = Leaf [] }

let bounds tree = tree.bounds
let size tree = tree.size
let is_empty tree = tree.size = 0

let child_index bounds (point : Vec2.t) =
  let center_x = (bounds.Bounds2.min.x +. bounds.max.x) *. 0.5
  and center_y = (bounds.min.y +. bounds.max.y) *. 0.5 in
  (if point.x >= center_x then 1 else 0)
  + (if point.y >= center_y then 2 else 0)

let child_bounds bounds index =
  let minimum = bounds.Bounds2.min and maximum = bounds.max in
  let center_x = (minimum.x +. maximum.x) *. 0.5
  and center_y = (minimum.y +. maximum.y) *. 0.5 in
  let x0, x1 = if index land 1 = 0 then minimum.x, center_x else center_x, maximum.x in
  let y0, y1 = if index land 2 = 0 then minimum.y, center_y else center_y, maximum.y in
  Bounds2.make ~min:(Vec2.create x0 y0) ~max:(Vec2.create x1 y1)

let terminal bounds depth max_depth =
  depth >= max_depth || (Bounds2.width bounds <= 1e-12 && Bounds2.height bounds <= 1e-12)

let rec insert_node capacity max_depth depth bounds entry = function
  | Leaf values when List.length values < capacity || terminal bounds depth max_depth ->
      Leaf (entry :: values)
  | Leaf values ->
      let children = Array.make 4 (Leaf []) in
      let branch = Branch children in
      List.fold_left (fun node value -> insert_node capacity max_depth depth bounds value node) branch (entry :: values)
  | Branch children ->
      let index = child_index bounds entry.point in
      let copy = Array.copy children in
      let child_bounds = child_bounds bounds index in
      copy.(index) <- insert_node capacity max_depth (depth + 1) child_bounds entry copy.(index);
      Branch copy

let insert point value tree =
  if not (Bounds2.contains tree.bounds point) then
    Error "Quadtree.insert: point is outside tree bounds"
  else
    Ok { tree with size = tree.size + 1;
         root = insert_node tree.capacity tree.max_depth 0 tree.bounds { point; value } tree.root }

let insert_exn point value tree =
  match insert point value tree with Ok tree -> tree | Error message -> invalid_arg message

let path_bit coordinate depth =
  coordinate >= 1.
  || mod_float (Float.ldexp coordinate (depth + 1)) 2. >= 1.

let rec insert_mutable capacity max_depth depth entry = function
  | Mutable_leaf values
    when List.length values < capacity || depth >= max_depth ->
      Mutable_leaf (entry :: values)
  | Mutable_leaf values ->
      let branch = Mutable_branch (Array.make 4 (Mutable_leaf [])) in
      List.fold_left
        (fun node value ->
          insert_mutable capacity max_depth depth value node)
        branch (entry :: values)
  | Mutable_branch children as branch ->
      let index =
        (if path_bit entry.nx depth then 1 else 0)
        + (if path_bit entry.ny depth then 2 else 0) in
      children.(index) <- insert_mutable capacity max_depth (depth + 1)
          entry children.(index);
      branch

let rec freeze = function
  | Mutable_leaf values -> Leaf (List.map (fun value -> value.entry) values)
  | Mutable_branch children -> Branch (Array.map freeze children)

let of_list ?capacity ?max_depth bounds values =
  let empty = create ?capacity ?max_depth bounds in
  match List.find_opt (fun (point, _) -> not (Bounds2.contains bounds point)) values with
  | Some _ -> Error "Quadtree.insert: point is outside tree bounds"
  | None ->
      let width = Bounds2.width bounds and height = Bounds2.height bounds in
      let rec effective_depth depth width height =
        if depth >= empty.max_depth
           || (width <= 1e-12 && height <= 1e-12)
        then depth
        else effective_depth (depth + 1) (width *. 0.5) (height *. 0.5) in
      let max_depth = effective_depth 0 width height in
      let root = ref (Mutable_leaf []) in
      List.iter (fun (point, value) ->
        let nx = if width <= 0. then 0.
          else (point.Vec2.x -. bounds.min.x) /. width
        and ny = if height <= 0. then 0.
          else (point.y -. bounds.min.y) /. height in
        root := insert_mutable empty.capacity max_depth 0
            { entry = { point; value }; nx; ny } !root) values;
      Ok { empty with size = List.length values; root = freeze !root }

let rec fold_node operation accumulator = function
  | Leaf values -> List.fold_left operation accumulator values
  | Branch children -> Array.fold_left (fold_node operation) accumulator children

let fold operation accumulator tree = fold_node operation accumulator tree.root
let entries tree = fold (fun result entry -> entry :: result) [] tree |> List.rev

let rec query_bounds_node query node_bounds node result =
  if not (Bounds2.intersects query node_bounds) then result
  else match node with
    | Leaf values -> List.fold_left (fun result entry -> if Bounds2.contains query entry.point then entry :: result else result) result values
    | Branch children ->
        let result = ref result in
        for index = 0 to 3 do
          result := query_bounds_node query (child_bounds node_bounds index)
              children.(index) !result
        done;
        !result

let query_bounds query tree = query_bounds_node query tree.bounds tree.root [] |> List.rev

let query_circle ~center ~radius tree =
  if not (Float.is_finite radius) || radius < 0. then invalid_arg "Quadtree.query_circle: radius must be finite and non-negative";
  let radius_sq = radius *. radius in
  let rec visit node_bounds node result =
    if Bounds2.distance_sq node_bounds center > radius_sq then result
    else match node with
      | Leaf values -> List.fold_left (fun result entry ->
          let dx = entry.point.x -. center.x
          and dy = entry.point.y -. center.y in
          if (dx *. dx) +. (dy *. dy) <= radius_sq
          then entry :: result else result) result values
      | Branch children ->
          let result = ref result in
          for index = 0 to 3 do
            result := visit (child_bounds node_bounds index) children.(index) !result
          done;
          !result in
  List.rev (visit tree.bounds tree.root [])

let nearest ?(max_distance = infinity) point tree =
  if max_distance < 0. || Float.is_nan max_distance then invalid_arg "Quadtree.nearest: max_distance must be non-negative";
  let best = ref None and best_sq = ref (max_distance *. max_distance) in
  let rec visit node_bounds = function
    | _ when Bounds2.distance_sq node_bounds point > !best_sq -> ()
    | Leaf values ->
        List.iter (fun entry ->
          let dx = entry.point.x -. point.x
          and dy = entry.point.y -. point.y in
          let distance = (dx *. dx) +. (dy *. dy) in
          if distance <= !best_sq then begin best := Some entry; best_sq := distance end) values
    | Branch children ->
        let first = child_index node_bounds point in
        visit (child_bounds node_bounds first) children.(first);
        for offset = 1 to 3 do
          let index = (first + offset) land 3 in
          visit (child_bounds node_bounds index) children.(index)
        done
  in
  visit tree.bounds tree.root;
  !best

let rec node_size = function Leaf values -> List.length values | Branch children -> Array.fold_left (fun total node -> total + node_size node) 0 children

let rec filter_node capacity predicate = function
  | Leaf values -> Leaf (List.filter predicate values)
  | Branch children ->
      let children = Array.map (filter_node capacity predicate) children in
      let count = Array.fold_left (fun total node -> total + node_size node) 0 children in
      if count <= capacity then
        Leaf (Array.fold_left (fun result node -> fold_node (fun result entry -> entry :: result) result node) [] children)
      else Branch children

let filter predicate tree =
  let root = filter_node tree.capacity predicate tree.root in
  { tree with root; size = node_size root }

let remove_if predicate = filter (fun entry -> not (predicate entry))

let map operation tree =
  let rec map_node = function
    | Leaf values -> Leaf (List.map (fun entry -> { point = entry.point; value = operation entry.value }) values)
    | Branch children -> Branch (Array.map map_node children)
  in
  { bounds = tree.bounds; capacity = tree.capacity; max_depth = tree.max_depth; size = tree.size; root = map_node tree.root }
