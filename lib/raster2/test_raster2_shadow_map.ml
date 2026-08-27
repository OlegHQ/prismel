open Raster2.Shadow_map
let ok=function Ok x->x|Error _->failwith"shadow error"
let identity=[|1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.|]
let v x y z={x;y;z}
let check_snapshot prepared =
  let first = snapshot prepared in
  if first.width <> 4 || first.height <> 4 then failwith "snapshot extent";
  if Array.length first.depths <> 16 || abs_float (first.depths.(10) -. 0.4) > 1e-6 then
    failwith "snapshot depth";
  if first.matrix <> identity || first.bias <> { constant = 0.; slope = 0. }
     || first.kernel <> Tap9 || first.strength <> 1.
  then failwith "snapshot metadata";
  first.matrix.(0) <- 9.;
  first.depths.(10) <- 0.;
  let second = snapshot prepared in
  if second.matrix.(0) <> 1. || abs_float (second.depths.(10) -. 0.4) > 1e-6 then
    failwith "snapshot alias"
let fixture kernel =
  let map=ok(create~width:4~height:4)in ok(clear map~depth:1.);
  ok(write map~x:2~y:2~depth:0.4);
  let shadow=ok(prepare map~light_kind:Directional~matrix:identity~bias:{constant=0.;slope=0.}~kernel)in
  let dark=visibility shadow~position:(v 0. 0. 0.6)~normal_dot_light:1.
  and lit=visibility shadow~position:(v 0. 0. 0.3)~normal_dot_light:1.
  and edge=visibility shadow~position:(v 2. 0. 0.6)~normal_dot_light:1. in
  if dark>=1.||lit<>1.||edge<>1. then failwith"visibility";
  let biased=ok(prepare map~light_kind:Spot~matrix:identity~bias:{constant=0.25;slope=0.}~kernel:Tap1)in
  if visibility biased~position:(v 0. 0. 0.6)~normal_dot_light:1.<>1. then failwith"bias";
  (dark,lit,edge)
let ()=
  ignore(fixture Tap1);ignore(fixture Tap4);let expected=Array.init 600(fun _->fixture Tap9)in
  let map=ok(create~width:4~height:4)in ok(clear map~depth:1.);
  ok(write map~x:2~y:2~depth:0.4);
  check_snapshot (ok (prepare map ~light_kind:Directional ~matrix:identity
    ~bias:{constant=0.;slope=0.} ~kernel:Tap9));
  let workers=Array.init 4(fun _->Domain.spawn(fun()->Array.init 600(fun _->fixture Tap9)))in
  Array.iter(fun worker->if Domain.join worker<>expected then failwith"domain drift")workers;
  begin match prepare(ok(create~width:1~height:1))~light_kind:Directional~matrix:[|nan|]~bias:{constant=0.;slope=0.}~kernel:Tap1 with Error Invalid_matrix->()|_->failwith"matrix"end;
  print_endline"Raster2 deterministic shadow map passed"
