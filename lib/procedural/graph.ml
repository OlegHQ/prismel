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
}

let inspect root =
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
      } :: !result
    end
  in
  visit root;
  List.rev !result

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
