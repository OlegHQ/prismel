open Flow
open Value

let rec sample name = function
  | Ty.Int -> Int (if name = "index" || name = "active" then 0 else 2)
  | Float -> Float (if name = "ratio" then 0.5 else 1.5)
  | Bool -> Bool true | Vec3 -> Vec3 (1., 2., 3.)
  | Text | Color -> Text (if name = "axis" then "horizontal" else if name = "button" then "left" else "a")
  | List e -> List [|sample "" e; sample "" e|]
  | Array e -> Value.array_init e 2 (fun _ -> sample "" e)
  | Panel -> Struct ("ui/outline", Ty.Panel, [])
  | Scene -> Struct ("scene/merge", Ty.Scene, [])
  | World -> Struct ("world/none", Ty.World, [])
  | Settings -> Struct ("settings/config", Ty.Settings, [])
  | Editor -> Struct ("ui/workspace", Ty.Editor, [])
  | Material -> Struct ("material/standard", Ty.Material, [])
  | Drawing -> Deferred (Ty.Drawing, 0) | Geometry -> No_geo | Any -> Float 1.5
  | Record fs -> Record (List.map (fun (n,t) -> n, sample n t) fs)
  | Fn -> Fn ()

let check (o : Op.t) args =
  try
    let made = ref [] in
    let node name args = let id = List.length !made in made := (name,args) :: !made; Deferred (o.out (List.map (fun (_,v) -> Value.ty_of v) args), id) in
    let result = o.body ~live:(Frame_input.at_time 0.) ~node args in
    assert (Ty.fits (Value.ty_of result) (o.out (List.map (fun (_,v) -> Value.ty_of v) args)));
    (match o.shape with Op.Struct _ -> assert (match result with Struct _ -> true | _ -> false) | Scalar -> ());
    result
  with Value.Fail (code, msg, _) -> failwith (o.name ^ ": " ^ code ^ ": " ^ msg)

let () =
  assert (List.length Op.all = 83);
  List.iter (fun (o : Op.t) ->
    assert (Option.get (Op.find o.name o.ctx) == o);
    let s = o.signature in
    let base = List.map (fun (n,t) -> n, sample n t) s.pos in
    let optional = [base; base @ List.map (fun (n,t) -> n, sample n t) s.opt] in
    List.iter (fun args ->
      ignore (check o args);
      (match s.rest with None -> () | Some (n,t) -> ignore (check o (args @ [n,sample n t; n,sample n t])));
      List.iter (fun (n,t) ->
        let v = match List.assoc_opt n o.choices with Some (c::_) -> Text c | _ -> sample n t in
        ignore (check o (args @ [n,v]))) s.kw) optional;
    let valid = match s.rest with Some (n,t) -> base @ [n,sample n t] | None -> base in
    o.check valid;
    List.iter (fun (n,t) ->
      let v = match List.assoc_opt n o.choices with Some (c::_) -> Text c | _ -> sample n t in
      o.check (valid @ [n,v])) s.kw;
    List.iter (fun (n, choices) -> assert (List.mem_assoc n (s.pos @ s.opt @ s.kw)); assert (choices <> [])) o.choices;
    (match Op.arith o.name with
     | None -> ()
     | Some binary -> List.iter (fun (a,b) ->
         assert (binary.apply a b = check o ["a",a; "b",b]))
         [Int 2,Int 3; Float 1.5,Int 2; Vec3 (1.,2.,3.),Float 2.; Float 2.,Vec3 (1.,2.,3.)])) Op.all;
  List.iter (fun ctx ->
    List.iter (fun (o : Op.t) -> assert (o.ctx = ctx || o.ctx = Context.Value)) (Op.of_context ctx)) Context.all;
  assert ((Option.get (Op.find "rand" Context.Scene)).name = "value/rand");
  let rejects name args =
    try (Option.get (Op.find name Context.Editor)).check args; assert false
    with Value.Fail ("E_RANGE", _, _) -> () in
  rejects "ui/graph" ["view",Text "invalid"];
  rejects "ui/lisp" ["tab",Text "invalid"];
  rejects "ui/split" ["axis",Text "invalid"];
  rejects "ui/split-at" ["ratio",Float 1.];
  rejects "ui/tile" [];
  rejects "ui/switch" ["panel",sample "" Ty.Panel; "active",Int 1];
  (Option.get (Op.find "ui/graph" Context.Editor)).check ["view",Residual ()];
  let empty = {Check.version = 1; kinds = []} in
  let forms = Result.get_ok (Syntax.parse "(workspace w (graph g :context material (material/standard)))") in
  let ws, ds = Workspace.check empty forms in
  assert (ws <> None && not (List.exists (fun (d : Diagnostic.t) -> d.severity = Error) ds));
  let reserved, ds = Workspace.check empty (Result.get_ok (Syntax.parse
    "(workspace w (defmacro m [] `(standard)) (graph g :context material (m)))")) in
  assert (reserved <> None && ds = []);
  let known, ds = Workspace.check empty (Result.get_ok (Syntax.parse
    "(workspace w (graph g :context value (material/standard)))")) in
  assert (known = None && List.exists (fun (d : Diagnostic.t) -> d.code = "E_WRONG_CONTEXT") ds);
  (* Context survives aliases and function-value calls; the prefix has no semantic role. *)
  let k : Check.kind = {qualified="custom/root"; aliases=["root"]; context=Context.Scene;
    slots=[]; parameters=[]; outputs=[]} in
  let ws, ds = Workspace.check {empty with kinds=[k]} (Result.get_ok (Syntax.parse
    "(workspace w (graph g :context scene (root)))")) in
  assert (ds = []);
  let evaluated = Result.get_ok (Eval.run ~time:0. (Option.get ws)) in
  assert (List.assoc "g" evaluated.results = Eval.Struct ("custom/root", Ty.Scene, []));
  assert (Array.length evaluated.plan.nodes = 0);
  let k = {k with slots=[{Check.name="child"; required=true; rest=false}]} in
  let ws, ds = Workspace.check {empty with kinds=[k]} (Result.get_ok (Syntax.parse
    "(workspace w (graph g :context scene (first (map root (list nil)))))")) in
  assert (ds = []);
  let evaluated = Result.get_ok (Eval.run ~time:0. (Option.get ws)) in
  assert (List.assoc "g" evaluated.results = Eval.Struct ("custom/root", Ty.Scene, ["child",Eval.No_geo]));
  assert (Array.length evaluated.plan.nodes = 0)
