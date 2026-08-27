open Raster2.Scene3_lighting
let ok = function Ok x -> x | Error _ -> failwith "lighting validation"
let white={r=1.;g=1.;b=1.;a=1.} and black={r=0.;g=0.;b=0.;a=1.}
let v x y z={x;y;z}
let material={ambient=black;diffuse={white with r = 0.25;g = 0.25;b = 0.25};specular={white with r = 0.5;g = 0.5;b = 0.5};emissive=black;shininess=8.}
let descriptor={ambient=black;lights=[|Directional{direction=v 0. 0. (-1.);color=white;intensity=1.}|];material;fog=No_fog;separate_specular=true;two_sided=true}
let render prepared frame =
  let normal=orient_normal ~reversed_winding:(frame land 1=0) (v 0. 0. 1.) in
  let normal=if frame land 1=0 then orient_normal ~reversed_winding:true normal else normal in
  shade prepared ~position:(v 0. 0. 0.) ~normal ~view:(v 0. 0. 1.) ~front_facing:true ~texture:(Some 0x808080ffl) ~fog_distance:0.
let spot concentration cutoff = Spot {position=v 0. 0. 2.;
  direction=v 0. 0.(-1.);inner_cos=cos cutoff;outer_cos=cos cutoff;
  concentration;color=white;intensity=1.;
  attenuation={constant=1.;linear=0.;quadratic=0.}}
let spot_material={material with diffuse=white;specular=black;shininess=0.}
let spot_descriptor concentration cutoff={descriptor with
  lights=[|spot concentration cutoff|];material=spot_material;
  separate_specular=false}
let shade_spot prepared position=shade prepared~position~normal:(v 0. 0. 1.)
  ~view:(v 0. 0. 1.)~front_facing:true~texture:None~fog_distance:0.
let red value=Int32.(to_int(logand(shift_right_logical value 24)0xffl))
let ()=
  let prepared=ok(prepare descriptor) in
  let lit=render prepared 1 in if lit=0l then failwith"unlit";
  if render prepared 2<>lit then failwith"reversed authored normal";
  let fogged=ok(prepare{descriptor with fog=Linear{color={r=1.;g=0.;b=0.;a=1.};near=0.;far=1.}})in
  if shade fogged~position:(v 0. 0. 0.)~normal:(v 0. 0. 1.)~view:(v 0. 0. 1.)~front_facing:true~texture:None~fog_distance:1.<>0xff0000ffl then failwith"fog";
  let separate=lit and combined=shade(ok(prepare{descriptor with separate_specular=false}))~position:(v 0. 0. 0.)~normal:(v 0. 0. 1.)~view:(v 0. 0. 1.)~front_facing:true~texture:(Some 0x808080ffl)~fog_distance:0. in
  if separate=combined then failwith"separate specular";
  begin match prepare{descriptor with material={material with shininess=nan}}with Error Invalid_shininess->()|_->failwith"nonfinite"end;
  let exponent0=ok(prepare(spot_descriptor 0. 1.))
  and exponent1=ok(prepare(spot_descriptor 1. 1.))
  and exponent32=ok(prepare(spot_descriptor 32. 1.))in
  let sample=v 0.5 0. 0. in
  let value0=shade_spot exponent0 sample and value1=shade_spot exponent1 sample
  and value32=shade_spot exponent32 sample in
  if not(red value0>red value1&&red value1>red value32)then
    failwith"spot exponent policy";
  let high_cutoff=ok(prepare(spot_descriptor 1. 1.55))in
  if shade_spot high_cutoff(v 10. 0. 0.)=0x000000ffl then
    failwith"high cutoff rejected an inside sample";
  begin match prepare(spot_descriptor nan 1.)with
  | Error Invalid_spot->()|_->failwith"nonfinite spot concentration"
  end;
  let expected=Array.init 600(fun i->render prepared(i+1))in
  let workers=Array.init 4(fun _->Domain.spawn(fun()->Array.init 600(fun i->render prepared(i+1))))in
  Array.iter(fun worker->if Domain.join worker<>expected then failwith"domain drift")workers;
  let spot_expected=Array.init 600(fun _->shade_spot exponent32 sample)in
  let spot_workers=Array.init 4(fun _->Domain.spawn(fun()->
    Array.init 600(fun _->shade_spot exponent32 sample)))in
  Array.iter(fun worker->if Domain.join worker<>spot_expected then
    failwith"spot domain drift")spot_workers;
  print_endline"Raster2 deterministic Scene3 lighting passed"
