open Prismel

type cell = int * int * int

type node =
  | Leaf of int64
  | Branch of int * node array

type t = {
  origin : Vec3.t;
  size : float;
  precision : float;
  max_depth : int;
  stride : int;
  root : node;
}

let compute_max_depth size precision =
  let rec loop cell depth =
    if cell <= precision then max 0 (depth - 1)
    else if depth >= 20 then 19
    else loop (cell /. 2.) (depth + 1)
  in
  loop size 0

let empty_branch = Branch (0, [||])

let popcount value =
  let rec count value total =
    if value = 0 then total
    else count (value land (value - 1)) (total + 1)
  in
  count value 0

let child_position bitmap index =
  popcount (bitmap land ((1 lsl index) - 1))

let child bitmap children index =
  let bit = 1 lsl index in
  if bitmap land bit = 0 then None
  else Some children.(child_position bitmap index)

let insert_at index value source =
  let output = Array.make (Array.length source + 1) value in
  Array.blit source 0 output 0 index;
  Array.blit source index output (index + 1) (Array.length source - index);
  output

let remove_at index source =
  let length = Array.length source - 1 in
  if length = 0 then [||]
  else
    let fill = if index = 0 then source.(1) else source.(0) in
    let output = Array.make length fill in
    Array.blit source 0 output 0 index;
    Array.blit source (index + 1) output index (length - index);
    output

let create ~origin ~size ~precision =
  if not (Float.is_finite size) || size <= 0. ||
     not (Float.is_finite precision) || precision <= 0. then
    invalid_arg "Svo3.create: size and precision must be finite and positive";
  let max_depth = compute_max_depth size precision in
  let stride = 1 lsl (max_depth + 1) in
  { origin; size; precision = size /. float_of_int stride;
    max_depth; stride; root = empty_branch }

let origin tree = tree.origin
let size tree = tree.size
let precision tree = tree.precision
let max_depth tree = tree.max_depth
let clamp_depth tree depth = max 0 (min tree.max_depth depth)
let dimensions_at_depth tree depth = 1 lsl (clamp_depth tree depth + 1)
let size_at_depth tree depth =
  tree.size /. float_of_int (dimensions_at_depth tree depth)

let cell_at point tree =
  let x = point.Vec3.x -. tree.origin.x
  and y = point.y -. tree.origin.y
  and z = point.z -. tree.origin.z in
  if x < 0. || y < 0. || z < 0. ||
     x > tree.size || y > tree.size || z > tree.size then None
  else
    let coordinate value = min (tree.stride - 1)
        (int_of_float (floor (value /. tree.precision))) in
    Some (coordinate x, coordinate y, coordinate z)

let child_index tree depth (x, y, z) =
  let shift = tree.max_depth - depth in
  (((x lsr shift) land 1) lsl 2)
  lor (((y lsr shift) land 1) lsl 1)
  lor ((z lsr shift) land 1)

let code_of_cell tree cell =
  let code = ref 0L in
  for depth = 0 to tree.max_depth do
    code := Int64.logor (Int64.shift_left !code 3)
        (Int64.of_int (child_index tree depth cell))
  done;
  !code

let child_index_of_code tree depth code =
  let shift = (tree.max_depth - depth) * 3 in
  Int64.to_int (Int64.logand (Int64.shift_right_logical code shift) 7L)

let contains_cell cell tree =
  let rec descend depth = function
    | Leaf code -> code = code_of_cell tree cell
    | Branch (bitmap, children) ->
        if depth > tree.max_depth then false
        else
          match child bitmap children (child_index tree depth cell) with
          | None -> false
          | Some child -> descend (depth + 1) child
  in
  descend 0 tree.root

