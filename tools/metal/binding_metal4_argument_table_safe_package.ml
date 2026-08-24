type resource_kind = Buffer | Acceleration_structure | Texture | Sampler
type resource = { token : int; device : int; kind : resource_kind; destroyed : bool }
type state = Mutable | Submitted
type t =
  { device : int; slot_kinds : resource_kind array; bindings : resource option array
  ; mutable state : state; mutable destroyed : bool }

let callable_ids = [ "method:-[MTL4ArgumentTable setResource:atBufferIndex:]" ]

let buffer_resource_kind = function Buffer | Acceleration_structure -> true | Texture | Sampler -> false

let create ~available ~device ~slot_kinds =
  if not available then Error "MTL4 argument tables require macOS 26"
  else if Array.length slot_kinds = 0 then Error "MTL4 argument table requires buffer slots"
  else if Array.exists (fun kind -> not (buffer_resource_kind kind)) slot_kinds then
    Error "setResource buffer slots cannot be texture or sampler slots"
  else Ok { device; slot_kinds = Array.copy slot_kinds; bindings = Array.make (Array.length slot_kinds) None
          ; state = Mutable; destroyed = false }

let set_resource (table : t) ~buffer_index (resource : resource) =
  if table.destroyed then Error "destroyed MTL4 argument table"
  else if table.state <> Mutable then Error "submitted MTL4 argument table is immutable"
  else if buffer_index < 0 || buffer_index >= Array.length table.bindings then Error "MTL4 buffer index out of range"
  else if resource.destroyed then Error "destroyed MTL4 argument-table resource"
  else if resource.device <> table.device then Error "MTL4 argument-table resource belongs to another device"
  else if resource.kind <> table.slot_kinds.(buffer_index) then Error "MTL4 argument-table resource kind mismatch"
  else begin table.bindings.(buffer_index) <- Some resource; Ok () end

let retained_tokens table =
  table.bindings |> Array.to_list
  |> List.filter_map (Option.map (fun (resource : resource) -> resource.token))

let submit table =
  if table.destroyed then Error "destroyed MTL4 argument table"
  else if table.state = Submitted then Error "MTL4 argument table already submitted"
  else begin table.state <- Submitted; Ok () end

let complete table = if table.state = Submitted then table.state <- Mutable

let destroy table =
  if not table.destroyed then begin
    table.destroyed <- true;
    Array.fill table.bindings 0 (Array.length table.bindings) None
  end

let validate_handoff () =
  if callable_ids <> [ "method:-[MTL4ArgumentTable setResource:atBufferIndex:]" ] then
    invalid_arg "MTL4ArgumentTable callable1 drift"
