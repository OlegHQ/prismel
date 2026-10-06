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
    geometry : Rdk.Geometry.t;
    diagnostics : Diagnostic.t list;
    instances : Rays_math.Mat4.t array option;
    (** Packed: [geometry] is a prototype drawn at these transforms. *)
  }
end

type t = {
  id : int;
  label : string;
  operation : string;
  version : int;
  parameters : string;
  parameter_key : string;
  cook_mode : cook_mode;
  dependencies : Context.Dependencies.t;
  input_policy : Private_types.input_policy;
  inputs : t array;
  cook : node_id:int -> Context.t -> Rdk.Geometry.t array ->
    (Private_types.cooked, Diagnostic.error) result;
  expand : (Context.t -> t array -> Rdk.Geometry.t array -> (t array, Diagnostic.error) result) option;
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
let parameter_key value = value.parameter_key
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

let relabel label value =
  if String.trim label = "" then value else { value with label = String.trim label }

let parameterize ~schema ~values ~rebuild value =
  let values = match Parameter.normalize schema values with
    | Ok values -> values
    | Error message -> invalid_arg ("Node.parameterize: " ^ message)
  in
  let rebuild ~label ~inputs values =
    rebuild ~label ~inputs:(Array.to_list inputs) values
  in
  { value with parameter_key = Parameter.cook_key schema values;
               parameterization = Some (Parameters { schema; values; rebuild }) }

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

  let fresh_id = fresh_id

  let reserve_id id =
    if id < 1 || id = max_int then Error "node id is out of range" else
    let rec reserve () =
      let next = Atomic.get next_id in
      if next <= id && not (Atomic.compare_and_set next_id next (id + 1)) then reserve () in
    reserve ();
    Ok ()

  let restore_id id value = Result.map (fun () -> {value with id}) (reserve_id id)

  let make ?label ~operation ~version ~parameters ~cook_mode ~dependencies
      ?(input_policy = All) ?expand ~inputs cook =
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
    { id = fresh_id (); label; operation; version; parameters;
      parameter_key = ""; cook_mode;
      dependencies; input_policy; inputs; cook; expand; parameterization = None }

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
  let adopt_identity ~source value =
    { value with id = source.id; label = source.label }
  let cook value context inputs = value.cook ~node_id:value.id context inputs
  let expand value = value.expand
end
