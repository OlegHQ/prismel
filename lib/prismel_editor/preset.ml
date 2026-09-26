open Procedural

type loaded = {
  doc : Document.t;
  view : Yojson.Safe.t;
}

let version = 2  (* 1: one SOP network, migrated on load *)

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
  | `Assoc ["float", `Float value] -> Ok (Float_value value)
  | `Assoc ["float", `Int value] -> Ok (Float_value (float_of_int value))
  | `Assoc ["text", `String value] -> Ok (Text_value value)
  | `Assoc ["choice", `String value] -> Ok (Choice_value value)
  | json -> Error ("unreadable parameter value " ^ Yojson.Safe.to_string json)

let optional_int = function Some value -> `Int value | None -> `Null

let network_json (network : Document.network) =
  let position id = Option.value ~default:(0., 0.)
      (Document.Layout.find_opt id network.layout) in
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
          "x", `Float x; "y", `Float y ]) in
  `Assoc [ "nodes", `List (List.map node (Edit_graph.inspect network.graph));
           "display", `Int network.displayed ]

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
}

let ( let* ) = Result.bind

let rec all = function
  | [] -> Ok []
  | Ok value :: rest -> Result.map (fun rest -> value :: rest) (all rest)
  | Error message :: _ -> Error message

let number = function
  | `Float value -> Ok value | `Int value -> Ok (float_of_int value)
  | _ -> Error "expected a number"

let saved_node : Yojson.Safe.t -> (saved, string) result = function
  | `Assoc fields ->
      let field name = List.assoc_opt name fields in
      let* id = match field "id" with Some (`Int id) -> Ok id | _ -> Error "node without id" in
      let factory_key = match field "factory_key" with Some (`String key) -> Some key | _ -> None in
      let label = match field "label" with Some (`String label) -> label | _ -> "" in
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
        | _ -> Ok [] in
      let* x = Option.fold ~none:(Ok 0.) ~some:number (field "x") in
      let* y = Option.fold ~none:(Ok 0.) ~some:number (field "y") in
      Ok { id; factory_key; label; inputs; params; x; y }
  | _ -> Error "node is not an object"

let nodes_of = function
  | Some (`List nodes) -> all (List.map saved_node nodes)
  | _ -> Error "preset has no nodes"

