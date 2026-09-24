open Prismel

type point
type vertex
type primitive
type owner = Point | Vertex | Primitive
type expression =
  | All
  | Point_bounds of Vec3.t * Vec3.t
  | Indices of int array
  | Union of expression * expression
  | Intersection of expression * expression
  | Difference of expression * expression
  | Complement of expression

type 'owner t = { owner : owner; expression : expression; key : string }

let float_key value = Int64.to_string (Int64.bits_of_float value)
let vec3_key value = String.concat "," [float_key value.Vec3.x;
  float_key value.y; float_key value.z]

let all_points = { owner = Point; expression = All; key = "point:*" }
let all_vertices = { owner = Vertex; expression = All; key = "vertex:*" }
let all_primitives = { owner = Primitive; expression = All; key = "primitive:*" }

let points_in_bounds ~min ~max =
  let finite value = Float.is_finite value in
  if not (finite min.Vec3.x && finite min.y && finite min.z
          && finite max.Vec3.x && finite max.y && finite max.z)
     || min.x > max.x || min.y > max.y || min.z > max.z
  then invalid_arg "Select.points_in_bounds: invalid finite bounds";
  let min = Vec3.create min.x min.y min.z and max = Vec3.create max.x max.y max.z in
  { owner = Point; expression = Point_bounds (min, max);
    key = "point:bounds:" ^ vec3_key min ^ ":" ^ vec3_key max }

let make_indices owner prefix supplied =
  let indices = Array.copy supplied in
  Array.sort Int.compare indices;
  if Array.exists (fun index -> index < 0) indices then
    invalid_arg "Select.primitive_indices: negative index";
  let unique = if Array.length indices = 0 then [||] else begin
    let count = ref 1 in
    for index = 1 to Array.length indices - 1 do
      if indices.(index) <> indices.(index - 1) then incr count
    done;
    let output = Array.make !count indices.(0) and at = ref 1 in
    for index = 1 to Array.length indices - 1 do
      if indices.(index) <> indices.(index - 1) then begin
        output.(!at) <- indices.(index); incr at
      end
    done;
    output
  end in
  { owner; expression = Indices unique;
    key = prefix ^ ":indices:" ^ String.concat ","
      (Array.to_list (Array.map string_of_int unique)) }

let point_indices indices = make_indices Point "point" indices
let vertex_indices indices = make_indices Vertex "vertex" indices
let primitive_indices indices = make_indices Primitive "primitive" indices

let combine constructor symbol left right =
  { owner = left.owner; expression = constructor (left.expression, right.expression);
    key = "(" ^ left.key ^ symbol ^ right.key ^ ")" }
let union (left : 'owner t) (right : 'owner t) : 'owner t =
  combine (fun (left, right) -> Union (left, right)) "|" left right
let intersection (left : 'owner t) (right : 'owner t) : 'owner t =
  combine (fun (left, right) -> Intersection (left, right)) "&" left right
let difference (left : 'owner t) (right : 'owner t) : 'owner t =
  combine (fun (left, right) -> Difference (left, right)) "-" left right
let complement value =
  { value with expression = Complement value.expression; key = "!(" ^ value.key ^ ")" }
let fingerprint value = value.key

let owner_length owner geometry = match owner with
  | Point -> Pdk.Geometry.point_count geometry
  | Vertex -> Pdk.Geometry.vertex_count geometry
  | Primitive -> Pdk.Geometry.primitive_count geometry
let pdk_owner = function Point -> Pdk.Group.Point | Vertex -> Pdk.Group.Vertex
  | Primitive -> Pdk.Group.Primitive

let evaluate ~name selection geometry =
  let owner = pdk_owner selection.owner and length = owner_length selection.owner geometry in
  let rec run = function
    | All -> Ok (Pdk.Group.init ~owner ~name:"__all" length (fun _ -> true))
    | Point_bounds (minimum, maximum) ->
        let positions = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry) in
        Ok (Pdk.Group.init ~owner:Pdk.Group.Point ~name:"__bounds" length (fun index ->
          let x = positions.x.(index) and y = positions.y.(index)
          and z = positions.z.(index) in
          x >= minimum.x && x <= maximum.x && y >= minimum.y && y <= maximum.y
          && z >= minimum.z && z <= maximum.z))
    | Indices indices ->
        (match Array.find_opt (fun index -> index >= length) indices with
         | Some index -> Error (Printf.sprintf
             "Select.indices: index %d is outside owner length %d" index length)
         | None ->
             let builder = Pdk.Group.Builder.create ~owner
                 ~name:"__indices" length in
             Array.iter (fun index -> Pdk.Group.Builder.set builder index true) indices;
             Ok (Pdk.Group.Builder.freeze builder))
    | Union (left, right) ->
        Result.bind (run left) (fun left ->
          Result.bind (run right) (Pdk.Group.union left))
    | Intersection (left, right) ->
        Result.bind (run left) (fun left ->
          Result.bind (run right) (Pdk.Group.intersection left))
    | Difference (left, right) ->
        Result.bind (run left) (fun left ->
          Result.bind (run right) (Pdk.Group.difference left))
    | Complement value ->
        Result.bind (run All) (fun all ->
          Result.bind (run value) (Pdk.Group.difference all)) in
  Result.map (Pdk.Group.with_name name) (run selection.expression)
