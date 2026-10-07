open Flow
open Flow_graph
let catalog = {Check.version = 1; kinds = []}
let ok = function Ok x -> x | Error d -> failwith (Diagnostic.to_string d)
let () =
  let source = ok (Syntax.parse "(workspace toy (graph g :context draw (let* [elapsed (state [s 0.0] (+ s (frame/dt))) dot (draw/circle [12 20 0] (+ 1 elapsed) :fill \"#00ffff\")] (draw/merge dot))))") in
  let source, workspace = ok (Flow_edit.apply_checked catalog source
    (Set_arg {node = ["g"; "elapsed"]; key = Bv (1, 1); sub = []; value = Syntax.make (Num "2.0")})) in
  ignore source;
  let scope = Projection.of_graph catalog workspace "g" in
  let state = Option.get (Projection.find scope ["g"; "elapsed"]) in
  assert ((Option.get state.zone).kind = Projection.State);
  let dot = Option.get (Projection.find scope ["g"; "dot"]) in
  assert (dot.ty = Ty.Drawing && List.length dot.rows = 4);
  let evaluated = ok (Eval.static ~record:true workspace) in
  assert (Array.length evaluated.plan.nodes = 2);
  let session = Eval.create_state () in
  let live = {(Frame_input.at_time 0.) with dt = 0.25} in
  let probes = Probe.make ~state:session ~live evaluated in
  ignore (Probe.records probes ["g"; "elapsed"]);
  let record = List.assoc ["g"; "elapsed"] evaluated.records |> List.hd |> snd in
  assert (ok (Eval.force ~state:session record ~live) = Eval.Float 2.25)
