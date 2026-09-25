open Procedural

type loaded = {
  document : Edit_graph.t;
  positions : (int * float * float) list;
  display : int option;
  active_camera : int option;
  view : Yojson.Safe.t;
}

let version = 1

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

let to_json ~sketch ~document ~positions ~display ~active_camera ~view =
  let positions_by_id = Hashtbl.create (List.length positions) in
  List.iter (fun (id, x, y) ->
    if not (Hashtbl.mem positions_by_id id) then
      Hashtbl.add positions_by_id id (x, y)) positions;
  let position id = Option.value ~default:(0., 0.)
      (Hashtbl.find_opt positions_by_id id) in
  let node (info : Edit_graph.node_info) =
    let x, y = position info.id in
    `Assoc ([ "id", `Int info.id ]
      @ (match Edit_graph.node_factory_key document ~node_id:info.id with
        | Some key -> [ "factory_key", `String key ] | None -> [])
      @ [ "label", `String info.label;
          "inputs", `List (Array.to_list (Array.map optional_int info.inputs));
          "params", `List (List.map (fun (field : Parameter.field_view) ->
            `List [ `String field.name; value_json field.current ])
            (Node.parameter_fields info.node));
          "x", `Float x; "y", `Float y ]) in
  (* The shared Prismel save envelope ("prismel"/"kind"), so presets stay
     loadable when settings join the same format. *)
  `Assoc [ "prismel", `Int 1; "kind", `String "preset";
           "version", `Int version; "sketch", `String sketch;
           "nodes", `List (List.map node (Edit_graph.inspect document));
           "display", optional_int display; "active_camera", optional_int active_camera;
           "view", view ]

let rec mkdir_p directory =
  if not (Sys.file_exists directory) then begin
    mkdir_p (Filename.dirname directory);
    try Unix.mkdir directory 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

(* Written to a temporary file and renamed, so a crash never leaves a torn
   preset behind. *)
let save ~directory ~name ~sketch ~document ~positions ~display ~active_camera ~view =
  if sanitize name = "" then Error "preset name is empty" else
  let target = path ~directory ~name in
  try
    mkdir_p directory;
    let temporary = target ^ ".tmp" in
    Yojson.Safe.to_file temporary
      (to_json ~sketch ~document ~positions ~display ~active_camera ~view);
    Sys.rename temporary target;
    Ok target
  with Sys_error message | Unix.Unix_error (_, _, message) -> Error message

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

let decode path = match Yojson.Safe.from_file path with
  | exception Yojson.Json_error message -> Error ("corrupt preset: " ^ message)
  | exception Sys_error message -> Error message
  | `Assoc fields ->
      let field name = List.assoc_opt name fields in
      let* () = match field "version" with
        | Some (`Int v) when v = version -> Ok ()
        | Some (`Int v) -> Error (Printf.sprintf "unsupported preset version %d" v)
        | _ -> Error "preset has no version" in
      let* nodes = match field "nodes" with
        | Some (`List nodes) -> all (List.map saved_node nodes)
        | _ -> Error "preset has no nodes" in
      let optional name = match field name with Some (`Int id) -> Some id | _ -> None in
      Ok (nodes, optional "display", optional "active_camera",
          Option.value ~default:`Null (field "view"))
  | _ -> Error "corrupt preset: not an object"

let load ~path ~code ~factories =
  let* nodes, display, active_camera, view = decode path in
  let code_document = Edit_graph.of_graph code in
  let factories_by_key = Hashtbl.create (List.length factories) in
  List.iter (fun factory ->
    let key = Edit_graph.factory_key factory in
    if not (Hashtbl.mem factories_by_key key) then
      Hashtbl.add factories_by_key key factory) factories;
  (* Catalog nodes are recreated with fresh ids; code nodes rebind by id. *)
  let* document, mapping = List.fold_left (fun state (node : saved) ->
    let* document, mapping = state in
    match node.factory_key with
    | Some key ->
        (match Hashtbl.find_opt factories_by_key key with
         | None -> Error (Printf.sprintf "preset node %S uses unknown SOP %S" node.label key)
         | Some factory ->
             let arity = Edit_graph.factory_arity factory in
             let* created = Edit_graph.instantiate_optional factory (List.init arity (fun _ -> None)) in
             let* document = Edit_graph.add_node ~factory
                 ~inputs:(Array.make arity None) created document in
             Ok (document, (node.id, Node.id created) :: mapping))
    | None when Edit_graph.find code_document ~node_id:node.id <> None ->
        Ok (document, (node.id, node.id) :: mapping)
    | None -> Error (Printf.sprintf
        "preset node %S (#%d) is not in this sketch's code graph" node.label node.id))
    (Ok (code_document, [])) nodes in
  let mapping_by_id = Hashtbl.create (List.length mapping) in
  let kept = Hashtbl.create (List.length mapping) in
  List.iter (fun (old_id, new_id) ->
    if not (Hashtbl.mem mapping_by_id old_id) then
      Hashtbl.add mapping_by_id old_id new_id;
    Hashtbl.replace kept new_id ()) mapping;
  let target id = match Hashtbl.find_opt mapping_by_id id with
    | Some id -> Ok id | None -> Error (Printf.sprintf "preset references missing node #%d" id) in
  let document = Edit_graph.remove_nodes (Edit_graph.inspect document
    |> List.filter_map (fun (info : Edit_graph.node_info) ->
      if Hashtbl.mem kept info.id then None else Some info.id)) document in
  let* document = List.fold_left (fun state (node : saved) ->
    let* document = state in
    let* consumer = target node.id in
    let current = Option.value ~default:[||] (Edit_graph.inputs document ~node_id:consumer) in
    List.fold_left (fun state (input_index, input) ->
      let* document = state in
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
  let* display = match display with
    | None -> Ok None | Some id -> Result.map Option.some (target id) in
  let* document = match display with
    | None -> Ok document | Some id -> Edit_graph.set_root id document in
  let* active_camera = match active_camera with
    | None -> Ok None | Some id -> Result.map Option.some (target id) in
  let* positions = all (List.map (fun (node : saved) ->
    Result.map (fun id -> id, node.x, node.y) (target node.id)) nodes) in
  Ok { document; positions; display; active_camera; view }
