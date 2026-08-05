open Prismel

type edge = { a : int; b : int }
type report = {
  faces : int;
  components : int;
  boundary_edges : edge list;
  non_manifold_edges : edge list;
  degenerate_faces : int list;
  duplicate_faces : int list;
}

module Edge_key = struct
  type t = int * int
  let equal = ( = )
  let hash = Hashtbl.hash
end

module Edge_table = Hashtbl.Make (Edge_key)

let edge_key a b = if a < b then a, b else b, a

let edge_faces faces =
  let table = Edge_table.create (Array.length faces * 3) in
  let add face a b =
    let key = edge_key a b in
    Edge_table.replace table key
      (face :: Option.value ~default:[] (Edge_table.find_opt table key))
  in
  Array.iteri (fun face (a, b, c) -> add face a b; add face b c; add face c a) faces;
  table

let canonical_face (a, b, c) =
  if a <= b then
    if b <= c then a, b, c
    else if a <= c then a, c, b
    else c, a, b
  else if a <= c then b, a, c
  else if b <= c then b, c, a
  else c, b, a

let face_degenerate epsilon vertices (a, b, c) =
  a = b || b = c || c = a
  || Vec3.length_sq
       (Vec3.cross
          (Vec3.sub vertices.(b) vertices.(a))
          (Vec3.sub vertices.(c) vertices.(a)))
     <= epsilon *. epsilon

let component_count face_count edges =
  let parent = Array.init face_count Fun.id in
  let rec root face =
    let next = parent.(face) in
    if next = face then face
    else begin
      let result = root next in
      parent.(face) <- result;
      result
    end
  in
  let join left right =
    let left = root left and right = root right in
    if left <> right then parent.(max left right) <- min left right
  in
  Edge_table.iter
    (fun _ -> function
      | [] -> ()
      | first :: rest -> List.iter (join first) rest)
    edges;
  let count = ref 0 in
  for face = 0 to face_count - 1 do
    if root face = face then incr count
  done;
  !count

let analyze ?(epsilon = 1e-12) mesh =
  if not (Float.is_finite epsilon) || epsilon < 0. then invalid_arg "Mesh_repair.analyze: epsilon must be finite and non-negative";
  let vertices = (Mesh.Private.view mesh).vertices
  and faces = Mesh.Private.triangle_indices mesh in
  let edges = edge_faces faces in
  let boundary_edges = ref [] and non_manifold_edges = ref [] in
  Edge_table.iter (fun (a, b) incident ->
    let edge = { a; b } in
    match List.length incident with
    | 1 -> boundary_edges := edge :: !boundary_edges
    | 2 -> ()
    | _ -> non_manifold_edges := edge :: !non_manifold_edges) edges;
  let degenerate_faces = ref [] in
  Array.iteri (fun face triangle -> if face_degenerate epsilon vertices triangle then degenerate_faces := face :: !degenerate_faces) faces;
  let seen = Hashtbl.create (Array.length faces) and duplicate_faces = ref [] in
  Array.iteri (fun face triangle ->
    let key = canonical_face triangle in
    if Hashtbl.mem seen key then duplicate_faces := face :: !duplicate_faces
    else Hashtbl.add seen key face) faces;
  {
    faces = Array.length faces;
    components = component_count (Array.length faces) edges;
    boundary_edges = List.rev !boundary_edges;
    non_manifold_edges = List.rev !non_manifold_edges;
    degenerate_faces = List.rev !degenerate_faces;
    duplicate_faces = List.rev !duplicate_faces;
  }

