type fence = { token : int; device : int; value : int64; destroyed : bool }
type state = Active | Ended | Completed
type t = { device : int; mutable state : state; mutable retained_fences : fence list; mutable destroyed : bool }

let callable_ids = [ "method:-[MTL4CommandEncoder waitForFence:beforeEncoderStages:]" ]

let create ~available ~device =
  if not available then Error "MTL4 command encoders require macOS 26"
  else Ok { device; state = Active; retained_fences = []; destroyed = false }

let valid_stage_mask = Int64.sub (Int64.shift_left 1L 10) 1L

let wait_for_fence (encoder : t) (fence : fence) ~before_stages =
  if encoder.destroyed then Error "destroyed MTL4 command encoder"
  else if encoder.state <> Active then Error "MTL4 command encoder is not active"
  else if fence.destroyed then Error "destroyed MTL4 fence"
  else if fence.device <> encoder.device then Error "MTL4 fence belongs to another device"
  else if Int64.compare fence.value 0L <= 0 then Error "MTL4 fence has not been updated"
  else if before_stages = 0L || Int64.logand before_stages (Int64.lognot valid_stage_mask) <> 0L then
    Error "invalid MTL4 before-stage mask"
  else begin
    if not (List.exists (fun (retained : fence) -> retained.token = fence.token) encoder.retained_fences) then
      encoder.retained_fences <- fence :: encoder.retained_fences;
    Ok ()
  end

let retained_fence_tokens encoder = List.map (fun (fence : fence) -> fence.token) encoder.retained_fences

let end_encoding encoder =
  if encoder.destroyed then Error "destroyed MTL4 command encoder"
  else if encoder.state <> Active then Error "MTL4 command encoder already ended"
  else begin encoder.state <- Ended; Ok () end

let complete encoder =
  if encoder.state = Ended then begin encoder.state <- Completed; encoder.retained_fences <- [] end

let destroy encoder =
  if not encoder.destroyed then begin
    encoder.destroyed <- true; encoder.retained_fences <- []
  end

let validate_handoff () =
  if callable_ids <> [ "method:-[MTL4CommandEncoder waitForFence:beforeEncoderStages:]" ] then
    invalid_arg "MTL4CommandEncoder remaining callable closure drift"
