module N = Rays_math.Noise
module P = Rays_math.Parallel
let bits x y = Int64.bits_of_float x = Int64.bits_of_float y
let rejects f = match f () with
  | exception Invalid_argument _ -> ()
  | () -> failwith "accepted an invalid noise span"

let () =
  let count = 2051 in
  let x = Array.init count (fun i -> float i *. 0.137 -. 256.2)
  and y = Array.init count (fun i -> sin (float i *. 0.37))
  and z = Array.init count (fun i -> float (i mod 19) *. (-0.31)) in
  List.iter (fun seed ->
    let noise = N.create seed in
    let reference = Array.init count (fun i -> N.sample3 noise ~x:x.(i) ~y:y.(i) ~z:z.(i)) in
    List.iter (fun domains -> P.run ~domains (fun () ->
      let out = Array.make count (-1.) in
      P.for_ ~chunk_size:1 ~start:0 ~finish:2 (fun block ->
        let first = block * 1024 and last = min count ((block + 1) * 1024) in
        N.Private.sample3_into noise ~first ~last ~x ~y ~z ~output:out ());
      assert (Array.for_all2 bits out reference))) [1; 8];
    let scratch = Array.make (count * 4) (-1.) in
    Array.blit x 0 scratch 0 count;
    Array.blit y 0 scratch count count;
    Array.blit z 0 scratch (count * 2) count;
    N.Private.sample3_into noise ~first:1 ~last:(count - 1)
      ~x:scratch ~y:scratch ~z:scratch ~output:scratch
      ~y_offset:count ~z_offset:(count * 2) ~output_offset:(count * 3) ();
    assert (scratch.(count * 3) = -1. && scratch.(count * 4 - 1) = -1.);
    for i = 1 to count - 2 do assert (bits scratch.(count * 3 + i) reference.(i)) done;
    let in_place = Array.copy x in
    N.Private.sample3_into noise ~first:0 ~last:count ~x:in_place ~y ~z ~output:in_place ();
    assert (Array.for_all2 bits in_place reference);
    List.iter (fun frequency ->
      let out = Array.make count 0. in
      N.Private.sample3_into noise ~first:0 ~last:count ~frequency ~x ~y ~z ~output:out ();
      Array.iteri (fun i sample -> assert (bits sample (N.sample3 noise
        ~x:(x.(i) *. frequency) ~y:(y.(i) *. frequency) ~z:(z.(i) *. frequency)))) out)
      [0.; -0.; 0.16; -3.7];
    let out = [| -1. |] in
    List.iter (fun invalid ->
      N.Private.sample3_into noise ~first:0 ~last:1 ~x:[|invalid|] ~y:[|0.|] ~z:[|0.|] ~output:out ();
      assert (Float.is_nan out.(0))) [nan; infinity; neg_infinity];
    rejects (fun () -> N.Private.sample3_into noise ~first:(-1) ~last:1 ~x ~y ~z ~output:in_place ());
    rejects (fun () -> N.Private.sample3_into noise ~first:2 ~last:1 ~x ~y ~z ~output:in_place ());
    rejects (fun () -> N.Private.sample3_into noise ~first:0 ~last:count ~x_offset:max_int ~x ~y ~z ~output:in_place ());
    rejects (fun () -> N.Private.sample3_into noise ~first:0 ~last:(count - 1)
      ~x:in_place ~y ~z ~output:in_place ~output_offset:1 ());
    N.Private.sample3_into noise ~first:count ~last:count ~x ~y ~z ~output:in_place ())
    [0; 42; -17];
  List.iter (fun (op : Flow.Op.t) ->
    assert (Flow.Op.validate [op] = None);
    assert (Option.get (Flow.Op.find ~extra:Flow_ir.Operators.all op.name Flow.Context.sop) == op);
    let result = op.body ~live:(Frame_input.at_time 0.)
      ~node:(fun _ _ -> failwith "noise created a geometry node")
      ["position", Flow.Value.Vec3 (0.37, -1.25, 17.4)] in
    assert (Flow.Ty.fits (Flow.Value.ty_of result) (op.out [Flow.Ty.Vec3]));
    match result with
    | Flow.Value.Float n -> assert (bits n (N.sample3 (N.create 0) ~x:0.37 ~y:(-1.25) ~z:17.4))
    | _ -> assert false) [Flow_ir.Operators.noise3];
  print_endline "Packed noise spans, scalar bits and one/eight-domain parity passed"

let () =
  let noise = Flow_ir.Operators.noise3 in
  assert (Flow.Op.packed_kind noise = Some Flow.Op.Noise3);
  assert (noise.packed_extension = Some Flow.Packed_ops.Noise3);
  List.iter (fun (op : Flow.Op.t) ->
    assert (op.packed_extension = None && Flow.Op.packed_kind op = None))
    (List.filter (fun (op : Flow.Op.t) -> op.name <> "noise3") Flow_ir.Operators.all);
  let reversed = {noise with signature = {noise.signature with kw = List.rev noise.signature.kw}} in
  assert (Flow.Op.validate [reversed] = None && Flow.Op.packed_kind reversed = Some Flow.Op.Noise3);
  List.iter (fun (op : Flow.Op.t) ->
    assert (Flow.Op.packed_kind op = None);
    match Flow.Op.validate [op] with
    | Some d -> assert (d.code = "E_OP_DECLARATION" && String.length d.message > 0)
    | None -> assert false)
    [{noise with signature = {noise.signature with pos = ["position", Flow.Ty.Vec2]}};
     {noise with out = (fun _ -> Flow.Ty.Vec3)};
     {noise with signature = {noise.signature with kw = ["seed", Flow.Ty.Int; "seed", Flow.Ty.Int]}};
     {noise with signature = {noise.signature with kw = ["seed", Flow.Ty.Int; "octaves", Flow.Ty.Float]}};
     {noise with name = "other_noise"}; {noise with live = true}];
  let sine = Option.get (Flow.Op.find "sin" Flow.Context.value) in
  let counterfeit = {sine with name = "noise3"} in
  assert (Flow.Op.validate [counterfeit] = None && Flow.Op.packed_kind counterfeit = None);
  let compile op body source =
    let text = "(workspace w (graph g :context value (let* [tested (map (fn [p] "
      ^ body ^ ") " ^ source ^ ")] 0.0)))" in
    let forms = Result.get_ok (Flow.Syntax.parse text) in
    let workspace = match Flow.Workspace.check ~ops:[op] {Flow.Check.version=1;kinds=[]} forms with
      | Some w, [] -> w
      | _, ds -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string ds)) in
    let evaluated = Result.get_ok (Flow.Eval.static ~record:true workspace) in
    match List.assoc ["g";"tested"] evaluated.records |> List.hd |> snd with
    | Flow.Eval.Residual residual ->
        Flow_ir.Packed.compile residual (Flow.Eval.Private.residual_view residual).term
    | _ -> failwith "capability test did not defer its map" in
  assert (Option.is_some (compile noise "(noise3 (+ p [t 0 0]))" "(array/vec3 2051 [0.3 0.7 -0.2])"));
  assert (compile counterfeit "(noise3 (+ p t))" "(array/range 2051)" = None)
