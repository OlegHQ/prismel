type queue_kind = Classic | Metal4
type queue = { token : int; device : int; kind : queue_kind; destroyed : bool }
type scope = { device : int; queue : queue option; label : string option; active : bool }

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

let snapshot_label = function
  | Some label when not (valid_utf8 label) -> Error "invalid UTF-8 capture-scope label"
  | label -> Ok (Option.map (fun value -> String.sub value 0 (String.length value)) label)

let create ~device ~queue ~label =
  match queue with
  | Some queue when queue.destroyed -> Error "destroyed capture-scope queue"
  | Some queue when queue.device <> device -> Error "capture-scope queue belongs to another device"
  | _ -> Result.map (fun label -> { device; queue; label; active = false }) (snapshot_label label)

let device scope = scope.device
let label scope = scope.label

let command_queue ~metal4_available scope =
  match scope.queue with
  | Some { kind = Metal4; _ } when not metal4_available -> Error "MTL4 capture scope requires macOS 26"
  | Some ({ kind = Classic; _ } as queue) -> Ok (Some queue)
  | _ -> Ok None

let mtl4_command_queue ~metal4_available scope =
  if not metal4_available then Error "MTL4 capture scope requires macOS 26"
  else match scope.queue with Some ({ kind = Metal4; _ } as queue) -> Ok (Some queue) | _ -> Ok None

let set_label scope label = Result.map (fun label -> { scope with label }) (snapshot_label label)

let begin_scope ~native_ok scope =
  if scope.active then Error "capture scope is already active"
  else if not native_ok then Error "native beginScope failed"
  else Ok { scope with active = true }

let end_scope ~native_ok scope =
  if not scope.active then Error "capture scope is not active"
  else if not native_ok then Error "native endScope failed"
  else Ok { scope with active = false }

let is_active scope = scope.active

let validate_handoff () =
  if List.length Binding_capture_scope_tail_handoff.callable_ids <> 11 then
    invalid_arg "CaptureScope callable11 drift"
