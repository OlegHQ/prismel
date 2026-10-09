module E=Flow.Eval
module P=Flow_ir.Packed
let ok=function Ok value->value|Error d->failwith(Flow.Diagnostic.to_string d)
let bytes value=Marshal.to_string value [Marshal.No_sharing]
let same a b=match a,b with
  |Ok a,Ok b->bytes a=bytes b
  |Error a,Error b->Flow.Diagnostic.to_string a=Flow.Diagnostic.to_string b
  |_->false
let components=function E.Float x->[|x|]|Vec2(x,y)->[|x;y|]
  |Vec3(x,y,z)->[|x;y;z|]|Vec4(x,y,z,w)->[|x;y;z;w|]|_->assert false
let width=function Flow.Ty.Float->1|Vec2->2|Vec3->3|Vec4->4|_->assert false
let source ty : Flow.Op.t={Flow_ir.Operators.noise3 with
  name="probe/data";packed_extension=None;
  signature={pos=[];opt=[];rest=None;kw=[]};out=(fun _->Flow.Ty.Array ty);
  shape=Flow.Op.Struct{splice=false};check=(fun _->());
  body=(fun ~live:_ ~node:_ _->Flow.Value.Struct("probe/data",Flow.Ty.Array ty,[]))}
let workspace ?(bindings="") ops body=
  let forms=ok(Flow.Syntax.parse("(workspace w (graph g :context value (let* ["^bindings^
    " tested "^body^"] 0.0)))"))in
  match Flow.Workspace.check ~ops {Flow.Check.version=1;kinds=[]} forms with
  |Some workspace,[]->workspace
  |_,ds->failwith(String.concat "; "(List.map Flow.Diagnostic.to_string ds))
let evaluate workspace=List.assoc ["g";"tested"](ok(E.static ~record:true workspace)).records
  |> List.hd |> snd
