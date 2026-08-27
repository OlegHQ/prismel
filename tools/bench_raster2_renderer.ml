open Raster2

type scenario = Basic | Path | Text | Scene3 | Offscreen
type sample = { wall:float; cpu:float; promoted:float; major:float; live:int; hash:int64 }

let scenario_name=function Basic->"basic2d"|Path->"path"|Text->"text"|Scene3->"scene3"|Offscreen->"offscreen"
let parse_scenario=function"basic"|"basic2d"->Basic|"path"->Path|"text"->Text|"scene3"->Scene3|"offscreen"->Offscreen|value->invalid_arg("unknown scenario: "^value)
let hash_bytes bytes=let h=ref 0xcbf29ce484222325L in Bytes.iter(fun c->h:=Int64.mul(Int64.logxor !h(Int64.of_int(Char.code c)))0x100000001b3L)bytes;!h
let combine a b=Int64.mul(Int64.logxor a b)0x100000001b3L
let ok=function Ok x->x|Error _->failwith"Raster2 workload failed"

let basic frame=
 let surface=ok(Surface.create~width:320~height:180())in Surface.clear surface 0x07111fffl;
 for i=0 to 127 do let x=(i*37+frame)mod 320 and y=(i*19)mod 180 in Primitive.rect surface~blend:Composite.Alpha~x~y~width:19~height:13(Int32.of_int(((i*17 land 255)lsl 24)lor 0x4080c0a0))done;
 hash_bytes(Surface.bytes surface)

let path frame=
 let p x y={Path.x=x;y}in let commands=[|Path.Move_to(p 20. 20.);Cubic_to(p 80.(20.+.float(frame mod 7)),p 180. 150.,p 290. 30.);Line_to(p 260. 160.);Line_to(p 40. 150.);Close|]in
 let mesh=ok(Path.tessellate~tolerance:0.2~fill_rule:Even_odd(Path.of_commands commands))and surface=ok(Surface.create~width:320~height:180())in
 for i=0 to Array.length mesh.indices/3-1 do let point index=let q=mesh.vertices.(mesh.indices.(3*i+index))in int_of_float q.x,int_of_float q.y in Primitive.triangle surface~blend:Composite.Alpha(point 0)(point 1)(point 2)0x22cc88d0l done;hash_bytes(Surface.bytes surface)

let text frame=
 let atlas=ok(Atlas.create~page_width:32~page_height:32~max_pages:1~max_entries:16~padding:0)in let pixels=Bytes.make(6*8*4)'\255'in for code=65 to 72 do ignore(ok(Atlas.add atlas(Atlas.Glyph{font=1L;codepoint=code;density=1})~width:6~height:8 pixels))done;
 let metric={Text.advance=6.;bearing_x=0.;bearing_y=8.;width=6;height=8}in let glyphs=Array.init 8(fun i->{Text.codepoint=65+i;metric})in let run={Text.font=1L;density=1;origin_x=float(frame mod 32);baseline=40.;color=0xffffffffl;clip=None;glyphs;kernings=[||]}in let prepared=ok(Text.prepare~atlas~page_width:32~page_height:32~resource_id:1~hard_capacity:4096 run)and surface=ok(Surface.create~width:320~height:180())in ok(Text.render prepared~target:surface);hash_bytes(Surface.bytes surface)

let scene3 frame=
 let color=ok(Surface.create~width:320~height:180())and depth=ok(Depth_stencil.create~width:320~height:180())in let white={Scene3_lighting.r=1.;g=1.;b=1.;a=1.}and black={Scene3_lighting.r=0.;g=0.;b=0.;a=1.}in let lighting={Scene3_lighting.ambient=white;lights=[||];material={ambient=black;diffuse=white;specular=black;emissive=white;shininess=1.};fog=No_fog;separate_specular=false;two_sided=false}and normal={Scene3_lighting.x=0.;y=0.;z=1.}in let vertex x y={Scene3_consumer.position={Scene3_lighting.x=x;y;z=0.5};normal;color=0xffffffffl;u=0.;v=0.}in let matrix=[|1.;0.;0.;float(frame mod 3)/.100.;0.;1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.|]in let draw={Scene3_consumer.matrix;viewport={Scene3.x=0.;y=0.;width=320.;height=180.;min_depth=0.;max_depth=1.};scissor={Triangle.x=0;y=0;width=320;height=180};topology=Triangle_list;vertices=[|vertex(-0.8)(-0.8);vertex 0.8(-0.8);vertex 0. 0.8|];indices=[|0;1;2|];lighting;shadows=[||];shading=Smooth;texture=None;cull=Cull_none;blend=Composite.Alpha}in ok(Scene3_consumer.render~target:{color;depth=Some depth;multisample=None}~clear:0x101820ffl~clear_depth:1.~draws:[|draw|]);combine(hash_bytes(Surface.bytes color))(hash_bytes(Depth_stencil.bytes depth))

