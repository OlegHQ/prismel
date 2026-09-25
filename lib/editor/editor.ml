module Store = Store

module History = struct
  type merge =
    | Step
    | Gesture of int
    | Burst of { key : string; at : float; window : float }
    | Repair

  type 'a t = {
    past : 'a list; present : 'a; future : 'a list;
    capacity : int; depth : int; merge : merge option;
  }

  let create ?(capacity = 64) present =
    if capacity < 1 then invalid_arg "Editor.History.create: capacity must be positive";
    { past = []; present; future = []; capacity; depth = 0; merge = None }

  let present t = t.present
  let can_undo t = t.past <> []
  let can_redo t = t.future <> []
  let depth t = t.depth

  (* ponytail: the bound is enforced by walking the list, O(capacity) per
     commit; switch to a deque if capacities grow past a few hundred. *)
  let commit value t =
    if value == t.present then t
    else
      let past = t.present :: t.past in
      let past, depth =
        if t.depth < t.capacity then past, t.depth + 1
        else List.filteri (fun index _ -> index < t.capacity) past, t.capacity in
      { t with past; present = value; future = []; depth; merge = None }

  let amend value t =
    if value == t.present then t else { t with present = value; future = [] }

  let record ?(merge = Step) value t =
    let continuation = match merge, t.merge with
      | Repair, _ -> true
      | Gesture id, Some (Gesture previous) -> id = previous
      | Burst { key; at; window }, Some (Burst previous) ->
          String.equal key previous.key && at >= previous.at
          && at -. previous.at < window
      | _ -> false in
    let t = if continuation then amend value t else commit value t in
    { t with merge = (if merge = Repair then t.merge else Some merge) }

  let seal t = if t.merge = None then t else { t with merge = None }

  let undo t = match t.past with
    | [] -> None
    | previous :: past ->
        Some { t with past; present = previous; future = t.present :: t.future;
               depth = t.depth - 1; merge = None }

  let redo t = match t.future with
    | [] -> None
    | next :: future ->
        Some { t with past = t.present :: t.past; present = next; future;
               depth = t.depth + 1; merge = None }
end

module Keymap = struct
  type trigger = Leader of char | Chord of Prismel.Input.key * Prismel.Input.key list

  type ('scope, 'action) binding = {
    trigger : trigger;
    label : string;
    scope : 'scope option;
    action : 'action;
  }

  let visible bindings focus = List.filter (fun binding ->
    binding.scope = None || binding.scope = Some focus) bindings

  let same_key a b = match a, b with
    | Prismel.Input.KeyChar a, Prismel.Input.KeyChar b ->
        Char.lowercase_ascii a = Char.lowercase_ascii b
    | _ -> a = b

  let chord bindings focus keys key =
    visible bindings focus |> List.filter_map (fun binding ->
      match binding.trigger with
      | Chord (bound, modifiers) when same_key bound key
          && List.for_all (fun modifier -> List.mem modifier keys) modifiers
          && List.for_all (fun modifier ->
               not (List.mem modifier keys) || List.mem modifier modifiers)
               [Prismel.Input.Meta; Prismel.Input.Ctrl] ->
          Some (List.length modifiers, binding.action)
      | _ -> None)
    |> List.fold_left (fun best candidate -> match best with
      | Some (count, _) when count >= fst candidate -> best
      | _ -> Some candidate) None
    |> Option.map snd
end

module Router = struct
  type state = Idle | Pending

  let modifier = function
    | Prismel.Input.Shift | Prismel.Input.Ctrl | Prismel.Input.Alt
    | Prismel.Input.Meta -> true
    | _ -> false

  let step keymap ~focus ~text_focus ~(frame : Prismel.Frame.t) state =
    let open Prismel in
    if text_focus then Idle, [], frame else
    let command = List.mem Input.Meta frame.keys || List.mem Input.Ctrl frame.keys in
    let state, actions, passed = List.fold_left (fun (state, actions, passed) event ->
      match state, event with
      | Idle, Event.KeyPressed Input.Space when not text_focus && not command ->
          Pending, actions, passed
      | Idle, Event.KeyPressed key when not text_focus ->
          (match Keymap.chord keymap focus frame.keys key with
           | Some action -> Idle, action :: actions, passed
           | None -> Idle, actions, event :: passed)
      | Idle, _ -> Idle, actions, event :: passed
      | Pending, Event.KeyPressed key when modifier key -> Pending, actions, passed
      | Pending, Event.KeyPressed (Input.KeyChar character) ->
          let character = Char.lowercase_ascii character in
          let actions = match List.find_opt (fun binding ->
              binding.Keymap.trigger = Keymap.Leader character)
              (Keymap.visible keymap focus) with
            | Some binding -> binding.action :: actions
            | None -> actions in
          Idle, actions, passed
      | Pending, (Event.TextInput _ | Event.TextEditing _) -> Pending, actions, passed
      | Pending, (Event.KeyPressed _ | Event.MousePressed _) -> Idle, actions, passed
      | Pending, Event.WindowFocusLost -> Idle, actions, event :: passed
      | Pending, _ -> Pending, actions, event :: passed)
      (state, [], []) frame.events in
    let passed = if state = Idle && actions <> [] then List.filter (function
        | Event.TextInput _ -> false | _ -> true) passed else passed in
    state, List.rev actions, { frame with events = List.rev passed }
end