let is_closed report = report.boundary_edges = [] && report.non_manifold_edges = []
let is_manifold report = report.non_manifold_edges = []
let weld ?(epsilon = 1e-9) mesh =
  if not (Float.is_finite epsilon) || epsilon < 0. then
    invalid_arg "Mesh_repair.weld: epsilon must be finite and non-negative";
  match Pdk.Prismel_mesh.of_mesh mesh with
  | Error error -> invalid_arg (Pdk.Error.to_string error)
  | Ok geometry ->
      (match Pdk.Ops.fuse ~tolerance:epsilon
          ~position:Pdk.Ops.First_position ~attributes:Pdk.Ops.Keep_first
          ~metric:Pdk.Ops.Componentwise ~inclusive:false
          ~match_attributes:true geometry with
       | Error error -> invalid_arg (Pdk.Error.to_string error)
       | Ok geometry ->
           match Pdk.Prismel_mesh.to_mesh geometry with
           | Ok mesh -> mesh
           | Error error -> invalid_arg (Pdk.Error.to_string error))

let rebuild_array mesh faces =
  let indices = Array.make (Array.length faces * 3) 0 in
  Array.iteri
    (fun face (a, b, c) ->
      let offset = face * 3 in
      indices.(offset) <- a;
      indices.(offset + 1) <- b;
      indices.(offset + 2) <- c)
    faces;
  let view = Mesh.Private.view mesh in
  Mesh.Private.create_owned ~mode:Mesh.Triangles ~indices
    ?colors:(Option.map Array.copy view.colors)
    ?tex_coords:(Option.map Array.copy view.tex_coords)
    (Array.copy view.vertices)
  |> Result.map Mesh.recalculate_normals

let remove_degenerate ?(epsilon = 1e-12) mesh =
  if not (Float.is_finite epsilon) || epsilon < 0. then invalid_arg "Mesh_repair.remove_degenerate: epsilon must be finite and non-negative";
  let vertices = (Mesh.Private.view mesh).vertices
  and faces = Mesh.Private.triangle_indices mesh in
  let kept = ref 0 in
  Array.iter
    (fun face ->
      if not (face_degenerate epsilon vertices face) then incr kept)
    faces;
  let output = Array.make !kept (0, 0, 0) and index = ref 0 in
  Array.iter
    (fun face ->
      if not (face_degenerate epsilon vertices face) then begin
        output.(!index) <- face;
        incr index
      end)
    faces;
  rebuild_array mesh output

let remove_duplicate_faces mesh =
  let faces = Mesh.Private.triangle_indices mesh in
  let seen = Hashtbl.create (Array.length faces)
  and keep = Array.make (Array.length faces) false
  and kept = ref 0 in
  Array.iteri
    (fun index face ->
      let key = canonical_face face in
      if not (Hashtbl.mem seen key) then begin
        Hashtbl.add seen key ();
        keep.(index) <- true;
        incr kept
      end)
    faces;
  let output = Array.make !kept (0, 0, 0) and index = ref 0 in
  Array.iteri
    (fun face triangle ->
      if keep.(face) then begin
        output.(!index) <- triangle;
        incr index
      end)
    faces;
  rebuild_array mesh output

let collapse_short_edges ~epsilon mesh =
  if not (Float.is_finite epsilon) || epsilon < 0. then
    invalid_arg "Mesh_repair.collapse_short_edges: epsilon must be finite and non-negative";
  let vertices = (Mesh.Private.view mesh).vertices in
  let parent = Array.init (Array.length vertices) Fun.id in
  let rec root index =
    if parent.(index) = index then index
    else begin parent.(index) <- root parent.(index); parent.(index) end
  in
  let join left right =
    let left = root left and right = root right in
    if left <> right then parent.(max left right) <- min left right
  in
  let epsilon_sq = epsilon *. epsilon in
  let faces = Mesh.Private.triangle_indices mesh in
  let join_if_short left right =
    if Vec3.length_sq (Vec3.sub vertices.(left) vertices.(right)) <= epsilon_sq
    then join left right
  in
  Array.iter
    (fun (a, b, c) ->
      join_if_short a b;
      join_if_short b c;
      join_if_short c a)
    faces;
  Array.iteri
    (fun index (a, b, c) -> faces.(index) <- root a, root b, root c)
    faces;
  Result.bind (rebuild_array mesh faces) (fun mesh ->
    Result.bind (remove_degenerate mesh) remove_duplicate_faces)