let set_at point tree =
  match cell_at point tree with
  | None -> Error "Svo3.set_at: point is outside the tree bounds"
  | Some cell when contains_cell cell tree -> Ok tree
  | Some cell ->
      let cell_code = code_of_cell tree cell in
      let rec insert depth existing =
        if depth > tree.max_depth then Leaf cell_code
        else
          match existing with
          | Some (Leaf existing_code) ->
              let existing_index =
                child_index_of_code tree depth existing_code
              and index = child_index tree depth cell in
              if existing_index = index then
                Branch (1 lsl index,
                  [|insert (depth + 1) (Some (Leaf existing_code))|])
              else
                let bitmap = (1 lsl existing_index) lor (1 lsl index) in
                let children =
                  if existing_index < index then
                    [|Leaf existing_code; Leaf cell_code|]
                  else [|Leaf cell_code; Leaf existing_code|]
                in
                Branch (bitmap, children)
          | Some (Branch (bitmap, children)) ->
              let index = child_index tree depth cell in
              let bit = 1 lsl index in
              let position = child_position bitmap index in
              if bitmap land bit = 0 then
                Branch (bitmap lor bit,
                  insert_at position (Leaf cell_code) children)
              else
                let output = Array.copy children in
                output.(position) <-
                  insert (depth + 1) (Some output.(position));
                Branch (bitmap, output)
          | None -> Leaf cell_code
      in
      Ok { tree with root = insert 0 (Some tree.root) }

let delete_at point tree =
  match cell_at point tree with
  | None -> tree
  | Some cell when not (contains_cell cell tree) -> tree
  | Some cell ->
      let rec remove depth = function
        | Leaf _ -> None
        | Branch (bitmap, children) ->
            let index = child_index tree depth cell in
            let bit = 1 lsl index in
            let position = child_position bitmap index in
            (match remove (depth + 1) children.(position) with
             | Some updated ->
                 let children = Array.copy children in
                 children.(position) <- updated;
                 Some (Branch (bitmap, children))
             | None ->
                 let bitmap = bitmap land lnot bit in
                 if bitmap = 0 then None
                 else Some (Branch (bitmap, remove_at position children)))
      in
      let root =
        match remove 0 tree.root with
        | Some root -> root
        | None -> empty_branch
      in
      { tree with root }

let contains point tree =
  match cell_at point tree with
  | None -> false
  | Some cell -> contains_cell cell tree

let depth_at ?max_depth point tree =
  match cell_at point tree with
  | None -> None
  | Some cell ->
      let maximum =
        clamp_depth tree (Option.value max_depth ~default:tree.max_depth) in
      let rec descend depth deepest = function
        | Leaf _ -> Some maximum
        | Branch (bitmap, children) ->
            if depth > maximum then deepest
            else
              match child bitmap children (child_index tree depth cell) with
              | None -> deepest
              | Some child -> descend (depth + 1) (Some depth) child
      in
      descend 0 None tree.root

let select_cells ~depth tree =
  let target = clamp_depth tree depth in
  let rec visit depth x y z result = function
    | Leaf code ->
        let x = ref x and y = ref y and z = ref z in
        for level = depth to target do
          let index = child_index_of_code tree level code in
          x := (!x lsl 1) lor ((index lsr 2) land 1);
          y := (!y lsl 1) lor ((index lsr 1) land 1);
          z := (!z lsl 1) lor (index land 1)
        done;
        (!x, !y, !z) :: result
    | Branch (bitmap, children) ->
        let result = ref result in
        let position = ref 0 in
        for index = 0 to 7 do
          if bitmap land (1 lsl index) <> 0 then begin
                let child = children.(!position) in
                incr position;
                let child_x = (x lsl 1) lor ((index lsr 2) land 1)
                and child_y = (y lsl 1) lor ((index lsr 1) land 1)
                and child_z = (z lsl 1) lor (index land 1) in
                if depth = target then
                  result := (child_x, child_y, child_z) :: !result
                else
                  result := visit (depth + 1) child_x child_y child_z
                      !result child
          end
        done;
        !result
  in
  visit 0 0 0 0 [] tree.root |> List.sort compare

