type owned = { token : int; device : int; destroyed : bool }
type buffer = { owned : owned; length : int }
type buffer_range = { buffer : buffer; offset : int; length : int }
type acceleration_structure = { owned : owned }
type as_descriptor = { owned : owned; primitive_count : int }
type tensor = { owned : owned; dimensions : int array }
type state = Active | Ended | Completed
type t = { device : int; mutable state : state; mutable retained : int list; mutable destroyed : bool }

let callable_ids =
  [ "method:-[MTL4ComputeCommandEncoder buildAccelerationStructure:descriptor:scratchBuffer:]"
  ; "method:-[MTL4ComputeCommandEncoder copyFromTensor:sourceOrigin:sourceDimensions:toTensor:destinationOrigin:destinationDimensions:]"
  ; "method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:]"
  ; "method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:options:]"
  ; "method:-[MTL4ComputeCommandEncoder writeCompactedAccelerationStructureSize:toBuffer:]" ]

let create ~available ~device =
  if not available then Error "MTL4 compute encoders require macOS 26"
  else Ok { device; state = Active; retained = []; destroyed = false }

let validate_owned (encoder : t) label (owned : owned) =
  if encoder.destroyed then Error "destroyed MTL4 compute encoder"
  else if encoder.state <> Active then Error "MTL4 compute encoder is not active"
  else if owned.destroyed then Error ("destroyed " ^ label)
  else if owned.device <> encoder.device then Error (label ^ " belongs to another device")
  else Ok ()

let validate_range (encoder : t) (range : buffer_range) =
  match validate_owned encoder "MTL4 buffer" range.buffer.owned with
  | Error error -> Error error
  | Ok () ->
      if range.offset < 0 || range.length <= 0 || range.offset > range.buffer.length
         || range.length > range.buffer.length - range.offset then Error "MTL4 buffer range out of bounds"
      else Ok ()

let retain encoder tokens = encoder.retained <- tokens @ encoder.retained

let build encoder ~(destination : acceleration_structure) ~(descriptor : as_descriptor) ~(scratch : buffer_range) =
  match validate_owned encoder "acceleration structure" destination.owned,
        validate_owned encoder "acceleration descriptor" descriptor.owned,
        validate_range encoder scratch with
  | Error error, _, _ | _, Error error, _ | _, _, Error error -> Error error
  | Ok (), Ok (), Ok () ->
      if descriptor.primitive_count <= 0 || descriptor.primitive_count > scratch.length / 64 then
        Error "acceleration build scratch/cardinality mismatch"
      else begin retain encoder [ destination.owned.token; descriptor.owned.token; scratch.buffer.owned.token ]; Ok () end

let refit encoder ~(source : acceleration_structure) ~(descriptor : as_descriptor)
    ~(destination : acceleration_structure option) ~(scratch : buffer_range) ~options =
  let destination_validation = match destination with
    | None -> Ok () | Some value -> validate_owned encoder "destination acceleration structure" value.owned in
  match validate_owned encoder "source acceleration structure" source.owned,
        validate_owned encoder "acceleration descriptor" descriptor.owned,
        destination_validation, validate_range encoder scratch with
  | Error error, _, _, _ | _, Error error, _, _ | _, _, Error error, _ | _, _, _, Error error -> Error error
  | Ok (), Ok (), Ok (), Ok () ->
      if options < 0 || options land lnot 0x3 <> 0 then Error "invalid acceleration refit options"
      else if descriptor.primitive_count <= 0 || descriptor.primitive_count > scratch.length / 32 then
        Error "acceleration refit scratch/cardinality mismatch"
      else
        let tokens = source.owned.token :: descriptor.owned.token :: scratch.buffer.owned.token ::
          (match destination with None -> [] | Some value -> [ value.owned.token ]) in
        retain encoder tokens; Ok ()

let write_compacted_size encoder (acceleration : acceleration_structure) (range : buffer_range) =
  match validate_owned encoder "acceleration structure" acceleration.owned, validate_range encoder range with
  | Error error, _ | _, Error error -> Error error
  | Ok (), Ok () ->
      if range.offset mod 8 <> 0 || range.length < 8 then Error "compacted-size range must hold aligned uint64"
      else begin retain encoder [ acceleration.owned.token; range.buffer.owned.token ]; Ok () end

let validate_slice dimensions origin slice =
  let rank = Array.length dimensions in
  if rank = 0 || Array.length origin <> rank || Array.length slice <> rank then Error "tensor copy rank mismatch"
  else
    let rec loop index =
      if index = rank then Ok ()
      else if dimensions.(index) <= 0 || origin.(index) < 0 || slice.(index) <= 0
              || origin.(index) > dimensions.(index)
              || slice.(index) > dimensions.(index) - origin.(index) then Error "tensor copy range out of bounds"
      else loop (index + 1)
    in loop 0

let copy_tensor encoder ~(source : tensor) ~source_origin ~source_dimensions ~(destination : tensor)
    ~destination_origin ~destination_dimensions =
  match validate_owned encoder "source tensor" source.owned,
        validate_owned encoder "destination tensor" destination.owned,
        validate_slice source.dimensions source_origin source_dimensions,
        validate_slice destination.dimensions destination_origin destination_dimensions with
  | Error error, _, _, _ | _, Error error, _, _ | _, _, Error error, _ | _, _, _, Error error -> Error error
  | Ok (), Ok (), Ok (), Ok () ->
      if Array.to_list source_dimensions <> Array.to_list destination_dimensions then
        Error "tensor copy cardinality mismatch"
      else begin retain encoder [ source.owned.token; destination.owned.token ]; Ok () end

let retained_tokens encoder = List.rev encoder.retained
let end_encoding encoder =
  if encoder.destroyed then Error "destroyed MTL4 compute encoder"
  else if encoder.state <> Active then Error "MTL4 compute encoder already ended"
  else begin encoder.state <- Ended; Ok () end
let complete encoder = if encoder.state = Ended then begin encoder.state <- Completed; encoder.retained <- [] end
let destroy encoder = if not encoder.destroyed then begin encoder.destroyed <- true; encoder.retained <- [] end

let validate_handoff () =
  if List.length callable_ids <> 5 || List.length (List.sort_uniq String.compare callable_ids) <> 5 then
    invalid_arg "MTL4ComputeEncoder callable5 drift"