let offscreen frame=
 let target=ok(Offscreen.create~depth:true~width:320~height:180())in let view=ok(Offscreen.view target)in let ir=ok(Render_ir.create[|Clear(Int32.of_int(((frame land 255)lsl 24)lor 0x2030ff));Geometry{vertices=[|10.;10.;300.;20.;160.;170.|];indices=[|0;1;2|];color=0xff8040ffl}|])in ok(Offscreen.render view~lookup:(fun _->None)ir);let capture=ok(Offscreen.capture view)in let hash=hash_bytes capture.pixels in ok(Offscreen.release_view view);ok(Offscreen.destroy target);hash

let workload scenario=match scenario with Basic->basic|Path->path|Text->text|Scene3->scene3|Offscreen->offscreen
let run_frames scenario frames=let run=workload scenario and hash=ref 0L in for frame=1 to frames do hash:=combine !hash(run frame)done;!hash
let measure scenario frames=Gc.full_major();let before=Gc.quick_stat()and times=Unix.times()and started=Unix.gettimeofday()in let hash=run_frames scenario frames in let wall=Unix.gettimeofday()-.started and after_times=Unix.times()and after=Gc.quick_stat()in{wall;cpu=(after_times.tms_utime+.after_times.tms_stime)-.(times.tms_utime+.times.tms_stime);promoted=after.promoted_words-.before.promoted_words;major=after.major_words-.before.major_words;live=after.live_words;hash}
let median values=let copy=Array.copy values in Array.sort Float.compare copy;copy.(Array.length copy/2)

let ()=
 let scenario=ref Basic and warmup=ref 2 and samples=ref 5 and frames=ref 60 and domains=ref 1 and check=ref false and json=ref true in
 let specifications=["--warmup",Arg.Set_int warmup,"warmup iterations";"--samples",Arg.Set_int samples,"measured samples";"--frames",Arg.Set_int frames,"frames per sample";"--domains",Arg.Set_int domains,"reported domain count";"--check",Arg.Set check,"run correctness checks";"--json",Arg.Set json,"emit JSON"]in
 Arg.parse specifications(fun value->scenario:=parse_scenario value)"bench_renderer [scenario] [options]";
 if !warmup<0 || !samples<=0 || !frames<=0 || !domains<=0 then invalid_arg"counts must be positive";
 for _=1 to !warmup do ignore(run_frames !scenario !frames)done;
 let results=Array.init !samples(fun _->measure !scenario !frames)in let hashes=Array.map(fun x->x.hash)results in Array.iter(fun hash->if hash<>hashes.(0)then failwith"nondeterministic output hash")hashes;
 let walls=Array.map(fun x->x.wall)results and cpus=Array.map(fun x->x.cpu)results in
 if !check&&(median walls>60.||Array.exists(fun x->x.live>1_000_000_000)results)then failwith"diagnostic benchmark threshold exceeded";
 if !json then let floats field=Array.to_list(Array.map(fun x->`Float(field x))results)in let ints field=Array.to_list(Array.map(fun x->`Int(field x))results)in
  let output=`Assoc["schema",`Int 1;"scenario",`String(scenario_name !scenario);"input",`Assoc["width",`Int 320;"height",`Int 180;"frames",`Int !frames];"warmup",`Int !warmup;"samples",`Int !samples;"domains",`Int !domains;"machine",`Assoc["os",`String Sys.os_type;"ocaml",`String Sys.ocaml_version;"word_size",`Int Sys.word_size];"wall_seconds",`List(floats(fun x->x.wall));"cpu_seconds",`List(floats(fun x->x.cpu));"promoted_words",`List(floats(fun x->x.promoted));"major_words",`List(floats(fun x->x.major));"live_words",`List(ints(fun x->x.live));"median_wall_seconds",`Float(median walls);"median_cpu_seconds",`Float(median cpus);"output_hash",`String(Printf.sprintf"%016Lx"hashes.(0))]in print_endline(Yojson.Safe.to_string output)
