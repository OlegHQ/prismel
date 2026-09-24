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
  parameterization : parameterization option;
}
and parameterization = Parameters : {
  schema : 'parameters Parameter.schema;
  values : 'parameters;
  rebuild : label:string -> inputs:t array -> 'parameters -> t;
} -> parameterization

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

let parameter_fields value = match value.parameterization with
  | None -> []
  | Some (Parameters parameterization) ->
      Parameter.view parameterization.schema parameterization.values

let has_parameters value = Option.is_some value.parameterization

let parameterize ~schema ~values ~rebuild value =
  let values = match Parameter.normalize schema values with
    | Ok values -> values
    | Error message -> invalid_arg ("Node.parameterize: " ^ message)
  in
  let rebuild ~label ~inputs values =
    rebuild ~label ~inputs:(Array.to_list inputs) values
  in
  { value with parameterization = Some (Parameters { schema; values; rebuild }) }

let apply_parameters value changes = match value.parameterization with
  | None when changes = [] -> Ok (value, Parameter.no_effects)
  | None -> Error (Printf.sprintf "node %S has no exposed parameters" value.label)
  | Some (Parameters parameterization) ->
      Result.map (fun (values, effects) ->
        if not (Parameter.has_effects effects) then value, effects
        else if effects.cook then
          let rebuilt = parameterization.rebuild ~label:value.label
              ~inputs:(Array.copy value.inputs) values in
          { rebuilt with id = value.id }, effects
        else
          { value with parameterization = Some (Parameters {
              parameterization with values }) }, effects)
        (Parameter.apply_all parameterization.schema parameterization.values changes)

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
      dependencies; input_policy; inputs; cook; parameterization = None }

  let input_policy value = value.input_policy
  let input_array value = Array.copy value.inputs
  let with_inputs value inputs =
    let inputs = Array.copy inputs in
    (match value.input_policy with
     | All -> ()
     | Only index when index >= 0 && index < Array.length inputs -> ()
    | Only _ -> invalid_arg "Node.with_inputs: selected input is out of bounds");
    { value with inputs }
  let rebuild_with_inputs value inputs =
    let inputs = Array.copy inputs in
    match value.parameterization with
    | None -> with_inputs value inputs
    | Some (Parameters parameterization) ->
        let rebuilt = parameterization.rebuild ~label:value.label
            ~inputs parameterization.values in
        { rebuilt with id = value.id }
  let clone_with_inputs value inputs =
    let inputs = Array.copy inputs in
    match value.parameterization with
    | None -> { value with id = fresh_id (); inputs }
    | Some (Parameters parameterization) ->
        parameterization.rebuild ~label:value.label
          ~inputs parameterization.values
  let adopt_identity ~source value =
    { value with id = source.id; label = source.label }
  let cook value context inputs = value.cook ~node_id:value.id context inputs
end
