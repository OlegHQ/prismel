type cook_mode =
  | Generator
  | Duplicate_input of int
  | In_place of int
  | Instance_input of int
  | Passthrough of int
  | Generic

module Private_types = struct
  type input_policy = All | Only of int
  type cooked = {
    geometry : Pdk.Geometry.t;
    diagnostics : Diagnostic.t list;
  }
end

type t = {
  id : int;
  label : string;
  operation : string;
  version : int;
  parameters : string;
  cook_mode : cook_mode;
  dependencies : Context.Dependencies.t;
  input_policy : Private_types.input_policy;
  inputs : t array;
  cook : node_id:int -> Context.t -> Pdk.Geometry.t array ->
    (Private_types.cooked, Diagnostic.error) result;
}

let next_id = Atomic.make 1
let fresh_id () = Atomic.fetch_and_add next_id 1

let id value = value.id
let label value = value.label
let operation value = value.operation
let version value = value.version
let parameters value = value.parameters
let cook_mode value = value.cook_mode
let dependencies value = value.dependencies
let inputs value = Array.to_list value.inputs
let trace value = Diagnostic.{ node_id = value.id; label = value.label;
                               operation = value.operation }

module Private = struct
  include Private_types

  let make ?label ~operation ~version ~parameters ~cook_mode ~dependencies
      ?(input_policy = All) ~inputs cook =
    if version < 0 then invalid_arg "Node.make: version must be non-negative";
    if String.trim operation = "" then invalid_arg "Node.make: empty operation";
    let label = match label with
      | None -> operation
      | Some label when String.trim label = "" -> operation
      | Some label -> label
    in
    let inputs = Array.copy inputs in
    (match input_policy with
     | All -> ()
     | Only index when index >= 0 && index < Array.length inputs -> ()
     | Only _ -> invalid_arg "Node.make: selected input is out of bounds");
    { id = fresh_id (); label; operation; version; parameters; cook_mode;
      dependencies; input_policy; inputs; cook }

  let input_policy value = value.input_policy
  let input_array value = Array.copy value.inputs
  let cook value context inputs = value.cook ~node_id:value.id context inputs
end
