open Flow
let check body =
  let forms = Result.get_ok (Syntax.parse ("(workspace w (graph g :context value " ^ body ^ "))")) in
  match Workspace.check {Check.version = 1; kinds = []} forms with
  | Some w, [] -> w
  | _, ds -> failwith (String.concat "; " (List.map Diagnostic.to_string ds))
let value body = List.assoc "g" (Result.get_ok (Eval.run ~time:0. (check body))).results
let () =
  assert (value "(array/count (array/float 10000))" = Eval.Int 10000);
  assert (value "(array/sum (array/float 10000 2))" = Eval.Float 20000.);
  assert (value "(let* [p (array/nth (array/vec3 10000 [1 2 3]) 9999)] p.x)" = Eval.Float 1.);
  assert (value "(array/sum (map (fn [x] (+ x 1)) (array/range 10000)))" = Eval.Float 50005000.);
  assert (value "(fold [s 0.0] [x (array/float 10000 2)] (+ s x))" = Eval.Float 20000.);
  assert (value "(sum [x (array/float 10000 2)] x)" = Eval.Float 20000.);
  assert (value "(array/count (for [x (array/range 10000)] [x 0 0]))" = Eval.Int 10000);
  assert (value "(array/count (filter (fn [x] (> x 4999)) (array/range 10000)))" = Eval.Int 5000);
  assert (value "(array/nth (sort-by (fn [x] (- 0 x)) (array/range 10)) 0)" = Eval.Float 9.);
  let w = check "(let* [p (state [prev (array/float 10000)] (map (fn [x] (+ x (frame/dt))) prev))] (array/sum p))" in
  let export () =
    let s = Eval.create_state () in
    Array.init 5 (fun frame -> List.assoc "g" (Result.get_ok (Eval.run ~state:s
      ~live:{(Frame_input.at_time (float frame)) with frame; dt = 0.125} ~time:(float frame) w)).results) in
  assert (export () = [|Eval.Float 1250.; Float 2500.; Float 3750.; Float 5000.; Float 6250.|]);
  assert (Marshal.to_string (export ()) [] = Marshal.to_string (export ()) []);
  assert (Ty.of_string "array:vec3" = Some (Ty.Array Ty.Vec3));
  assert (Ty.of_string "array:text" = None);
  assert (Result.is_error (Eval.static (check "(array/count (array/float -1))")));
  assert (Result.is_error (Eval.static (check "(array/nth (array/float 10) 10)")));
  assert (Result.is_error (Eval.run ~time:0. (check "(sum [x (array/float 2 1e308)] x)")));
  let typed = check "(array/count (array/float (frame/index)))" in
  assert (List.assoc "g" (Result.get_ok (Eval.run ~live:{(Frame_input.at_time 0.) with frame = 10000} ~time:0. typed)).results = Eval.Int 10000)

let () =
  (* Packed live maps/for/scan defer instead of trying to store residual boxes. *)
  assert (value "(array/sum (map (fn [x] (+ x t)) (array/float 10 2)))" = Eval.Float 20.);
  let live_value body = List.assoc "g" (Result.get_ok (Eval.run ~time:1.25 (check body))).results in
  assert (live_value "(array/sum (map (fn [x] (+ x t)) (array/float 10 2)))" = Eval.Float 32.5);
  assert (live_value "(array/sum (for [x (array/float 10 2)] (+ x t)))" = Eval.Float 32.5);
  assert (live_value "(array/sum (scan [s 0.0] [x (array/float 3 2)] (+ s (+ x t))))" = Eval.Float 19.5);
  assert (live_value "(let* [p (array/nth (map (fn [p] (+ p [t 0 0])) (array/vec3 3 [1 2 3])) 2)] p.x)" = Eval.Float 2.25);
  let bounded = check "(array/sum (map (fn [x] (sum [i (range 4096)] (+ x (+ i t)))) (array/float 1024)))" in
  (match Eval.run ~time:1. bounded with
   | Error d -> assert (d.Diagnostic.code = "E_EVAL_BUDGET")
   | Ok _ -> failwith "packed block bypassed the evaluation budget");
  assert (live_value "(array/sum (map (fn [x] (+ x t)) (array/float 100000 2)))" = Eval.Float 325000.);
  assert (live_value "(sum [x (array/float 100000 2)] (+ x t))" = Eval.Float 325000.);
  assert (live_value "(fold [s 0.0] [x (array/float 100000 2)] (+ s (+ x t)))" = Eval.Float 325000.);
  let forms = Result.get_ok (Syntax.parse
    "(workspace w (graph g :context value (map + (list 1 2) (array/float 2))))") in
  let _, ds = Workspace.check {Check.version = 1; kinds = []} forms in
  assert (List.exists (fun (d : Diagnostic.t) -> d.code = "E_ARRAY_TYPE") ds)