let select ~depth tree =
  let cell_size = size_at_depth tree depth in
  select_cells ~depth tree |> List.map (fun (x, y, z) ->
    Vec3.create
      (tree.origin.x +. ((float_of_int x +. 0.5) *. cell_size))
      (tree.origin.y +. ((float_of_int y +. 0.5) *. cell_size))
      (tree.origin.z +. ((float_of_int z +. 0.5) *. cell_size)))

let fold_points operation accumulator tree =
  let half = tree.precision /. 2. in
  select_cells ~depth:tree.max_depth tree
  |> List.fold_left (fun accumulator (x, y, z) ->
    operation accumulator (Vec3.create
      (tree.origin.x +. (float_of_int x *. tree.precision) +. half)
      (tree.origin.y +. (float_of_int y *. tree.precision) +. half)
      (tree.origin.z +. (float_of_int z *. tree.precision) +. half)))
      accumulator

let of_points ~origin ~size ~precision points =
  let tree = create ~origin ~size ~precision in
  let count = List.length points in
  let codes = Array.make count 0L in
  let code_at point =
    let x = point.Vec3.x -. tree.origin.x
    and y = point.y -. tree.origin.y
    and z = point.z -. tree.origin.z in
    if x < 0. || y < 0. || z < 0.
       || x > tree.size || y > tree.size || z > tree.size
    then None
    else
      let coordinate value =
        min (tree.stride - 1)
          (int_of_float (floor (value /. tree.precision)))
      in
      let x = coordinate x and y = coordinate y and z = coordinate z in
      let code = ref 0L in
      for depth = 0 to tree.max_depth do
        let shift = tree.max_depth - depth in
        let child =
          (((x lsr shift) land 1) lsl 2)
          lor (((y lsr shift) land 1) lsl 1)
          lor ((z lsr shift) land 1)
        in
        code := Int64.logor (Int64.shift_left !code 3) (Int64.of_int child)
      done;
      Some !code
  in
  let rec encode index = function
    | [] -> Ok ()
    | point :: rest ->
        (match code_at point with
         | None -> Error "Svo3.set_at: point is outside the tree bounds"
         | Some code ->
             codes.(index) <- code;
             encode (index + 1) rest)
  in
  match encode 0 points with
  | Error _ as error -> error
  | Ok () ->
      Array.sort Int64.compare codes;
      let unique_count =
        if count = 0 then 0
        else begin
          let output = ref 1 in
          for index = 1 to count - 1 do
            if codes.(index) <> codes.(!output - 1) then begin
              codes.(!output) <- codes.(index);
              incr output
            end
          done;
          !output
        end
      in
      let child_at = child_index_of_code tree in
      let rec freeze depth first last =
        if last - first = 1 then Leaf codes.(first)
        else if depth > tree.max_depth then Leaf codes.(first)
        else begin
          let starts = Array.make 8 (-1) and stops = Array.make 8 (-1) in
          let bitmap = ref 0 and child_count = ref 0 in
          let index = ref first in
          while !index < last do
            let child = child_at depth codes.(!index) in
            let start = !index in
            incr index;
            while !index < last && child_at depth codes.(!index) = child do
              incr index
            done;
            starts.(child) <- start;
            stops.(child) <- !index;
            bitmap := !bitmap lor (1 lsl child);
            incr child_count
          done;
          let child = ref 0 in
          let children = Array.init !child_count (fun _ ->
            while starts.(!child) < 0 do incr child done;
            let result = freeze (depth + 1) starts.(!child) stops.(!child) in
            incr child;
            result)
          in
          Branch (!bitmap, children)
        end
      in
      let root =
        if unique_count = 0 then empty_branch
        else freeze 0 0 unique_count
      in
      Ok { tree with root }

let to_voxel3 ~depth tree =
  let depth = clamp_depth tree depth in
  let dimensions = dimensions_at_depth tree depth in
  match
    Voxel3.of_cells ~origin:tree.origin
      ~dimensions:(dimensions, dimensions, dimensions)
      ~voxel_size:(size_at_depth tree depth)
      (select_cells ~depth tree)
  with
  | Ok voxels -> voxels
  | Error message -> failwith message
