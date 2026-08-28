open Prismel

type metadata={pieces:int;triangles:int;render_vertices:int;cook_seconds:float;
  cook_seconds_four:float;pack_seconds:float;topology_hash:string;
  attribute_hash:string;order_hash:string;render_hash:string;artifact:string}

let get operation=function Ok value->value|Error error->
  failwith(Format.asprintf"%s: %a"operation Prismel_next_execution.pp_error error)
let putf bytes offset value=Bytes.set_int64_le bytes offset(Int64.bits_of_float value)
let pack mesh =
  let view=Mesh.Private.packed_view mesh and count=Mesh.vertex_count mesh in
  let vertices=Bytes.make(count*68)'\000'in
  for index=0 to count-1 do
    let offset=index*68 in
    putf vertices offset view.vertices.x.(index);
    putf vertices(offset+8)view.vertices.y.(index);
    putf vertices(offset+16)view.vertices.z.(index);
    (match view.normals with
    |None->putf vertices(offset+40)1.
    |Some normals->putf vertices(offset+24)normals.x.(index);
        putf vertices(offset+32)normals.y.(index);
        putf vertices(offset+40)normals.z.(index));
    Bytes.set_int32_le vertices(offset+48)(match view.colors with
      |None->Int32.minus_one
      |Some colors->let c=colors.(index)in
          Int32.of_int((c.r lsl 24)lor(c.g lsl 16)lor(c.b lsl 8)lor c.a))
  done;
  let indices=Bytes.create(Array.length view.indices*4)in
  Array.iteri(fun index value->Bytes.set_int32_le indices(index*4)(Int32.of_int value))view.indices;
  vertices,indices

let percentile p values=
  let copy=Array.copy values in Array.sort Float.compare copy;
  copy.(max 0(min(Array.length copy-1)(int_of_float(Float.ceil(p*.float(Array.length copy)))-1)))
let rss_kib()=
  let arguments=[|"/bin/ps";"-o";"rss=";"-p";string_of_int(Unix.getpid())|]in
  let input=Unix.open_process_args_in arguments.(0)arguments in
  Fun.protect~finally:(fun()->ignore(Unix.close_process_in input))
    (fun()->int_of_string(String.trim(input_line input)))

