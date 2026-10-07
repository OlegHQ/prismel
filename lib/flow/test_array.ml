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
  let forms = Result.get_ok (Syntax.parse
    "(workspace w (graph g :context value (map + (list 1 2) (array/float 2))))") in
  let _, ds = Workspace.check {Check.version = 1; kinds = []} forms in
  assert (List.exists (fun (d : Diagnostic.t) -> d.code = "E_ARRAY_TYPE") ds)
