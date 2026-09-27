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

let network_json (network : Document.network) =
  let position id = Option.value ~default:(0., 0.)
      (Document.Layout.find_opt id network.layout.at) in
  let node (info : Edit_graph.node_info) =
    let x, y = position info.id in
    `Assoc ([ "id", `Int info.id ]
      @ (match Edit_graph.node_factory_key network.graph ~node_id:info.id with
        | Some key -> [ "factory_key", `String key ] | None -> [])
      @ [ "label", `String info.label;
          "inputs", `List (Array.to_list (Array.map optional_int info.inputs));
          "params", `List (List.map (fun (field : Parameter.field_view) ->
            `List [ `String field.name; value_json field.current ])
            (Node.parameter_fields info.node));
          "x", `Float x; "y", `Float y;
          "level", `String (match Document.Layout.find_opt info.id network.layout.level with
            | Some Layout.Point -> "point" | Some Chip -> "chip" | Some Full -> "full"
            | Some Card | None -> "card");
          "pinned", `Bool (Option.value ~default:false
            (Document.Layout.find_opt info.id network.layout.pinned));
          "rows", `Assoc (Option.value ~default:Layout.String_map.empty
            (Document.Layout.find_opt info.id network.layout.rows)
            |> Layout.String_map.bindings |> List.map (fun (name, shown) -> name, `Bool shown));
          "split", `List [] ]) in
  `Assoc [ "nodes", `List (List.map node (Edit_graph.inspect network.graph));
           "display", optional_int network.displayed;
           "geometry_bends", `List (Layout.Port_map.bindings network.layout.bends
             |> List.map (fun ((id, slot), points) -> `Assoc [
               "to", `List [`Int id; `String slot];
               "bends", `List (List.map (fun (x, y) -> `List [`Float x; `Float y]) points)])) ]

