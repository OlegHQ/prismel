type stage = Vertex | Fragment | Compute
type kind = Buffer | Texture | Sampler | Acceleration_structure
type layout_entry = { binding : int; kind : kind; visibility : stage list }
type layout = layout_entry list
type pipeline_layout =
  { device : Handle.device; capabilities : Capabilities.t; groups : (int * layout) list }
type resource = Resource : kind * 'a Handle.t -> resource
type group_entry = { binding : int; resource : resource }
type bind_group =
  { owner : Handle.device; group : int; entries : group_entry list }
type resource_snapshot = { binding : int; kind : kind; id : int64 }

let invalid operation message = Error (Error.make operation Error.Invalid_argument message)
let stale operation message = Error (Error.make operation Error.Stale_handle message)
let compare_layout (left : layout_entry) (right : layout_entry) = Int.compare left.binding right.binding
let compare_group (left : group_entry) (right : group_entry) = Int.compare left.binding right.binding

let create_layout entries =
  let entries = List.sort compare_layout entries in
  let rec validate previous (remaining : layout_entry list) = match remaining with
    | [] -> Ok entries
    | value :: _ when value.binding < 0 -> invalid "Ogpu.Binding.create_layout" "binding is negative"
    | value :: _ when value.visibility = [] -> invalid "Ogpu.Binding.create_layout" "visibility is empty"
    | value :: _ when List.sort_uniq compare value.visibility <> value.visibility ->
        invalid "Ogpu.Binding.create_layout" "visibility must be sorted and unique"
    | value :: _ when previous = Some value.binding ->
        invalid "Ogpu.Binding.create_layout" "duplicate binding"
    | value :: rest -> validate (Some value.binding) rest
  in
  validate None entries

let layout_entries value = value

let create_pipeline_layout ~device ~capabilities groups =
  if Handle.device_destroyed device then stale "Ogpu.Binding.create_pipeline_layout" "device is destroyed"
  else
    let groups = List.sort (fun (left, _) (right, _) -> Int.compare left right) groups in
    if List.length groups > capabilities.Capabilities.limits.max_bind_groups then
      Error (Error.make "Ogpu.Binding.create_pipeline_layout" Error.Capacity "bind-group limit exceeded")
    else
      let rec validate expected = function
        | [] -> Ok { device; capabilities; groups }
        | (group, _) :: _ when group <> expected ->
            invalid "Ogpu.Binding.create_pipeline_layout" "groups must be contiguous from zero"
        | _ :: rest -> validate (expected + 1) rest
      in
      validate 0 groups

let pipeline_layouts value = List.map (fun (group, layout) -> group, layout) value.groups
let buffer handle = Resource (Buffer, handle)
let texture handle = Resource (Texture, handle)
let sampler handle = Resource (Sampler, handle)
let acceleration_structure handle = Resource (Acceleration_structure, handle)

let find_group value group = List.assoc_opt group value.groups

let create_group pipeline ~group entries =
  if Handle.device_destroyed pipeline.device then stale "Ogpu.Binding.create_group" "device is destroyed"
  else
    match find_group pipeline group with
    | None -> invalid "Ogpu.Binding.create_group" "group is absent from pipeline layout"
    | Some expected ->
        let entries = List.sort compare_group entries in
        let rec validate (expected : layout_entry list) (actual : group_entry list) =
          match expected, actual with
          | [], [] -> Ok { owner = pipeline.device; group; entries }
          | [], _ :: _ -> invalid "Ogpu.Binding.create_group" "unexpected binding"
          | _ :: _, [] -> invalid "Ogpu.Binding.create_group" "missing binding"
          | expected :: _, actual :: _ when expected.binding <> actual.binding ->
              invalid "Ogpu.Binding.create_group" "missing or unexpected binding"
          | expected :: expected_rest, actual :: actual_rest ->
              let Resource (kind, handle) = actual.resource in
              if kind <> expected.kind then invalid "Ogpu.Binding.create_group" "binding type mismatch"
              else if kind = Acceleration_structure && not pipeline.capabilities.ray_tracing then
                invalid "Ogpu.Binding.create_group" "acceleration structures are unsupported"
              else
                match Handle.validate_for ~operation:"Ogpu.Binding.create_group" pipeline.device handle with
                | Error _ as error -> error
                | Ok () -> validate expected_rest actual_rest
        in
        validate expected entries

let group_entries (value : bind_group) =
  List.map
    (fun (entry : group_entry) ->
      let Resource (kind, handle) = entry.resource in
      { binding = entry.binding; kind; id = Handle.id handle })
    value.entries

let validate_group (pipeline : pipeline_layout) (value : bind_group) =
  if Handle.device_id pipeline.device <> Handle.device_id value.owner then
    Error (Error.make "Ogpu.Binding.validate_group" Error.Cross_device "bind group belongs to another device")
  else
    match find_group pipeline value.group with
    | None -> invalid "Ogpu.Binding.validate_group" "group is absent from pipeline layout"
    | Some _ ->
        let rec loop = function
          | [] -> Ok ()
          | (entry : group_entry) :: rest ->
              let Resource (_, handle) = entry.resource in
              match Handle.validate_for ~operation:"Ogpu.Binding.validate_group" pipeline.device handle with
              | Error _ as error -> error | Ok () -> loop rest
        in
        loop value.entries
