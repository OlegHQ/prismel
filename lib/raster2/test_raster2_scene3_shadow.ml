open Raster2
let ok=function Ok x->x|Error _->failwith"scene shadow"
let v x y z={Scene3_lighting.x=x;y;z}
let color x={Scene3_lighting.r=x;g=x;b=x;a=1.}
let matrix=[|1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.|]
let descriptor={Scene3_lighting.ambient=color 0.;lights=[|Directional{direction=v 0. 0.(-1.);color=color 1.;intensity=1.}|];material={ambient=color 0.;diffuse=color 0.5;specular=color 0.;emissive=color 0.;shininess=1.};fog=No_fog;separate_specular=true;two_sided=false}
let fixture frame =
 let map=ok(Shadow_map.create~width:4~height:4)in ok(Shadow_map.clear map~depth:1.);ok(Shadow_map.write map~x:2~y:2~depth:0.4);
 let shadow=ok(Shadow_map.prepare map~light_kind:Directional~matrix~bias:{constant=0.;slope=0.}~kernel:Tap1)in
 let lit=ok(Scene3_lighting.prepare descriptor)and shaded=ok(Scene3_lighting.prepare_with_shadows descriptor[|Some shadow|])in
 let position=v 0. 0.(0.6+.float(frame land 1)*.0.)and normal=v 0. 0. 1. and view=v 0. 0. 1. in
 let a=Scene3_lighting.shade lit~position~normal~view~front_facing:true~texture:None~fog_distance:0.
 and b=Scene3_lighting.shade shaded~position~normal~view~front_facing:true~texture:None~fog_distance:0. in
 if a=b||b<>0x000000ffl then failwith"shadow factor";
 let pcf=ok(Shadow_map.prepare map~light_kind:Spot~matrix~bias:{constant=0.;slope=0.}~kernel:Tap9)in
 let edge=Shadow_map.visibility pcf~position:{Shadow_map.x=0.;y=0.;z=0.6}~normal_dot_light:1. in
 if edge<=0.||edge>=1. then failwith"pcf edge";
 (a,b,edge)
let ()=
 let expected=Array.init 600 fixture in
 let workers=Array.init 4(fun _->Domain.spawn(fun()->Array.init 600 fixture))in
 Array.iter(fun worker->if Domain.join worker<>expected then failwith"domain drift")workers;
 begin match Scene3_lighting.prepare_with_shadows descriptor[||]with Error Invalid_shadow->()|_->failwith"atomic shadow validation"end;
 print_endline"Raster2 deterministic Scene3 shadows passed"
