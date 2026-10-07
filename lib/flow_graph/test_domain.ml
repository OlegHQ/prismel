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
  assert (dot.ty = Flow.Ty.drawing && List.length dot.rows = 4);
  let evaluated = ok (Eval.static ~record:true workspace) in
  assert (Array.length evaluated.plan.nodes = 2);
  let session = Eval.create_state () in
  let live = {(Frame_input.at_time 0.) with dt = 0.25} in
  let probes = Probe.make ~state:session ~live evaluated in
  ignore (Probe.records probes ["g"; "elapsed"]);
  let record = List.assoc ["g"; "elapsed"] evaluated.records |> List.hd |> snd in
  assert (ok (Eval.force ~state:session record ~live) = Eval.Float 2.25)

let () =
  let source = ok (Syntax.parse "(workspace readback (graph g :context value (let* [x (exact (sin t))] x)))") in
  let workspace = match Workspace.check catalog source with Some w, [] -> w | _ -> failwith "exact did not check" in
  let scope = Projection.of_graph catalog workspace "g" in
  let card = Option.get (Projection.find scope ["g"; "x"]) in
  assert (card.ty = Ty.Float && List.length card.rows = 1);
  let source, edited = ok (Flow_edit.apply_checked catalog source
    (Set_arg {node = ["g"; "x"]; key = Pos 0; sub = []; value = Syntax.make (Num "2.5")})) in
  ignore source;
  let result = ok (Eval.run ~time:7. edited) in
  assert (List.assoc "g" result.results = Eval.Float 2.5)

let () =
  let source = ok (Syntax.parse "(workspace maps (graph g :context value (let* [amp 2.0 out (map (fn [(x : float)] (let* [shift (+ x amp)] (* shift 3.0))) (array/float 10003 0.5))] (array/count out))))") in
  let workspace = match Workspace.check catalog source with Some w, [] -> w | _, ds ->
    failwith (String.concat "\n" (List.map Diagnostic.to_string ds)) in
  let scope = Projection.of_graph catalog workspace "g" in
  let fn = Option.get (Projection.find scope ["g"; "out#0"]) in
  assert (fn.ty = Ty.Fn && (Option.get fn.zone).kind = Projection.Fn);
  assert (List.exists (fun (rail : Projection.rail_row) -> rail.name = "x" && rail.ty = Some Ty.Float)
    (Option.get fn.zone).rail);
  let card = Option.get (Projection.find scope ["g"; "out"]) in
  assert ((List.hd card.rows).chip = Projection.Name "out#0");
  let chain = Probe.chains scope in
  assert (Hashtbl.find chain ["g"; "out#0"; "shift"] = [["g"; "out#0"]]);
  let probe = Probe.make (ok (Eval.static ~record:true workspace)) in
  assert (List.assoc ["g"; "out#0"] (Probe.counts probe scope ~probe:(fun _ -> 0)) = 10003);
  let shift = Option.get (Projection.find scope ["g"; "out#0"; "shift"]) in
  assert ((Probe.footer probe shift ~probes:[9999]).value = "2.5");
  let source, edited = ok (Flow_edit.apply_checked catalog source
    (Set_arg {node = shift.path; key = Pos 1; sub = []; value = Syntax.make (Num "4.0")})) in
  ignore source;
  let scope = Projection.of_graph catalog edited "g" in
  let shift = Option.get (Projection.find scope shift.path) in
  let probe = Probe.make (ok (Eval.static ~record:true edited)) in
  assert ((Probe.footer probe shift ~probes:[9999]).value = "4.5");
  let source = ok (Syntax.parse "(workspace nested (graph g :context value (array/count (map (fn [(x : float)] (+ x 2.0)) (array/float 3 1.0)))))") in
  let workspace = match Workspace.check catalog source with Some w, [] -> w | _ -> assert false in
  let scope = Projection.of_graph catalog workspace "g" in
  let fn = Option.get (Projection.find scope ["g"; "@result#0#0"]) in
  let body = Option.get (Projection.find scope (fn.path @ ["@result"])) in
  let _, edited = ok (Flow_edit.apply_checked catalog source
    (Set_arg {node = body.path; key = Pos 1; sub = []; value = Syntax.make (Num "5.0")})) in
  let probe = Probe.make (ok (Eval.static ~record:true edited)) in
  assert ((Probe.footer probe body ~probes:[2]).value = "6")