let optional_of = function Some (`Int id) -> Some id | _ -> None

let network_of = function
  | `Assoc fields ->
      Result.map (fun nodes -> nodes, optional_of (List.assoc_opt "display" fields))
        (nodes_of (List.assoc_opt "nodes" fields))
  | _ -> Error "preset network is not an object"

type decoded =
  | Single of saved list * int option  (* version 1 *)
  | Scene of { scene : saved list * int option;
               networks : (int * (saved list * int option)) list }

let decode path = match Yojson.Safe.from_file path with
  | exception Yojson.Json_error message -> Error ("corrupt preset: " ^ message)
  | exception Sys_error message -> Error message
  | `Assoc fields ->
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
      let* decoded = match field "version" with
        | Some (`Int 1) ->
            Result.map (fun nodes -> Single (nodes, optional_of (field "display")))
              (nodes_of (field "nodes"))
        | Some (`Int 2) ->
            let* scene = network_of (Option.value ~default:`Null (field "scene")) in
            let* networks = match field "networks" with
              | Some (`List entries) -> all (List.map (function
                  | `Assoc entry ->
                      (match List.assoc_opt "object" entry, List.assoc_opt "network" entry with
                       | Some (`Int id), Some network ->
                           Result.map (fun network -> id, network) (network_of network)
                       | _ -> Error "preset network has no object")
                  | _ -> Error "preset network entry is not an object") entries)
              | _ -> Ok [] in
            Ok (Scene { scene; networks })
        | Some (`Int v) -> Error (Printf.sprintf "unsupported preset version %d" v)
        | _ -> Error "preset has no version" in
      let* settings = match field "settings" with
        | None -> Ok []
        | Some (`List entries) -> all (List.map (function
            | `List [ `String name; value ] ->
                Result.map (fun value -> name, value) (value_of_json value)
            | _ -> Error "unreadable preset setting") entries)
        | Some _ -> Error "preset settings are not a list" in
      Ok (decoded, optional_of (field "active_camera"), settings, view)
  | _ -> Error "corrupt preset: not an object"

(* Rebuild one network: catalog nodes are recreated with fresh ids, code
   nodes rebind by id. Returns the network and the old-to-new id map. *)
let rebuild ~code ~factories (nodes, display) =
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
  let* document, mapping = List.fold_left (fun state (node : saved) ->
    let* document, mapping = state in
    match node.factory_key with
    | Some key ->
        (match Hashtbl.find_opt factories_by_key key with
         | None -> Error (Printf.sprintf "preset node %S uses unknown node type %S" node.label key)
         | Some factory ->
             let arity = Edit_graph.factory_arity factory in
             let* created = Edit_graph.instantiate_optional factory (List.init arity (fun _ -> None)) in
             let* document = Edit_graph.add_node ~factory
                 ~inputs:(Array.make arity None) (Node.relabel node.label created) document in
             Ok (document, (node.id, Node.id created) :: mapping))
    | None ->
        (match Edit_graph.find document ~node_id:node.id with
         | Some code_node when Node.label code_node <> node.label && node.label <> "" ->
             Result.map (fun document -> document, (node.id, node.id) :: mapping)
               (Edit_graph.replace_node (Node.relabel node.label code_node) document)
         | Some _ -> Ok (document, (node.id, node.id) :: mapping)
         | None -> Error (Printf.sprintf
             "preset node %S (#%d) is not in this sketch's code graph" node.label node.id)))
    (Ok (base, [])) nodes in
  let target id = match List.assoc_opt id mapping with
    | Some id -> Ok id | None -> Error (Printf.sprintf "preset references missing node #%d" id) in
  let* document = List.fold_left (fun state (node : saved) ->
    let* document = state in
    let* consumer = target node.id in
    List.fold_left (fun state (input_index, input) ->
      let* document = state in
      let current = Option.value ~default:[||] (Edit_graph.inputs document ~node_id:consumer) in
      match input with
      | Some source ->
          let* source = target source in
          Edit_graph.connect ~source ~consumer ~input_index document
      | None when input_index < Array.length current && current.(input_index) <> None ->
          Edit_graph.disconnect ~consumer ~input_index document
      | None -> Ok document)
      (Ok document) (List.mapi (fun index input -> index, input) node.inputs))
    (Ok document) nodes in
  let* document = List.fold_left (fun state (node : saved) ->
    let* document = state in
    let* node_id = target node.id in
    if node.params = [] then Ok document
    else Result.map fst (Edit_graph.apply_parameters document ~node_id node.params))
    (Ok document) nodes in
  let* displayed = match display with
    | Some id -> target id
    | None -> (match List.rev mapping with (_, id) :: _ -> Ok id
      | [] -> Error "preset network has no nodes") in
  let* document = Edit_graph.set_root displayed document in
  let layout = List.fold_left (fun layout (node : saved) ->
      match List.assoc_opt node.id mapping with
      | Some id -> Document.Layout.add id (node.x, node.y) layout
      | None -> layout) Document.Layout.empty nodes in
  Ok ({ Document.graph = document; layout; displayed }, mapping)

let load ~path ~code ~factories ~settings =
  let* decoded, active_camera, values, view = decode path in
  let code = Edit_graph.of_graph code in
  let* settings = Result.map fst (Settings.apply settings values) in
  let* doc = match decoded with
    | Single (nodes, display) ->
        (* Version 1: the one network is geo1; camera SOPs become objects. *)
        let* network, mapping = rebuild ~code
            ~factories:(Objects.Camera.factory :: factories) (nodes, display) in
        let cameras = List.filter (fun (info : Edit_graph.node_info) ->
            info.operation = "camera") (Edit_graph.inspect network.graph) in
        let sop = Edit_graph.remove_nodes (List.map (fun (info : Edit_graph.node_info) ->
            info.id) cameras) network.graph in
        let* geometry = Edit_graph.instantiate_optional Objects.Geometry.factory [None] in
        let geometry = Node.relabel "geo1" geometry in
        let* scene = Edit_graph.add_node ~factory:Objects.Geometry.factory
            ~inputs:[|None|] geometry Edit_graph.empty in
        let* scene = List.fold_left (fun state (info : Edit_graph.node_info) ->
            let* scene = state in
            let factory = match Edit_graph.node_factory_key network.graph ~node_id:info.id with
              | Some _ -> Some Objects.Camera.factory | None -> None in
            Edit_graph.add_node ?factory info.node scene) (Ok scene) cameras in
        let displayed = if List.exists (fun (info : Edit_graph.node_info) ->
            info.id = network.displayed) cameras
          then Option.value ~default:network.displayed (Edit_graph.root sop)
          else network.displayed in
        let active_camera = Option.bind active_camera (fun id -> List.assoc_opt id mapping) in
        Ok { Document.scene = { graph = scene; layout = Document.Layout.empty;
               displayed = Node.id geometry };
             networks = Document.Layout.singleton (Node.id geometry)
               { network with graph = sop; displayed };
             active_camera; settings }
    | Scene { scene; networks } ->
        let* scene_network, mapping = rebuild ~code
            ~factories:(Objects.catalog @ [Layers.Settings.factory]) scene in
        let* networks = List.fold_left (fun state (old_id, saved) ->
            let* networks = state in
            match List.assoc_opt old_id mapping with
            | None -> Ok networks
            | Some id ->
                let factories = match Option.map Node.operation
                    (Edit_graph.find scene_network.graph ~node_id:id) with
                  | Some "world" -> Layers.catalog
                  | _ -> factories in
                let* network, _ = rebuild ~code ~factories saved in
                Ok (Document.Layout.add id network networks))
            (Ok Document.Layout.empty) networks in
        Ok { Document.scene = scene_network; networks;
             active_camera = Option.bind active_camera (fun id -> List.assoc_opt id mapping);
             settings } in
  Ok { doc; view }