let run ~visibility ~seconds ~report ~metadata mesh =
  if seconds<=0. then invalid_arg"R11 duration must be positive";
  if visibility<>"hidden"&&visibility<>"visible"then
    invalid_arg"R11 visibility must be hidden or visible";
  let width=1200 and height=760 in
  let vertices,indices=pack mesh in
  if Bytes.length vertices<>metadata.render_vertices*68||
     Bytes.length indices<>metadata.triangles*12 then
    failwith"actual-sketch R11 packed mesh cardinality drift";
  let configuration={Prismel_next_execution.default_configuration with
    target=Native;logical_width=width;logical_height=height;
    drawable_width=width;drawable_height=height;timing=Variable;
    title="Prismel shattered cube · R11 actual sketch"}in
  let execution=get"create"(Prismel_next_execution.create configuration)in
  Fun.protect~finally:(fun()->ignore(Prismel_next_execution.destroy execution))(fun()->
    ignore(get visibility((if visibility="visible"then Prismel_next_execution.show
      else Prismel_next_execution.hide)execution));
    let observed_visible=get"visible"(Prismel_next_execution.visible execution)in
    if observed_visible<>(visibility="visible")then
      failwith"actual-sketch R11 window visibility did not match the requested mode";
    let state:Scene_execution.state={viewport=(0,0,width,height);scissor=(0,0,width,height);
      cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;
      depth_write=false;depth_load=Ogpu.Render_pass.Clear;depth_clear=1.;
      transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Clear;
      stencil_clear=0}in
    let raw={Scene_execution.mesh={key="shattered-sketch:"^metadata.render_hash;
      vertices;vertex_count=metadata.render_vertices;indices;
      index_count=metadata.triangles*3};state}in
    let draw=Prismel_next_execution.prepared_draw~family:Scene3 raw in
    for _=1 to 5 do ignore(get"warmup"(Prismel_next_execution.step execution[draw]))done;
    let before=get"stats"(Prismel_next_execution.stats execution)in
    Gc.full_major();let gc0=Gc.quick_stat()and allocated0=Gc.allocated_bytes()
    and cpu0=Unix.times()and started=Unix.gettimeofday()in
    let rec loop acc =
      let now=Unix.gettimeofday()in if acc<>[]&&now-.started>=seconds then Array.of_list(List.rev acc)
      else let frame=now in ignore(get"step"(Prismel_next_execution.step execution[draw]));
        loop((Unix.gettimeofday()-.frame)::acc)in
    let frames=loop[]in
    let wall=Unix.gettimeofday()-.started and cpu1=Unix.times()and gc1=Gc.quick_stat()
    and allocated=Gc.allocated_bytes()-.allocated0 in
    let after=get"stats"(Prismel_next_execution.stats execution)in
    let delta current initial=Int64.sub current initial in
    let promoted=(gc1.promoted_words-.gc0.promoted_words)*.float(Sys.word_size/8)in
    let gpu_duration=after.gpu_duration_seconds-.before.gpu_duration_seconds
    and gpu_samples=delta after.gpu_sample_count before.gpu_sample_count in
    let gpu=if after.gpu_timing_supported then `Assoc[
      "status",`String"measured";"supported",`Bool true;
      "gpu_duration",`Float gpu_duration;"sample_count",`Intlit(Int64.to_string gpu_samples);
      "gpu_utilization",`Float(100.*.gpu_duration/.wall);"reason",`Null]
    else `Assoc["status",`String"unsupported";"supported",`Bool false;
      "gpu_duration",`Null;"sample_count",`Int 0;"gpu_utilization",`Null;
      "reason",`String"Metal command-buffer timestamps are unavailable on this device/API"]in
    let json=`Assoc[
      "schema",`Int 2;"scenario",`String"shattered-cube";
      "backend",`String"actual-sketch-runtime-next-metal";
      "visibility",`String visibility;"observed_visible",`Bool observed_visible;
      "protocol_r11_requested",`Bool(seconds=30.);
      "r11_sketch_invocation",`Assoc[
        "status",`String"actual-sketch-cooked-and-rendered";
        "evidence_class",`String"candidate";"frozen_r11_closure",`Bool false;
        "invoked_executable",`String Sys.executable_name;
        "measured_executable",`String Sys.executable_name;
        "artifact",`String metadata.artifact];
      "width",`Int width;"height",`Int height;"warmup_frames",`Int 5;
      "sample_frames",`Int(Array.length frames);"wall_seconds",`Float wall;
      "median_ms",`Float(1000.*.percentile 0.5 frames);
      "p95_ms",`Float(1000.*.percentile 0.95 frames);
      "p99_ms",`Float(1000.*.percentile 0.99 frames);
      "fps",`Float(float(Array.length frames)/.wall);
      "user_seconds",`Float(cpu1.tms_utime-.cpu0.tms_utime);
      "system_seconds",`Float(cpu1.tms_stime-.cpu0.tms_stime);
      "allocated_bytes",`Float allocated;"promoted_bytes",`Float promoted;
      "rss_kib",`Int(rss_kib());"pieces",`Int metadata.pieces;
      "triangles",`Int metadata.triangles;"render_vertices",`Int metadata.render_vertices;
      "prepared_upload_bytes",`String(Int64.to_string before.uploaded_bytes);
      "measurement_upload_bytes",`String(Int64.to_string(delta after.uploaded_bytes before.uploaded_bytes));
      "draws",`Intlit(Int64.to_string(delta after.logical_draws before.logical_draws));
      "passes",`Intlit(Int64.to_string(delta after.logical_passes before.logical_passes));
      "backend_calls",`Intlit(Int64.to_string(delta after.logical_submissions before.logical_submissions));
      "cache_entries",`Int after.cache_entries;"native_gpu_counters",gpu;
      "acceptance_cook",`Assoc["cook_seconds_one_domain",`Float metadata.cook_seconds;
        "cook_seconds_four_domains",`Float metadata.cook_seconds_four;
        "pack_seconds_one_domain",`Float metadata.pack_seconds;
        "topology_hash",`String metadata.topology_hash;
        "attribute_hash",`String metadata.attribute_hash;
        "order_hash",`String metadata.order_hash;"render_hash",`String metadata.render_hash]]in
    let output=open_out_bin report in Fun.protect~finally:(fun()->close_out output)
      (fun()->Yojson.Safe.pretty_to_channel output json;output_char output '\n'))
