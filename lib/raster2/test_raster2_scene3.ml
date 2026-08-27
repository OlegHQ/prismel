open Raster2
let ok=function Ok x->x|Error _->failwith"scene3 error"
let matrix=[|1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.|]
let viewport={Scene3.x=0.;y=0.;width=100.;height=50.;min_depth=0.;max_depth=1.}
let scissor={Triangle.x=3;y=4;width=80;height=40}
let vertex x y z={Scene3.x=x;y;z;color=0xffffffffl;u=x;v=y}
let encode topology vertices indices=Marshal.to_bytes(ok(Scene3.prepare~matrix~viewport~scissor~topology~vertices~indices))[]
let ()=
 let triangle=[|vertex(-0.5)(-0.5)0.5;vertex 0.5(-0.5)0.5;vertex 0. 0.5 0.5|]in
 let prepared=ok(Scene3.prepare~matrix~viewport~scissor~topology:Triangle_list~vertices:triangle~indices:[|0;1;2|])in
 assert(Array.length prepared.triangles=1&&prepared.clip=scissor);
 let near=[|vertex(-0.5)(-0.5)(-0.5);vertex 0.5(-0.5)0.5;vertex 0. 0.5 0.5|]in
 assert(Array.length(ok(Scene3.prepare~matrix~viewport~scissor~topology:Triangle_list~vertices:near~indices:[|0;1;2|])).triangles=2);
 let quad=[|vertex(-0.5)(-0.5)0.5;vertex 0.5(-0.5)0.5;vertex(-0.5)0.5 0.5;vertex 0.5 0.5 0.5|]in
 assert(Array.length(ok(Scene3.prepare~matrix~viewport~scissor~topology:Triangle_strip~vertices:quad~indices:[|0;1;2;3|])).triangles=2);
 assert(Array.length(ok(Scene3.prepare~matrix~viewport~scissor~topology:Triangle_fan~vertices:quad~indices:[|0;1;3;2|])).triangles=2);
 List.iter(fun frame->let vertices=Array.map(fun (v:Scene3.vertex)->{v with u=v.u+.float frame})triangle in let expected=encode Triangle_list vertices[|0;1;2|]in let workers=Array.init 4(fun _->Domain.spawn(fun()->encode Triangle_list vertices[|0;1;2|]))in Array.iter(fun worker->assert(Domain.join worker=expected))workers)[1;600];
 (match Scene3.prepare~matrix:[|1.|]~viewport~scissor~topology:Triangle_list~vertices:triangle~indices:[|0;1;2|]with Error Scene3.Invalid_matrix->()|_->failwith"matrix");
 print_endline"Raster2 deterministic Scene3 preparation passed"
