module Edit = Procedural.Edit_graph

let key = "flow.curve"
let parameter = "points"

let encode points =
  let buffer = Buffer.create (Array.length points * 40) in
  Array.iteri (fun i (x, y, z) ->
    if i > 0 then Buffer.add_char buffer ';';
    Buffer.add_string buffer (Printf.sprintf "%h,%h,%h" x y z)) points;
  Buffer.contents buffer

let decode text =
  if text = "" then Ok [||] else
  try Ok (Array.of_list (List.map (fun point ->
    match String.split_on_char ',' point with
    | [x; y; z] -> float_of_string x, float_of_string y, float_of_string z
    | _ -> failwith "point") (String.split_on_char ';' text)))
  with Failure _ -> Error "curve points: expected x,y,z;..."

let schema = Procedural.Parameter.schema ~name:"flow_curve" ~default:[||] [
  Procedural.Parameter.field ~name:parameter ~label:"Points"
    ~kind:(Procedural.Parameter.encoded ~equal:( = ) ~encode ~decode)
    ~default:[||] ~get:Fun.id ~set:(fun points _ -> points) () ]

let node points =
  Procedural.Custom.node ~label:"Curve" ~operation:"flow_curve" ~schema
    ~values:points [] (fun ~label ~inputs:_ ~parameters ->
      Procedural.Sop.polyline ~label parameters)

let factory = Edit.factory ~key ~label:"Curve" ~category:["Flow"] ~arity:0
  ~fields:(Procedural.Node.parameter_fields (node [||])) (fun _ -> node [||])
