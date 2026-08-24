type extents = int64 array
type graph_kind = Descriptor_dimensions | Descriptor_strides | Tensor_dimensions | Tensor_strides | Tensor_buffer
type constructor = Device_tensor | Device_size_and_align | Buffer_tensor

let constructors =
  [ Device_tensor, "method:-[MTLDevice newTensorWithDescriptor:error:]"
  ; Device_size_and_align, "method:-[MTLDevice tensorSizeAndAlignWithDescriptor:]"
  ; Buffer_tensor, "method:-[MTLBuffer newTensorWithDescriptor:offset:error:]" ]

let copy values = Array.copy values

let validate_extents values =
  if Array.length values = 0 then Error "tensor rank must be positive"
  else if Array.exists (fun value -> Int64.compare value 0L <= 0) values then
    Error "tensor extent must be positive"
  else Ok (copy values)

let validate_shape ~dimensions ~strides =
  match validate_extents dimensions, validate_extents strides with
  | Error error, _ | _, Error error -> Error error
  | Ok dimensions, Ok strides when Array.length dimensions <> Array.length strides ->
      Error "tensor dimension/stride rank mismatch"
  | Ok dimensions, Ok strides -> Ok (dimensions, strides)

let checked_add a b =
  if Int64.compare b 0L < 0 || Int64.compare a (Int64.sub Int64.max_int b) > 0 then None
  else Some (Int64.add a b)

let checked_mul a b =
  if Int64.compare a 0L < 0 || Int64.compare b 0L < 0 then None
  else if a = 0L || b = 0L then Some 0L
  else if Int64.compare a (Int64.div Int64.max_int b) > 0 then None
  else Some (Int64.mul a b)

let validate_slice ~tensor_dimensions ~origin ~slice_dimensions ~byte_strides
    ~element_size ~bytes_length =
  let rank = Array.length tensor_dimensions in
  if rank = 0 || Array.length origin <> rank || Array.length slice_dimensions <> rank
     || Array.length byte_strides <> rank
  then Error "tensor slice rank mismatch"
  else if element_size <= 0 || bytes_length < 0 then Error "invalid tensor byte size"
  else
    let rec loop index maximum =
      if index = rank then
        (match checked_add maximum (Int64.of_int element_size) with
         | Some required when Int64.compare required (Int64.of_int bytes_length) <= 0 -> Ok required
         | Some _ -> Error "tensor byte slice is undersized"
         | None -> Error "tensor byte range overflow")
      else
        let dimension = tensor_dimensions.(index)
        and start = origin.(index)
        and count = slice_dimensions.(index)
        and stride = byte_strides.(index) in
        if Int64.compare dimension 0L <= 0 || Int64.compare start 0L < 0
           || Int64.compare count 0L <= 0 || Int64.compare stride 0L <= 0
        then Error "invalid tensor slice component"
        else
          match checked_add start count with
          | None -> Error "tensor slice range overflow"
          | Some limit when Int64.compare limit dimension > 0 -> Error "tensor slice exceeds dimensions"
          | Some _ ->
              (match checked_mul (Int64.pred count) stride with
               | None -> Error "tensor byte range overflow"
               | Some contribution ->
                   (match checked_add maximum contribution with
                    | None -> Error "tensor byte range overflow"
                    | Some maximum -> loop (index + 1) maximum))
    in
    loop 0 0L

let retained_graph =
  [ Descriptor_dimensions; Descriptor_strides; Tensor_dimensions; Tensor_strides; Tensor_buffer ]

let validate_handoff () =
  Binding_tensor_safe_handoff.validate ();
  if List.length Binding_tensor_safe_handoff.callable_ids <> 44
     || List.length constructors <> 3 || List.length retained_graph <> 5
  then invalid_arg "Tensor safe package closure drift"
