type function_type = Vertex | Fragment | Kernel | Intersection | Mesh | Object
type native_kind = Function_handle | Other_handle
type device = { token : int; destroyed : bool }
type t =
  { device : device; function_type : function_type; gpu_resource_id : int64; name : string
  ; mutable destroyed : bool }

let callable_ids =
  [ "method:-[MTLFunctionHandle device]"; "method:-[MTLFunctionHandle functionType]"
  ; "method:-[MTLFunctionHandle gpuResourceID]"; "method:-[MTLFunctionHandle name]"
  ; "property:MTLFunctionHandle:device"; "property:MTLFunctionHandle:functionType"
  ; "property:MTLFunctionHandle:gpuResourceID"; "property:MTLFunctionHandle:name" ]

let valid_utf8 value =
  let length = String.length value in
  let continuation index = index < length && Char.code value.[index] land 0xc0 = 0x80 in
  let rec loop index =
    if index = length then true else
    let byte = Char.code value.[index] in
    if byte < 0x80 then loop (index + 1)
    else if byte >= 0xc2 && byte <= 0xdf && continuation (index + 1) then loop (index + 2)
    else if byte >= 0xe0 && byte <= 0xef && continuation (index + 1) && continuation (index + 2) then
      let second = Char.code value.[index + 1] in
      if (byte = 0xe0 && second < 0xa0) || (byte = 0xed && second >= 0xa0) then false else loop (index + 3)
    else if byte >= 0xf0 && byte <= 0xf4 && continuation (index + 1)
            && continuation (index + 2) && continuation (index + 3) then
      let second = Char.code value.[index + 1] in
      if (byte = 0xf0 && second < 0x90) || (byte = 0xf4 && second >= 0x90) then false else loop (index + 4)
    else false
  in loop 0

let create ~native_kind ~(device : device) ~function_type ~gpu_resource_id ~name =
  if native_kind <> Function_handle then Error "native handle is not an MTLFunctionHandle"
  else if device.destroyed then Error "destroyed function-handle device"
  else if not (valid_utf8 name) then Error "invalid UTF-8 function-handle name"
  else Ok { device; function_type; gpu_resource_id
          ; name = String.sub name 0 (String.length name); destroyed = false }

let live (handle : t) = if handle.destroyed then Error "destroyed function handle" else Ok handle
let device handle = Result.map (fun handle -> handle.device) (live handle)
let function_type handle = Result.map (fun handle -> handle.function_type) (live handle)
let gpu_resource_id handle = Result.map (fun handle -> handle.gpu_resource_id) (live handle)
let name handle = Result.map (fun handle -> handle.name) (live handle)
let destroy handle = handle.destroyed <- true

let validate_handoff () =
  if List.length callable_ids <> 8 || List.length (List.sort_uniq String.compare callable_ids) <> 8 then
    invalid_arg "FunctionHandle callable8 drift"
