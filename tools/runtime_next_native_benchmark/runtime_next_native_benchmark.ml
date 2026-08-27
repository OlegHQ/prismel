type scenario = Basic | Pxui | Canvas | Scene3 | Shattered
type visibility=Visible|Hidden
type window_facts={pixel_density:float;display_scale:float;drawable_width:int;drawable_height:int}
type acceptance_artifact={pieces:int;triangles:int;render_vertices:int;cook_seconds:float;cook_seconds_four:float;pack_seconds:float;topology_hash:string;attribute_hash:string;order_hash:string;render_hash:string;vertices:bytes;indices:bytes}

type counters = {
  mutable buffer_creates : int;
  mutable buffer_bytes : int64;
  mutable submissions : int;
  mutable render_passes : int;
  mutable draws : int;
}

let get = function Ok value -> value | Error error ->
  failwith (Ogpu.Error.to_string error)
let metal = function Ok value -> value | Error error ->
  failwith (Format.asprintf "%a" Metal.pp_error error)
let sdl operation = function Ok value -> value | Error error ->
  failwith (operation ^ ": " ^ Format.asprintf "%a" Sdl3.pp_error error)

let scenario_name = function Basic->"basic"|Pxui->"pxui-like"|Canvas->"canvas-like"|Scene3->"scene3-double68"|Shattered->"shattered-cube"
let parse = function "basic"->Basic|"pxui"->Pxui|"canvas"->Canvas|"scene3"->Scene3|"shattered"->Shattered|value->invalid_arg("unknown scenario: "^value)
let percentile p values=let copy=Array.copy values in Array.sort Float.compare copy;copy.(max 0(min(Array.length copy-1)(int_of_float(Float.ceil(p*.float(Array.length copy)))-1)))
let rss_kib()=let argv=[|"/bin/ps";"-o";"rss=";"-p";string_of_int(Unix.getpid())|]in let input=Unix.open_process_args_in argv.(0)argv in Fun.protect~finally:(fun()->ignore(Unix.close_process_in input))(fun()->int_of_string(String.trim(input_line input)))
let putf bytes offset value=Bytes.set_int64_le bytes offset(Int64.bits_of_float value)
let measure_frames render count seconds = match seconds with
|None->Array.init count(fun _->let started=Unix.gettimeofday()in ignore(get(render()));Unix.gettimeofday()-.started)
|Some duration->let deadline=Unix.gettimeofday()+.duration in let rec loop acc=let started=Unix.gettimeofday()in if started>=deadline then Array.of_list(List.rev acc)else(ignore(get(render()));loop((Unix.gettimeofday()-.started)::acc))in loop[]

let mesh16 ~key triangles =
  let vertices=Bytes.make 48 '\000' and indices=Bytes.create(triangles*12)in
  List.iteri(fun i(x,y)->putf vertices(i*16)x;putf vertices(i*16+8)y)[-1.,1.;1.,1.;-1.,-1.];
  for i=0 to triangles-1 do let o=i*12 in Bytes.set_int32_le indices o 0l;Bytes.set_int32_le indices(o+4)1l;Bytes.set_int32_le indices(o+8)2l done;
  {Scene_execution.key;vertices;vertex_count=3;indices;index_count=triangles*3}

let mesh68 ~key triangles =
  let vertices=Bytes.make(3*68)'\000'and indices=Bytes.create(triangles*12)in
  List.iteri(fun i(x,y,r,g,b)->let o=i*68 in putf vertices o x;putf vertices(o+8)y;putf vertices(o+16)0.;putf vertices(o+24)1.;putf vertices(o+28)r;putf vertices(o+36)g;putf vertices(o+44)b;putf vertices(o+52)0.;putf vertices(o+60)0.)[-1.,1.,1.,0.,0.;1.,1.,0.,1.,0.;-1.,-1.,0.,0.,1.];
  for i=0 to triangles-1 do let o=i*12 in Bytes.set_int32_le indices o 0l;Bytes.set_int32_le indices(o+4)1l;Bytes.set_int32_le indices(o+8)2l done;
  {Scene_execution.key;vertices;vertex_count=3;indices;index_count=triangles*3}

