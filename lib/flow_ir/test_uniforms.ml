module E=Flow.Eval
module P=Flow_ir.Packed
let ok=function Ok value->value|Error d->failwith(Flow.Diagnostic.to_string d)
let bytes value=Marshal.to_string value [Marshal.No_sharing]
let same a b=match a,b with
  |Ok a,Ok b->bytes a=bytes b
  |Error a,Error b->Flow.Diagnostic.to_string a=Flow.Diagnostic.to_string b
  |_->false
let components=function E.Float x->[|x|]|Vec3(x,y,z)->[|x;y;z|]|_->assert false
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
  let vector=ty=Flow.Ty.Vec3 in
  let seed=Option.value ~default:(if vector then "[-0.0 -0.0 -0.0]"else "-0.0") seed in
  let body=if vector then "[s.x s.y s.z t]"else "[s uv.x uv.y t]"in
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
let observed counter=Some((fun()->0.),(fun packed ~seconds:_ ~reference->
  if not reference && not(P.Private.view packed).collecting then incr counter))
let cancellation i=match i mod 5 with 0->1e16|1->1.|2-> -1e16|3->1.|_-> -0.
let data ty count time=if ty=Flow.Ty.Float then
    E.Float_array(Array.init count(fun i->if i=count-1 then time else cancellation i))
  else E.Vec3_array(Array.init(count*3)(fun i->match i mod 3 with
    |0->cancellation(i/3)|1->time|_-> -0.))
let resolve_source current=function
  |E.Struct("probe/data",_,_)->Ok !current
  |_->Error(Flow.Diagnostic.error ~code:"E_DATA_SOURCE" "Unexpected source.")
let ()=
  let addition=Option.get(Flow.Op.find "+" Flow.Context.value)in
  let custom={addition with arithmetic=None;
    body=(fun ~live:_ ~node:_ args->match List.map snd args with
      |[a;b]->Flow.Value.Float(Flow.Value.num a-.Flow.Value.num b)|_->assert false)}in
  List.iter(fun(ty,reducer,override,seed,packed_expected)->
    let value,sum,packed=fixture ?override ?seed ty reducer in
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
        assert(same(P.force ~resolve:(resolve_source current) ?measure:(observed cpu) packed ~live)expected);
        assert(same(Flow_ir.Executor.force ~resolve:(resolve_source current)
          (ok(Flow_ir.Executor.compile sum)) ~live)(Ok scalar));
        let prepared=ok(P.Private.prepare ~resolve:(resolve_source current) ?measure:(observed gpu) packed ~live)in
        assert(Array.exists(fun actual->bytes actual=bytes uniform)prepared.uniforms);
        assert((!cpu>0)=packed_expected && (!gpu>0)=packed_expected);
        assert(bytes !current=original))) [1;8]) [0.;0.25;0.5]) [0;32769])
    [Flow.Ty.Float,"+",None,None,true;
     Float,"(fn [a x] (+ a x))",None,None,true;
     Vec3,"+",None,None,true;
     Vec3,"(fn [a x] (+ a x))",None,None,true;
     Float,"min",None,None,false;
     Float,"+",Some custom,None,false;
     Float,"+",None,Some "0",false];
  (* A resolver may advance a fold before a later reduction error; both callers roll it back. *)
  let value,_,packed=fixture Flow.Ty.Float "+"in
  let fold=evaluate(workspace [] "(state [a 0.0] (+ a 1.0))")in
  let live=Frame_input.at_time 0. in
  List.iter(fun domains->Rays_math.Parallel.run ~domains(fun()->
    List.iter(fun gpu->
      let state=E.create_state()in let before=E.state_stamp state in
      let current=ref(E.Float_array[|1e308;1e308|])in
      let resolve value=ignore(ok(E.Private.force_reference ~state fold ~live));resolve_source current value in
      let reference_state=E.create_state()in
      let reference_resolve value=ignore(ok(E.Private.force_reference ~state:reference_state fold ~live));
        resolve_source current value in
      let expected=E.Private.force_reference ~state:reference_state ~resolve:reference_resolve value ~live in
      assert(Result.is_error expected && E.state_stamp reference_state=before);
      let result=if gpu then Result.map(fun _->E.Int 0)(P.Private.prepare ~state ~resolve packed ~live)
        else P.force ~state ~resolve packed ~live in
      assert(same result expected && E.state_stamp state=before);
      current:=E.Float_array[|1.;2.;3.|];
      let expected=E.Private.force_reference ~resolve:(resolve_source current) value ~live in
      if gpu then ignore(ok(P.Private.prepare ~state ~resolve packed ~live))
      else assert(same(P.force ~state ~resolve packed ~live)expected);
      assert(ok(E.Private.force_reference ~state fold ~live)=E.Float 1.)) [false;true])) [1;8];
  print_endline "Captured uniform packed/reference parity, ordered named reductions, changing inputs, errors and rollback passed"
