type queue = { token : int; destroyed : bool }
type notification_state = Pending | Fired | Cancelled
type listener =
  { queue : queue option; max_pending : int; mutable destroyed : bool
  ; mutable pending : notification list; mutable callback_errors : int }
and shared_event =
  { token : int; device : int; label : string option; mutable value : int64
  ; mutable notifications : notification list }
and notification =
  { event : shared_event; listener : listener; threshold : int64
  ; callback : unit -> unit; mutable state : notification_state }
type shared_handle = { event_token : int; device : int; label : string option }

let copy_label = Option.map (fun value -> String.sub value 0 (String.length value))

let create_listener ~max_pending (queue : queue option) =
  if max_pending <= 0 then Error "listener pending capacity must be positive"
  else match queue with
  | Some queue when queue.destroyed -> Error "destroyed event listener queue"
  | _ -> Ok { queue; max_pending; destroyed = false; pending = []; callback_errors = 0 }

let listener_queue listener = listener.queue

let cancel notification =
  match notification.state with
  | Fired | Cancelled -> false
  | Pending ->
      notification.state <- Cancelled;
      notification.listener.pending <- List.filter (fun item -> item != notification) notification.listener.pending;
      notification.event.notifications <- List.filter (fun item -> item != notification) notification.event.notifications;
      true

let destroy_listener listener =
  if not listener.destroyed then begin
    listener.destroyed <- true;
    List.iter (fun notification -> ignore (cancel notification)) listener.pending
  end

let create_event ~token ~device ~label = { token; device; label = copy_label label; value = 0L; notifications = [] }
let event_device (event : shared_event) = event.device
let export_handle (event : shared_event) = { event_token = event.token; device = event.device; label = copy_label event.label }

let notify_at event listener ~value callback =
  if listener.destroyed then Error "destroyed shared-event listener"
  else if List.length listener.pending >= listener.max_pending then Error "shared-event listener capacity exceeded"
  else
    let notification = { event; listener; threshold = value; callback; state = Pending } in
    listener.pending <- notification :: listener.pending;
    event.notifications <- notification :: event.notifications;
    Ok notification

let fire notification =
  match notification.state with
  | Fired | Cancelled -> ()
  | Pending ->
      notification.state <- Fired;
      notification.listener.pending <- List.filter (fun item -> item != notification) notification.listener.pending;
      (try notification.callback () with _ ->
         notification.listener.callback_errors <- notification.listener.callback_errors + 1)

let signal event value =
  if Int64.compare value event.value > 0 then event.value <- value;
  let ready, waiting = List.partition (fun notification ->
    notification.state = Pending && Int64.compare event.value notification.threshold >= 0) event.notifications in
  event.notifications <- waiting;
  List.iter fire ready

let retained_callback_count listener = List.length listener.pending
let callback_error_count listener = listener.callback_errors

let validate_handoff () =
  if List.length Binding_event_tail_handoff.callable_ids <> 10 then
    invalid_arg "Event callable10 drift"