let fixture ?override ?seed ty reducer=
  let width=width ty in
  let seed=Option.value ~default:(if width=1 then "-0.0" else
    "["^String.concat " "(List.init width(fun _->"-0.0"))^"]") seed in
  let body=match width with 1->"[s uv.x uv.y t]"|2->"[s.x s.y uv.x t]"
    |3->"[s.x s.y s.z t]"|_->"[s.x s.y s.z s.w]"in
  let workspace=workspace ~bindings:("data (probe/data) s (reduce "^reducer^" "^seed^" data)")
    [source ty]("(fn [(uv : vec2)] "^body^")")in
  (* Exercise the compiler's independent declaration guard even for an unchecked extension. *)
  let workspace=Option.fold ~none:workspace ~some:(fun op->{workspace with ops=op::workspace.ops})override in
  let fn=match evaluate workspace with E.Fn fn->fn|_->assert false in
  let sum=List.assoc "s"(E.Private.function_bindings fn)in
  let uv=E.Vec2_array(Array.init(32769*2)(fun i->float(i mod 17)/.16.))in
  let value=ok(E.Private.map_function ~signature:Flow.Ty.{params=[Vec2];result=Vec4} fn [uv])in
  let packed=match value with E.Residual r->
    P.compile r(E.Private.residual_view r).term |> Option.get|_->assert false in
  value,sum,packed
let observed ?fast counter=Some((fun()->0.),(fun packed ~seconds:_ ~reference->
  if not reference && not(P.Private.view packed).collecting then begin
    incr counter;Option.iter(fun expected->assert(P.Private.ordered_add packed=expected))fast
  end))
let cancellation i=match i mod 5 with 0->1e16|1->1.|2-> -1e16|3->1.|_-> -0.
let data ty count time=
  let width=width ty in
  let values=Array.init(count*width)(fun i->if width=1 then
    (if i=count-1 then time else cancellation i)
    else match i mod width with
    |0->cancellation(i/width)|1->time|2-> -0.|_->cancellation(i/width)+.time)in
  match width with 1->E.Float_array values|2->Vec2_array values
    |3->Vec3_array values|_->Vec4_array values
let resolve_source current=function
  |E.Struct("probe/data",_,_)->Ok !current
  |_->Error(Flow.Diagnostic.error ~code:"E_DATA_SOURCE" "Unexpected source.")
let ()=
  let addition=Option.get(Flow.Op.find "+" Flow.Context.value)in
  let custom={addition with arithmetic=None;
    body=(fun ~live:_ ~node:_ args->match List.map snd args with
      |[a;b]->Flow.Value.Float(Flow.Value.num a-.Flow.Value.num b)|_->assert false)}in
  List.iter(fun(ty,reducer,override,seed,packed_expected,fast)->
    let value,sum,packed=fixture ?override ?seed ty reducer in
    let counts=if ty=Flow.Ty.Vec3 && reducer="+"then
      [0;1;1023;1024;1025;16383;16384;16385;32769]else[0;32769]in
    List.iter(fun count->List.iter(fun time->
      let current=ref(data ty count time)in let original=bytes !current in
      let live={(Frame_input.at_time time)with frame=int_of_float(time*.4.)}in
      let expected=E.Private.force_reference ~resolve:(resolve_source current) value ~live in
      let scalar=ok(E.Private.force_reference ~resolve:(resolve_source current) sum ~live)in
      if seed=Some "0" then (match count,scalar with
        |0,E.Int 0->()|n,E.Float _ when n>0->()|_->assert false);
      let uniform=match scalar with E.Int n->[|float n|]|_->components scalar in
      List.iter(fun domains->Rays_math.Parallel.run ~domains(fun()->
        let cpu=ref 0 and gpu=ref 0 in
        assert(same(P.force ~resolve:(resolve_source current) ?measure:(observed ~fast cpu) packed ~live)expected);
        assert(same(Flow_ir.Executor.force ~resolve:(resolve_source current)
          (ok(Flow_ir.Executor.compile sum)) ~live)(Ok scalar));
        let prepared=ok(P.Private.prepare ~resolve:(resolve_source current) ?measure:(observed ~fast gpu) packed ~live)in
        assert(Array.exists(fun actual->bytes actual=bytes uniform)prepared.uniforms);
        assert((!cpu>0)=packed_expected && (!gpu>0)=packed_expected);
        assert(bytes !current=original))) [1;8]) [0.;0.25;0.5]) counts)
    [Flow.Ty.Float,"+",None,None,true,true;
     Float,"(fn [a x] (+ a x))",None,None,true,true;
     Vec2,"+",None,None,true,true;
     Vec3,"+",None,None,true,true;
     Vec4,"+",None,None,true,true;
     Vec3,"(fn [a x] (+ a x))",None,None,true,true;
     Float,"(fn [a x] (+ (* a 0.99) x))",None,None,true,false;
     Vec3,"(fn [a x] (+ x a))",None,None,true,false;
     Float,"min",None,None,false,false;
     Float,"+",Some custom,None,false,false;
     Float,"+",None,Some "0",false,false];
  List.iter(fun body->
    let value=evaluate(workspace [] body)in
    let packed=match value with E.Residual r->P.compile r(E.Private.residual_view r).term
      |> Option.get|_->assert false in
    assert(not(P.Private.ordered_add packed));
    List.iter(fun domains->Rays_math.Parallel.run ~domains(fun()->
      let live=Frame_input.at_time 0. in
      assert(same(P.force packed ~live)(E.Private.force_reference value ~live))))[1;8])
    ["(scan [a [t 0.0]] [x (map (fn [x] [x -0.0]) (array/range 32769))] (+ a x))";
     "(fold [a [t 0.0]] [x (array/range 32769)] (+ a x))"];
  let value=evaluate(workspace []
    "(fold [a [t 0.0 0.0]] [x (array/vec3 32769 [0.25 -0.0 1.0])] (+ a x))")in
  let packed=match value with E.Residual r->P.compile r(E.Private.residual_view r).term
    |> Option.get|_->assert false in
  (* Same instructions as a supported reduction, but the fold is a Product loop. *)
  assert((P.Private.view packed).code=[|P.Input(0,3,0);Input(0,3,1);Input(0,3,2);
    Accumulator 0;Accumulator 1;Accumulator 2;
    Binary(Add,3,0);Binary(Add,4,1);Binary(Add,5,2)|]);
  assert(not(P.Private.ordered_add packed));
  List.iter(fun domains->Rays_math.Parallel.run ~domains(fun()->
    let live=Frame_input.at_time 0.25 in
    assert(same(P.force packed ~live)(E.Private.force_reference value ~live))))[1;8];
  (* A resolver may advance a fold before a later reduction error; both callers roll it back. *)
  let fold=evaluate(workspace [] "(state [a 0.0] (+ a 1.0))")in
  let live=Frame_input.at_time 0. in
  List.iter(fun(ty,failed_component)->
  let value,sum,packed=fixture ty "+"in
  let width=width ty in
  List.iter(fun domains->Rays_math.Parallel.run ~domains(fun()->
    List.iter(fun count->List.iter(fun gpu->
      let state=E.create_state()in let before=E.state_stamp state in
      let values=Array.init(count*width)(fun i->
        if i mod width=failed_component && i/width>=count-2 then 1e308 else 0.)in
      let current=ref(if width=1 then E.Float_array values else E.Vec3_array values)in
      let original=bytes !current in
      let resolve value=ignore(ok(E.Private.force_reference ~state fold ~live));resolve_source current value in
      let reference_state=E.create_state()in
      let reference_resolve value=ignore(ok(E.Private.force_reference ~state:reference_state fold ~live));
        resolve_source current value in
      let expected=E.Private.force_reference ~state:reference_state ~resolve:reference_resolve value ~live in
      assert(Result.is_error expected && E.state_stamp reference_state=before);
      let result=if gpu then Result.map(fun _->E.Int 0)(P.Private.prepare ~state ~resolve packed ~live)
        else P.force ~state ~resolve packed ~live in
      assert(same result expected && E.state_stamp state=before);
      assert(bytes !current=original);
      current:=(if width=1 then E.Float_array[|1.;2.;3.|]
        else E.Vec3_array[|1.;2.;3.;4.;5.;6.|]);
      let expected=E.Private.force_reference ~resolve:(resolve_source current) value ~live in
      if gpu then begin
        let prepared=ok(P.Private.prepare ~state ~resolve packed ~live)in
        let expected_uniform=ok(E.Private.force_reference ~resolve:(resolve_source current) sum ~live)
          |> components in
        assert(Array.exists(fun actual->bytes actual=bytes expected_uniform)prepared.uniforms)
      end
      else assert(same(P.force ~state ~resolve packed ~live)expected);
      assert(ok(E.Private.force_reference ~state fold ~live)=E.Float 1.)) [false;true]) [2;16385])) [1;8])
    [Flow.Ty.Float,0;Vec3,0;Vec3,1;Vec3,2];
  print_endline "Captured uniform packed/reference parity, ordered named reductions, changing inputs, errors and rollback passed"
