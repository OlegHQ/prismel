open Ogpu_metal
let get=function Ok value->value|Error value->failwith(Ogpu.Error.to_string value)
let get_metal=function Ok value->value|Error value->failwith(Format.asprintf"%a"Metal.pp_error value)
let outcome=function Ok()->"supported"|Error value when value.Ogpu.Error.kind=Ogpu.Error.Unsupported->"unsupported"|Error value->"error:"^Ogpu.Error.to_string value
let operations=Ogpu.Caps.[Buffer;Texture;Sampler;Compute_pipeline;Render_pipeline;Queue;Surface;Memory;Event_synchronization;Timeline_fence;Timestamp_queries;Ray_tracing;Metal_fx;Sparse_memory;Unknown"future"]
let source ray_tracing metal_fx : Ogpu.Caps.t={Ogpu.Caps.minimum_m1 with limits={Ogpu.Caps.minimum_m1.limits with max_buffer_size=1_073_741_824L};ray_tracing;metal_fx}
let profile source ~timestamp_queries ~sparse_memory:_=get(Ogpu.Caps.create {source with metal_fx=false}~timestamp_queries~sparse_memory:false~conservative_limits:[])
let matrix value=List.map(fun feature->outcome(Ogpu.Caps.require value feature))operations
let run () =
  let profiles=[profile(source false false)~timestamp_queries:false~sparse_memory:false;
    profile(source true false)~timestamp_queries:true~sparse_memory:true;
    profile(source false true)~timestamp_queries:true~sparse_memory:false;
    profile(source true true)~timestamp_queries:false~sparse_memory:false]in
  let expected=List.map matrix profiles in let workers=Array.init 4(fun _->Domain.spawn(fun()->List.map matrix profiles))in
  Array.iter(fun worker->if Domain.join worker<>expected then failwith"capability matrix domain drift")workers;
  List.iter(fun row->if List.length row<>List.length operations then failwith"operation matrix cardinality")expected;
  List.iter(fun value->if outcome(Ogpu.Caps.require value Ogpu.Caps.Metal_fx)<>"unsupported"||outcome(Ogpu.Caps.require value Ogpu.Caps.Sparse_memory)<>"unsupported"||outcome(Ogpu.Caps.require value(Ogpu.Caps.Unknown"future"))<>"unsupported"then failwith"unsupported feature fallback")profiles;
  if outcome(Ogpu.Caps.require(List.nth profiles 1)Ogpu.Caps.Ray_tracing)<>"supported"||outcome(Ogpu.Caps.require(List.hd profiles)Ogpu.Caps.Ray_tracing)<>"unsupported"then failwith"mock ray-tracing profile drift";
  let device=get(Device.system_default())in let native=Device.Private.metal device in let info=get_metal(Metal.Device.info native)and reported=Device.capabilities device in
  if reported.limits.max_buffer_size<>info.max_buffer_length||reported.ray_tracing<>info.raytracing then failwith"reported capability differs from Metal probe";
  let rec maximum current=function []->current|sample::rest->maximum(if get_metal(Metal.Device.supports_texture_sample_count native sample)then sample else current)rest in
  if reported.limits.max_sample_count<>min 4(maximum 1[2;4;8])then failwith"sample limit differs from qualified Metal probes";
  let profile=Device.capability_profile device in
  if outcome(Device.supports device Ogpu.Caps.Timestamp_queries)<>outcome(Ogpu.Caps.require profile Ogpu.Caps.Timestamp_queries)then failwith"timestamp support drift";
  if outcome(Device.supports device Ogpu.Caps.Sparse_memory)<>outcome(Ogpu.Caps.require profile Ogpu.Caps.Sparse_memory)then failwith"sparse support drift";
  if outcome(Device.supports device Ogpu.Caps.Metal_fx)<>"unsupported"then failwith"MetalFX semantic fallback";
  if outcome(Device.supports device Ogpu.Caps.Timeline_fence)<>"unsupported"then failwith"timeline fence semantic fallback";
  if List.length profile.conservative_limits<>5 then failwith"conservative evidence drift";
  get(Device.destroy device);print_endline"ogpu_metal capability truth: 15 operations x4 profiles, real probes consistent, no fallback"
