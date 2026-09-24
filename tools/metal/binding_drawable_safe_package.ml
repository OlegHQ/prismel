type layer = { token : int; device : int; destroyed : bool }
type schedule = Immediate | At_time of float | After_minimum_duration of float
type state = Available | Scheduled of float | Presented of float
type t =
  { layer : layer; drawable_id : int; max_handlers : int; mutable state : state
  ; mutable handlers : (float -> unit) list; mutable callback_errors : int; mutable destroyed : bool }

let callable_ids =
  [ "method:-[MTLDrawable addPresentedHandler:]"; "method:-[MTLDrawable drawableID]"
  ; "method:-[MTLDrawable presentAfterMinimumDuration:]"; "method:-[MTLDrawable presentAtTime:]"
  ; "method:-[MTLDrawable present]"; "method:-[MTLDrawable presentedTime]"
  ; "property:MTLDrawable:drawableID"; "property:MTLDrawable:presentedTime" ]

let finite value = Float.is_finite value

let create ~(layer : layer) ~drawable_id ~max_handlers =
  if layer.destroyed then Error "destroyed drawable parent layer"
  else if drawable_id < 0 then Error "invalid drawable identifier"
  else if max_handlers <= 0 then Error "drawable handler capacity must be positive"
  else Ok { layer; drawable_id; max_handlers; state = Available; handlers = []
          ; callback_errors = 0; destroyed = false }

let drawable_id drawable = drawable.drawable_id
let parent_layer drawable = drawable.layer
let device drawable = drawable.layer.device

let add_presented_handler drawable handler =
  if drawable.destroyed then Error "destroyed drawable"
  else match drawable.state with
  | Presented time ->
      (try handler time with _ -> drawable.callback_errors <- drawable.callback_errors + 1);
      Ok ()
  | Available | Scheduled _ ->
      if List.length drawable.handlers >= drawable.max_handlers then Error "drawable handler capacity exceeded"
      else begin drawable.handlers <- handler :: drawable.handlers; Ok () end

let present ~now drawable schedule =
  if drawable.destroyed then Error "destroyed drawable"
  else if not (finite now) then Error "invalid presentation clock"
  else match drawable.state with
  | Scheduled _ | Presented _ -> Error "drawable presentation is already scheduled"
  | Available ->
      let target = match schedule with Immediate -> Some now | At_time time ->
        if finite time && time >= now then Some time else None
        | After_minimum_duration duration ->
            if finite duration && duration >= 0. then Some (now +. duration) else None
      in
      (match target with
       | None -> Error "invalid drawable presentation time"
       | Some target when not (finite target) -> Error "drawable presentation time overflow"
       | Some target -> drawable.state <- Scheduled target; Ok ())

let mark_presented drawable ~time =
  if drawable.destroyed then Error "destroyed drawable"
  else if not (finite time) then Error "invalid presented time"
  else match drawable.state with
  | Available -> Error "drawable was not scheduled"
  | Presented _ -> Error "drawable was already presented"
  | Scheduled target when time < target -> Error "drawable presented before its scheduled time"
  | Scheduled _ ->
      drawable.state <- Presented time;
      let handlers = List.rev drawable.handlers in
      drawable.handlers <- [];
      List.iter (fun handler ->
        try handler time with _ -> drawable.callback_errors <- drawable.callback_errors + 1) handlers;
      Ok ()

let presented_time drawable = match drawable.state with Presented time -> Some time | _ -> None
let rooted_handler_count drawable = List.length drawable.handlers
let callback_error_count drawable = drawable.callback_errors

let destroy drawable =
  if drawable.destroyed then Ok ()
  else match drawable.state with
  | Scheduled _ -> Error "scheduled drawable must remain alive through presentation"
  | Available | Presented _ -> drawable.destroyed <- true; drawable.handlers <- []; Ok ()

let validate_handoff () =
  if List.length callable_ids <> 8 || List.length (List.sort_uniq String.compare callable_ids) <> 8 then
    invalid_arg "Drawable callable8 drift"
