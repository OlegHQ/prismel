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
        has_parameters = Node.has_parameters node;
      } :: !result
    end
  in
  visit root;
  List.rev !result

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

