type owned = { token:int64; device:int64; mutable live:bool; mutable retains:int }
type fence = owned
type heap = owned
type resource = owned
type icb = { owned:owned; max_commands:int }
type store_action = Dont_care | Store | Resolve | Store_and_resolve

type backend =
  { update_fence : int64 -> int64 -> int -> unit
  ; wait_fence : int64 -> int64 -> int -> unit
  ; depth_store : int64 -> int -> unit
  ; stencil_store : int64 -> int -> unit
  ; use_heaps : int64 -> int64 array -> int -> unit
  ; use_resources : int64 -> int64 array -> int -> int -> unit
  ; execute_icb : int64 -> int64 -> int -> int -> unit
  ; execute_icb_indirect : int64 -> int64 -> int64 -> int64 -> unit
  }

type encoder =
  { token:int64; device:int64; backend:backend; sample_count:int
  ; depth:bool; stencil:bool; pipeline_supports_icb:bool
  ; mutable open_:bool; mutable retained:owned list }

let owned ~token ~device = {token;device;live=true;retains=0}
let icb ~token ~device ~max_commands = {owned=owned ~token ~device;max_commands}
let encoder ~token ~device ~backend ~sample_count ~depth ~stencil
    ~pipeline_supports_icb =
  if sample_count <= 0 then invalid_arg "sample_count";
  {token;device;backend;sample_count;depth;stencil;pipeline_supports_icb;
   open_=true;retained=[]}

let error message = Error message
let validate_owned e value =
  if not e.open_ then error "render encoder is ended"
  else if not value.live then error "resource is destroyed"
  else if value.device <> e.device then error "resource belongs to another device"
  else Ok ()

let retain e value =
  if not (List.exists (fun current -> current == value) e.retained) then begin
    value.retains <- value.retains + 1; e.retained <- value :: e.retained
  end

let destroy value =
  if not value.live then error "resource is destroyed"
  else if value.retains <> 0 then error "resource has command dependents"
  else (value.live <- false; Ok ())

let stages value = value > 0 && value land lnot 0x3f = 0
let update_fence e fence ~after_stages =
  match validate_owned e fence with Error _ as failure -> failure | Ok () ->
    if not (stages after_stages) then error "invalid render stages" else
    (e.backend.update_fence e.token fence.token after_stages; retain e fence; Ok ())
let wait_fence e fence ~before_stages =
  match validate_owned e fence with Error _ as failure -> failure | Ok () ->
    if not (stages before_stages) then error "invalid render stages" else
    (e.backend.wait_fence e.token fence.token before_stages; retain e fence; Ok ())

let action_code e = function
  | Dont_care -> Ok 0 | Store -> Ok 1
  | Resolve when e.sample_count > 1 -> Ok 2
  | Store_and_resolve when e.sample_count > 1 -> Ok 3
  | Resolve | Store_and_resolve -> error "resolve action requires multisampling"
let set_depth_store e action =
  if not e.open_ then error "render encoder is ended"
  else if not e.depth then error "render pass has no depth attachment"
  else match action_code e action with Error _ as failure -> failure | Ok code ->
    e.backend.depth_store e.token code; Ok ()
let set_stencil_store e action =
  if not e.open_ then error "render encoder is ended"
  else if not e.stencil then error "render pass has no stencil attachment"
  else match action_code e action with Error _ as failure -> failure | Ok code ->
    e.backend.stencil_store e.token code; Ok ()

let validate_many e values =
  if values = [] then error "resource list is empty"
  else
    let rec loop seen = function
      | [] -> Ok ()
      | value::rest ->
          match validate_owned e value with Error _ as failure -> failure | Ok () ->
            if List.exists (fun token -> token=value.token) seen then error "duplicate resource"
            else loop (value.token::seen) rest
    in loop [] values
let use_heaps e heaps ~stages:stage_mask =
  match validate_many e heaps with Error _ as failure -> failure | Ok () ->
    if not (stages stage_mask) then error "invalid render stages" else
    (e.backend.use_heaps e.token (Array.of_list (List.map (fun (x:owned)->x.token) heaps)) stage_mask;
     List.iter (retain e) heaps; Ok ())
let use_resources e resources ~usage ~stages:stage_mask =
  match validate_many e resources with Error _ as failure -> failure | Ok () ->
    if usage <= 0 || usage land lnot 7 <> 0 || not (stages stage_mask) then
      error "invalid resource usage or render stages"
    else (e.backend.use_resources e.token
            (Array.of_list (List.map (fun (x:owned)->x.token) resources)) usage stage_mask;
          List.iter (retain e) resources; Ok ())

let execute_icb e value ~location ~length =
  match validate_owned e value.owned with Error _ as failure -> failure | Ok () ->
    if not e.pipeline_supports_icb then error "pipeline lacks ICB support"
    else if location < 0 || length <= 0 || location > value.max_commands-length then
      error "ICB range is invalid"
    else (e.backend.execute_icb e.token value.owned.token location length;
          retain e value.owned; Ok ())
let execute_icb_indirect e value range_buffer ~offset =
  match validate_owned e value.owned, validate_owned e range_buffer with
  | Error _ as failure, _ | _, (Error _ as failure) -> failure
  | Ok (), Ok () ->
      if not e.pipeline_supports_icb then error "pipeline lacks ICB support"
      else if offset < 0L || Int64.rem offset 8L <> 0L then error "indirect range offset is invalid"
      else (e.backend.execute_icb_indirect e.token value.owned.token range_buffer.token offset;
            retain e value.owned; retain e range_buffer; Ok ())

let end_encoding e = if not e.open_ then error "render encoder is ended" else (e.open_<-false;Ok())
let complete e =
  List.iter (fun value -> value.retains <- value.retains - 1) e.retained;
  e.retained <- []
