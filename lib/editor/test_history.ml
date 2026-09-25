let () =
  let open Editor.History in
  let h = create ~capacity:3 0 in
  let h = commit 1 h |> commit 2 |> amend 3 in
  assert (present h = 3 && depth h = 2);
  let h = Option.get (undo h) in
  assert (present h = 1 && can_redo h);
  let h = Option.get (redo h) in
  assert (present h = 3 && not (can_redo h));
  let h = commit 4 h |> commit 5 |> commit 6 in
  assert (depth h = 3);
  let rec bottom h = match undo h with Some h -> bottom h | None -> h in
  assert (present (bottom h) = 3 && not (can_undo (bottom h)));
  assert (commit 6 h == h);
  print_endline "editor history: commit/amend/undo/redo/bounded ok"