let acceptance_mesh source =
  {Scene_execution.key="acceptance:"^source.render_hash;vertices=source.vertices;vertex_count=source.render_vertices;indices=source.indices;index_count=source.triangles*3}

let state : Scene_execution.state =
  { viewport = (0, 0, 64, 64);
    scissor = (0, 0, 64, 64);
    cull = Ogpu.Render_pass.Cull_none;
    depth_compare = Ogpu.Render_pass.Always;
    depth_write = false;
    depth_load = Ogpu.Render_pass.Clear;
    depth_clear = 1.;
    transform_uniforms = None }
let workload ?acceptance=function
  |Basic->[Scene_execution.Scene2,Ogpu.Pipeline.Replace,{Scene_execution.mesh=mesh16~key:"basic"128;state}]
  |Pxui->List.init 64(fun i->Scene_execution.Scene2,Ogpu.Pipeline.Alpha,{Scene_execution.mesh=mesh16~key:("pxui-"^string_of_int i)2;state})
  |Canvas->List.init 8(fun i->Scene_execution.Scene2,Ogpu.Pipeline.Replace,{Scene_execution.mesh=mesh16~key:("canvas-"^string_of_int i)32;state})
  |Scene3->List.init 12(fun i->Scene_execution.Scene3,Ogpu.Pipeline.Replace,{Scene_execution.mesh=mesh68~key:("scene3-"^string_of_int i)9_216;state})
  |Shattered->let accepted=Option.get acceptance in[Scene_execution.Scene3,Ogpu.Pipeline.Replace,{Scene_execution.mesh=acceptance_mesh accepted;state}]

let instrument counters(driver:Ogpu.Backend.driver):Ogpu.Backend.driver={create_device=(fun()->Result.map(fun(device:Ogpu.Backend.driver_device)->
  let create_buffer descriptor=counters.buffer_creates<-counters.buffer_creates+1;counters.buffer_bytes<-Int64.add counters.buffer_bytes descriptor.Ogpu.Types.size;device.create_buffer descriptor in
  let create_queue()=Result.map(fun(queue:Ogpu.Backend.driver_queue)->{queue with submit=(fun command~resources~pipelines->counters.submissions<-counters.submissions+1;(match command with Ogpu.Backend.Render submission->counters.render_passes<-counters.render_passes+1;counters.draws<-counters.draws+List.length(Ogpu.Render_pass.submission_draws submission)|_->());queue.submit command~resources~pipelines)})(device.create_queue())in
  {device with create_buffer;create_queue})(driver.create_device()))}

let scene2_source={|#include <metal_stdlib>
using namespace metal;struct Out{float4 position[[position]];float4 color;};vertex Out scene_vertex(uint i[[vertex_id]],const device uchar*input[[buffer(0)]]){const device float2*p=(const device float2*)input;Out o;o.position=float4(p[i],0,1);o.color=float4(1,1,1,1);return o;}fragment float4 scene_fragment(Out i[[stage_in]]){return i.color;}|}
let scene3_source={|#include <metal_stdlib>
using namespace metal;struct Out{float4 position[[position]];float4 color;};vertex Out scene_vertex(uint i[[vertex_id]],const device uchar*input[[buffer(0)]]){const device uchar*p=input+i*68;Out o;o.position=*((const device float4*)p);o.color=*((const device float4*)(p+28));return o;}fragment float4 scene_fragment(Out i[[stage_in]]){return i.color;}|}