let to_sections ~(doc : Document.t) ~view =
  [ "graph", `Assoc [
      "version", `Int version;
      "scene", network_json doc.scene;
      "networks", `List (List.map (fun (id, network) ->
        `Assoc [ "object", `Int id; "network", network_json network ])
        (Document.Layout.bindings doc.networks));
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
}

let rec all = function
  | [] -> Ok []
  | Ok value :: rest -> Result.map (fun rest -> value :: rest) (all rest)
  | Error message :: _ -> Error message

let number = function
  | `Float value when Float.is_finite value -> Ok value
  | `Int value -> Ok (float_of_int value)
  | _ -> Error "expected a finite number"

let saved_node : Yojson.Safe.t -> (saved, string) result = function
  | `Assoc fields ->
      let* () = unique ~what:"node field" (List.map fst fields) in
      let field name = List.assoc_opt name fields in
      let* id = match field "id" with Some (`Int id) -> Ok id | _ -> Error "node without id" in
      let* factory_key = match field "factory_key" with
        | Some (`String key) -> Ok (Some key) | None -> Ok None
        | _ -> Error "invalid factory key" in
      let* label = match field "label" with
        | Some (`String label) -> Ok label | None -> Ok ""
        | _ -> Error "invalid node label" in
      let* inputs = match field "inputs" with
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
      let* () = match field "split" with
        | None | Some (`List []) -> Ok () | _ -> Error "vector splits require value ports" in
      Ok { id; factory_key; label; inputs; params;
        x = Layout.snap x; y = Layout.snap y; level; pinned; rows }
  | _ -> Error "node is not an object"

let nodes_of = function
  | Some (`List nodes) -> all (List.map saved_node nodes)
  | _ -> Error "preset has no nodes"

let optional_of = function
  | Some (`Int id) -> Ok (Some id) | Some `Null | None -> Ok None
  | _ -> Error "expected a node id or null"

let network_of = function
  | `Assoc fields ->
      let* () = unique ~what:"network field" (List.map fst fields) in
      let* nodes = nodes_of (List.assoc_opt "nodes" fields) in
      let* display = optional_of (List.assoc_opt "display" fields) in
      let* bends = match List.assoc_opt "geometry_bends" fields with
        | None -> Ok []
        | Some (`List entries) -> all (List.map (function
            | `Assoc entry ->
                let* () = unique ~what:"bend entry field" (List.map fst entry) in
                let* port = match List.assoc_opt "to" entry with
                  | Some (`List [`Int id; `String slot]) -> Ok (id, slot)
                  | _ -> Error "bend without destination port" in
                let* points = match List.assoc_opt "bends" entry with
                  | Some (`List points) -> all (List.map (function
                      | `List [x; y] -> let* x = number x in let* y = number y in
                          Ok (Layout.snap x, Layout.snap y)
                      | _ -> Error "invalid bend point") points)
                  | _ -> Error "bend points are not a list" in
                Ok (port, points)
            | _ -> Error "invalid bend entry") entries)
        | _ -> Error "geometry bends are not a list" in
      let* () = unique ~what:"bend destination" (List.map fst bends) in
      Ok (nodes, display, bends)
  | _ -> Error "preset network is not an object"

type saved_network = saved list * int option * ((int * string) * (float * float) list) list

type decoded = { scene : saved_network; networks : (int * saved_network) list }

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
            Ok { scene; networks }
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
let rebuild ~code ~factories (nodes, display, bends) =
  let* () = unique ~what:"node id" (List.map (fun node -> node.id) nodes) in
  let ids = Hashtbl.create (List.length nodes) in
  List.iter (fun node -> Hashtbl.add ids node.id ()) nodes;
  let reference id = if Hashtbl.mem ids id then Ok ()
    else Error (Printf.sprintf "preset references missing node #%d" id) in
  let* () = Option.fold ~none:(Ok ()) ~some:reference display in
  let* () = List.fold_left (fun state node ->
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
    if node.params = [] then Ok document
    else Result.map fst (Edit_graph.apply_parameters document ~node_id:node.id node.params))
    (Ok document) nodes in
  let displayed = match display with Some _ -> display | None -> Edit_graph.root document in
  let* document = Option.fold ~none:(Ok document)
    ~some:(fun id -> Edit_graph.set_root id document) displayed in
  let layout = List.fold_left (fun (layout : Layout.t) (node : saved) ->
    { layout with at = Layout.Int_map.add node.id (node.x, node.y) layout.at;
      level = Layout.Int_map.add node.id node.level layout.level;
      pinned = Layout.Int_map.add node.id node.pinned layout.pinned;
      rows = if Layout.String_map.is_empty node.rows then layout.rows
        else Layout.Int_map.add node.id node.rows layout.rows })
      { Layout.empty with bends = Layout.Port_map.of_list bends } nodes in
  Ok { Document.graph = document; layout; displayed }

let load ~path ~code ~factories ~settings =
  let* decoded, active_camera, values, view = decode path in
  let code = Edit_graph.of_graph code in
  let* settings = Result.map fst (Settings.apply settings values) in
  let { scene; networks } = decoded in
  let* scene_network = rebuild ~code
      ~factories:(Objects.catalog @ [Layers.Settings.factory]) scene in
  let* networks = List.fold_left (fun state (id, saved) ->
      let* networks = state in
      let* factories = match Option.map Node.operation
          (Edit_graph.find scene_network.graph ~node_id:id) with
        | Some "world" -> Ok Layers.catalog
        | Some "geometry" -> Ok factories
        | None -> Error (Printf.sprintf "network has missing owner #%d" id)
        | Some _ -> Error (Printf.sprintf "object #%d cannot own a network" id) in
      let* network = rebuild ~code ~factories saved in
      Ok (Document.Layout.add id network networks))
      (Ok Document.Layout.empty) networks in
  let* active_camera = match active_camera with
    | Some id when Edit_graph.find scene_network.graph ~node_id:id = None ->
        Error "preset active camera is missing"
    | value -> Ok value in
  let doc = { Document.scene = scene_network; networks; active_camera; settings } in
  let* () = Document.validate doc in
  Ok { doc; view }
