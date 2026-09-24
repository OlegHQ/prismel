type resource_kind = Buffer | Texture | Sampler | Render_pipeline | Compute_pipeline | Indirect_command_buffer
type resource = { token : int; device : int; kind : resource_kind; destroyed : bool }
type range = { location : int; length : int }
type retained = resource option array

let callable_ids = Binding_argument_encoder_handoff.callable_ids

let allowed expected resource = resource.kind = expected

let validate_resource ~device ~expected = function
  | None -> Ok None
  | Some resource when resource.destroyed -> Error "destroyed argument resource"
  | Some resource when resource.device <> device -> Error "argument resource belongs to another device"
  | Some resource when not (allowed expected resource) -> Error "wrong argument resource kind"
  | Some resource -> Ok (Some resource)

let validate_array ~capacity ~device ~expected ~range resources =
  if range.location < 0 || range.length < 0 || range.location > capacity
     || range.length > capacity - range.location
  then Error "argument binding range is out of bounds"
  else if Array.length resources <> range.length then Error "argument array/range cardinality mismatch"
  else
    let copy = Array.copy resources in
    let rec loop index =
      if index = Array.length copy then Ok copy
      else match validate_resource ~device ~expected copy.(index) with
        | Error error -> Error error
        | Ok value -> copy.(index) <- value; loop (index + 1)
    in loop 0

let replace_atomic retained ~range replacements =
  if range.location < 0 || range.length <> Array.length replacements
     || range.location > Array.length retained
     || range.length > Array.length retained - range.location
  then Error "argument retained replacement range is invalid"
  else
    let next = Array.copy retained in
    Array.blit replacements 0 next range.location range.length;
    Ok next

type encoder = { token : int; device : int; parent : encoder option; mutable destroyed : bool }

let nested ~parent ~token =
  if parent.destroyed then Error "destroyed parent argument encoder"
  else if token < 0 then Error "negative nested argument index"
  else Ok { token; device = parent.device; parent = Some parent; destroyed = false }

type constant_policy = Availability_only
let constant_policy = Availability_only

let validate_handoff () =
  let items = callable_ids |> List.map (fun id ->
    Binding_argument_encoder_handoff.classify
      ~kind:(if String.starts_with ~prefix:"property:" id then "property" else "method") id) in
  let count lane = List.length (List.filter (fun (item : Binding_argument_encoder_handoff.item) -> item.lane = lane) items) in
  if List.length callable_ids <> 32
     || count Binding_argument_encoder_handoff.Mechanical <> 4
     || count Binding_argument_encoder_handoff.Ownership <> 28
  then invalid_arg "ArgumentEncoder callable32 drift"
