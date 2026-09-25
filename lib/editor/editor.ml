module History = struct
  type 'a t = { past : 'a list; present : 'a; future : 'a list; capacity : int; depth : int }

  let create ?(capacity = 64) present =
    if capacity < 1 then invalid_arg "Editor.History.create: capacity must be positive";
    { past = []; present; future = []; capacity; depth = 0 }

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
      { t with past; present = value; future = []; depth }

  let amend value t = { t with present = value }

  let undo t = match t.past with
    | [] -> None
    | previous :: past ->
        Some { t with past; present = previous; future = t.present :: t.future;
               depth = t.depth - 1 }

  let redo t = match t.future with
    | [] -> None
    | next :: future ->
        Some { t with past = t.present :: t.past; present = next; future;
               depth = t.depth + 1 }
end