let create_renderer counters visibility =
  sdl"init"(Sdl3.Init.init[Sdl3.Init.Video]);
  let window=sdl"window"(Sdl3.Window.create~title:"native benchmark"~width:64~height:64~flags:[Hidden;Metal]())in
  sdl"visibility"((match visibility with Visible->Sdl3.Window.show|Hidden->Sdl3.Window.hide)window);
  let pixel_density=sdl"density"(Sdl3.Window.pixel_density window)and display_scale=sdl"scale"(Sdl3.Window.display_scale window)and drawable_width,drawable_height=sdl"pixels"(Sdl3.Window.size_in_pixels window)in
  let view=sdl"view"(Sdl3.Metal_view.create window)in let token=sdl"layer"(Sdl3.Metal_view.layer view)in
  let device=get(Ogpu_metal.Device.system_default())in let layer=metal(Metal.Metal_layer.adopt_borrowed(Ogpu_metal.Device.Private.metal device)token(Metal.Metal_layer.default~width:64~height:64))in
  let driver,control=Ogpu_metal.Backend.create~device~layer()in let driver=instrument counters driver in let cache=get(Ogpu_metal.Pipeline.create_cache~capacity:18)in
  let make backend family blend=let source=match family with Scene_execution.Scene2->scene2_source|Scene3|Scene3_textured|Scene3_shadow->scene3_source in let artifact entry stage bindings=get(Ogpu.Shader.create{backend="metal";label=Some"native-benchmark";bytes=Bytes.of_string source;entry_points=[{name=entry;stage}];bindings})in let vertex=artifact"scene_vertex"Vertex[{group=0;binding=0;kind=Storage_buffer;visibility=[Vertex]}]and fragment=artifact"scene_fragment"Fragment[]in let layout0=get(Ogpu.Binding.create_layout[{binding=0;kind=Buffer;visibility=[Vertex]}])in let layout=get(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle backend)~capabilities:(Ogpu.Backend.capabilities backend)[0,layout0])in let descriptor:Ogpu.Pipeline.render_descriptor={backend="metal";label=Some"native-benchmark";layout;vertex;vertex_entry="scene_vertex";fragment=Some fragment;fragment_entry=Some"scene_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1}in match Ogpu_metal.Pipeline.create_render_runtime_msl~blend cache device descriptor with Error _ as e->e|Ok native->Ogpu_metal.Backend.register_pipeline control native;Ok(Ogpu_metal.Pipeline.Private.portable native)in
  let config:Ogpu.Surface.configuration={logical_width=64;logical_height=64;physical_width=64;physical_height=64;format=Bgra8_unorm;present_mode=Fifo;max_acquired=2}in
  let renderer=get(Scene_execution.create_with_pipeline_variants driver config~before_device_destroy:(fun()->Ogpu_metal.Pipeline.clear_cache cache;Result.map_error(fun e->Ogpu.Error.make"native-benchmark"Ogpu.Error.Invalid_state(Format.asprintf"%a"Metal.pp_error e))(Metal.Metal_layer.destroy layer))make)in
  renderer,{pixel_density;display_scale;drawable_width;drawable_height},(fun()->get(Scene_execution.destroy renderer);sdl"view destroy"(Sdl3.Metal_view.destroy view);sdl"window destroy"(Sdl3.Window.destroy window);sdl"quit"(Sdl3.Init.quit_subsystems[Sdl3.Init.Video]))

let ()=let selected=ref Basic and warmup=ref 5 and samples=ref 30 and sample_seconds=ref None and report=ref None and artifact_path=ref None and visibility=ref Hidden in Arg.parse["--warmup",Arg.Set_int warmup,"frames";"--samples",Arg.Set_int samples,"frames";"--sample-seconds",Arg.Float(fun x->sample_seconds:=Some x),"duration";"--report",Arg.String(fun x->report:=Some x),"path";"--acceptance-artifact",Arg.String(fun x->artifact_path:=Some x),"cooked shattered artifact";"--visibility",Arg.Symbol(["visible";"hidden"],fun x->visibility:=if x="visible"then Visible else Hidden),"window visibility"](fun x->selected:=parse x)"runtime_next_native_benchmark scenario";if !warmup<1|| !samples<1||Option.fold~none:false~some:(fun x->x<=0.)!sample_seconds then invalid_arg"counts";
  let protocol_r11=ref(!sample_seconds=Some 30.)in
  let counters={buffer_creates=0;buffer_bytes=0L;submissions=0;render_passes=0;draws=0}in
  let renderer,window,cleanup=create_renderer counters!visibility in
  let acceptance=match!selected,!artifact_path with Shattered,Some path->let input=open_in_bin path in Some(Fun.protect~finally:(fun()->close_in input)(fun()->Marshal.from_channel input))|Shattered,None->invalid_arg"shattered requires --acceptance-artifact"|_,_->None in
  let work=workload ?acceptance!selected in
  let prepared=List.map(fun(family,blend,draw)->family,blend,None,None,1,draw)work in
  let render renderer=Scene_execution.render_prepared_sampled_resources~identity:(scenario_name!selected)~version:1L renderer prepared in
  for _=1 to !warmup do ignore(get(render renderer))done;let upload0=Scene_execution.upload_bytes renderer and creates0=counters.buffer_creates and submits0=counters.submissions and passes0=counters.render_passes and draws0=counters.draws in Gc.full_major();let gc0=Gc.quick_stat()and allocated0=Gc.allocated_bytes()and cpu0=Unix.times()in let walls=measure_frames(fun()->render renderer)!samples!sample_seconds in let measured=Array.length walls in samples:=measured;let gc1=Gc.quick_stat()and cpu1=Unix.times()and allocated=Gc.allocated_bytes()-.allocated0 and upload1=Scene_execution.upload_bytes renderer in let rss=rss_kib()and cache=Scene_execution.cache_entries renderer in cleanup();let total=Array.fold_left(+.)0. walls and cpu=cpu1.tms_utime+.cpu1.tms_stime-.cpu0.tms_utime-.cpu0.tms_stime in let promoted=(gc1.promoted_words-.gc0.promoted_words)*.float(Sys.word_size/8)in let pieces=Option.fold~none:(List.length work)~some:(fun one->one.pieces)acceptance and triangles=List.fold_left(fun n(_,_,d)->n+d.Scene_execution.mesh.index_count/3)0 work in let misses=counters.buffer_creates-creates0 in let hits=max 0(measured*pieces-misses)in
  let acceptance_json=match acceptance with None->`Null|Some one->`Assoc["pieces",`Int one.pieces;"triangles",`Int one.triangles;"render_vertices",`Int one.render_vertices;"cook_seconds_one_domain",`Float one.cook_seconds;"cook_seconds_four_domains",`Float one.cook_seconds_four;"pack_seconds_one_domain",`Float one.pack_seconds;"one_four_domain_exact",`Bool true;"topology_hash",`String one.topology_hash;"attribute_hash",`String one.attribute_hash;"order_hash",`String one.order_hash;"render_hash",`String one.render_hash]in
  let json=`Assoc["schema",`Int 1;"scenario",`String(scenario_name!selected);"backend",`String"real-m1-runtime-next-metal";"profile",`String"release";"visibility",`String(match!visibility with Visible->"visible"|Hidden->"hidden");"protocol_r11_requested",`Bool!protocol_r11;"window",`Assoc["pixel_density",`Float window.pixel_density;"display_scale",`Float window.display_scale;"drawable_width",`Int window.drawable_width;"drawable_height",`Int window.drawable_height;"refresh_hz",`Null;"power_state",`Null;"thermal_state",`Null];"warmup_frames",`Int!warmup;"sample_frames",`Int!samples;"pieces",`Int pieces;"triangles",`Int triangles;"acceptance_cook",acceptance_json;"wall_seconds",`Float total;"user_seconds",`Float(cpu1.tms_utime-.cpu0.tms_utime);"system_seconds",`Float(cpu1.tms_stime-.cpu0.tms_stime);"median_ms",`Float(1000.*.percentile 0.5 walls);"p95_ms",`Float(1000.*.percentile 0.95 walls);"p99_ms",`Float(1000.*.percentile 0.99 walls);"fps",`Float(float!samples/.total);"cpu_percent",`Float(100.*.cpu/.total);"allocated_bytes",`Float allocated;"promoted_bytes",`Float promoted;"rss_kib",`Int rss;"prepared_upload_bytes",`String(Int64.to_string upload0);"measurement_upload_bytes",`String(Int64.to_string(Int64.sub upload1 upload0));"draws",`Int(counters.draws-draws0);"passes",`Int(counters.render_passes-passes0);"backend_calls",`Int(counters.submissions-submits0);"cache_entries",`Int cache;"cache_hits_inferred",`Int hits;"cache_misses_observed",`Int misses;"native_gpu_counters",`Null;"machine",`Assoc["arch",`String(Sys.getenv_opt"HOSTTYPE"|>Option.value~default:"arm64");"ocaml",`String Sys.ocaml_version]]in let text=Yojson.Safe.pretty_to_string json^"\n"in match!report with None->print_string text|Some path->let out=open_out_bin path in output_string out text;close_out out
