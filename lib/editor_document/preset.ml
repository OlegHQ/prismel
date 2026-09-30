open Procedural

let ( let* ) = Result.bind

let unique ~what keys =
  let seen = Hashtbl.create (List.length keys) in
  List.fold_left (fun state key ->
    let* () = state in
    if Hashtbl.mem seen key then Error ("duplicate " ^ what)
    else (Hashtbl.add seen key (); Ok ())) (Ok ()) keys

let rec finite_json = function
  | `Float x -> Float.is_finite x
  | `Assoc fields -> List.for_all (fun (_, json) -> finite_json json) fields
  | `List entries -> List.for_all finite_json entries
  | _ -> true

type loaded = {
  doc : Document.t;
  view : Yojson.Safe.t;
}

module Layout = Editor_core.Network_layout
let version = 3

let sanitize name = String.map (function
  | ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-') as character -> character
  | _ -> '_') (String.trim name)

let default_name () =
  let time = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02d_%02d-%02d-%02d" (time.tm_year + 1900)
    (time.tm_mon + 1) time.tm_mday time.tm_hour time.tm_min time.tm_sec

let path ~directory ~name = Filename.concat directory (sanitize name ^ ".json")

let value_json : Parameter.value -> Yojson.Safe.t = function
  | Bool_value value -> `Assoc ["bool", `Bool value]
  | Int_value value -> `Assoc ["int", `Int value]
  | Float_value value -> `Assoc ["float", `Float value]
  | Text_value value -> `Assoc ["text", `String value]
  | Choice_value value -> `Assoc ["choice", `String value]

let value_of_json : Yojson.Safe.t -> (Parameter.value, string) result = function
  | `Assoc ["bool", `Bool value] -> Ok (Bool_value value)
  | `Assoc ["int", `Int value] -> Ok (Int_value value)
  | `Assoc ["float", `Float value] when Float.is_finite value -> Ok (Float_value value)
  | `Assoc ["float", `Float _] -> Error "nonfinite parameter value"
  | `Assoc ["float", `Int value] -> Ok (Float_value (float_of_int value))
  | `Assoc ["text", `String value] -> Ok (Text_value value)
  | `Assoc ["choice", `String value] -> Ok (Choice_value value)
  | _ -> Error "unreadable parameter value"

let optional_int = function Some value -> `Int value | None -> `Null

let flow_result result = Result.map_error Flow.Diagnostic.to_string result
let port_json (id, path) = `List [`Int id; `String path]
let points_json points = `List (List.map (fun (x, y) -> `List [`Float x; `Float y]) points)
let params_json fields = `List (List.map (fun (field : Parameter.field_view) ->
    `List [`String field.name; value_json field.current]) fields)

let network_json (network : Document.network) =
  let layout id =
    let x, y = Option.value ~default:(0., 0.) (Document.Layout.find_opt id network.layout.at) in
    ["x", `Float x; "y", `Float y;
     "level", `String (match Document.Layout.find_opt id network.layout.level with
       | Some Layout.Point -> "point" | Some Chip -> "chip" | Some Full -> "full"
       | Some Card | None -> "card");
     "pinned", `Bool (Option.value ~default:false (Document.Layout.find_opt id network.layout.pinned));
     "rows", `Assoc (Option.value ~default:Layout.String_map.empty
       (Document.Layout.find_opt id network.layout.rows)
       |> Layout.String_map.bindings |> List.map (fun (name, shown) -> name, `Bool shown));
     "split", `List (Option.value ~default:Layout.String_set.empty
       (Document.Layout.find_opt id network.layout.split)
       |> Layout.String_set.elements |> List.map (fun name -> `String name))] in
  let node (info : Edit_graph.node_info) = `Assoc (
    ["id", `Int info.id] @
    (match Edit_graph.node_factory_key network.graph.geometry ~node_id:info.id with
     | Some key -> ["factory_key", `String key] | None -> []) @
    ["label", `String info.label; "bypass", `Bool info.bypass;
     "inputs", `List (Array.to_list (Array.map optional_int info.inputs));
     "params", params_json (Node.parameter_fields info.node)] @ layout info.id) in
  let value (node : Flow.Graph.node) = `Assoc (
    ["id", `Int node.id; "kind", `String (Flow.Value_kind.key (Flow.Value_kind.kind node.parameters));
     "label", `String node.label; "params", params_json (Flow.Value_kind.fields node.parameters)] @ layout node.id) in
  let bends port = Option.value ~default:[] (Layout.Port_map.find_opt port network.layout.bends) in
  let drive ((target : Flow_sop.Port.t), drive) =
    let port = target.node, target.path in
    `Assoc (["to", port_json port] @ match drive with
    | Flow_sop.Drive.Expr expr -> ["expr", `String (Flow.Expr.infix expr)]
    | Live _ -> ["live", `String "t"]  (* lowered workspaces only; never saved *)
    | Wire source -> ["wire", port_json (source.node, source.output);
        "bends", points_json (bends port);
        "wireless", `Bool (Layout.Port_set.mem port network.layout.wireless)]) in
  let geometry_ports = Layout.Port_map.fold (fun port _ ports -> Layout.Port_set.add port ports)
      network.layout.bends network.layout.wireless
    |> Layout.Port_set.filter (fun (node, path) ->
      not (Flow_sop.Port.Map.mem {node; path} network.graph.drives)) in
  `Assoc ["context", `String (Flow.Context.name network.context);
    "nodes", `List (List.map node (Edit_graph.inspect network.graph.geometry));
    "values", `List (List.map value (Flow.Graph.inspect network.graph.values));
    "instances", `List (Flow_sop.Network.Int_map.bindings network.graph.instances
      |> List.map (fun (id, instance) ->
        `Assoc ["id", `Int id; "definition", `String instance.Flow_sop.Network.definition;
          "literals", `List (Flow_sop.Network.String_map.bindings instance.literals
            |> List.map (fun (name, value) -> `List [`String name; value_json value]))]));
    "geometry_outputs", `List (Flow_sop.Port.Map.bindings network.graph.geometry_outputs
      |> List.map (fun ((target : Flow_sop.Port.t), output) ->
        `Assoc ["to", port_json (target.node, target.path);
          "output", `String output]));
    "drives", `List (List.map drive (Flow_sop.Port.Map.bindings network.graph.drives));
    "display", optional_int network.displayed;
    "geometry_bends", `List (Layout.Port_set.elements geometry_ports |> List.map (fun port ->
      `Assoc ["to", port_json port; "bends", points_json (bends port);
        "wireless", `Bool (Layout.Port_set.mem port network.layout.wireless)]))]

let interface_json (port : Flow_sop.Network.interface_port) = `Assoc [
  "name", `String port.name;
  "type", `String (Flow.Port_type.name port.ty);
  "default", Option.fold ~none:`Null ~some:(function
    | Flow_sop.Port.Scalar value -> value_json value
    | Flow_sop.Port.Vector (x,y,z) ->
        `Assoc ["vec3", `List [`Float x; `Float y; `Float z]]) port.default;
  "label", `String port.label;
  "soft", Option.fold ~none:`Null ~some:(fun (low, high) ->
    `List [`Float low; `Float high]) port.soft]

let definition_json (definition : Document.definition) =
  let spec = definition.spec in
  let body : Document.network = {context = spec.context; graph = spec.body;
    layout = definition.layout; displayed = definition.displayed} in
  `Assoc ["name", `String spec.name;
    "context", `String (Flow.Context.name spec.context);
    "inputs", `List (List.map interface_json spec.inputs);
    "outputs", `List (List.map interface_json spec.outputs);
    "body", network_json body]

let to_sections ~(doc : Document.t) ~view =
  [ "graph", `Assoc [
      "version", `Int version;
      "scene", network_json doc.scene;
      "networks", `List (List.map (fun (id, network) ->
        `Assoc [ "object", `Int id; "network", network_json network ])
        (Document.Layout.bindings doc.networks));
      "compiled_ids", `List (List.map (fun (path, id) ->
        `Assoc ["path", `List (List.map (fun part -> `Int part) path); "id", `Int id])
        (Flow_sop.Instance_path.Map.bindings doc.compiled_ids));
      "definitions", `List (Document.String_map.bindings doc.definitions
        |> List.map (fun (_, definition) -> definition_json definition));
      "active_camera", optional_int doc.active_camera;
      "settings", `List (List.map (fun (field : Parameter.field_view) ->
        `List [ `String field.name; value_json field.current ])
        (Settings.fields doc.settings)) ];
    "viewport", view ]

(* Written to a temporary file and renamed, so a crash never leaves a torn
   preset behind. *)
let save ~directory ~name ~sketch ~doc ~view =
  if sanitize name = "" then Error "preset name is empty" else
  let* () = Document.validate doc in
  let* () = if finite_json view then Ok () else Error "viewport contains nonfinite values" in
  let target = path ~directory ~name in
  Editor_core.Store.save ~filename:target ~kind:Editor_core.Store.Preset ~sketch
    ~sections:(to_sections ~doc ~view)
  |> Result.map (fun () -> target)

let list ~directory =
  match Sys.readdir directory with
  | exception Sys_error _ -> []
  | files ->
      Array.to_list files
      |> List.filter_map (fun file ->
        if not (Filename.check_suffix file ".json") then None
        else match Unix.stat (Filename.concat directory file) with
          | { Unix.st_mtime; _ } -> Some (Filename.chop_suffix file ".json", st_mtime)
          | exception Unix.Unix_error _ -> None)
      |> List.sort (fun (a, at) (b, bt) ->
        let order = Float.compare bt at in if order <> 0 then order else String.compare a b)

let delete ~directory ~name =
  try Sys.remove (path ~directory ~name); Ok () with Sys_error message -> Error message

(* ---- load: rebuild the full document from the code graph ---- *)

type saved = {
  id : int;
  factory_key : string option;
  label : string;
  inputs : int option list;
  params : (string * Parameter.value) list;
  x : float;
  y : float;
  level : Layout.level;
  pinned : bool;
  rows : bool Layout.String_map.t;
  bypass : bool;
  split : Layout.String_set.t;
  kind : Flow.Value_kind.kind option;
}

let rec all = function
  | [] -> Ok []
  | Ok value :: rest -> Result.map (fun rest -> value :: rest) (all rest)
  | Error message :: _ -> Error message

let number = function
  | `Float value when Float.is_finite value -> Ok value
  | `Int value -> Ok (float_of_int value)
  | _ -> Error "expected a finite number"

let saved_node ~value : Yojson.Safe.t -> (saved, string) result = function
  | `Assoc fields ->
      let* () = unique ~what:"node field" (List.map fst fields) in
      let field name = List.assoc_opt name fields in
      let* id = match field "id" with Some (`Int id) -> Ok id | _ -> Error "node without id" in
      let* kind = if not value then Ok None else match field "kind" with
        | Some (`String key) -> Result.map Option.some (flow_result (Flow.Value_kind.of_key key))
        | _ -> Error "value node without kind" in
      let* () = if value && (field "factory_key" <> None || field "inputs" <> None || field "bypass" <> None)
        then Error "value node has geometry fields" else Ok () in
      let* factory_key = match field "factory_key" with
        | Some (`String key) -> Ok (Some key) | None -> Ok None
        | _ -> Error "invalid factory key" in
      let* label = match field "label" with
        | Some (`String label) -> Ok label | None -> Ok ""
        | _ -> Error "invalid node label" in
      let* bypass = match field "bypass" with
        | None -> Ok false | Some (`Bool b) -> Ok b | _ -> Error "invalid bypass" in
      let* inputs = if value then Ok [] else match field "inputs" with
        | Some (`List inputs) -> all (List.map (function
            | `Int id -> Ok (Some id) | `Null -> Ok None
            | _ -> Error "bad input slot") inputs)
        | _ -> Error "node without inputs" in
      let* params = match field "params" with
        | Some (`List params) -> all (List.map (function
            | `List [ `String name; value ] ->
                Result.map (fun value -> name, value) (value_of_json value)
            | _ -> Error "bad parameter") params)
        | None -> Ok [] | _ -> Error "parameters are not a list" in
      let* () = unique ~what:"parameter name" (List.map fst params) in
      let* x = Option.fold ~none:(Ok 0.) ~some:number (field "x") in
      let* y = Option.fold ~none:(Ok 0.) ~some:number (field "y") in
      let* level = match field "level" with
        | None | Some (`String "card") -> Ok Layout.Card
        | Some (`String "point") -> Ok Layout.Point
        | Some (`String "chip") -> Ok Layout.Chip
        | Some (`String "full") -> Ok Layout.Full
        | _ -> Error "invalid detail level" in
      let* pinned = match field "pinned" with
        | None -> Ok false | Some (`Bool b) -> Ok b | _ -> Error "invalid pin" in
      let* rows = match field "rows" with
        | None -> Ok Layout.String_map.empty
        | Some (`Assoc rows) ->
            let* () = unique ~what:"row pin" (List.map fst rows) in
            let* rows = all (List.map (function name, `Bool b -> Ok (name, b)
              | _ -> Error "invalid row pin") rows) in
            Ok (Layout.String_map.of_list rows)
        | _ -> Error "invalid row pins" in
      let* split = match field "split" with
        | None -> Ok Layout.String_set.empty
        | Some (`List groups) ->
            let* groups = all (List.map (function `String group -> Ok group
              | _ -> Error "invalid vector split") groups) in
            let* () = unique ~what:"vector split" groups in
            Ok (Layout.String_set.of_list groups)
        | _ -> Error "invalid vector splits" in
      Ok { id; factory_key; label; inputs; params;
        x = Layout.snap x; y = Layout.snap y; level; pinned; rows; bypass; split; kind }
  | _ -> Error "node is not an object"

let nodes_of ~value = function
  | Some (`List nodes) -> all (List.map (saved_node ~value) nodes)
  | _ -> Error "preset has no nodes"

let optional_of = function
  | Some (`Int id) -> Ok (Some id) | Some `Null | None -> Ok None
  | _ -> Error "expected a node id or null"

type saved_network = {
  context : Flow.Context.t;
  nodes : saved list;
  values : saved list;
  display : int option;
  drives : (Flow_sop.Port.t * Flow_sop.Drive.t) list;
  bends : ((int * string) * (float * float) list) list;
  wireless : Layout.Port_set.t;
  geometry_outputs : (Flow_sop.Port.t * string) list;
  instances : (int * Flow_sop.Network.instance) list;
}

let port_of = function
  | Some (`List [`Int node; `String path]) -> Ok (node, path)
  | _ -> Error "expected a node and port name"
let points_of = function
  | None -> Ok []
  | Some (`List points) -> all (List.map (function
      | `List [x; y] -> let* x = number x in let* y = number y in Ok (Layout.snap x, Layout.snap y)
      | _ -> Error "invalid bend point") points)
  | _ -> Error "bend points are not a list"
let wireless_of = function None -> Ok false | Some (`Bool b) -> Ok b | _ -> Error "invalid wireless flag"

let network_of = function
  | `Assoc fields ->
      let* () = unique ~what:"network field" (List.map fst fields) in
      let field name = List.assoc_opt name fields in
      let* context = match field "context" with
        | Some (`String context) -> flow_result (Flow.Context.of_string context)
        | _ -> Error "network without context" in
      let* nodes = nodes_of ~value:false (field "nodes") in
      let* values = nodes_of ~value:true (field "values") in
      let* instances = match field "instances" with
        | None -> Ok []
        | Some (`List entries) -> all (List.map (function
            | `Assoc fields ->
                let* () = unique ~what:"instance field" (List.map fst fields) in
                (match List.assoc_opt "id" fields, List.assoc_opt "definition" fields,
                    List.assoc_opt "literals" fields with
                 | Some (`Int id), Some (`String definition), Some (`List literals) ->
                     let* literals = all (List.map (function
                       | `List [`String name; value] ->
                           Result.map (fun value -> name, value) (value_of_json value)
                       | _ -> Error "unreadable instance literal") literals) in
                     let* () = unique ~what:"instance literal" (List.map fst literals) in
                     Ok (id, {Flow_sop.Network.definition;
                       literals = Flow_sop.Network.String_map.of_list literals})
                 | _ -> Error "instance needs id, definition and literals")
            | _ -> Error "instance entry is not an object") entries)
        | Some _ -> Error "instances are not a list" in
      let* () = unique ~what:"instance id" (List.map fst instances) in
      let* geometry_outputs = match field "geometry_outputs" with
        | None -> Ok []
        | Some (`List entries) -> all (List.map (function
            | `Assoc fields ->
                let* () = unique ~what:"geometry output field" (List.map fst fields) in
                let* node, path = port_of (List.assoc_opt "to" fields) in
                (match List.assoc_opt "output" fields with
                 | Some (`String output) -> Ok ({Flow_sop.Port.node; path}, output)
                 | _ -> Error "geometry output needs a name")
            | _ -> Error "geometry output entry is not an object") entries)
        | Some _ -> Error "geometry outputs are not a list" in
      let* () = unique ~what:"geometry output destination"
        (List.map fst geometry_outputs) in
      let* display = optional_of (field "display") in
      let metadata entry =
        let* port = port_of (List.assoc_opt "to" entry) in
        let* bends = points_of (List.assoc_opt "bends" entry) in
        let* wireless = wireless_of (List.assoc_opt "wireless" entry) in
        Ok (port, bends, wireless) in
      let* drives = match field "drives" with
        | Some (`List entries) -> all (List.map (function
            | `Assoc entry ->
                let* () = unique ~what:"drive field" (List.map fst entry) in
                let* port, bends, wireless = metadata entry in
                let node, path = port in
                let* drive = match List.assoc_opt "wire" entry, List.assoc_opt "expr" entry with
                  | Some wire, None ->
                      let* node, output = port_of (Some wire) in
                      Ok (Flow_sop.Drive.Wire {node; output})
                  | None, Some (`String expression) ->
                      let* () = if List.assoc_opt "bends" entry <> None || List.assoc_opt "wireless" entry <> None
                        then Error "expression drives have no wire layout" else Ok () in
                      Result.map (fun expr -> Flow_sop.Drive.Expr expr) (flow_result (Flow.Expr.parse expression))
                  | _ -> Error "drive requires exactly one wire or expression" in
                Ok (({Flow_sop.Port.node; path}, drive), (port, bends, wireless))
            | _ -> Error "invalid drive") entries)
        | _ -> Error "network without drives" in
      let* geometry = match field "geometry_bends" with
        | None -> Ok []
        | Some (`List entries) -> all (List.map (function
            | `Assoc entry ->
                let* () = unique ~what:"bend entry field" (List.map fst entry) in metadata entry
            | _ -> Error "invalid bend entry") entries)
        | _ -> Error "geometry bends are not a list" in
      let* () = unique ~what:"drive destination" (List.map (fun ((target, _), _) -> target) drives) in
      let* () = unique ~what:"bend destination" (List.map (fun (port, _, _) -> port) geometry) in
      let metadata = geometry @ List.map snd drives in
      let* () = unique ~what:"wire destination" (List.map (fun (port, _, _) -> port) metadata) in
      let bends = List.filter_map (fun (port, points, _) ->
          if points = [] then None else Some (port, points)) metadata in
      (* Even an empty geometry bend entry must name a connected geometry slot. *)
      let bends = List.fold_left (fun bends (port, points, _) ->
          if points = [] then (port, []) :: bends else bends) bends geometry in
      let wireless = List.fold_left (fun flags (port, _, on) ->
          if on then Layout.Port_set.add port flags else flags) Layout.Port_set.empty metadata in
      Ok {context; nodes; values; display; drives = List.map fst drives;
        bends; wireless; geometry_outputs; instances}
  | _ -> Error "preset network is not an object"

type saved_definition = {
  name : string;
  context : Flow.Context.t;
  inputs : Flow_sop.Network.interface_port list;
  outputs : Flow_sop.Network.interface_port list;
  body : saved_network;
}

let interface_of = function
  | `Assoc fields ->
      let* () = unique ~what:"interface port field" (List.map fst fields) in
      let field name = List.assoc_opt name fields in
      let* name = match field "name" with Some (`String name) -> Ok name
        | _ -> Error "interface port needs a name" in
      let* ty = match field "type" with
        | Some (`String "Geometry") -> Ok Flow.Port_type.Geometry
        | Some (`String "Float") -> Ok Flow.Port_type.Float
        | Some (`String "Int") -> Ok Flow.Port_type.Int
        | Some (`String "Bool") -> Ok Flow.Port_type.Bool
        | Some (`String "Vec3") -> Ok Flow.Port_type.Vec3
        | _ -> Error "unknown interface port type" in
      let* default = match field "default" with
        | None | Some `Null -> Ok None
        | Some (`Assoc ["vec3", `List [x;y;z]]) ->
            let* x = number x in
            let* y = number y in
            Result.map (fun z -> Some (Flow_sop.Port.Vector (x,y,z)))
              (number z)
        | Some value -> Result.map (fun value ->
            Some (Flow_sop.Port.Scalar value)) (value_of_json value) in
      let* label = match field "label" with Some (`String label) -> Ok label
        | None -> Ok name | _ -> Error "interface label is not text" in
      let* soft = match field "soft" with
        | None | Some `Null -> Ok None
        | Some (`List [low; high]) ->
            let* low = number low in
            Result.map (fun high -> Some (low, high)) (number high)
        | _ -> Error "interface soft range is invalid" in
      Ok Flow_sop.Network.{name; ty; default; label; soft}
  | _ -> Error "interface port is not an object"

let definition_of = function
  | `Assoc fields ->
      let* () = unique ~what:"definition field" (List.map fst fields) in
      let field name = List.assoc_opt name fields in
      let* name = match field "name" with Some (`String name) -> Ok name
        | _ -> Error "definition needs a name" in
      let* context = match field "context" with
        | Some (`String context) -> flow_result (Flow.Context.of_string context)
        | _ -> Error "definition needs a context" in
      let* inputs = match field "inputs" with
        | Some (`List ports) -> all (List.map interface_of ports)
        | _ -> Error "definition inputs are not a list" in
      let* outputs = match field "outputs" with
        | Some (`List ports) -> all (List.map interface_of ports)
        | _ -> Error "definition outputs are not a list" in
      let* body = match field "body" with Some body -> network_of body
        | None -> Error "definition needs a body" in
      if body.context <> context then Error "definition body has the wrong context" else
      Ok {name; context; inputs; outputs; body}
  | _ -> Error "definition is not an object"

type decoded = {
  scene : saved_network;
  networks : (int * saved_network) list;
  definitions : saved_definition list;
  compiled_ids : int Flow_sop.Instance_path.Map.t;
}

let decode path = match Yojson.Safe.from_file path with
  | exception Yojson.Json_error message -> Error ("corrupt preset: " ^ message)
  | exception Sys_error message -> Error message
  | `Assoc fields ->
      let* () = unique ~what:"preset field" (List.map fst fields) in
      let* fields, view = match List.assoc_opt "sections" fields with
        | Some (`Assoc _) ->
            let* _, sections = Editor_core.Store.load ~filename:path ~kind:Editor_core.Store.Preset in
            (match List.assoc_opt "graph" sections with
             | Some (`Assoc graph) ->
                 Ok (graph, Option.value ~default:`Null
                   (List.assoc_opt "viewport" sections))
             | _ -> Error "preset has no graph section")
        | Some _ -> Error "preset sections are not an object"
        | None -> Ok (fields, Option.value ~default:`Null (List.assoc_opt "view" fields)) in
      let field name = List.assoc_opt name fields in
      let* () = unique ~what:"graph field" (List.map fst fields) in
      let* () = if finite_json view then Ok () else Error "viewport contains nonfinite values" in
      let* decoded = match field "version" with
        | Some (`Int 3) ->
            let* scene = network_of (Option.value ~default:`Null (field "scene")) in
            let* networks = match field "networks" with
              | Some (`List entries) -> all (List.map (function
                  | `Assoc entry ->
                      let* () = unique ~what:"network entry field" (List.map fst entry) in
                      (match List.assoc_opt "object" entry, List.assoc_opt "network" entry with
                       | Some (`Int id), Some network ->
                           Result.map (fun network -> id, network) (network_of network)
                       | _ -> Error "preset network has no object")
                  | _ -> Error "preset network entry is not an object") entries)
              | None -> Ok [] | _ -> Error "networks are not a list" in
            let* () = unique ~what:"network owner" (List.map fst networks) in
            let* definitions = match field "definitions" with
              | None -> Ok []
              | Some (`List entries) -> all (List.map definition_of entries)
              | Some _ -> Error "definitions are not a list" in
            let* () = unique ~what:"definition name"
              (List.map (fun definition -> definition.name) definitions) in
            let* compiled_ids = match field "compiled_ids" with
              | None -> Ok Flow_sop.Instance_path.Map.empty
              | Some (`List entries) ->
                  let* entries = all (List.map (function
                    | `Assoc fields ->
                        let* () = unique ~what:"compiled id field" (List.map fst fields) in
                        (match List.assoc_opt "path" fields, List.assoc_opt "id" fields with
                         | Some (`List path), Some (`Int id) ->
                             let* path = all (List.map (function
                               | `Int part -> Ok part
                               | _ -> Error "compiled id path contains a non-integer") path) in
                             Ok (path, id)
                         | _ -> Error "compiled id needs a path and id")
                    | _ -> Error "compiled id entry is not an object") entries) in
                  let* () = unique ~what:"compiled id path" (List.map fst entries) in
                  Ok (Flow_sop.Instance_path.Map.of_list entries)
              | Some _ -> Error "compiled ids are not a list" in
            Ok { scene; networks; definitions; compiled_ids }
        | Some (`Int v) -> Error (Printf.sprintf "unsupported preset version %d" v)
        | _ -> Error "preset has no version" in
      let* settings = match field "settings" with
        | None -> Ok []
        | Some (`List entries) -> all (List.map (function
            | `List [ `String name; value ] ->
                Result.map (fun value -> name, value) (value_of_json value)
            | _ -> Error "unreadable preset setting") entries)
        | Some _ -> Error "preset settings are not a list" in
      let* () = unique ~what:"setting name" (List.map fst settings) in
      let* active_camera = optional_of (field "active_camera") in
      Ok (decoded, active_camera, settings, view)
  | _ -> Error "corrupt preset: not an object"

(* Rebuild catalog closures and rebind code nodes, preserving saved ids. *)
let rebuild ~code ~factories (saved : saved_network) =
  let {nodes; display; bends; _} = saved in
  let migrate_parameters (node : saved) =
    match node.factory_key with
    | Some "set_color" ->
        List.filter_map (fun (name, value) -> match name, value with
          | ("red" | "green" | "blue"), Parameter.Int_value channel ->
              Some ("color_" ^ String.sub name 0 1, Parameter.Float_value (float_of_int channel /. 255.))
          | "alpha", Parameter.Int_value channel ->
              Some (name, Parameter.Float_value (float_of_int channel /. 255.))
          | ("red" | "green" | "blue"), _ -> None
          | name, value -> Some (name, value)) node.params
    | _ -> node.params in
  let* () = unique ~what:"node id" (List.map (fun node -> node.id) nodes) in
  let ids = Hashtbl.create (List.length nodes) in
  List.iter (fun node -> Hashtbl.add ids node.id ()) nodes;
  let reference id = if Hashtbl.mem ids id then Ok ()
    else Error (Printf.sprintf "preset references missing node #%d" id) in
  let* () = Option.fold ~none:(Ok ()) ~some:reference display in
  let* () = List.fold_left (fun state (node : saved) ->
    let* () = state in
    List.fold_left (fun state input ->
      let* () = state in
      Option.fold ~none:(Ok ()) ~some:reference input) (Ok ()) node.inputs) (Ok ()) nodes in
  let factories_by_key = Hashtbl.create (List.length factories) in
  List.iter (fun factory ->
    let key = Edit_graph.factory_key factory in
    if not (Hashtbl.mem factories_by_key key) then
      Hashtbl.add factories_by_key key factory) factories;
  (* Code nodes this network lists stay in place with their code wiring;
     every other code node is dropped. *)
  let listed = List.filter_map (fun (node : saved) ->
      if node.factory_key = None then Some node.id else None) nodes in
  let base = Edit_graph.remove_nodes (List.filter_map (fun (info : Edit_graph.node_info) ->
      if List.mem info.id listed then None else Some info.id) (Edit_graph.inspect code)) code in
  let* document = List.fold_left (fun state (node : saved) ->
    let* document = state in
    match node.factory_key with
    | Some key ->
        (match Hashtbl.find_opt factories_by_key key with
         | None -> Error (Printf.sprintf "preset node %S uses unknown node type %S" node.label key)
         | Some factory ->
             let arity = Edit_graph.factory_arity factory in
             let* created = Edit_graph.instantiate_optional factory (List.init arity (fun _ -> None)) in
             let* created = Node.Private.restore_id node.id (Node.relabel node.label created) in
             Edit_graph.add_node ~factory ~inputs:(Array.make arity None) created document)
    | None ->
        (match Edit_graph.find document ~node_id:node.id with
         | Some code_node when Node.label code_node <> node.label && node.label <> "" ->
             Edit_graph.replace_node (Node.relabel node.label code_node) document
         | Some _ -> Ok document
         | None -> Error (Printf.sprintf
             "preset node %S (#%d) is not in this sketch's code graph" node.label node.id)))
    (Ok base) nodes in
  let* document = List.fold_left (fun state (node : saved) ->
    let* document = state in
    let consumer = node.id in
    let* () = match Edit_graph.inputs document ~node_id:consumer with
      | Some inputs when Array.length inputs = List.length node.inputs -> Ok ()
      | _ -> Error (Printf.sprintf "preset node #%d has the wrong input arity" node.id) in
    List.fold_left (fun state (input_index, input) ->
      let* document = state in
      let current = Option.value ~default:[||] (Edit_graph.inputs document ~node_id:consumer) in
      match input with
      | Some source ->
          Edit_graph.connect ~source ~consumer ~input_index document
      | None when input_index < Array.length current && current.(input_index) <> None ->
          Edit_graph.disconnect ~consumer ~input_index document
      | None -> Ok document)
      (Ok document) (List.mapi (fun index input -> index, input) node.inputs))
    (Ok document) nodes in
  let* document = List.fold_left (fun state (node : saved) ->
    let* document = state in
    let params = migrate_parameters node in
    let known = Option.fold ~none:[] ~some:Node.parameter_fields
      (Edit_graph.find document ~node_id:node.id) in
    let* () = List.fold_left (fun checked (name, _) ->
      let* () = checked in
      if List.exists (fun (field : Parameter.field_view) -> field.name = name) known
      then Ok () else Error (Printf.sprintf "preset node #%d has unknown parameter %S" node.id name))
      (Ok ()) params in
    let* document = Edit_graph.set_bypass document ~node_id:node.id node.bypass in
    if params = [] then Ok document
    else Result.map fst (Edit_graph.apply_parameters document ~node_id:node.id params))
    (Ok document) nodes in
  let displayed = match display with Some _ -> display | None -> Edit_graph.root document in
  let* document = Option.fold ~none:(Ok document)
    ~some:(fun id -> Edit_graph.set_root id document) displayed in
  let layout = List.fold_left (fun (layout : Layout.t) (node : saved) ->
    { layout with at = Layout.Int_map.add node.id (node.x, node.y) layout.at;
      level = Layout.Int_map.add node.id node.level layout.level;
      pinned = Layout.Int_map.add node.id node.pinned layout.pinned;
      rows = if Layout.String_map.is_empty node.rows then layout.rows
        else Layout.Int_map.add node.id node.rows layout.rows;
      split = if Layout.String_set.is_empty node.split then layout.split
        else Layout.Int_map.add node.id node.split layout.split })
      { Layout.empty with bends = Layout.Port_map.of_list bends; wireless = saved.wireless }
      (nodes @ saved.values) in
  let* values = List.fold_left (fun state (node : saved) ->
    let* values = state in
    let* value = flow_result (Flow.Graph.node ~id:node.id ~label:node.label (Option.get node.kind)) in
    let* values = flow_result (Flow.Graph.add_node value values) in
    Result.map fst (flow_result (Flow.Graph.apply_parameters values ~node_id:node.id node.params)))
      (Ok Flow.Graph.empty) saved.values in
  let* graph = flow_result (Flow_sop.Network.of_parts ~geometry:document ~values
      ~drives:(Flow_sop.Port.Map.of_list saved.drives)
      ~geometry_outputs:(Flow_sop.Port.Map.of_list saved.geometry_outputs)
      ~instances:(Flow_sop.Network.Int_map.of_list saved.instances)) in
  Ok { Document.context = saved.context; graph; layout; displayed }

let load ~path ~code ~factories ~settings =
  let* decoded, active_camera, values, view = decode path in
  let code = Edit_graph.of_graph code in
  let* settings = Result.map fst (Settings.apply settings values) in
  let { scene; networks; definitions; compiled_ids } = decoded in
  let compound_factories = List.concat_map (fun (definition : saved_definition) ->
    Flow_sop.Compound_node.factories ~name:definition.name
      ~inputs:definition.inputs ~outputs:definition.outputs) definitions in
  let* scene_network = rebuild ~code
      ~factories:(Objects.catalog @ [Layers.Settings.factory]) scene in
  let* networks = List.fold_left (fun state (id, saved) ->
      let* networks = state in
      let* factories = match Option.map Node.operation
          (Edit_graph.find scene_network.graph.geometry ~node_id:id) with
        | Some "world" -> Ok Layers.catalog
        | Some "geometry" -> Ok (factories @ compound_factories)
        | None -> Error (Printf.sprintf "network has missing owner #%d" id)
        | Some _ -> Error (Printf.sprintf "object #%d cannot own a network" id) in
      let* network = rebuild ~code ~factories saved in
      Ok (Document.Layout.add id network networks))
      (Ok Document.Layout.empty) networks in
  let* definitions = List.fold_left (fun state saved ->
      let* definitions = state in
      let* network = rebuild ~code:Edit_graph.empty
        ~factories:(factories @ compound_factories) saved.body in
      let spec : Flow_sop.Network.definition = {
        name = saved.name; context = saved.context;
        inputs = saved.inputs; outputs = saved.outputs; body = network.graph} in
      let definition : Document.definition = {
        spec; layout = network.layout; displayed = network.displayed} in
      Ok (Document.String_map.add saved.name definition definitions))
    (Ok Document.String_map.empty) definitions in
  let* active_camera = match active_camera with
    | Some id when Edit_graph.find scene_network.graph.geometry ~node_id:id = None ->
        Error "preset active camera is missing"
    | value -> Ok value in
  let doc = { Document.scene = scene_network; networks;
    definitions; compiled_ids;
    active_camera; settings } in
  let* () = Document.validate doc in
  let* () = Flow_sop.Instance_path.Map.fold (fun _ id result ->
    let* () = result in Node.Private.reserve_id id)
    compiled_ids (Ok ()) in
  Ok { doc; view }
