open Raster2
let ok=function Ok x->x|Error _->failwith"mesh cache"
let vertex x y={Scene3.x=x;y;z=0.5;color=0xffffffffl;u=0.;v=0.}
let vertices=[|vertex(-0.5)(-0.5);vertex 0.5(-0.5);vertex 0. 0.5|]
let indices=[|0;1;2|]
let viewport={Scene3.x=0.;y=0.;width=8.;height=8.;min_depth=0.;max_depth=1.}
let scissor={Triangle.x=0;y=0;width=8;height=8}
let matrix frame=[|1.;0.;0.;float frame*.0.001;0.;1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.|]
let run ()=
 let cache=ok(Scene3_mesh_cache.create~capacity:4)and key={Scene3_mesh_cache.id=1L;version=1L;layout=7L}in
 let first=ok(Scene3_mesh_cache.prepare cache~key~topology:Triangle_list~vertices~indices)in
 let initial=Scene3_mesh_cache.counters cache in
 for frame=1 to 600 do let same=ok(Scene3_mesh_cache.prepare cache~key~topology:Triangle_list~vertices~indices)in
   if same!=first then failwith"camera replaced mesh";ignore(ok(Scene3_mesh_cache.prepare_view same~matrix:(matrix frame)~viewport~scissor))done;
 let after=Scene3_mesh_cache.counters cache in
 if after.preparation_bytes<>initial.preparation_bytes||after.upload_intent_bytes<>initial.upload_intent_bytes then failwith"camera upload drift";
 for version=2 to 100_001 do ignore(ok(Scene3_mesh_cache.prepare cache~key:{key with id=Int64.of_int version;version=Int64.of_int version}~topology:Triangle_list~vertices~indices))done;
 if Scene3_mesh_cache.length cache<>4 then failwith"unbounded cache";
 (Scene3_mesh_cache.keys_lru cache,Scene3_mesh_cache.counters cache)
let ()=
 let expected=run()in let workers=Array.init 4(fun _->Domain.spawn run)in
 Array.iter(fun worker->if Domain.join worker<>expected then failwith"domain drift")workers;
 let cache=ok(Scene3_mesh_cache.create~capacity:1)in
 begin match Scene3_mesh_cache.prepare cache~key:{id=(-1L);version=0L;layout=0L}~topology:Triangle_list~vertices~indices with Error Invalid_key->()|_->failwith"key"end;
 print_endline"Raster2 bounded deterministic Scene3 mesh cache passed"
