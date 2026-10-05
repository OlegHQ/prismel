module Store = Store
module Panels = Panels
module Param = Param

module History = struct
  type merge =
    | Step
    | Gesture of string
    | Burst of { key : string; at : float; window : float }
    | Repair

  (* Each entry carries the label of the edit that produced it. *)
  type 'a t = {
    past : ('a * string) list; present : 'a; label : string;
    future : ('a * string) list;
    capacity : int; depth : int; merge : merge option;
  }

  let create ?(capacity = 128) present =
    if capacity < 1 then invalid_arg "Editor_core.History.create: capacity must be positive";
    { past = []; present; label = ""; future = []; capacity; depth = 0; merge = None }

  let present t = t.present
  let label t = t.label
  let redo_label t = match t.future with (_, label) :: _ -> Some label | [] -> None
  let can_undo t = t.past <> []
  let can_redo t = t.future <> []
  let depth t = t.depth

  (* ponytail: the bound is enforced by walking the list, O(capacity) per
     commit; switch to a deque if capacities grow past a few hundred. *)
  let commit value label t =
    if value == t.present then t
    else
      let past = (t.present, t.label) :: t.past in
      let past, depth =
        if t.depth < t.capacity then past, t.depth + 1
        else List.filteri (fun index _ -> index < t.capacity) past, t.capacity in
      { t with past; present = value; label; future = []; depth; merge = None }

  let amend value t =
    if value == t.present then t else { t with present = value; future = [] }

  let record ?(merge = Step) ?(label = "Edit") value t =
    let continuation = match merge, t.merge with
      | Repair, _ -> true
      | Gesture id, Some (Gesture previous) -> id = previous
      | Burst { key; at; window }, Some (Burst previous) ->
          String.equal key previous.key && at >= previous.at
          && at -. previous.at < window
      | _ -> false in
    let t = if continuation then amend value t else commit value label t in
    { t with merge = (if merge = Repair then t.merge else Some merge) }

  let seal ?(gesture_only = false) t = match t.merge with
    | None -> t
    | Some (Gesture _) -> { t with merge = None }
    | Some _ when not gesture_only -> { t with merge = None }
    | Some _ -> t

  let undo t = match t.past with
    | [] -> None
    | (previous, label) :: past ->
        Some { t with past; present = previous; label;
               future = (t.present, t.label) :: t.future;
               depth = t.depth - 1; merge = None }

  let redo t = match t.future with
    | [] -> None
    | (next, label) :: future ->
        Some { t with past = (t.present, t.label) :: t.past; present = next; label;
               future; depth = t.depth + 1; merge = None }
end

module Keymap = struct
  type trigger = Leader of string | Chord of Rays.Input.key * Rays.Input.key list

  let label = function
    | Leader sequence ->
        (* the sheets write each key apart: Space o v *)
        "Space " ^ String.concat " " (List.init (String.length sequence) (fun i -> String.make 1 sequence.[i]))
    | Chord (key, modifiers) ->
        let open Rays.Input in
        let key, modifiers = if key = KeyChar '/' && List.mem Shift modifiers then
          KeyChar '?', List.filter (( <> ) Shift) modifiers else key, modifiers in
        (* the sheets' vocabulary: modifier glyphs before the key with no dash, a letter under a
           modifier in capitals (⌘G, ⇧D), ↵ ⇥ ⌫ and esc *)
        let key = match key with
          | KeyChar c -> String.make 1 (if modifiers = [] then Char.lowercase_ascii c else Char.uppercase_ascii c)
          | ArrowUp -> "↑" | ArrowDown -> "↓" | ArrowLeft -> "←" | ArrowRight -> "→"
          | Space -> "Space" | Enter -> "↵" | Escape -> "esc" | Backspace -> "⌫"
          | Tab -> "⇥" | Home -> "Home" | End -> "End" | PageUp -> "PgUp"
          | PageDown -> "PgDn" | Insert -> "Ins" | Delete -> "⌦"
          | Shift -> "⇧" | Ctrl -> "⌃" | Alt -> "⌥" | Meta -> "⌘"
          | F1 -> "F1" | F2 -> "F2" | F3 -> "F3" | F4 -> "F4" | F5 -> "F5" | F6 -> "F6"
          | F7 -> "F7" | F8 -> "F8" | F9 -> "F9" | F10 -> "F10" | F11 -> "F11" | F12 -> "F12"
          | Unknown code -> "Key " ^ string_of_int code in
        List.fold_left (fun label (modifier, name) ->
          if List.mem modifier modifiers then label ^ name else label) ""
          [Meta, "⌘"; Ctrl, "⌃"; Alt, "⌥"; Shift, "⇧"] ^ key
end

module Guide_context = struct
  type t = Canvas | Node | Multi | Hints | Leader | Search | List | Text

  let name = function
    | Canvas -> "Canvas" | Node -> "Node" | Multi -> "Selection" | Hints -> "Hints"
    | Leader -> "Leader" | Search -> "Search" | List -> "List" | Text -> "Text"
end

module Command = struct
  type ('scope, 'action) t = {
    id : string;
    label : string;
    trigger : Keymap.trigger option;
    scope : 'scope option;
    guide : Guide_context.t list;
    action : 'action;
  }

  let make ?trigger ?scope ?(guide = []) ~id ~label action =
    { id; label; trigger; scope; guide; action }

  let for_guide commands ~focus ~context =
    List.filter (fun command -> command.trigger <> None
      && (command.scope = None || command.scope = Some focus)
      && List.mem context command.guide) commands
end

module Router = struct
  open Command
  open Keymap
  type state = Idle | Pending of string  (* the leader keys typed so far *)

  let visible commands focus = List.filter (fun command ->
    command.scope = None || command.scope = Some focus) commands

  let same_key a b = match a, b with
    | Rays.Input.KeyChar a, Rays.Input.KeyChar b ->
        Char.lowercase_ascii a = Char.lowercase_ascii b
    | _ -> a = b

  let chord commands focus keys key =
    visible commands focus |> List.filter_map (fun command ->
      match command.trigger with
      | Some (Chord (bound, modifiers)) when same_key bound key
          && List.for_all (fun modifier -> List.mem modifier keys) modifiers
          && (bound <> Rays.Input.Tab || List.for_all (fun modifier ->
               List.mem modifier keys = List.mem modifier modifiers)
               [Rays.Input.Shift; Rays.Input.Alt])
          && List.for_all (fun modifier ->
               not (List.mem modifier keys) || List.mem modifier modifiers)
               [Rays.Input.Meta; Rays.Input.Ctrl] ->
          Some (List.length modifiers, command)
      | _ -> None)
    |> List.fold_left (fun best candidate -> match best with
      | Some (count, _) when count >= fst candidate -> best
      | _ -> Some candidate) None
    |> Option.map snd

  let fly (frame : Rays.Frame.t) =
    let open Rays in
    let exits = List.exists (function
      | Event.KeyPressed (Input.Escape | Input.Space) | Event.WindowFocusLost -> true
      | _ -> false) frame.events in
    exits, { frame with events = List.filter (function
      | Event.KeyPressed Input.Space | Event.WindowFocusLost -> true
      | Event.KeyPressed _ | Event.KeyReleased _ | Event.TextInput _
      | Event.TextEditing _ -> false
      | _ -> true) frame.events }

  let modifier = function
    | Rays.Input.Shift | Rays.Input.Ctrl | Rays.Input.Alt
    | Rays.Input.Meta -> true
    | _ -> false

  let step ?(previous_keys = []) keymap ~focus ~text_focus ~(frame : Rays.Frame.t) state =
    let open Rays in
    if text_focus then Idle, [], frame else
    let modifiers = ref (Event.Private.keys_before ~previous:previous_keys
      ~held:frame.keys frame.events) in
    let traversing = ref false in
    let state, actions, passed = List.fold_left (fun (state, actions, passed) event ->
      modifiers := Event.Private.keys_after !modifiers event;
      let command = List.mem Input.Meta !modifiers || List.mem Input.Ctrl !modifiers in
      if !traversing then Idle, actions, event :: passed else match state, event with
      | _, Event.KeyPressed Input.Tab when not command ->
          traversing := true;
          (match chord keymap focus !modifiers Input.Tab with
           | None -> Idle, actions, event :: passed
           | Some action -> Idle, action :: actions, passed)
      | Idle, Event.KeyPressed Input.Space when not text_focus && not command ->
          Pending "", actions, passed
      | Idle, Event.KeyPressed key when not text_focus ->
          (match chord keymap focus !modifiers key with
           | Some action -> Idle, action :: actions, passed
           | None -> Idle, actions, event :: passed)
      | Idle, Event.TextInput _ when actions <> [] -> Idle, actions, passed
      | Idle, _ -> Idle, actions, event :: passed
      | Pending _, Event.KeyPressed key when modifier key -> state, actions, passed
      | Pending prefix, Event.KeyPressed (Input.KeyChar character) ->
          (* An exact sequence runs; a proper prefix opens the next page. *)
          let typed = prefix ^ String.make 1 (Char.lowercase_ascii character) in
          let commands = visible keymap focus in
          (match List.find_opt (fun command ->
              command.trigger = Some (Leader typed)) commands with
           | Some command -> Idle, command :: actions, passed
           | None when List.exists (fun command -> match command.trigger with
               | Some (Leader sequence) -> String.starts_with ~prefix:typed sequence
               | _ -> false) commands -> Pending typed, actions, passed
           | None -> Idle, actions, passed)
      | Pending _, (Event.TextInput _ | Event.TextEditing _) -> state, actions, passed
      | Pending _, (Event.KeyPressed _ | Event.MousePressed _) -> Idle, actions, passed
      | Pending _, Event.WindowFocusLost -> Idle, actions, event :: passed
      | Pending _, _ -> state, actions, event :: passed)
      (state, [], []) frame.events in
    state, List.rev actions, { frame with events = List.rev passed }
end
