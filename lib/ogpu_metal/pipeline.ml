open Ogpu.Pipeline
type native=Compute of Metal.Compute_pipeline.t|Render of Metal.Render_pipeline.t
type pipeline_kind
type t={native:native;library:Metal.Library.t;mutable functions:Metal.Function.t list;descriptor_destroy:(unit->unit)option;handle:pipeline_kind Ogpu.Handle.t;device:Device.t;portable:Ogpu.Pipeline.t;mutable dead:bool;mutable submission_uses:int;mutable destroy_requested:bool}
type cache={values:t Ogpu.Cache.t}
let error op kind message=Error(Ogpu.Error.make op kind message)
let key value=Ogpu.Pipeline.cache_key value.portable
let label value=Ogpu.Pipeline.label value.portable
let device_id value=Device.id value.device
let generation value=Ogpu.Handle.generation value.handle
let destroyed value=value.dead
let validate device value=Ogpu.Handle.validate_for~operation:"Ogpu_metal.Pipeline.validate"(Device.Private.handle device)value.handle
let finish_destroy value=let operation="Ogpu_metal.Pipeline.destroy"in let native_result=match value.native with Compute x->Metal.Compute_pipeline.destroy x|Render x->Metal.Render_pipeline.destroy x in match native_result with Error e->Error(Adapter.error~operation e)|Ok()->let first=List.fold_left(fun failure function_->match failure,Metal.Function.destroy function_ with Some _,_->failure|None,Ok()->None|None,Error e->Some e)None value.functions in let first=match first,Metal.Library.destroy value.library with Some e,_->Some e|None,Ok()->None|None,Error e->Some e in match first with Some e->Error(Adapter.error~operation e)|None->Option.iter(fun f->f())value.descriptor_destroy;Device.Private.detach_resource value.device;Ok()
let destroy value=if value.dead then Ok()else if value.submission_uses>0 then(Ogpu.Handle.destroy value.handle;value.dead<-true;value.destroy_requested<-true;Ok())else match finish_destroy value with Error _ as failure->failure|Ok()->Ogpu.Handle.destroy value.handle;value.dead<-true;Ok()
let create_cache~capacity=Result.map(fun values->{values})(Ogpu.Cache.create~capacity~on_evict:(fun~key:_ value _->ignore(destroy value)))
let cache_length value=Ogpu.Cache.length value.values
let cache_keys_lru value=Ogpu.Cache.keys_lru value.values
let clear_cache value=Ogpu.Cache.clear value.values
let metal_kind=function Ogpu.Shader.Uniform_buffer|Storage_buffer->`Buffer|Sampled_texture|Storage_texture->`Texture|Sampler->`Sampler
let reflected_kind (value:Metal.Binding.t)=match value.kind with Buffer_binding _->`Buffer|Texture_binding _->`Texture|Sampler_binding->`Sampler|_->`Other
let validate_reflection op shader bindings =
  let expected=Ogpu.Shader.bindings shader in
  if List.exists(fun(b:Ogpu.Shader.binding)->b.group<>0)expected then error op Ogpu.Error.Invalid_argument"Metal foundation maps only bind group zero"else
  let expected=List.sort compare(List.map(fun(b:Ogpu.Shader.binding)->b.binding,metal_kind b.kind)expected)and actual=bindings|>List.filter(fun(b:Metal.Binding.t)->b.used)|>List.map(fun(b:Metal.Binding.t)->Int64.to_int b.index,reflected_kind b)|>List.sort compare in
  if expected<>actual then error op Ogpu.Error.Invalid_argument"native Metal reflection does not match OGPU slots and resource classes"else Ok()
let compile_library op device shader=if Ogpu.Shader.backend shader<>"metal"then error op Ogpu.Error.Invalid_argument"shader backend is not metal"else match Metal.Library.compile_source~device:(Device.Private.metal device)?label:(Ogpu.Shader.label shader)(Bytes.to_string(Ogpu.Shader.bytes shader))with Ok x->Ok x|Error e->Error(Adapter.error~operation:op e)
let cached cache device portable build=let k=Ogpu.Pipeline.cache_key portable in match Ogpu.Cache.get cache.values k with Some value->(match validate device value with Ok()->Ok value|Error _ as e->e)|None->match build()with Error _ as e->e|Ok value->(match Ogpu.Cache.insert cache.values k value with Ok()->Ok value|Error e->ignore(destroy value);Error e)
let create_compute cache device descriptor=let op="Ogpu_metal.Pipeline.create_compute"in if Device.destroyed device then error op Ogpu.Error.Stale_handle"device is destroyed"else match Ogpu.Pipeline.create_compute(Device.capabilities device)descriptor with Error _ as e->e|Ok portable->cached cache device portable(fun()->match compile_library op device descriptor.shader with Error _ as e->e|Ok library->match Metal.Function.find~library descriptor.entry with Error e->ignore(Metal.Library.destroy library);Error(Adapter.error~operation:op e)|Ok function_->match Metal.Compute_pipeline.create~label:(Option.value descriptor.label~default:descriptor.entry)~reflection:true function_ with Error e->ignore(Metal.Function.destroy function_);ignore(Metal.Library.destroy library);Error(Adapter.error~operation:op e)|Ok pipeline->match Option.value(Metal.Compute_pipeline.bindings pipeline)~default:[]|>validate_reflection op descriptor.shader with Error e->ignore(Metal.Compute_pipeline.destroy pipeline);ignore(Metal.Function.destroy function_);ignore(Metal.Library.destroy library);Error e|Ok()->let value={native=Compute pipeline;library;functions=[function_];descriptor_destroy=None;handle=Ogpu.Handle.create~device:(Device.Private.handle device);device;portable;dead=false;submission_uses=0;destroy_requested=false}in Device.Private.attach_resource device;Ok value)
let attachment blend format =
  let open Metal.Render_pipeline in
  match blend with
  | Ogpu.Pipeline.Replace -> color_attachment format
  | Alpha -> color_attachment ~blending:Blend_enabled ~source_rgb:Blend_source_alpha
      ~destination_rgb:Blend_one_minus_source_alpha ~source_alpha:Blend_one
      ~destination_alpha:Blend_one_minus_source_alpha format
  | Add -> color_attachment ~blending:Blend_enabled ~source_rgb:Blend_one
      ~destination_rgb:Blend_one ~source_alpha:Blend_one ~destination_alpha:Blend_one format
  | Multiply -> color_attachment ~blending:Blend_enabled ~source_rgb:Blend_destination_color
      ~destination_rgb:Blend_zero ~source_alpha:Blend_one
      ~destination_alpha:Blend_one_minus_source_alpha format
  | Screen -> color_attachment ~blending:Blend_enabled
      ~source_rgb:Blend_one_minus_destination_color ~destination_rgb:Blend_one
      ~source_alpha:Blend_one ~destination_alpha:Blend_one_minus_source_alpha format
  | Subtract -> color_attachment ~blending:Blend_enabled ~source_rgb:Blend_one
      ~destination_rgb:Blend_one ~rgb_operation:Blend_reverse_subtract
      ~source_alpha:Blend_one ~destination_alpha:Blend_one_minus_source_alpha format

let create_render_internal ?(support_indirect_command_buffers=false) ?(blend=Ogpu.Pipeline.Replace) cache device descriptor=let op="Ogpu_metal.Pipeline.create_render"in if Device.destroyed device then error op Ogpu.Error.Stale_handle"device is destroyed"else match Ogpu.Pipeline.create_render~blend(Device.capabilities device)descriptor with Error _ as e->e|Ok portable->cached cache device portable(fun()->match compile_library op device descriptor.vertex with Error _ as e->e|Ok library->let color=match descriptor.color_format with Rgba8_unorm->Metal.Texture.Rgba8_unorm|Bgra8_unorm->Metal.Texture.Bgra8_unorm in match Metal.Compiler.create(Device.Private.metal device)with Error e->ignore(Metal.Library.destroy library);Error(Adapter.error~operation:op e)|Ok compiler->let fragment=Option.map(fun(_:Ogpu.Shader.t)->Option.get descriptor.fragment_entry)descriptor.fragment in match Metal.Compiler.create_render_pipeline?label:descriptor.label?fragment~reflection:true~raster_sample_count:descriptor.sample_count~color_attachments:[attachment blend color]~support_indirect_command_buffers compiler~library~vertex:descriptor.vertex_entry with Error e->ignore(Metal.Compiler.destroy compiler);ignore(Metal.Library.destroy library);Error(Adapter.error~operation:op e)|Ok pipeline->ignore(Metal.Compiler.destroy compiler);let reflection=Option.value(Metal.Render_pipeline.reflection pipeline)~default:{vertex=[];fragment=[];tile=[];object_=[];mesh=[]}in match validate_reflection op descriptor.vertex reflection.vertex with Error e->ignore(Metal.Render_pipeline.destroy pipeline);ignore(Metal.Library.destroy library);Error e|Ok()->let value={native=Render pipeline;library;functions=[];descriptor_destroy=None;handle=Ogpu.Handle.create~device:(Device.Private.handle device);device;portable;dead=false;submission_uses=0;destroy_requested=false}in Device.Private.attach_resource device;Ok value)
let create_render ?blend cache device descriptor=create_render_internal?blend cache device descriptor
let create_compute_runtime_msl=create_compute
let create_render_runtime_msl=create_render
let create_render_argument_buffer ?blend cache device descriptor=
  let operation="Ogpu_metal.Pipeline.create_render_argument_buffer"in
  match descriptor.fragment_entry with None->error operation Ogpu.Error.Invalid_argument"argument-buffer pipeline requires a fragment entry"|Some entry->
  let descriptor={descriptor with label=Some((Option.value descriptor.label~default:"render")^":argument-buffer-icb")}in
  match create_render_internal~support_indirect_command_buffers:true ?blend cache device descriptor with Error _ as e->e|Ok value->
  let rollback error=ignore(Ogpu.Cache.remove cache.values(Ogpu.Pipeline.cache_key value.portable));Error error in
  match value.native with Compute _->rollback(Ogpu.Error.make operation Ogpu.Error.Invalid_state"argument render factory returned compute pipeline")|Render native->match Metal.Render_pipeline.supports_indirect_command_buffers native with Error e->rollback(Adapter.error~operation e)|Ok false->rollback(Ogpu.Error.make operation Ogpu.Error.Unsupported"native pipeline does not support indirect commands")|Ok true->
  if value.functions<>[]then Ok value else match Metal.Function.find~library:value.library entry with Error e->rollback(Adapter.error~operation e)|Ok function_->value.functions<-[function_];Ok value
module Private=struct
  type nonrec native=native=Compute of Metal.Compute_pipeline.t|Render of Metal.Render_pipeline.t
  let native value=value.native
  let portable value=value.portable
  let native_identity value=Ogpu.Handle.id value.handle,Ogpu.Handle.generation value.handle
  let argument_function value=match value.native,value.functions with Render _,function_::_->Some function_|_->None
  let argument_encoder value ~buffer_index=match argument_function value with None->error"Ogpu_metal.Pipeline.argument_encoder"Ogpu.Error.Invalid_state"fragment function was not retained"|Some function_->(match Metal.Function.argument_encoder function_~buffer_index with Error e->Error(Adapter.error~operation:"Ogpu_metal.Pipeline.argument_encoder" e)|Ok encoder->Ok encoder)
  let retain_submission value=if value.dead then Error(Ogpu.Error.make"Ogpu_metal.Pipeline.retain_submission"Ogpu.Error.Stale_handle"pipeline is destroyed")else(value.submission_uses<-value.submission_uses+1;Ok())
  let release_submission value=value.submission_uses<-value.submission_uses-1;if value.submission_uses=0&&value.destroy_requested then ignore(finish_destroy value)
end
