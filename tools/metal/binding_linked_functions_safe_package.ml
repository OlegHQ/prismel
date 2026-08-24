type fn = { token : int; device : int; destroyed : bool }
type t =
  { device : int; mutable binary : fn list option; mutable private_ : fn list option
  ; mutable groups : (string * fn list) list option; mutable destroyed : bool }

let callable_ids =
  [ "method:-[MTLLinkedFunctions binaryFunctions]"; "method:-[MTLLinkedFunctions groups]"
  ; "method:-[MTLLinkedFunctions privateFunctions]"; "method:-[MTLLinkedFunctions setBinaryFunctions:]"
  ; "method:-[MTLLinkedFunctions setGroups:]"; "method:-[MTLLinkedFunctions setPrivateFunctions:]"
  ; "property:MTLLinkedFunctions:binaryFunctions"; "property:MTLLinkedFunctions:groups"
  ; "property:MTLLinkedFunctions:privateFunctions" ]

let create ~device = { device; binary = None; private_ = None; groups = None; destroyed = false }

let valid_utf8 value =
  let length = String.length value in
  let continuation index = index < length && Char.code value.[index] land 0xc0 = 0x80 in
  let rec loop index =
    if index = length then true else
    let byte = Char.code value.[index] in
    if byte < 0x80 then loop (index + 1)
    else if byte >= 0xc2 && byte <= 0xdf && continuation (index + 1) then loop (index + 2)
    else if byte >= 0xe0 && byte <= 0xef && continuation (index + 1) && continuation (index + 2) then loop (index + 3)
    else if byte >= 0xf0 && byte <= 0xf4 && continuation (index + 1)
            && continuation (index + 2) && continuation (index + 3) then loop (index + 4)
    else false
  in loop 0

let validate_functions ~device (functions : fn list) =
  let rec loop seen (remaining : fn list) = match remaining with
    | [] -> Ok ()
    | fn :: _ when fn.destroyed -> Error "destroyed linked function"
    | fn :: _ when fn.device <> device -> Error "linked function belongs to another device"
    | fn :: _ when List.mem fn.token seen -> Error "duplicate linked function"
    | fn :: rest -> loop (fn.token :: seen) rest
  in loop [] functions

let set_array linked value assign =
  if linked.destroyed then Error "destroyed linked-functions descriptor"
  else match value with
  | None -> assign None; Ok ()
  | Some functions ->
      (match validate_functions ~device:linked.device functions with
       | Error error -> Error error
       | Ok () -> assign (Some (List.map (fun fn -> fn) functions)); Ok ())

let set_binary_functions linked value = set_array linked value (fun value -> linked.binary <- value)
let set_private_functions linked value = set_array linked value (fun value -> linked.private_ <- value)

let set_groups linked value =
  if linked.destroyed then Error "destroyed linked-functions descriptor"
  else match value with
  | None -> linked.groups <- None; Ok ()
  | Some groups ->
      let rec validate names = function
        | [] -> Ok ()
        | (name, _) :: _ when name = "" || not (valid_utf8 name) -> Error "invalid linked-function group name"
        | (name, _) :: _ when List.mem name names -> Error "duplicate linked-function group name"
        | (name, functions) :: rest ->
            (match validate_functions ~device:linked.device functions with
             | Error error -> Error error
             | Ok () -> validate (name :: names) rest)
      in
      match validate [] groups with
      | Error error -> Error error
      | Ok () ->
          linked.groups <- Some (groups
            |> List.map (fun (name, functions) ->
                 String.sub name 0 (String.length name), List.map (fun fn -> fn) functions)
            |> List.sort (fun (left, _) (right, _) -> String.compare left right));
          Ok ()

let live linked = if linked.destroyed then Error "destroyed linked-functions descriptor" else Ok ()
let binary_functions linked = Result.map (fun () -> linked.binary) (live linked)
let private_functions linked = Result.map (fun () -> linked.private_) (live linked)
let groups linked = Result.map (fun () -> linked.groups) (live linked)

let retained_tokens linked =
  let array_tokens = function None -> [] | Some functions -> List.map (fun (fn : fn) -> fn.token) functions in
  let group_tokens = match linked.groups with None -> [] | Some groups ->
    List.concat_map (fun (_, functions) -> List.map (fun (fn : fn) -> fn.token) functions) groups in
  array_tokens linked.binary @ array_tokens linked.private_ @ group_tokens

let destroy linked =
  if not linked.destroyed then begin
    linked.destroyed <- true; linked.binary <- None; linked.private_ <- None; linked.groups <- None
  end

let validate_handoff () =
  if List.length callable_ids <> 9 || List.length (List.sort_uniq String.compare callable_ids) <> 9 then
    invalid_arg "LinkedFunctions callable9 drift"
