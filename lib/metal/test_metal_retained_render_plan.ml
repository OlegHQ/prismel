open Metal

let get = function Ok value -> value | Error error -> failwith error.message

let expect kind = function
  | Error error when error.kind=kind -> ()
  | Error error -> failwith("unexpected error: "^error.message)
  | Ok _ -> failwith"expected failure"

let plan_descriptor () =
  Indirect_command_buffer.descriptor ~max_kernel_buffer_bind_count:1
    ~command_types:[Indirect_concurrent_dispatch_threads] ()

let build_counter builds buffer =
  incr builds;
  let command=get(Indirect_command_buffer.Compute_command.at buffer 0)in
  get(Indirect_command_buffer.Compute_command.reset command);
  get(Indirect_command_buffer.Compute_command.destroy command);
  Ok()

let pixel_source={|
#include <metal_stdlib>
using namespace metal;
struct O { float4 position [[position]]; };
vertex O vertex_main(device const float2 *p [[buffer(0)]], uint i [[vertex_id]]) {
  O o; o.position=float4(p[i],0.,1.); return o;
}
fragment float4 fragment_main(O o [[stage_in]]) {
  return float4(.25,.5,.75,1.);
}
|}

let () =
  let device=get(Device.system_default())in
  let descriptor=plan_descriptor()in
  let probe=get(Indirect_command_buffer.create~device~storage:Buffer.Private
    ~max_command_count:1 descriptor)in
  let one_buffer_bytes=Indirect_command_buffer.allocated_size probe in
  if one_buffer_bytes<=1L then failwith(Printf.sprintf
    "invalid ICB allocated-size fixture: %Ld"one_buffer_bytes);
  get(Indirect_command_buffer.destroy probe);

  expect Invalid_argument(Retained_render_plan.create~device~capacity:0());
  expect Invalid_argument(
    Retained_render_plan.create~device~byte_capacity:0L());
  let defaults=get(Retained_render_plan.create~device())in
  let default_stats=Retained_render_plan.stats defaults in
  if default_stats.entries<>0||default_stats.retained_bytes<>0L||
     default_stats.entry_capacity<>64||
     default_stats.byte_capacity<>Int64.mul 64L 1_048_576L then
    failwith"retained-plan default statistics";
  get(Retained_render_plan.destroy defaults);

  let exact_builds=ref 0 in
  let exact=get(Retained_render_plan.create~device~capacity:2
    ~byte_capacity:(Int64.mul one_buffer_bytes 4L)())in
  let first,hit=get(Retained_render_plan.find_or_create exact~key:"exact"
    ~generation:1L~command_count:1~descriptor
    ~build:(build_counter exact_builds))in
  if hit|| !exact_builds<>1 then failwith"first retained-plan admission";
  let first_bytes=Indirect_command_buffer.allocated_size first in
  let admitted=Retained_render_plan.stats exact in
  if admitted.entries<>1||admitted.retained_bytes<>first_bytes||
     admitted.entry_capacity<>2 then failwith"exact admitted byte statistics";
  let same,hit=get(Retained_render_plan.find_or_create exact~key:"exact"
    ~generation:1L~command_count:1~descriptor
    ~build:(build_counter exact_builds))in
  if not hit||same!=first|| !exact_builds<>1||
     Retained_render_plan.stats exact<>admitted then
    failwith"exact retained-plan hit changed state";

  let stale_build_observed=ref false in
  expect Invalid_argument(Retained_render_plan.find_or_create exact~key:"exact"
    ~generation:2L~command_count:1~descriptor~build:(fun candidate->
      stale_build_observed:=not(Indirect_command_buffer.destroyed first)&&
        Retained_render_plan.stats exact=admitted;
      Indirect_command_buffer.reset candidate~location:(-1)~length:1));
  if not !stale_build_observed||Indirect_command_buffer.destroyed first||
     Retained_render_plan.stats exact<>admitted then
    failwith"failed stale build mutated the admitted entry";
  let old,hit=get(Retained_render_plan.find_or_create exact~key:"exact"
    ~generation:1L~command_count:1~descriptor
    ~build:(build_counter exact_builds))in
  if not hit||old!=first then failwith"stale failure lost exact old hit";
  let replacement,hit=get(Retained_render_plan.find_or_create exact~key:"exact"
    ~generation:2L~command_count:1~descriptor
    ~build:(build_counter exact_builds))in
  if hit||replacement==first||not(Indirect_command_buffer.destroyed first)then
    failwith"successful stale replacement did not hand off old entry";
  let replacement_stats=Retained_render_plan.stats exact in
  if replacement_stats.entries<>1||replacement_stats.retained_bytes<>
      Indirect_command_buffer.allocated_size replacement then
    failwith"stale replacement byte accounting";
  get(Retained_render_plan.destroy exact);
  if not(Indirect_command_buffer.destroyed replacement)||
     (Retained_render_plan.stats exact).retained_bytes<>0L then
    failwith"exact cache teardown";

  let byte_cache=get(Retained_render_plan.create~device~capacity:4
    ~byte_capacity:one_buffer_bytes())in
  let byte_builds=ref 0 in
  let byte_first,_=get(Retained_render_plan.find_or_create byte_cache~key:"a"
    ~generation:1L~command_count:1~descriptor
    ~build:(build_counter byte_builds))in
  let byte_second,_=get(Retained_render_plan.find_or_create byte_cache~key:"b"
    ~generation:1L~command_count:1~descriptor
    ~build:(build_counter byte_builds))in
  let byte_stats=Retained_render_plan.stats byte_cache in
  if not(Indirect_command_buffer.destroyed byte_first)||
     Indirect_command_buffer.destroyed byte_second||byte_stats.entries<>1||
     byte_stats.retained_bytes<>
       Indirect_command_buffer.allocated_size byte_second then
    failwith"byte capacity did not evict the oldest exact entry";
  get(Retained_render_plan.destroy byte_cache);
  if not(Indirect_command_buffer.destroyed byte_second)||
     Retained_render_plan.stats byte_cache<>
       {entries=0;retained_bytes=0L;entry_capacity=4;
        byte_capacity=one_buffer_bytes}then
    failwith"byte cache teardown accounting";

  let phased=get(Retained_render_plan.create~device~capacity:1
    ~byte_capacity:one_buffer_bytes())in
  let phased_builds=ref 0 in
  let active,_=get(Retained_render_plan.find_or_create phased~key:"active"
    ~generation:1L~command_count:1~descriptor
    ~build:(build_counter phased_builds))in
  let active_stats=Retained_render_plan.stats phased in
  let discarded_candidate=match get(Retained_render_plan.prepare phased
      ~key:"discarded"~generation:1L~command_count:1~descriptor
      ~build:(build_counter phased_builds))with
    |Hit _->failwith"saturated miss unexpectedly hit"
    |Candidate candidate->candidate in
  let discarded_buffer=Retained_render_plan.candidate_buffer
      discarded_candidate in
  if Retained_render_plan.stats phased<>active_stats||
     Indirect_command_buffer.destroyed active then
    failwith"candidate preparation mutated the saturated cache";
  get(Retained_render_plan.discard discarded_candidate);
  if not(Indirect_command_buffer.destroyed discarded_buffer)||
     Indirect_command_buffer.destroyed active||
     Retained_render_plan.stats phased<>active_stats then
    failwith"candidate discard mutated active cache state";
  expect Invalid_state(Retained_render_plan.discard discarded_candidate);
  expect Invalid_state(Retained_render_plan.admit phased discarded_candidate);
  let admitted_candidate=match get(Retained_render_plan.prepare phased
      ~key:"admitted"~generation:1L~command_count:1~descriptor
      ~build:(build_counter phased_builds))with
    |Hit _->failwith"second saturated miss unexpectedly hit"
    |Candidate candidate->candidate in
  let admitted_buffer=Retained_render_plan.candidate_buffer admitted_candidate in
  if Retained_render_plan.stats phased<>active_stats||
     Indirect_command_buffer.destroyed active then
    failwith"admission candidate evicted active state during preparation";
  get(Retained_render_plan.admit phased admitted_candidate);
  let admitted_stats=Retained_render_plan.stats phased in
  if not(Indirect_command_buffer.destroyed active)||
     Indirect_command_buffer.destroyed admitted_buffer||
     admitted_stats.entries<>1||admitted_stats.retained_bytes<>
       Indirect_command_buffer.allocated_size admitted_buffer||
     admitted_stats.entry_capacity<>1||
     admitted_stats.byte_capacity<>one_buffer_bytes then
    failwith"two-phase admission eviction/accounting";
  expect Invalid_state(Retained_render_plan.admit phased admitted_candidate);
  expect Invalid_state(Retained_render_plan.discard admitted_candidate);
  (match get(Retained_render_plan.prepare phased~key:"admitted"
      ~generation:1L~command_count:1~descriptor
      ~build:(build_counter phased_builds))with
   |Hit buffer when buffer==admitted_buffer->()
   |Hit _|Candidate _->failwith"two-phase admitted entry did not hit");
  if !phased_builds<>3||Retained_render_plan.stats phased<>admitted_stats then
    failwith"two-phase hit changed cache state";
  get(Retained_render_plan.destroy phased);
  if not(Indirect_command_buffer.destroyed admitted_buffer)then
    failwith"two-phase admitted buffer survived teardown";

  let oversize_builds=ref 0 and oversize_handoffs=ref 0 in
  let oversize=get(Retained_render_plan.create~device~capacity:4
    ~byte_capacity:(Int64.pred one_buffer_bytes)
    ~on_evict:(fun~key:_~generation:_ _->incr oversize_handoffs)())in
  expect Invalid_argument(Retained_render_plan.find_or_create oversize~key:"big"
    ~generation:1L~command_count:1~descriptor~build:(fun buffer->
      build_counter oversize_builds buffer));
  if !oversize_builds<>0|| !oversize_handoffs<>0||
     (Retained_render_plan.stats oversize).entries<>0||
     (Retained_render_plan.stats oversize).retained_bytes<>0L then
    failwith"oversize candidate reached build or admission";
  get(Retained_render_plan.destroy oversize);

  let handed=ref[]and atomic_builds=ref 0 in
  let atomic=get(Retained_render_plan.create~device~capacity:2
    ~byte_capacity:(Int64.mul one_buffer_bytes 4L)
    ~on_evict:(fun~key~generation buffer->
      handed:=(key,generation,buffer)::!handed)())in
  let stable,_=get(Retained_render_plan.find_or_create atomic~key:"stable"
    ~generation:4L~command_count:1~descriptor
    ~build:(build_counter atomic_builds))in
  let stable_stats=Retained_render_plan.stats atomic in
  expect Invalid_argument(Retained_render_plan.find_or_create atomic~key:"failed"
    ~generation:1L~command_count:1~descriptor~build:(fun candidate->
      Indirect_command_buffer.reset candidate~location:(-1)~length:1));
  if !handed<>[]||Indirect_command_buffer.destroyed stable||
     Retained_render_plan.stats atomic<>stable_stats then
    failwith"failed new-key build was not atomic";
  expect Invalid_argument(Retained_render_plan.find_or_create atomic~key:"stable"
    ~generation:5L~command_count:1~descriptor~build:(fun candidate->
      if Indirect_command_buffer.destroyed stable||
         Retained_render_plan.stats atomic<>stable_stats then
        failwith"stale entry removed before candidate build";
      Indirect_command_buffer.reset candidate~location:(-1)~length:1));
  if !handed<>[]||Indirect_command_buffer.destroyed stable||
     Retained_render_plan.stats atomic<>stable_stats then
    failwith"failed stale replacement was not atomic";
  let next,_=get(Retained_render_plan.find_or_create atomic~key:"stable"
    ~generation:5L~command_count:1~descriptor
    ~build:(build_counter atomic_builds))in
  (match!handed with
   |[("stable",4L,buffer)]when buffer==stable->()
   |_->failwith"admitted stale entry was not handed off exactly once");
  if Indirect_command_buffer.destroyed stable then
    failwith"custom handoff unexpectedly destroyed old entry";
  get(Retained_render_plan.destroy atomic);
  get(Retained_render_plan.destroy atomic);
  (match!handed with
   |[("stable",5L,new_buffer);("stable",4L,old_buffer)]
      when new_buffer==next&&old_buffer==stable->()
   |_->failwith"teardown did not hand off admitted entries exactly once");
  let torn_down=Retained_render_plan.stats atomic in
  if torn_down.entries<>0||torn_down.retained_bytes<>0L then
    failwith"teardown retained cache accounting";
  get(Indirect_command_buffer.destroy stable);
  get(Indirect_command_buffer.destroy next);

  let library=get(Library.compile_source~device pixel_source)in
  let compiler=get(Compiler.create device)in
  let pipeline=get(Compiler.create_render_pipeline
    ~support_indirect_command_buffers:true~color_formats:[Texture.Rgba8_unorm]
    compiler~library~vertex:"vertex_main"~fragment:"fragment_main")in
  let vertices=Bytes.create 24 in
  List.iteri(fun index value->Bytes.set_int32_le vertices(index*4)
    (Int32.bits_of_float value))[-1.;-1.;3.;-1.;-1.;3.];
  let vertex_buffer=get(Buffer.create_copy~device~storage:Buffer.Shared vertices)in
  let target=get(Texture.create~device(Texture.descriptor_2d
    ~storage:Buffer.Shared~usage:[Texture.Render_target]
    ~format:Texture.Rgba8_unorm~width:1~height:1()))in
  let render_descriptor=Indirect_command_buffer.descriptor
    ~inherit_buffers:false~inherit_pipeline_state:false
    ~max_vertex_buffer_bind_count:1~command_types:[Indirect_draw]()in
  let pixel_builds=ref 0 in
  let build_pixel commands=
    incr pixel_builds;
    let command=get(Indirect_command_buffer.Render_command.at commands 0)in
    get(Indirect_command_buffer.Render_command.set_pipeline command pipeline);
    get(Indirect_command_buffer.Render_command.set_vertex_buffer command
      ~index:0~offset:0L vertex_buffer);
    get(Indirect_command_buffer.Render_command.draw_primitives command
      ~primitive:Indirect_command_buffer.Render_command.Triangle
      ~vertex_start:0~vertex_count:3());
    get(Indirect_command_buffer.Render_command.destroy command);
    Ok()in
  let pixel_cache=get(Retained_render_plan.create~device~capacity:1())in
  let pixel_icb,hit=get(Retained_render_plan.find_or_create pixel_cache
    ~key:"pixel"~generation:1L~command_count:1~descriptor:render_descriptor
    ~build:build_pixel)in
  if hit|| !pixel_builds<>1||
     (Retained_render_plan.stats pixel_cache).retained_bytes<>
       Indirect_command_buffer.allocated_size pixel_icb then
    failwith"retained pixel plan admission";
  let hit_icb,hit=get(Retained_render_plan.find_or_create pixel_cache
    ~key:"pixel"~generation:1L~command_count:1~descriptor:render_descriptor
    ~build:build_pixel)in
  if not hit||hit_icb!=pixel_icb|| !pixel_builds<>1 then
    failwith"retained pixel plan exact hit";
  let queue=get(Command_queue.create device)in
  let command=get(Command_buffer.create queue())in
  let encoder=get(Render_encoder.create command~target())in
  get(Render_encoder.set_pipeline encoder pipeline);
  get(Render_encoder.use_resources encoder
    [Render_encoder.Buffer_resource vertex_buffer]~usage:[Render_encoder.Read]
    ~stages:[Render_encoder.Vertex]);
  get(Render_encoder.execute_indirect_commands encoder hit_icb~location:0
    ~length:1);
  get(Render_encoder.end_encoding encoder);get(Command_buffer.commit command);
  get(Command_buffer.wait_until_completed command);get(Command_buffer.destroy command);
  let region={Texture.x=0;y=0;z=0;width=1;height=1;depth=1}in
  let pixels=get(Texture.read_bytes target~region~mip_level:0~slice:0
    ~bytes_per_row:4~bytes_per_image:4)in
  if pixels<>Bytes.of_string"\x40\x80\xbf\xff"then
    failwith"retained private ICB produced unexpected pixels";
  get(Command_queue.destroy queue);get(Retained_render_plan.destroy pixel_cache);
  get(Texture.destroy target);get(Buffer.destroy vertex_buffer);
  get(Render_pipeline.destroy pipeline);get(Compiler.destroy compiler);
  get(Library.destroy library);

  let unsupported=get(Retained_render_plan.create~device~enabled:false())in
  expect Unsupported(Retained_render_plan.find_or_create unsupported~key:"x"
    ~generation:1L~command_count:1~descriptor~build:(fun _->Ok()));
  get(Retained_render_plan.destroy unsupported);
  expect Destroyed(Retained_render_plan.invalidate atomic"stable");
  get(Device.destroy device);
  print_endline
    "metal retained render plan: exact bytes/hit/two-phase eviction/atomic/teardown"