let point_on_edge ~epsilon (point : Vec3.t) (left : Vec3.t) (right : Vec3.t) =
  let dx = right.x -. left.x
  and dy = right.y -. left.y
  and dz = right.z -. left.z in
  let length_sq = (dx *. dx) +. (dy *. dy) +. (dz *. dz) in
  if length_sq <= epsilon *. epsilon then false
  else
    let px = point.Vec3.x -. left.x
    and py = point.y -. left.y
    and pz = point.z -. left.z in
    let amount = ((px *. dx) +. (py *. dy) +. (pz *. dz)) /. length_sq in
    if amount <= epsilon || amount >= 1. -. epsilon then false
    else
      let ex = px -. (dx *. amount)
      and ey = py -. (dy *. amount)
      and ez = pz -. (dz *. amount) in
      (ex *. ex) +. (ey *. ey) +. (ez *. ez) <= epsilon *. epsilon

let repair_t_junctions ?(epsilon = 1e-8) mesh =
  if not (Float.is_finite epsilon) || epsilon <= 0. then
    invalid_arg "Mesh_repair.repair_t_junctions: epsilon must be finite and positive";
  let vertices = (Mesh.Private.view mesh).vertices in
  let finite point =
    Float.is_finite point.Vec3.x
    && Float.is_finite point.y
    && Float.is_finite point.z
  in
  let finite_count =
    Array.fold_left (fun count point -> count + if finite point then 1 else 0)
      0 vertices
  in
  let min_x = ref infinity and min_y = ref infinity and min_z = ref infinity
  and max_x = ref neg_infinity and max_y = ref neg_infinity
  and max_z = ref neg_infinity in
  Array.iter
    (fun point ->
      if finite point then begin
        min_x := Float.min !min_x point.x;
        min_y := Float.min !min_y point.y;
        min_z := Float.min !min_z point.z;
        max_x := Float.max !max_x point.x;
        max_y := Float.max !max_y point.y;
        max_z := Float.max !max_z point.z
      end)
    vertices;
  let resolution = (1 lsl 20) - 1 in
  let resolution_float = float_of_int resolution in
  let quantize value minimum maximum =
    if maximum <= minimum then 0
    else
      int_of_float
        (((value -. minimum) /. (maximum -. minimum))
         *. resolution_float)
  in
  let morton x y z =
    let rec interleave bit code =
      if bit = 20 then code
      else
        let output = bit * 3 in
        interleave (bit + 1)
          (code
           lor (((x lsr bit) land 1) lsl output)
           lor (((y lsr bit) land 1) lsl (output + 1))
           lor (((z lsr bit) land 1) lsl (output + 2)))
    in
    interleave 0 0
  in
  let entries = Array.make finite_count (0, 0) and offset = ref 0 in
  Array.iteri
    (fun index point ->
      if finite point then begin
        let x = quantize point.x !min_x !max_x
        and y = quantize point.y !min_y !max_y
        and z = quantize point.z !min_z !max_z in
        entries.(!offset) <- morton x y z, index;
        incr offset
      end)
    vertices;
  Array.sort
    (fun (left_code, left_index) (right_code, right_index) ->
      let result = Int.compare left_code right_code in
      if result <> 0 then result else Int.compare left_index right_index)
    entries;
  let bounds_min_x = Array.make finite_count 0.
  and bounds_min_y = Array.make finite_count 0.
  and bounds_min_z = Array.make finite_count 0.
  and bounds_max_x = Array.make finite_count 0.
  and bounds_max_y = Array.make finite_count 0.
  and bounds_max_z = Array.make finite_count 0. in
  let include_bounds parent child =
    bounds_min_x.(parent) <- Float.min bounds_min_x.(parent) bounds_min_x.(child);
    bounds_min_y.(parent) <- Float.min bounds_min_y.(parent) bounds_min_y.(child);
    bounds_min_z.(parent) <- Float.min bounds_min_z.(parent) bounds_min_z.(child);
    bounds_max_x.(parent) <- Float.max bounds_max_x.(parent) bounds_max_x.(child);
    bounds_max_y.(parent) <- Float.max bounds_max_y.(parent) bounds_max_y.(child);
    bounds_max_z.(parent) <- Float.max bounds_max_z.(parent) bounds_max_z.(child)
  in
  let rec fill_bounds first after =
    if first < after then begin
      let middle = first + ((after - first) / 2) in
      fill_bounds first middle;
      fill_bounds (middle + 1) after;
      let _, vertex = entries.(middle) in
      let point = vertices.(vertex) in
      bounds_min_x.(middle) <- point.x;
      bounds_min_y.(middle) <- point.y;
      bounds_min_z.(middle) <- point.z;
      bounds_max_x.(middle) <- point.x;
      bounds_max_y.(middle) <- point.y;
      bounds_max_z.(middle) <- point.z;
      if first < middle then
        include_bounds middle (first + ((middle - first) / 2));
      if middle + 1 < after then
        include_bounds middle
          (middle + 1 + ((after - middle - 1) / 2))
    end
  in
  fill_bounds 0 finite_count;
  let find_on a b c left right =
    let left_point = vertices.(left) and right_point = vertices.(right) in
    let min_x = Float.min left_point.x right_point.x -. epsilon
    and max_x = Float.max left_point.x right_point.x +. epsilon
    and min_y = Float.min left_point.y right_point.y -. epsilon
    and max_y = Float.max left_point.y right_point.y +. epsilon
    and min_z = Float.min left_point.z right_point.z -. epsilon
    and max_z = Float.max left_point.z right_point.z +. epsilon in
    let best = ref max_int in
    let rec visit first after =
      if first < after then begin
        let middle = first + ((after - first) / 2) in
        if bounds_max_x.(middle) >= min_x && bounds_min_x.(middle) <= max_x
           && bounds_max_y.(middle) >= min_y && bounds_min_y.(middle) <= max_y
           && bounds_max_z.(middle) >= min_z && bounds_min_z.(middle) <= max_z
        then begin
          let _, index = entries.(middle) in
          let point = vertices.(index) in
          if index < !best && index <> a && index <> b && index <> c
             && point.x >= min_x && point.x <= max_x
             && point.y >= min_y && point.y <= max_y
             && point.z >= min_z && point.z <= max_z
             && point_on_edge ~epsilon point left_point right_point
          then best := index;
          visit first middle;
          visit (middle + 1) after
        end
      end
    in
    visit 0 finite_count;
    if !best = max_int then None else Some !best
  in
  let input = Mesh.Private.triangle_indices mesh in
  let capacity = ref (max 16 (Array.length input))
  and output = ref (Array.make (max 16 (Array.length input)) (0, 0, 0))
  and output_count = ref 0 in
  let append face =
    if !output_count = !capacity then begin
      capacity := !capacity * 2;
      let grown = Array.make !capacity (0, 0, 0) in
      Array.blit !output 0 grown 0 !output_count;
      output := grown
    end;
    (!output).(!output_count) <- face;
    incr output_count
  in
  let pending = Stack.create () in
  Array.iter
    (fun face ->
      Stack.push face pending;
      while not (Stack.is_empty pending) do
        let (a, b, c as current) = Stack.pop pending in
        match find_on a b c a b with
        | Some point ->
            Stack.push (point, b, c) pending;
            Stack.push (a, point, c) pending
        | None ->
            (match find_on a b c b c with
             | Some point ->
                 Stack.push (point, c, a) pending;
                 Stack.push (b, point, a) pending
             | None ->
                 (match find_on a b c c a with
                  | Some point ->
                      Stack.push (point, a, b) pending;
                      Stack.push (c, point, b) pending
                  | None -> append current))
      done)
    input;
  rebuild_array mesh (Array.sub !output 0 !output_count)

