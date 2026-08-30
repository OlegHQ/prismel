open Ogpu_metal
let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let get_metal=function Ok x->x|Error e->failwith(Format.asprintf"%a"Metal.pp_error e)
let expect kind=function Error e when e.Ogpu.Error.kind=kind->()|_->failwith"backend rejection mismatch"
let source={|#include <metal_stdlib>
using namespace metal;
kernel void backend_compute(device uint *v [[buffer(0)]], uint i [[thread_position_in_grid]]) { v[i]=v[i]*2+1; }
struct V { float4 position [[position]]; };
vertex V backend_vertex(uint i [[vertex_id]]) { constexpr float2 p[3]={{-1.,-1.},{3.,-1.},{-1.,3.}}; V v;v.position=float4(p[i],0.,1.);return v; }
fragment float4 backend_fragment(){return float4(0.25,0.5,0.75,1.);}
fragment float4 backend_fragment2(){return float4(0.0,1.0,0.0,1.);}
struct A { texture2d<float,access::sample> image [[id(0)]]; sampler sampling [[id(1)]]; };
vertex V backend_argument_vertex(device const float2 *p [[buffer(0)]],uint i [[vertex_id]]) { V v;v.position=float4(p[i],0.,1.);return v; }
fragment float4 backend_argument_fragment(V v [[stage_in]],constant A&args [[buffer(1)]]) { return args.image.sample(args.sampling,float2(.5)); }
|}
let shader entries bindings=get(Ogpu.Shader.create{backend="metal";label=None;bytes=Bytes.of_string source;entry_points=entries;bindings})
let ()=match Device.system_default()with Error _->print_endline"ogpu_metal backend: skipped (no device)"|Ok native_device->
  let before=get_metal(Metal.Release_queue.stats())in let layer=get_metal(Metal.Metal_layer.create(Device.Private.metal native_device)(Metal.Metal_layer.default~width:4~height:4))in
  let driver,control=Backend.create~device:native_device~layer~retained_plan_capacity:1()in let device=get(Ogpu.Backend.create_device driver)in let cache=get(Pipeline.create_cache~capacity:4)in
  (match Ogpu.Backend.create_device driver with Error e when e.Ogpu.Error.kind=Ogpu.Error.Invalid_state->()|_->failwith"second live device accepted");
  let compute_shader=shader[{name="backend_compute";stage=Compute}][{group=0;binding=0;kind=Storage_buffer;visibility=[Compute]}]in let gl=get(Ogpu.Binding.create_layout[{binding=0;kind=Ogpu.Binding.Buffer;visibility=[Ogpu.Binding.Compute]}])in let layout=get(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle device)~capabilities:(Ogpu.Backend.capabilities device)[0,gl])in let compute_descriptor : Ogpu.Pipeline.compute_descriptor={backend="metal";label=None;layout;shader=compute_shader;entry="backend_compute"}in let native_compute=get(Pipeline.create_compute_runtime_msl cache native_device compute_descriptor)in Backend.register_pipeline control native_compute;let compute_pipeline=get(Ogpu.Backend.adopt_pipeline device(Pipeline.Private.portable native_compute))in
  let render_shader=shader[{name="backend_vertex";stage=Vertex};{name="backend_fragment";stage=Fragment};{name="backend_fragment2";stage=Fragment}][]in let empty=get(Ogpu.Binding.create_layout[])in let render_layout=get(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle device)~capabilities:(Ogpu.Backend.capabilities device)[0,empty])in let render_descriptor : Ogpu.Pipeline.render_descriptor={backend="metal";label=None;layout=render_layout;vertex=render_shader;vertex_entry="backend_vertex";fragment=Some render_shader;fragment_entry=Some"backend_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1}in let native_render=get(Pipeline.create_render_runtime_msl cache native_device render_descriptor)in Backend.register_pipeline control native_render;let render_pipeline=get(Ogpu.Backend.adopt_pipeline device(Pipeline.Private.portable native_render))in let native_render2=get(Pipeline.create_render_runtime_msl cache native_device{render_descriptor with fragment_entry=Some"backend_fragment2"})in Backend.register_pipeline control native_render2;let render_pipeline2=get(Ogpu.Backend.adopt_pipeline device(Pipeline.Private.portable native_render2))in
  let argument_vertex=shader[{name="backend_argument_vertex";stage=Vertex}][{group=0;binding=0;kind=Storage_buffer;visibility=[Vertex]}]
  and argument_fragment=shader[{name="backend_argument_fragment";stage=Fragment}][{group=0;binding=1;kind=Storage_buffer;visibility=[Fragment]}]in
  let argument_group=get(Ogpu.Binding.create_layout[{binding=0;kind=Buffer;visibility=[Ogpu.Binding.Vertex]};{binding=1;kind=Buffer;visibility=[Ogpu.Binding.Fragment]}])in
  let argument_layout=get(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle device)~capabilities:(Ogpu.Backend.capabilities device)[0,argument_group])in
  let argument_descriptor:Ogpu.Pipeline.render_descriptor={backend="metal";label=Some"backend-argument";layout=argument_layout;vertex=argument_vertex;vertex_entry="backend_argument_vertex";fragment=Some argument_fragment;fragment_entry=Some"backend_argument_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1}in
  let native_argument=get(Pipeline.create_render_argument_buffer cache native_device argument_descriptor)in Backend.register_pipeline control native_argument;let argument_pipeline=get(Ogpu.Backend.adopt_pipeline device(Pipeline.Private.portable native_argument))in
  let bd : Ogpu.Types.buffer_descriptor={label=None;size=64L;usage=[Copy_src;Copy_dst;Storage]}in let a=get(Ogpu.Backend.create_buffer device bd)and b=get(Ogpu.Backend.create_buffer device bd)in let input=Bytes.make 16 '\000'in for i=0 to 3 do Bytes.set_int32_le input(i*4)(Int32.of_int i)done;get(Ogpu.Backend.write_buffer a~offset:0L input);
  let transfer=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in get(Ogpu.Transfer_pass.copy_buffer transfer~src:(Ogpu.Backend.transfer_buffer a)~src_offset:0L~dst:(Ogpu.Backend.transfer_buffer b)~dst_offset:0L~length:16L);let queue=get(Ogpu.Backend.create_queue device)in let r=get(Ogpu.Backend.submit queue(get(Ogpu.Backend.transfer transfer))~resources:[`Buffer a;`Buffer b]~pipelines:[])in get(Ogpu.Backend.complete_through queue r.epoch);
  (* queue_scoped_completion_overlap: completing queue A must neither complete nor
     retire work owned by queue B.  Device teardown is atomic while either queue
     remains live. *)
  let queue2=get(Ogpu.Backend.create_queue device)in
  let transfer_a=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in
  let transfer2=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in
  get(Ogpu.Transfer_pass.copy_buffer transfer_a~src:(Ogpu.Backend.transfer_buffer a)~src_offset:0L~dst:(Ogpu.Backend.transfer_buffer b)~dst_offset:0L~length:16L);
  get(Ogpu.Transfer_pass.copy_buffer transfer2~src:(Ogpu.Backend.transfer_buffer b)~src_offset:0L~dst:(Ogpu.Backend.transfer_buffer a)~dst_offset:0L~length:16L);
  let ra=get(Ogpu.Backend.submit queue(get(Ogpu.Backend.transfer transfer_a))~resources:[`Buffer a;`Buffer b]~pipelines:[])
  and rb=get(Ogpu.Backend.submit queue2(get(Ogpu.Backend.transfer transfer2))~resources:[`Buffer a;`Buffer b]~pipelines:[])in
  get(Ogpu.Backend.complete_through queue ra.epoch);
  (match Ogpu.Backend.destroy_queue queue2 with Error e when e.Ogpu.Error.kind=Ogpu.Error.Invalid_state->()|_->failwith"queue-scoped completion overlap");
  (match Ogpu.Backend.destroy_device device with Error e when e.Ogpu.Error.kind=Ogpu.Error.Invalid_state->()|_->failwith"active-queue device destroy must reject atomically");
  get(Ogpu.Backend.complete_through queue2 rb.epoch);get(Ogpu.Backend.destroy_queue queue2);
  let group=get(Ogpu.Binding.create_group layout~group:0[{binding=0;resource=Ogpu.Backend.binding_buffer b}])in let declared : Ogpu.Compute_pass.resource={id=Ogpu.Backend.buffer_id b;access=Read_write;stages=[Compute_stage]}in let pass=get(Ogpu.Compute_pass.create(Ogpu.Backend.device_handle device)~limits:(Ogpu.Backend.capabilities device).limits~pipeline:(Pipeline.Private.portable native_compute)~layout~groups:[|0,group|]~resources:[|declared|]~dispatch:(Direct{x=4;y=1;z=1}))in for _=1 to 3 do let r=get(Ogpu.Backend.submit queue(Ogpu.Backend.compute pass)~resources:[`Buffer b]~pipelines:[compute_pipeline])in get(Ogpu.Backend.complete_through queue r.epoch)done;let out=get(Ogpu.Backend.read_buffer b~offset:0L~length:16)in for i=0 to 3 do if Bytes.get_int32_le out(i*4)<>Int32.of_int(i*8+7)then failwith"backend compute mismatch"done;
  let td : Ogpu.Types.texture_descriptor={label=None;width=4;height=4;depth=1;mip_levels=1;sample_count=1;usage=[Texture_binding;Render_attachment;Texture_copy_src]}in let target=get(Ogpu.Backend.create_texture device td)in let texture=Ogpu.Backend.render_texture target~format:Rgba8~usage:Render_target in let color : Ogpu.Render_pass.color={texture;resolve=None;load=Clear;store=Store;clear=(0.,0.,0.,1.)}in let rp=get(Ogpu.Render_pass.create(Ogpu.Backend.device_handle device){colors=[|Some color|];depth=None;stencil=None;viewport={x=0;y=0;width=4;height=4};scissor={x=0;y=0;width=4;height=4}})in
  let vertex=get(Ogpu.Backend.create_buffer device{label=Some"argument-vertices";size=24L;usage=[Vertex;Copy_dst]})in
  let vertex_bytes=Bytes.create 24 in List.iteri(fun i f->Bytes.set_int32_le vertex_bytes(i*4)(Int32.bits_of_float f))[-1.;-1.;3.;-1.;-1.;3.];get(Ogpu.Backend.write_buffer vertex~offset:0L vertex_bytes);
  let sampled=get(Ogpu.Backend.create_texture device{label=Some"argument-sampled";width=1;height=1;depth=1;mip_levels=1;sample_count=1;usage=[Texture_binding;Texture_copy_dst]})in
  let upload=get(Ogpu.Backend.create_buffer device{label=Some"argument-upload";size=256L;usage=[Copy_src;Copy_dst]})in let upload_bytes=Bytes.make 256 '\000'in Bytes.blit_string"\x11\x22\x33\xff"0 upload_bytes 0 4;get(Ogpu.Backend.write_buffer upload~offset:0L upload_bytes);
  let upload_pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in get(Ogpu.Transfer_pass.buffer_to_texture upload_pass~src:(Ogpu.Backend.transfer_buffer upload)~offset:0L~bytes_per_row:256L~bytes_per_image:256L~dst:(Ogpu.Backend.transfer_texture sampled)~mip:0~origin:{x=0;y=0;z=0}~extent:{width=1;height=1;depth=1});let uploaded=get(Ogpu.Backend.submit queue(get(Ogpu.Backend.transfer upload_pass))~resources:[`Buffer upload;`Texture sampled]~pipelines:[])in get(Ogpu.Backend.complete_through queue uploaded.epoch);
  let draw : Ogpu.Render_pass.draw={pipeline_key=Pipeline.key native_render;buffers=[];textures=[];samplers=[];primitive=Triangle_list;vertex_start=0;vertex_count=3;index=None}in
  let bad={draw with buffers=[{stage=Ogpu.Command.Vertex;index=0;buffer_id=Ogpu.Backend.buffer_id a;offset=0L};{stage=Ogpu.Command.Vertex;index=0;buffer_id=Ogpu.Backend.buffer_id b;offset=0L}]}in(match Ogpu.Backend.render rp[bad]with Error e when e.Ogpu.Error.kind=Ogpu.Error.Invalid_argument->()|_->failwith"backend render atomic validation");
  let rr=get(Ogpu.Backend.submit queue(get(Ogpu.Backend.render rp[draw]))~resources:[`Texture target]~pipelines:[render_pipeline])in get(Ogpu.Backend.complete_through queue rr.epoch);let pixels=get(Ogpu.Backend.read_texture target~bytes_per_row:16)in if Char.code(Bytes.get pixels 0)<>64||Char.code(Bytes.get pixels 1)<>128||Char.code(Bytes.get pixels 2)<>191 then failwith"backend nonindexed render mismatch";
  let stable_classic=get(Ogpu.Backend.render rp[draw])in
  List.iter(fun _frame->let receipt=get(Ogpu.Backend.submit queue stable_classic
    ~resources:[`Texture target]~pipelines:[render_pipeline])in
    get(Ogpu.Backend.complete_through queue receipt.epoch))[1;2;60;600];
  let stable_pixels=get(Ogpu.Backend.read_texture target~bytes_per_row:16)in
  if stable_pixels<>pixels then failwith"stable classic descriptor reuse pixels";
  let classic_probe=get(Ogpu.Backend.create_texture device td)in
  let classic_probe_texture=Ogpu.Backend.render_texture classic_probe~format:Rgba8~usage:Render_target in
  let classic_probe_color={color with texture=classic_probe_texture}in
  let classic_probe_pass=get(Ogpu.Render_pass.create(Ogpu.Backend.device_handle device){colors=[|Some classic_probe_color|];depth=None;stencil=None;viewport={x=0;y=0;width=4;height=4};scissor={x=0;y=0;width=4;height=4}})in
  let classic_probe_command=get(Ogpu.Backend.render classic_probe_pass[draw])in
  let classic_probe_receipt=get(Ogpu.Backend.submit queue classic_probe_command~resources:[`Texture classic_probe]~pipelines:[render_pipeline])in
  get(Ogpu.Backend.complete_through queue classic_probe_receipt.epoch);
  let classic_entries_before_destroy=Backend.classic_submission_entries control in
  if classic_entries_before_destroy<2 then failwith(Printf.sprintf
    "classic attachment cache fixture: %d"classic_entries_before_destroy);
  get(Ogpu.Backend.destroy_texture classic_probe);
  if Backend.classic_submission_entries control<>classic_entries_before_destroy-1 then
    failwith"destroyed classic attachment invalidated unrelated entries";
  let classic_replacement=get(Ogpu.Backend.create_texture device td)in
  let replacement_texture=Ogpu.Backend.render_texture classic_replacement~format:Rgba8~usage:Render_target in
  let replacement_color={color with texture=replacement_texture}in
  let replacement_pass=get(Ogpu.Render_pass.create(Ogpu.Backend.device_handle device){colors=[|Some replacement_color|];depth=None;stencil=None;viewport={x=0;y=0;width=4;height=4};scissor={x=0;y=0;width=4;height=4}})in
  let replacement_receipt=get(Ogpu.Backend.submit queue(get(Ogpu.Backend.render replacement_pass[draw]))~resources:[`Texture classic_replacement]~pipelines:[render_pipeline])in
  get(Ogpu.Backend.complete_through queue replacement_receipt.epoch);
  if get(Ogpu.Backend.read_texture classic_replacement~bytes_per_row:16)<>pixels then failwith"classic attachment replacement pixels";
  get(Ogpu.Backend.destroy_texture classic_replacement);
  let changed_resources=get(Ogpu.Backend.submit queue stable_classic
    ~resources:[`Texture target;`Buffer a]~pipelines:[render_pipeline])in
  get(Ogpu.Backend.complete_through queue changed_resources.epoch);
  let changed_resource_pixels=get(Ogpu.Backend.read_texture target~bytes_per_row:16)in
  if changed_resource_pixels<>pixels then
    failwith"classic descriptor differing-resource rebuild pixels";
  (* varying_viewport_scissor_classic_fallback: encoder-only state is retained by
     the classic pass and cannot be reused through an incompatible retained plan. *)
  let clipped=get(Ogpu.Render_pass.create(Ogpu.Backend.device_handle device){colors=[|Some color|];depth=None;stencil=None;viewport={x=0;y=0;width=4;height=4};scissor={x=1;y=1;width=2;height=2}})in
  let clipped_receipt=get(Ogpu.Backend.submit queue(get(Ogpu.Backend.render clipped[draw]))~resources:[`Texture target]~pipelines:[render_pipeline])in
  get(Ogpu.Backend.complete_through queue clipped_receipt.epoch);let clipped_pixels=get(Ogpu.Backend.read_texture target~bytes_per_row:16)in
  let channel x y c=Char.code(Bytes.get clipped_pixels((y*4+x)*4+c))in
  if channel 0 0 0<>0||channel 1 1 0<>64||channel 1 1 1<>128 then failwith"varying viewport/scissor fallback pixels";
  (* Exact argument ABI is eligible for retained ICB execution. *)
  let sampled_id=(Ogpu.Backend.render_texture sampled~format:Rgba8~usage:Render_target).id in
  let sampler:Ogpu.Types.sampler_descriptor={label=Some"argument-nearest";min_filter=Nearest;mag_filter=Nearest;mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
  let argument_draw:Ogpu.Render_pass.draw={pipeline_key=Pipeline.key native_argument;buffers=[{stage=Ogpu.Command.Vertex;index=0;buffer_id=Ogpu.Backend.buffer_id vertex;offset=0L}];textures=[{stage=Ogpu.Command.Fragment;index=0;texture_id=sampled_id}];samplers=[{stage=Ogpu.Command.Fragment;index=1;sampler}];primitive=Triangle_list;vertex_start=0;vertex_count=3;index=None}in
  let wrong_abi={argument_draw with samplers=[{stage=Ogpu.Command.Fragment;index=0;sampler}]}in
  let qa=get(Ogpu.Backend.create_queue device)and qb=get(Ogpu.Backend.create_queue device)in
  let argument_command=get(Ogpu.Backend.render rp[argument_draw])in
  let submit_argument q=Ogpu.Backend.submit q argument_command~resources:[`Texture target;`Texture sampled;`Buffer vertex]~pipelines:[argument_pipeline]in
  let stats0=Backend.retained_plan_stats control in if stats0.capacity<>1||stats0.entries<>0||stats0.builds<>0L||stats0.hits<>0L||stats0.misses<>0L||stats0.evictions<>0L||stats0.executions<>0L then failwith"retained plan initial statistics";
  let unchanged=get(Ogpu.Backend.read_texture target~bytes_per_row:16)in(match Ogpu.Backend.submit qa(get(Ogpu.Backend.render rp[wrong_abi]))~resources:[`Texture target;`Texture sampled;`Buffer vertex]~pipelines:[argument_pipeline]with Error e when e.Ogpu.Error.kind=Ogpu.Error.Invalid_argument||e.Ogpu.Error.kind=Ogpu.Error.Unsupported->()|_->failwith"wrong argument ABI accepted at native submit");if Backend.retained_plan_entries control<>0||get(Ogpu.Backend.read_texture target~bytes_per_row:16)<>unchanged then failwith"wrong argument ABI rejection was not atomic";
  if Backend.retained_plan_stats control<>stats0 then failwith"rejected retained plan changed statistics";
  let first=get(submit_argument qa)in get(Ogpu.Backend.complete_through qa first.epoch);let stats1=Backend.retained_plan_stats control in if Backend.retained_plan_entries control<>1||stats1.entries<>1||stats1.builds<>1L||stats1.misses<>1L||stats1.hits<>0L||stats1.executions<>1L then failwith"retained plan first insertion statistics";
  let hit=get(submit_argument qa)in get(Ogpu.Backend.complete_through qa hit.epoch);let stats2=Backend.retained_plan_stats control in if Backend.retained_plan_entries control<>1||Backend.retired_plan_entries control<>0||stats2.builds<>stats1.builds||stats2.misses<>stats1.misses||stats2.hits<>Int64.succ stats1.hits||stats2.executions<>Int64.succ stats1.executions then failwith"retained plan cache hit statistics";
  for _=3 to 600 do let receipt=get(submit_argument qa)in get(Ogpu.Backend.complete_through qa receipt.epoch)done;
  let stats600=Backend.retained_plan_stats control in
  if stats600.builds<>stats2.builds||stats600.misses<>stats2.misses||stats600.hits<>Int64.add stats2.hits 598L||stats600.executions<>Int64.add stats2.executions 598L then failwith"retained plan 600-frame reuse statistics";
  let exact=get(Ogpu.Backend.read_texture target~bytes_per_row:16)in if Bytes.sub_string exact 0 4<>"\x11\x22\x33\xff"then failwith"retained plan cache-hit pixels";
  (* A retained ICB owns draw bindings, not the render-pass attachment.  Rebind
     the same plan to a replacement target without rebuilding or invalidating
     it; this is the resize path used by the native runtime. *)
  let replacement_target=get(Ogpu.Backend.create_texture device td)in
  let replacement_target_texture=Ogpu.Backend.render_texture replacement_target~format:Rgba8~usage:Render_target in
  let replacement_target_color={color with texture=replacement_target_texture}in
  let replacement_target_pass=get(Ogpu.Render_pass.create(Ogpu.Backend.device_handle device)
    {colors=[|Some replacement_target_color|];depth=None;stencil=None;
     viewport={x=0;y=0;width=4;height=4};scissor={x=0;y=0;width=4;height=4}})in
  let before_attachment_rebind=Backend.retained_plan_stats control in
  let attachment_rebind=get(Ogpu.Backend.submit qa
    (get(Ogpu.Backend.render replacement_target_pass[argument_draw]))
    ~resources:[`Texture replacement_target;`Texture sampled;`Buffer vertex]
    ~pipelines:[argument_pipeline])in
  get(Ogpu.Backend.complete_through qa attachment_rebind.epoch);
  let after_attachment_rebind=Backend.retained_plan_stats control in
  if after_attachment_rebind.builds<>before_attachment_rebind.builds||
     after_attachment_rebind.misses<>before_attachment_rebind.misses||
     after_attachment_rebind.evictions<>before_attachment_rebind.evictions||
     after_attachment_rebind.hits<>Int64.succ before_attachment_rebind.hits||
     after_attachment_rebind.executions<>Int64.succ before_attachment_rebind.executions||
     after_attachment_rebind.entries<>1 then
    failwith"retained plan rebuilt for replacement attachment";
  let replacement_pixels=get(Ogpu.Backend.read_texture replacement_target~bytes_per_row:16)in
  if Bytes.sub_string replacement_pixels 0 4<>"\x11\x22\x33\xff"then
    failwith"retained plan rendered into stale attachment";
  get(Ogpu.Backend.destroy_texture replacement_target);
  if Backend.retained_plan_entries control<>1 then
    failwith"render attachment was retained as an ICB dependency";
  let stats2=after_attachment_rebind in
  let replacement_cache=get(Pipeline.create_cache~capacity:1)in let native_replacement=get(Pipeline.create_render_argument_buffer replacement_cache native_device argument_descriptor)in if Pipeline.Private.native_identity native_replacement=Pipeline.Private.native_identity native_argument||Pipeline.key native_replacement<>Pipeline.key native_argument then failwith"replacement pipeline identity fixture";Backend.register_pipeline control native_replacement;let replacement_pipeline=get(Ogpu.Backend.adopt_pipeline device(Pipeline.Private.portable native_replacement))in let replaced=get(Ogpu.Backend.submit qa(get(Ogpu.Backend.render rp[argument_draw]))~resources:[`Texture target;`Texture sampled;`Buffer vertex]~pipelines:[replacement_pipeline])in get(Ogpu.Backend.complete_through qa replaced.epoch);let stats3=Backend.retained_plan_stats control in if Backend.retained_plan_entries control<>1||stats3.entries<>1||stats3.builds<>Int64.succ stats2.builds||stats3.misses<>Int64.succ stats2.misses||stats3.hits<>stats2.hits||stats3.evictions<>Int64.succ stats2.evictions||stats3.executions<>Int64.succ stats2.executions then failwith"native pipeline identity replacement statistics";
  let pending_b=get(submit_argument qb)in let pending_a=get(submit_argument qa)in
  if Backend.retained_plan_entries control<>1||Backend.retired_plan_entries control<>1 then failwith"retained plan queue eviction state";
  get(Ogpu.Backend.complete_through qa pending_a.epoch);if Backend.retired_plan_entries control<>1 then failwith"queue A drained B retirement";
  get(Ogpu.Backend.complete_through qb pending_b.epoch);if Backend.retired_plan_entries control<>0 then failwith"queue B retirement remained";
  let shared=get(Ogpu.Backend.submit qa(get(Ogpu.Backend.render rp[argument_draw;argument_draw]))~resources:[`Texture target;`Texture sampled;`Buffer vertex]~pipelines:[argument_pipeline])in
  get(Ogpu.Backend.complete_through qa shared.epoch);
  let shared_pixels=get(Ogpu.Backend.read_texture target~bytes_per_row:16)in
  if Bytes.sub_string shared_pixels 0 4<>"\x11\x22\x33\xff"then failwith"duplicate retained resources changed exact pixels";
  (* A retained ICB is encoded through the classic render-pass descriptor.  Its
     Load action must preserve the color written by an earlier pass rather than
     silently clearing the attachment. *)
  let left_pass=get(Ogpu.Render_pass.create(Ogpu.Backend.device_handle device)
    {colors=[|Some color|];depth=None;stencil=None;viewport={x=0;y=0;width=4;height=4};scissor={x=0;y=0;width=2;height=4}})in
  let loaded_color={color with Ogpu.Render_pass.load=Load}in
  let right_pass=get(Ogpu.Render_pass.create(Ogpu.Backend.device_handle device)
    {colors=[|Some loaded_color|];depth=None;stencil=None;viewport={x=0;y=0;width=4;height=4};scissor={x=2;y=0;width=2;height=4}})in
  let left=get(Ogpu.Backend.submit qa(get(Ogpu.Backend.render left_pass[draw]))
    ~resources:[`Texture target]~pipelines:[render_pipeline])in
  get(Ogpu.Backend.complete_through qa left.epoch);
  let right=get(Ogpu.Backend.submit qa(get(Ogpu.Backend.render right_pass[argument_draw]))
    ~resources:[`Texture target;`Texture sampled;`Buffer vertex]~pipelines:[argument_pipeline])in
  get(Ogpu.Backend.complete_through qa right.epoch);
  let cross_pass=get(Ogpu.Backend.read_texture target~bytes_per_row:16)in
  let rgba x=Bytes.sub_string cross_pass(x*4)4 in
  if rgba 0<>"\x40\x80\xbf\xff"||rgba 3<>"\x11\x22\x33\xff"then
    failwith"retained ICB Load did not preserve the earlier pass color";
  let retained_probe=get(Ogpu.Backend.create_texture device{label=Some"retained-invalidation-probe";width=1;height=1;depth=1;mip_levels=1;sample_count=1;usage=[Texture_binding;Texture_copy_dst]})in
  let retained_probe_id=(Ogpu.Backend.render_texture retained_probe~format:Rgba8~usage:Render_target).id in
  let retained_probe_draw={argument_draw with textures=[{stage=Ogpu.Command.Fragment;index=0;texture_id=retained_probe_id}]}in
  let retained_probe_receipt=get(Ogpu.Backend.submit qa(get(Ogpu.Backend.render rp[retained_probe_draw]))~resources:[`Texture target;`Texture retained_probe;`Buffer vertex]~pipelines:[argument_pipeline])in
  get(Ogpu.Backend.complete_through qa retained_probe_receipt.epoch);
  if Backend.retained_plan_entries control<>1 then failwith"retained dependency invalidation fixture";
  get(Ogpu.Backend.destroy_texture retained_probe);
  if Backend.retained_plan_entries control<>0 then failwith"destroyed retained dependency remained cached";
  let invalidators_before=Backend.classic_invalidator_entries control in
  get(Ogpu.Backend.destroy_queue qa);get(Ogpu.Backend.destroy_queue qb);
  if Backend.classic_invalidator_entries control<>invalidators_before-2 then failwith"queue teardown retained classic invalidators";
  let before_disabled=get(Ogpu.Backend.read_texture target~bytes_per_row:16)in Backend.Private.disable_retained_plans_for_test control;(match submit_argument queue with Error e when e.Ogpu.Error.kind=Ogpu.Error.Unsupported->()|_->failwith"unavailable retained plan fell through classic path");if Backend.retained_plan_entries control<>0||Backend.retired_plan_entries control<>0||get(Ogpu.Backend.read_texture target~bytes_per_row:16)<>before_disabled then failwith"retained plan failure was not atomic";
  get(Ogpu.Backend.destroy_texture sampled);get(Ogpu.Backend.destroy_buffer vertex);if Backend.retained_plan_entries control<>0 then failwith"resource invalidation retained plan";
  let ibd : Ogpu.Types.buffer_descriptor={label=None;size=6L;usage=[Index;Copy_dst]}in let indices=get(Ogpu.Backend.create_buffer device ibd)in let ibytes=Bytes.create 6 in Bytes.set_uint16_le ibytes 0 0;Bytes.set_uint16_le ibytes 2 1;Bytes.set_uint16_le ibytes 4 2;get(Ogpu.Backend.write_buffer indices~offset:0L ibytes);let indexed={draw with index=Some(Uint16,Ogpu.Backend.buffer_id indices,0L,3)}in let draws=List.init 1000(fun i->if i land 1=0 then indexed else{draw with pipeline_key=Pipeline.key native_render2})in Gc.full_major();let allocated_before=Gc.allocated_bytes()in let rr=get(Ogpu.Backend.submit queue(get(Ogpu.Backend.render rp draws))~resources:[`Texture target;`Buffer indices]~pipelines:[render_pipeline;render_pipeline2])in let allocated=Gc.allocated_bytes()-.allocated_before in if allocated>9_000_000. then failwith(Printf.sprintf"backend 1000-draw allocation regression %.0f"allocated);get(Ogpu.Backend.destroy_buffer indices);get(Ogpu.Backend.complete_through queue rr.epoch);let pixels=get(Ogpu.Backend.read_texture target~bytes_per_row:16)in if Char.code(Bytes.get pixels 0)<>0||Char.code(Bytes.get pixels 1)<>255||Char.code(Bytes.get pixels 2)<>0 then failwith"backend ordered 1000-draw render mismatch";
  (* Surface lifecycle remains independently real and typed. *)
  let config : Ogpu.Surface.configuration={logical_width=4;logical_height=4;physical_width=4;physical_height=4;format=Bgra8_unorm;present_mode=Fifo;max_acquired=2}in
  let surface=get(Ogpu.Backend.create_surface device config)in
  let acquire_surface_frame()=match get(Ogpu.Backend.acquire surface)with
    |`Acquired frame->frame|_->failwith"backend surface acquire"in
  let acquire_surface_frame_sync()=match get(Ogpu.Backend.acquire_sync surface)with
    |`Acquired frame->frame|_->failwith"backend scoped surface acquire"in
  for i=0 to 2 do
    let frame=acquire_surface_frame()in
    if i land 1=0 then get(Ogpu.Backend.present~queue~source:target frame)
    else get(Ogpu.Backend.discard frame)
  done;
  let deferred_target=get(Ogpu.Backend.create_texture device
    {td with label=Some"deferred-presentation-source"})in
  let deferred_texture=Ogpu.Backend.render_texture deferred_target
    ~format:Rgba8~usage:Render_target in
  let deferred_color={color with Ogpu.Render_pass.texture=deferred_texture}in
  let deferred_pass=get(Ogpu.Render_pass.create(Ogpu.Backend.device_handle device)
    {colors=[|Some deferred_color|];depth=None;stencil=None;
     viewport={x=0;y=0;width=4;height=4};scissor={x=0;y=0;width=4;height=4}})in
  let combined_command=get(Ogpu.Backend.render deferred_pass[draw])in
  let combined_resources=[`Texture deferred_target]in
  let retry_frame=acquire_surface_frame()in
  Backend.Private.inject_next_active_queue_error control;
  expect Ogpu.Error.Device_lost
    (Ogpu.Backend.submit_present queue combined_command
      ~resources:combined_resources~pipelines:[render_pipeline]
      ~source:deferred_target retry_frame);
  expect Ogpu.Error.Invalid_state(Ogpu.Backend.configure surface config);
  expect Ogpu.Error.Invalid_state(Ogpu.Backend.destroy_surface surface);
  let retried=get(Ogpu.Backend.submit_present queue combined_command
    ~resources:combined_resources~pipelines:[render_pipeline]
    ~source:deferred_target retry_frame)in
  expect Ogpu.Error.Invalid_state(Ogpu.Backend.configure surface config);
  expect Ogpu.Error.Invalid_state(Ogpu.Backend.destroy_surface surface);
  get(Ogpu.Backend.destroy_texture deferred_target);
  expect Ogpu.Error.Stale_handle
    (Ogpu.Backend.read_texture deferred_target~bytes_per_row:16);
  get(Ogpu.Backend.complete_through queue retried.epoch);
  get(Ogpu.Backend.configure surface config);
  let terminal_command=get(Ogpu.Backend.render rp[draw])in
  let submit_terminal()=
    let frame=acquire_surface_frame_sync()in
    match Ogpu.Backend.submit_present_sync queue terminal_command
      ~resources:[`Texture target]~pipelines:[render_pipeline]
      ~source:target frame with
    |Error _ as error->error
    |Ok{receipt;completion=Ok()}->Ok receipt
    |Ok{completion=Error error;_}->Error error in
  for _=1 to 4 do
    ignore(get(submit_terminal()))
  done;
  Backend.Private.inject_next_active_queue_completion_error control;
  expect Ogpu.Error.Device_lost(submit_terminal());
  (* A terminal completion error is admitted work: the scoped frame must
     already be consumed and detached, so neither configure nor the next
     acquisition observes a stale outstanding frame. *)
  get(Ogpu.Backend.configure surface config);
  ignore(get(submit_terminal()));
  Gc.full_major();
  let control_gc_before=Gc.quick_stat()in
  for _=1 to 600 do
    let frame=acquire_surface_frame()in
    let receipt=get(Ogpu.Backend.submit queue terminal_command
      ~resources:[`Texture target]~pipelines:[render_pipeline])in
    get(Ogpu.Backend.complete_through queue receipt.epoch);
    get(Ogpu.Backend.present~queue~source:target frame)
  done;
  Gc.minor();
  let control_gc_after=Gc.quick_stat()in
  let control_promoted=
    (control_gc_after.promoted_words-.control_gc_before.promoted_words)*.
      float(Sys.word_size/8)/.600. in
  Gc.full_major();
  let presentation_gc_before=Gc.quick_stat()in
  for _frame=1 to 600 do ignore(get(submit_terminal()))done;
  Gc.minor();
  let presentation_gc_after=Gc.quick_stat()in
  let presentation_promoted=
    (presentation_gc_after.promoted_words-.
       presentation_gc_before.promoted_words)*.float(Sys.word_size/8)/.600. in
  let presentation_increment=max 0.(presentation_promoted-.control_promoted)in
  if presentation_increment>64. then
    failwith(Printf.sprintf
      "combined presentation incremental promotion regression %.1f B/frame (combined %.1f, control %.1f)"
      presentation_increment presentation_promoted control_promoted);
  let terminal_frame=acquire_surface_frame()in
  let terminal=get(Ogpu.Backend.submit_present queue terminal_command
    ~resources:[`Texture target]~pipelines:[render_pipeline]
    ~source:target terminal_frame)in
  Backend.Private.inject_next_active_queue_completion_error control;
  expect Ogpu.Error.Device_lost
    (Ogpu.Backend.complete_through queue terminal.epoch);
  get(Ogpu.Backend.configure surface config);
  get(Ogpu.Backend.destroy_surface surface);get(Ogpu.Backend.destroy_texture target);get(Ogpu.Backend.destroy_buffer upload);get(Ogpu.Backend.destroy_buffer a);get(Ogpu.Backend.destroy_buffer b);get(Ogpu.Backend.destroy_pipeline replacement_pipeline);Pipeline.clear_cache replacement_cache;get(Ogpu.Backend.destroy_pipeline argument_pipeline);get(Ogpu.Backend.destroy_pipeline compute_pipeline);get(Ogpu.Backend.destroy_pipeline render_pipeline);get(Ogpu.Backend.destroy_pipeline render_pipeline2);get(Ogpu.Backend.destroy_queue queue);get_metal(Metal.Metal_layer.destroy layer);get(Ogpu.Backend.destroy_device device);ignore(get_metal(Metal.Release_queue.drain()));let after=get_metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-1 then failwith(Printf.sprintf"backend adapter live delta before=%d after=%d pending=%d/%d created=%Ld/%Ld released=%Ld/%Ld plan=%d retired=%d sampler=%d"before.live_handles after.live_handles before.pending after.pending before.total_created after.total_created before.total_released after.total_released(Backend.retained_plan_entries control)(Backend.retired_plan_entries control)(Backend.sampler_cache_entries control));Printf.printf"ogpu_metal backend: transfer/compute/render1000/retained-plan queues/surface, combined %.1f/control %.1f/increment %.1f promoted B/frame, zero delta\n%!"presentation_promoted control_promoted presentation_increment
