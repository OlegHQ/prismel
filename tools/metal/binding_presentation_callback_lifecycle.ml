type phase = Recording | Submitted | Terminal

type callback = Pending | Fired | Cancelled

type t =
  { phase : phase
  ; callbacks : callback list
  ; presentation_scheduled : bool
  }

let empty = { phase = Recording; callbacks = []; presentation_scheduled = false }

let add_handler value =
  match value.phase with
  | Recording -> Ok { value with callbacks = Pending :: value.callbacks }
  | Submitted | Terminal -> Error `Not_recording

let present value =
  match value.phase, value.presentation_scheduled with
  | Recording, false -> Ok { value with presentation_scheduled = true }
  | Recording, true -> Error `Already_scheduled
  | (Submitted | Terminal), _ -> Error `Not_recording

let commit value =
  match value.phase with
  | Recording -> Ok { value with phase = Submitted }
  | Submitted | Terminal -> Error `Not_recording

let complete value =
  match value.phase with
  | Submitted ->
      { value with
        phase = Terminal
      ; callbacks = List.map (function Pending -> Fired | state -> state) value.callbacks
      }
  | Recording | Terminal -> value

(* Destroying a recording command buffer is cancellation, not completion.  A
   native callback root must have exactly one of these two terminal owners. *)
let destroy value =
  match value.phase with
  | Recording ->
      Ok
        { value with
          phase = Terminal
        ; callbacks =
            List.map (function Pending -> Cancelled | state -> state) value.callbacks
        }
  | Submitted -> Error `In_flight
  | Terminal -> Error `Terminal

let pending_roots value =
  List.fold_left
    (fun count -> function Pending -> count + 1 | Fired | Cancelled -> count)
    0 value.callbacks

let fired value =
  List.fold_left
    (fun count -> function Fired -> count + 1 | Pending | Cancelled -> count)
    0 value.callbacks

let cancelled value =
  List.fold_left
    (fun count -> function Cancelled -> count + 1 | Pending | Fired -> count)
    0 value.callbacks
