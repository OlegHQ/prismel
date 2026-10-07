open Flow
let check text =
  let forms = Result.get_ok (Syntax.parse ("(workspace w (graph g :context value " ^ text ^ "))")) in
  match Workspace.check {Check.version = 1; kinds = []} forms with
  | Some w, [] -> w
  | _, ds -> failwith (String.concat "; " (List.map Diagnostic.to_string ds))

let () =
  let w = check "(let* [x (pointer/x) r {:x x :y (pointer/y) :dt (frame/dt) :i (frame/index) :w (frame/width) :h (frame/height) :mouse (pointer/down) :right (pointer/down \"right\") :key (key/down \"space\") :time t}] r.x)" in
  let s = Result.get_ok (Eval.static ~record:true w) in
  let value = snd (List.hd (List.assoc ["g"; "r"] s.records)) in
  assert (Eval.is_live value && Eval.frame_dependent value);
  let live = { (Frame_input.at_time 3.) with dt = 0.125; frame = 24;
    size = 800, 600; pointer = 12., 37.; buttons = ["left"]; keys = ["space"];
    events = [Key_pressed "space"; Pointer_pressed ("left", (12., 37.))] } in
  let expected = Eval.Record ["x", Float 12.; "y", Float 37.; "dt", Float 0.125;
    "i", Int 24; "w", Int 800; "h", Int 600; "mouse", Bool true;
    "right", Bool false; "key", Bool true; "time", Float 3.] in
  assert (Eval.force value ~live = Ok expected);
  let changed = {live with pointer = 99., 37.; keys = []; size = 900, 600} in
  let interpreted live =
    Eval.Private.compile_residuals := false;
    let v = Eval.force value ~live in
    Eval.Private.compile_residuals := true; v in
  List.iter (fun live -> assert (Eval.force value ~live = interpreted live)) [live; changed; live];
  assert (Eval.force value ~live:changed <> Ok expected);
  assert (List.assoc "g" (Result.get_ok (Eval.run ~live ~time:3. w)).results = Eval.Float 12.);
  assert (Result.is_error (Eval.force value ~live:{live with dt = nan}));
  assert (Result.is_error (Eval.force value ~live:{live with size = -1, 600}));
  assert (Result.is_error (Eval.force value ~live:{live with events = [Pinched nan]}));
  assert (not (Frame_input.equal {live with dt = 0.} {live with dt = -0.}));
  let input = List.assoc "g" (Result.get_ok (Eval.static ~record:true
    (check "(let* [f (frame/input)] (count f.events))"))).results in
  assert (Eval.force input ~live = Ok (Eval.Int 2));
  let forms = Result.get_ok (Syntax.parse
    "(workspace w (graph g :context value (for [i (range (frame/index))] i)))") in
  let _, ds = Workspace.check {Check.version = 1; kinds = []} forms in
  assert (List.exists (fun (d : Diagnostic.t) -> d.code = "E_TIME_COUNT") ds)

let () =
  let forms = Result.get_ok (Syntax.parse
    "(workspace w (graph g :context value (let* [r (if (> (frame/index) 0) {:items (list 1 2)} {:items (list 1)})] (for [x r.items] x))))") in
  let _, ds = Workspace.check {Check.version = 1; kinds = []} forms in
  assert (List.exists (fun (d : Diagnostic.t) -> d.code = "E_TIME_COUNT") ds)

let () =
  let forms = Result.get_ok (Syntax.parse
    "(workspace w (graph g :context value (let* [f (frame/input)] (for [e f.events] e.kind))))") in
  let _, ds = Workspace.check {Check.version = 1; kinds = []} forms in
  assert (List.exists (fun (d : Diagnostic.t) -> d.code = "E_TIME_COUNT") ds)
