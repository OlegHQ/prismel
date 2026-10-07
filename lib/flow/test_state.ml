open Flow
let checked body =
  let source = "(workspace w (graph g :context value " ^ body ^ "))" in
  let forms = Result.get_ok (Syntax.parse source) in
  match Workspace.check {Check.version = 1; kinds = []} forms with
  | Some w, [] -> w
  | _, ds -> failwith (String.concat "; " (List.map Diagnostic.to_string ds))
let value r = List.assoc "g" (Result.get_ok r).Eval.results
let () =
  let w = checked "(let* [s (state [previous 0.0] (+ previous (frame/dt)))] (+ s s))" in
  let state = Eval.create_state () in
  let run frame = Eval.run ~state ~live:{(Frame_input.at_time (float frame)) with frame; dt = 0.25} ~time:(float frame) w in
  assert (value (run 0) = Eval.Float 0.5);
  assert (value (run 0) = Eval.Float 0.5);
  assert (value (run 1) = Eval.Float 1.);
  assert (value (run 2) = Eval.Float 1.5);
  (* Seeking backwards and explicit reload reset both begin a fresh fold. *)
  assert (value (run 0) = Eval.Float 0.5);
  Eval.reset_state state;
  assert (value (run 1) = Eval.Float 0.5);
  (* Independent playback sessions have independent snapshots. *)
  let export () =
    let state = Eval.create_state () in
    Array.init 8 (fun frame -> value (Eval.run ~state
      ~live:{(Frame_input.at_time (float frame *. 0.125)) with frame; dt = 0.125}
      ~time:(float frame *. 0.125) w)) in
  assert (Marshal.to_string (export ()) [] = Marshal.to_string (export ()) []);
  (* Every state reads the previous snapshot, independent of forcing order. *)
  let w = checked "(let* [a (state [x 0] (+ x 1)) b (state [y 0] (+ y a))] (+ a b))" in
  let s = Eval.create_state () in
  let run frame = value (Eval.run ~state:s ~live:{(Frame_input.at_time 0.) with frame} ~time:0. w) in
  assert (run 0 = Eval.Int 2 && run 1 = Eval.Int 5 && run 1 = Eval.Int 5);
  (* An error after the fold step must not commit a partial frame. *)
  let w = checked "(let* [a (state [x 0] (+ x 1))] (+ a (nth (list 0) (frame/index))))" in
  let s = Eval.create_state () in
  let run frame = Eval.run ~state:s ~live:{(Frame_input.at_time 0.) with frame} ~time:0. w in
  assert (value (run 0) = Eval.Int 1);
  assert (Result.is_error (run 1));
  assert (value (run 0) = Eval.Int 1);
  let forms = Result.get_ok (Syntax.parse "(workspace w (graph g :context value (state [s t] s)))") in
  let _, ds = Workspace.check {Check.version = 1; kinds = []} forms in
  assert (List.exists (fun (d : Diagnostic.t) -> d.code = "E_STATE_INIT") ds)
