module E = Flow.Eval
module I = Flow_ir
let ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d)
let checked text =
  match Flow.Workspace.check {Flow.Check.version = 1; kinds = []} (ok (Flow.Syntax.parse text)) with
  | Some w, [] -> w | _, ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds))
let read path = In_channel.with_open_text path In_channel.input_all
let bytes v = Marshal.to_string v [Marshal.No_sharing]
let same a b = match a, b with
  | Ok a, Ok b -> bytes a = bytes b
  | Error a, Error b -> Flow.Diagnostic.to_string a = Flow.Diagnostic.to_string b
  | _ -> false
let live frame dt = {(Frame_input.at_time (float frame /. 60.)) with frame; dt; size = 800, 600}
let compare_frames value frames =
  let program = ok (I.Executor.compile value) in
  let one = E.create_state () and eight = E.create_state () and reference = E.create_state () in
  List.iter (fun (frame, dt) ->
    let live = live frame dt in
    let expected = E.Private.force_reference ~state:reference value ~live in
    List.iter (fun (domains, state) -> Rays_math.Parallel.run ~domains (fun () ->
      assert (same (I.Executor.force ~state program ~live) expected);
      assert (E.state_stamp state = E.state_stamp reference))) [1, one; 8, eight]) frames

let () =
  let source = ok (Flow.Syntax.parse (read "../../examples/particles/sketch.rays")) in
  let source = match source with
    | [{node = Flow.Syntax.List (head :: name :: graphs); _} as workspace] ->
        let picture = List.find (fun (graph : Flow.Syntax.t) -> match graph.node with
          | List (_ :: {node = Sym "picture"; _} :: _) -> true | _ -> false) graphs in
        [{workspace with node = List [head; name; picture]}]
    | _ -> assert false in
  let workspace = match Flow.Workspace.check {Flow.Check.version = 1; kinds = []} source with
    | Some w, [] -> w | _, ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds)) in
  let evaluation = ok (E.static workspace) in
  let particles = List.hd evaluation.states in
  compare_frames particles [0, 1. /. 60.; 1, 0.125; 2, 20.; 2, 20.; 3, 20.; 4, 0.125; 1, 0.125];
  (* Prove template dispatch and reuse, then compare the public executor as well. *)
  let templates = ref [] and compiled = ref 0 and rebound = ref 0 and executed = ref 0 in
  let state = E.create_state () and reference = E.create_state () in
  let execute r live =
    let program = match List.find_map (fun p -> I.Packed.rebind p r) !templates with
      | Some p -> incr rebound; Some p
      | None ->
          let p = I.Packed.compile_template r (E.Private.residual_view r).term in
          Option.iter (fun p -> incr compiled; templates := p :: !templates) p; p in
    Option.map (fun p -> incr executed; I.Packed.force ~state p ~live) program in
  for frame = 0 to 5 do
    let live = live frame (if frame > 1 then 20. else 0.125) in
    assert (same (E.Private.force_with_executor ~state ~execute particles ~live)
      (E.Private.force_reference ~state:reference particles ~live))
  done;
  if !compiled <> 2 || !rebound <> 10 || !executed <> 12 then
    failwith (Printf.sprintf "template counts: %d compiled, %d rebound, %d executed" !compiled !rebound !executed);
  let value body =
    let ws = checked ("(workspace w (graph g :context value (let* [tested " ^ body ^ "] 0.0)))") in
    let evaluation = ok (E.static ~record:true ws) in
    List.assoc ["g"; "tested"] evaluation.records |> List.hd |> snd in
  List.iter (fun body -> compare_frames (value body)
    [0, 0.125; 1, 0.5; 2, 1.; 2, 1.; 1024, 0.125; 1025, 0.125; 1, 0.25])
    ["(state [p {:xs (array/float 2051) :scale 0.125}] {:xs (map (fn [x] (+ x p.scale)) p.xs) :scale (+ p.scale (frame/dt))})";
     "(state [p (array/float 0)] (map (fn [x] (+ x (frame/dt))) (array/range (frame/index))))";
     "(state [p (array/range 16385)] (map (fn [x] (if (not (and (>= x 0) (< x (frame/width)))) (- 0 x) (+ x (frame/dt)))) p))";
     "(state [p (array/float 2051)] (scan [a 0.0] [x p] (+ a (+ x (frame/dt)))))";
     "(state [p (array/float 2051)] (map (fn [x] (if (< (frame/dt) 1) (+ x (frame/dt)) (pow (+ x 2) 10000000))) p))"];
  let v = value "(let* [a (state [p (array/float 2051)] (map (fn [x] (+ x (frame/dt))) p))] {:xs a :error (array/nth (array/float 2) (frame/index))})" in
  compare_frames v [0, 0.125; 1, 0.125; 2, 0.125; 1, 0.125; 3, 0.125];
  print_endline "Packed frame folds: template reuse, particle branches, domains, resets, repeated reads and rollback passed"
