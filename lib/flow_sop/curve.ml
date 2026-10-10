module Edit = Sop.Edit_graph

let key = "flow.curve"
let parameter = "points"
let closed_parameter = "closed"

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

type t = { points : (float * float * float) array; closed : bool }

let default = { points = [||]; closed = false }

let schema = Sop.Parameter.schema ~name:"flow_curve" ~default [
  Sop.Parameter.field ~name:parameter ~label:"Points"
    ~kind:(Sop.Parameter.encoded ~equal:( = ) ~encode ~decode)
    ~default:default.points ~get:(fun curve -> curve.points)
    ~set:(fun points curve -> { curve with points }) ();
  Sop.Parameter.field ~name:closed_parameter ~label:"Closed"
    ~kind:Sop.Parameter.Toggle ~default:false ~get:(fun curve -> curve.closed)
    ~set:(fun closed curve -> { curve with closed }) () ]

let node curve =
  Sop.Custom.node ~label:"Curve" ~operation:"flow_curve" ~schema
    ~values:curve [] (fun ~label ~inputs:_ ~parameters ->
      let { points; closed } = parameters in
      let key = Printf.sprintf "count=%d;closed=%b" (Array.length points) closed in
      Sop.Node.Private.make_geometry ~label ~operation:"polyline" ~version:1
        ~parameters:key ~cook_mode:Sop.Node.Generator
        ~dependencies:Sop.Context.Dependencies.static ~inputs:[||]
        (fun ~node_id:_ _context _inputs ->
          match Rdk.Line_geometry.polyline ~closed (Array.copy points) with
          | Ok geometry -> Ok Sop.Node.Private.{geometry; diagnostics = []; instances = None}
          | Error error -> Error (Sop.Diagnostic.error ~code:(Rdk.Error.code error)
              ~cause:(Rdk.Error.to_string error) ~hints:(Rdk.Error.hints error)
              (Rdk.Error.operation error ^ " could not produce valid geometry"))))

let factory = Edit.factory ~key ~label:"Curve" ~category:["Flow"] ~arity:0
  ~fields:(Sop.Node.parameter_fields (node default)) (fun _ -> node default)
