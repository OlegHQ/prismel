let ok = function Ok value -> value | Error error -> failwith (Flow.Diagnostic.to_string error)
let compile body =
  let source="(workspace w (graph g :context value (let* [tested " ^ body ^ "] 0.0)))" in
  let forms=ok (Flow.Syntax.parse source) in
  let workspace=match Flow.Workspace.check ~ops:Flow_ir.Operators.all {Flow.Check.version=1;kinds=[]} forms with
    | Some workspace, [] -> workspace
    | _,errors -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string errors)) in
  let evaluated=ok (Flow.Eval.static ~record:true workspace) in
  match List.assoc ["g";"tested"] evaluated.records |> List.hd |> snd with
  | Flow.Eval.Residual residual ->
      Option.get (Flow_ir.Packed.compile residual (Flow.Eval.Private.residual_view residual).term)
  | _ -> failwith "expected live packed program"
let fixtures count =
  let array="(array/range " ^ string_of_int count ^ ")" in
  ["arithmetic",compile ("(map (fn [x] (+ (* x 2) t)) " ^ array ^ ")");
   "select",compile ("(map (fn [x] (if (< x t) (+ x 1) (- x 1))) " ^ array ^ ")");
   "noise",compile ("(map (fn [x] (noise3 [(* x 0.02) t 0.25] :seed 31 :octaves 3)) " ^ array ^ ")")]
