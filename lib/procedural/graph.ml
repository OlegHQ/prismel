type t = Node.t

type info = {
  id : int;
  label : string;
  operation : string;
  version : int;
  parameters : string;
  cook_mode : Node.cook_mode;
  dependencies : Context.Dependencies.t;
  input_ids : int list;
  has_parameters : bool;
}

let inspect_uncached root =
  let seen = Hashtbl.create 32 and result = ref [] in
  let rec visit node =
    if not (Hashtbl.mem seen (Node.id node)) then begin
      Hashtbl.add seen (Node.id node) ();
      List.iter visit (Node.inputs node);
      result := {
        id = Node.id node;
        label = Node.label node;
        operation = Node.operation node;
        version = Node.version node;
        parameters = Node.parameters node;
        cook_mode = Node.cook_mode node;
        dependencies = Node.dependencies node;
        input_ids = List.map Node.id (Node.inputs node);
        has_parameters = Node.has_parameters node;
      } :: !result
    end
  in
  visit root;
  List.rev !result

type inspection_cache_entry={root:t Weak.t;infos:info list;bytes:int}
let inspection_cache_capacity=64
let inspection_cache_byte_capacity=8*1024*1024
let inspection_caches=Domain.DLS.new_key(fun()->ref[])

let inspection_bytes infos=
  List.fold_left(fun bytes info->bytes+96+String.length info.label+
    String.length info.operation+String.length info.parameters+
    (16*List.length info.input_ids))0 infos

let rec find_inspection root=function
  |[]->None
  |entry::rest->match Weak.get entry.root 0 with
    |Some cached when cached==root->Some entry.infos
    |None|Some _->find_inspection root rest

let trim_inspections entries=
  let rec loop count bytes kept=function
    |[]->List.rev kept
    |entry::rest when Weak.check entry.root 0&&
        count<inspection_cache_capacity&&
        entry.bytes<=inspection_cache_byte_capacity-bytes->
        loop(count+1)(bytes+entry.bytes)(entry::kept)rest
    |_::rest->loop count bytes kept rest in
  loop 0 0[]entries

let inspect root=
  let cache=Domain.DLS.get inspection_caches in
  match find_inspection root!cache with
  |Some infos->infos
  |None->
      let infos=inspect_uncached root in
      let weak=Weak.create 1 in
      Weak.set weak 0(Some root);
      cache:=trim_inspections({root=weak;infos;
        bytes=inspection_bytes infos}::!cache);
      infos

let find root ~node_id =
  let seen = Hashtbl.create 32 in
  let rec visit node =
    if Node.id node = node_id then Some node
    else if Hashtbl.mem seen (Node.id node) then None
    else begin
      Hashtbl.add seen (Node.id node) ();
      let rec visit_inputs = function
        | [] -> None
        | input :: rest ->
            (match visit input with Some _ as found -> found | None -> visit_inputs rest)
      in
      visit_inputs (Node.inputs node)
    end
  in
  visit root

let dependencies root =
  inspect root |> List.fold_left (fun dependencies info ->
    Context.Dependencies.union dependencies info.dependencies)
    Context.Dependencies.static

let apply_parameters root ~node_id changes =
  let memo = Hashtbl.create 32 and found = ref false
  and effects = ref Parameter.no_effects in
  let rec replace node =
    match Hashtbl.find_opt memo (Node.id node) with
    | Some replacement -> Ok replacement
    | None ->
        let original_inputs = Node.Private.input_array node in
        let rec replace_inputs index changed =
          if index = Array.length original_inputs then
            Ok (if changed then
              Node.Private.rebuild_with_inputs node original_inputs else node)
          else
            Result.bind (replace original_inputs.(index)) (fun replacement ->
              let changed = changed || replacement != original_inputs.(index) in
              original_inputs.(index) <- replacement;
              replace_inputs (index + 1) changed)
        in
        Result.bind (replace_inputs 0 false) (fun node ->
          let edited = if Node.id node <> node_id then Ok node
            else begin
              found := true;
              Result.map (fun (node, node_effects) ->
                effects := Parameter.union_effects !effects node_effects;
                node) (Node.apply_parameters node changes)
            end
          in
          Result.map (fun replacement ->
            Hashtbl.add memo (Node.id node) replacement;
            replacement) edited)
  in
  Result.bind (replace root) (fun root ->
    if !found then Ok (root, !effects)
    else Error (Printf.sprintf "procedural graph has no node #%d" node_id))

let cook_mode_name = function
  | Node.Generator -> "generator"
  | Node.Duplicate_input index -> Printf.sprintf "duplicate(%d)" index
  | Node.In_place index -> Printf.sprintf "in_place(%d)" index
  | Node.Instance_input index -> Printf.sprintf "instance(%d)" index
  | Node.Passthrough index -> Printf.sprintf "passthrough(%d)" index
  | Node.Generic -> "generic"

let format root =
  let line info =
    Printf.sprintf "#%d %s [%s v%d; %s; deps=%s]%s"
      info.id info.label info.operation info.version
      (cook_mode_name info.cook_mode)
      (Context.Dependencies.to_string info.dependencies)
      (if info.parameters = "" then "" else " " ^ info.parameters)
  in
  inspect root |> List.map line |> String.concat "\n"

let dot_escape value =
  let buffer = Buffer.create (String.length value + 8) in
  String.iter (function
    | '"' -> Buffer.add_string buffer "\\\""
    | '\\' -> Buffer.add_string buffer "\\\\"
    | '\n' -> Buffer.add_string buffer "\\n"
    | character -> Buffer.add_char buffer character) value;
  Buffer.contents buffer

let to_dot root =
  let infos = inspect root in
  let buffer = Buffer.create (128 + (List.length infos * 96)) in
  Buffer.add_string buffer "digraph procedural {\n  rankdir=LR;\n";
  List.iter (fun info ->
    let label = Printf.sprintf "%s\n%s v%d\n%s"
        info.label info.operation info.version
        (Context.Dependencies.to_string info.dependencies) in
    Printf.bprintf buffer "  n%d [label=\"%s\"];\n" info.id (dot_escape label)) infos;
  List.iter (fun info ->
    List.iteri (fun input input_id ->
      Printf.bprintf buffer "  n%d -> n%d [label=\"%d\"];\n"
        input_id info.id input) info.input_ids) infos;
  Buffer.add_string buffer "}\n";
  Buffer.contents buffer
