type data_type = Bool | Int32 | UInt32 | Float32 | Int64 | Unsupported of int
type value = Bool_value of bool | Int32_value of int32 | UInt32_value of int32 | Float32_value of float | Int64_value of int64
type t = { max_constants : int; mutable values : (int * data_type * value) list }

let callable_ids =
  [ "method:-[MTLFunctionConstantValues reset]"
  ; "method:-[MTLFunctionConstantValues setConstantValue:type:atIndex:]"
  ; "method:-[MTLFunctionConstantValues setConstantValues:type:withRange:]" ]

let create ~max_constants =
  if max_constants <= 0 then Error "function constant capacity must be positive"
  else Ok { max_constants; values = [] }

let type_matches data_type value = match data_type, value with
  | Bool, Bool_value _ | Int32, Int32_value _ | UInt32, UInt32_value _
  | Float32, Float32_value _ | Int64, Int64_value _ -> true
  | Unsupported _, _ | _, _ -> false

let validate_index constants index =
  if index < 0 || index >= constants.max_constants then Error "function constant index out of range" else Ok ()

let replace index data_type value values =
  (index, data_type, value) :: List.filter (fun (existing, _, _) -> existing <> index) values

let set_single constants ~index ~data_type value =
  match validate_index constants index with
  | Error error -> Error error
  | Ok () when not (type_matches data_type value) -> Error "function constant data type mismatch"
  | Ok () -> constants.values <- replace index data_type value constants.values; Ok ()

let set_range constants ~start ~length ~data_type values =
  if start < 0 || length <= 0 || start > constants.max_constants
     || length > constants.max_constants - start then Error "function constant range out of bounds"
  else if List.length values <> length then Error "function constant range cardinality mismatch"
  else if List.exists (fun value -> not (type_matches data_type value)) values then
    Error "function constant range data type mismatch"
  else
    let next, _ = List.fold_left (fun (entries, index) value ->
      replace index data_type value entries, index + 1) (constants.values, start) values in
    constants.values <- next;
    Ok ()

let snapshot constants = List.sort (fun (left, _, _) (right, _, _) -> compare left right) constants.values
let reset constants = constants.values <- []

let validate_handoff () =
  if List.length callable_ids <> 3 || List.length (List.sort_uniq String.compare callable_ids) <> 3 then
    invalid_arg "FunctionConstantValues callable3 drift"