type edge_use = { face : int; from_ : int; to_ : int }

let oriented_edge_table faces =
  let table = Edge_table.create (Array.length faces * 3) in
  let add face from_ to_ =
    let key = edge_key from_ to_ in
    Edge_table.replace table key
      ({ face; from_; to_ } :: Option.value ~default:[] (Edge_table.find_opt table key))
  in
  Array.iteri (fun face (a, b, c) -> add face a b; add face b c; add face c a) faces;
  table

let orient_consistently mesh =
  let faces = Mesh.Private.triangle_indices mesh in
  if Array.length faces = 0 then Error "Mesh_repair.orient_consistently: mesh has no triangles"
  else
    let edges = oriented_edge_table faces in
    if Edge_table.to_seq_values edges |> Seq.exists (fun uses -> List.length uses > 2) then
      Error "Mesh_repair.orient_consistently: mesh has non-manifold edges"
    else
      let adjacency = Array.make (Array.length faces) [] in
      Edge_table.iter (fun _ -> function
        | [left; right] ->
            let same = left.from_ = right.from_ && left.to_ = right.to_ in
            adjacency.(left.face) <- (right.face, same) :: adjacency.(left.face);
            adjacency.(right.face) <- (left.face, same) :: adjacency.(right.face)
        | _ -> ()) edges;
      let flips = Array.make (Array.length faces) None in
      let components = ref [] and inconsistent = ref false in
      for start = 0 to Array.length faces - 1 do
        if Option.is_none flips.(start) then begin
          flips.(start) <- Some false;
          let pending = Queue.create () and component = ref [] in
          Queue.push start pending;
          while not (Queue.is_empty pending) do
            let face = Queue.pop pending in
            component := face :: !component;
            let current = Option.get flips.(face) in
            List.iter (fun (neighbor, same_direction) ->
              let expected = if same_direction then not current else current in
              match flips.(neighbor) with
              | None -> flips.(neighbor) <- Some expected; Queue.push neighbor pending
              | Some actual -> if actual <> expected then inconsistent := true) adjacency.(face)
          done;
          components := !component :: !components
        end
      done;
      if !inconsistent then Error "Mesh_repair.orient_consistently: topology is not consistently orientable"
      else
        let vertices = (Mesh.Private.view mesh).vertices in
        let effective face =
          let a, b, c = faces.(face) in
          if Option.get flips.(face) then a, c, b else a, b, c
        in
        List.iter (fun component ->
          let closed = List.for_all (fun face ->
            let a, b, c = faces.(face) in
            List.for_all (fun key -> match Edge_table.find_opt edges key with Some uses -> List.length uses = 2 | None -> false)
              [edge_key a b; edge_key b c; edge_key c a]) component in
          if closed then begin
            let volume = List.fold_left (fun total face ->
              let a, b, c = effective face in
              total +. Vec3.dot vertices.(a) (Vec3.cross vertices.(b) vertices.(c)) /. 6.) 0. component in
            if volume < 0. then List.iter (fun face -> flips.(face) <- Some (not (Option.get flips.(face)))) component
          end) !components;
        Array.mapi (fun face _ -> effective face) faces |> rebuild_array mesh

let make_watertight ?epsilon mesh =
  Result.bind (repair_t_junctions ?epsilon mesh) orient_consistently

let repair ?(weld_epsilon = 1e-9) ?(degenerate_epsilon = 1e-12)
    ?(t_junction_epsilon = 1e-8) mesh =
  let mesh = weld ~epsilon:weld_epsilon mesh in
  Result.bind (remove_degenerate ~epsilon:degenerate_epsilon mesh) (fun mesh ->
    Result.bind (remove_duplicate_faces mesh) (fun mesh ->
      Result.bind (repair_t_junctions ~epsilon:t_junction_epsilon mesh)
        orient_consistently))
