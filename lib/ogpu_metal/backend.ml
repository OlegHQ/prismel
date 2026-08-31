type resource=Buffer of Buffer.t|Texture of Texture.t
module Native_metal=Metal
module Metal=struct
  include Native_metal
  type indirect_primitive=Native_metal.Indirect_command_buffer.Render_command.primitive=Point|Line|Line_strip|Triangle|Triangle_strip
end
type plan_owner={queue_token:int64;generation:int64;command_count:int;
  mutable last_epoch:int64;dependencies:int64 array;pipeline_keys:string list;
  commands:Metal.Indirect_command_buffer.Render_command.t list;
  samplers:Metal.Sampler.t list;encoders:Metal.Shader_argument_encoder.t list;
  buffers:Metal.Buffer.t list;
  resource_sets:Metal.Render_encoder.prepared_resources list;
  vertex_resources:Metal.Render_encoder.prepared_resources;
  fragment_resources:Metal.Render_encoder.prepared_resources;
  texture_resources:Metal.Render_encoder.prepared_resources;
  owner_bytes:int64;mutable passes:(Render_pass.t*int64 array)list}
type classic_submission={classic_command:Ogpu.Backend.command;
  classic_resources:(int64*int64)list;classic_pipelines:int64 list;
  classic_pass:Render_pass.t;classic_bytes:int64;mutable classic_epoch:int64;
  mutable classic_retired:bool}
type classic_cache_control=
  { invalidate_classic_resource:int64->unit
  ; invalidate_classic_pipeline:int64->unit
  ; invalidate_retained_key:string->unit
  ; classic_entries:unit->int
  ; classic_retained_bytes:unit->int64
  ; retained_identity_entries:unit->int
  ; retained_replay_entries:unit->int
  ; retained_metadata_bytes:unit->int64
  ; clear_classics:unit->unit
  ; clear_retained_metadata:unit->unit
  ; retry_cleanup:unit->unit
  ; cleanup_empty:unit->bool
  }
type retained_identity={identity_draws:Ogpu.Render_pass.draw list;
  identity_pipelines:int64 list;identity_key:string;identity_generation:int64;
  identity_bytes:int64}
type retained_replay={replay_command:Ogpu.Backend.command;
  replay_pipelines:int64 list;replay_key:string;mutable replay_pass:Render_pass.t;
  replay_attachment_ids:int64 array;mutable replay_attachment_tokens:int64 array;
  replay_bytes:int64;mutable replay_epoch:int64;mutable replay_retired:bool}
type retired={queue_token:int64;epoch:int64;icb:Metal.Indirect_command_buffer.t;
  mutable candidate:Metal.Retained_render_plan.candidate option;
  mutable icb_released:bool;
  owner:plan_owner option;retired_bytes:int64}
type cleanup_failure=
  |Metal_cleanup of Metal.error
  |Pass_cleanup of Ogpu.Error.t
type retained_plan_stats=
  { builds:int64;hits:int64;misses:int64;evictions:int64;executions:int64
  ; entries:int;capacity:int
  ; icb_retained_bytes:int64;icb_byte_capacity:int64
  ; owner_retained_bytes:int64;owner_byte_capacity:int64
  ; retired_bytes:int64 }
type classic_submission_stats=
  { entries:int
  ; retained_bytes:int64
  ; queues:int
  ; entry_capacity:int
  ; byte_capacity:int64
  }
type retained_metadata_stats=
  { identity_entries:int
  ; replay_entries:int
  ; retained_bytes:int64
  ; queues:int
  ; identity_entry_capacity:int
  ; replay_entry_capacity:int
  ; byte_capacity:int64
  }
type active_queue=
  { queue:Queue.t
  ; submit_combined:Queue.presentation -> Ogpu.Backend.command ->
      resources:(int64*int64) list -> pipelines:int64 list ->
      (Ogpu.Backend.receipt,Ogpu.Error.t) result
  ; presentations:Surface.Private.pending_presentation array
  }
type control={resources:(int64,resource)Hashtbl.t;pipelines:(string,Pipeline.t)Hashtbl.t;pipeline_tokens:(int64,Pipeline.t)Hashtbl.t;sampler_cache:(Ogpu.Types.sampler_descriptor,Sampler.t)Hashtbl.t;plan_owners:(string,plan_owner)Hashtbl.t;mutable plan_owner_order:string list;mutable owner_retained_bytes:int64;classic_invalidators:(int64,classic_cache_control)Hashtbl.t;active_queues:(int64,active_queue)Hashtbl.t;completed_epochs:(int64,int64)Hashtbl.t;mutable retired:retired list;mutable retired_bytes:int64;mutable plan_cache:Metal.Retained_render_plan.t option;mutable cleanup_error:Ogpu.Error.t option;mutable device_live:bool;mutable next:int64;mutable plan_builds:int64;mutable plan_hits:int64;mutable plan_misses:int64;mutable plan_evictions:int64;mutable plan_executions:int64;plan_capacity:int;owner_byte_capacity:int64;classic_byte_capacity:int64;metadata_byte_capacity:int64;layer:Metal.Metal_layer.t option}
let error op kind text=Error(Ogpu.Error.make op kind text)
let token c=let x=c.next in c.next<-Int64.succ x;x
let register_pipeline c pipeline=Hashtbl.replace c.pipelines(Pipeline.key pipeline)pipeline
let sampler_cache_entries c=Hashtbl.length c.sampler_cache
let retained_plans_enabled=true
let retained_plan_entries c=Hashtbl.length c.plan_owners
let retired_plan_entries c=List.length c.retired
let retained_owner_pass_entries c=Hashtbl.fold(fun _ owner count->
  count+List.length owner.passes)c.plan_owners 0
let pending_presentation_capacity=3
let classic_submission_capacity=256
let retained_identity_capacity=256
let retained_replay_capacity=256
let default_classic_submission_byte_capacity=67_108_864L
let default_retained_metadata_byte_capacity=67_108_864L
let default_retained_plan_owner_byte_capacity=67_108_864L
let saturating_add left right=
  if left>Int64.sub Int64.max_int right then Int64.max_int
  else Int64.add left right
let accounted_items count item_bytes=
  let count=Int64.of_int count in
  if count>Int64.div Int64.max_int item_bytes then Int64.max_int
  else Int64.mul count item_bytes
let accounted_string value=
  saturating_add 16L(Int64.of_int(String.length value))
let accounted_label=function None->0L|Some value->accounted_string value
let plan_owner_bytes ~key ~dependencies ~pipeline_keys ~command_count
    ~encoder_count ~sampler_count ~argument_buffer_lengths
    ~resource_set_count ~resource_reference_count=
  let pipeline_bytes=List.fold_left(fun bytes pipeline_key->
    bytes|>saturating_add 32L|>saturating_add(accounted_string pipeline_key))
    0L pipeline_keys in
  let argument_bytes=List.fold_left(fun bytes length->
    bytes|>saturating_add 384L|>saturating_add length)
    0L argument_buffer_lengths in
  2_048L
  |>saturating_add(accounted_string key)
  |>saturating_add(accounted_items(Array.length dependencies)16L)
  |>saturating_add pipeline_bytes
  |>saturating_add(accounted_items command_count 384L)
  |>saturating_add(accounted_items encoder_count 384L)
  |>saturating_add(accounted_items sampler_count 384L)
  |>saturating_add argument_bytes
  |>saturating_add(accounted_items resource_set_count 512L)
  |>saturating_add(accounted_items resource_reference_count 128L)
let retained_plan_stats c=
  let icb_entries,icb_retained_bytes,icb_byte_capacity=
    match c.plan_cache with
    |None->0,0L,0L
    |Some cache->
        let stats=Metal.Retained_render_plan.stats cache in
        stats.entries,stats.retained_bytes,stats.byte_capacity in
  assert(icb_entries=Hashtbl.length c.plan_owners);
  assert(icb_retained_bytes>=0L&&icb_retained_bytes<=icb_byte_capacity);
  assert(c.owner_retained_bytes>=0L&&
    c.owner_retained_bytes<=c.owner_byte_capacity);
  let combined=saturating_add icb_retained_bytes c.owner_retained_bytes
  and combined_capacity=
    saturating_add icb_byte_capacity c.owner_byte_capacity in
  assert(combined<=combined_capacity);
  {builds=c.plan_builds;hits=c.plan_hits;misses=c.plan_misses;
   evictions=c.plan_evictions;executions=c.plan_executions;
   entries=Hashtbl.length c.plan_owners;capacity=c.plan_capacity;
   icb_retained_bytes;icb_byte_capacity;
   owner_retained_bytes=c.owner_retained_bytes;
   owner_byte_capacity=c.owner_byte_capacity;retired_bytes=c.retired_bytes}
let retained_draw_bytes(draw:Ogpu.Render_pass.draw)=
  let bytes=512L|>saturating_add(accounted_string draw.pipeline_key)
    |>saturating_add(accounted_items(List.length draw.buffers)128L)
    |>saturating_add(accounted_items(List.length draw.textures)128L)in
  let bytes=List.fold_left(fun total(binding:Ogpu.Render_pass.sampler_binding)->
    total|>saturating_add 384L
      |>saturating_add(accounted_label binding.sampler.Ogpu.Types.label))
    bytes draw.samplers in
  if Option.is_some draw.index then saturating_add bytes 128L else bytes
let retained_draws_bytes draws=
  List.fold_left(fun total draw->saturating_add total(retained_draw_bytes draw))
    256L draws
let retained_command_bytes=Ogpu.Backend.Private.command_retained_bytes
let retained_identity_bytes draws pipelines key=
  retained_draws_bytes draws|>saturating_add 512L
  |>saturating_add(accounted_items(List.length pipelines)32L)
  |>saturating_add(accounted_string key)
let retained_replay_bytes command pipelines key pass ids tokens=
  retained_command_bytes command|>saturating_add 512L
  |>saturating_add(Render_pass.Private.retained_bytes pass)
  |>saturating_add(accounted_items(List.length pipelines)32L)
  |>saturating_add(accounted_string key)
  |>saturating_add(accounted_items(Array.length ids)16L)
  |>saturating_add(accounted_items(Array.length tokens)16L)
let classic_entry_bytes command pass resources pipelines=
  retained_command_bytes command
  |>saturating_add(Render_pass.Private.retained_bytes pass)
  |>saturating_add 512L
  |>saturating_add(accounted_items(List.length resources)64L)
  |>saturating_add(accounted_items(List.length pipelines)32L)
let submit_native_render ~presenting presentation queue pass=
  if presenting then Queue.submit_render_pass_present queue presentation pass
  else Queue.submit_render_pass queue pass
let classic_submission_stats c=
  let entries,retained_bytes=Hashtbl.fold(fun _ cache (entries,bytes)->
    entries+cache.classic_entries(),
    saturating_add bytes(cache.classic_retained_bytes()))c.classic_invalidators
    (0,0L)in
  let queues=Hashtbl.length c.classic_invalidators in
  let entry_capacity=
    if queues>max_int/classic_submission_capacity then max_int
    else queues*classic_submission_capacity in
  {entries;retained_bytes;queues;entry_capacity;
   byte_capacity=accounted_items queues c.classic_byte_capacity}
let classic_submission_entries c=(classic_submission_stats c).entries
let retained_metadata_stats c=
  let identity_entries,replay_entries,retained_bytes=
    Hashtbl.fold(fun _ cache (identities,replays,bytes)->
      identities+cache.retained_identity_entries(),
      replays+cache.retained_replay_entries(),
      saturating_add bytes(cache.retained_metadata_bytes()))
      c.classic_invalidators(0,0,0L)in
  let queues=Hashtbl.length c.classic_invalidators in
  let aggregate_capacity per_queue=
    if queues>max_int/per_queue then max_int else queues*per_queue in
  {identity_entries;replay_entries;retained_bytes;queues;
   identity_entry_capacity=aggregate_capacity retained_identity_capacity;
   replay_entry_capacity=aggregate_capacity retained_replay_capacity;
   byte_capacity=accounted_items queues c.metadata_byte_capacity}
let classic_invalidator_entries c=Hashtbl.length c.classic_invalidators
let disable_retained_plans_for_test c=
  match c.plan_cache with
  |None->()
  |Some cache->
      (match Metal.Retained_render_plan.destroy cache with
       |Error error->
           if Option.is_none c.cleanup_error then
             c.cleanup_error<-Some(Adapter.error
               ~operation:"Ogpu_metal.Backend.disable_retained_plans" error)
       |Ok()->
           c.plan_cache<-None;
           Hashtbl.iter(fun _ cache->
             cache.clear_retained_metadata();cache.retry_cleanup())
             c.classic_invalidators)
let with_only_active_queue c action=
  match Hashtbl.fold(fun _ active found->match found with None->Some active|Some _->None)c.active_queues None with
  |Some active when Hashtbl.length c.active_queues=1->action active.queue
  |None|Some _->()
let inject_next_active_queue_error c=with_only_active_queue c Queue.inject_next_error
let inject_next_active_queue_completion_error c=with_only_active_queue c Queue.inject_next_completion_error
module Private=struct
  let disable_retained_plans_for_test=disable_retained_plans_for_test
  let inject_next_active_queue_error=inject_next_active_queue_error
  let inject_next_active_queue_completion_error=inject_next_active_queue_completion_error
  let retained_owner_pass_entries=retained_owner_pass_entries
end
let first_cleanup current failure=
  match current with Some _->current|None->Some failure
let first_metal_cleanup current=function
  |Ok()->current
  |Error error->first_cleanup current(Metal_cleanup error)
let first_pass_cleanup current=function
  |Ok()->current
  |Error error->first_cleanup current(Pass_cleanup error)
let rec token_in_resources dependency=function
  |[]->false
  |(_,token)::rest->Int64.equal token dependency||
      token_in_resources dependency rest
let dependencies_live dependencies resources=
  let index=ref 0 in
  while !index<Array.length dependencies&&
        token_in_resources(Array.unsafe_get dependencies !index)resources do
    incr index
  done;
  !index=Array.length dependencies
let destroy_owner_front owner=
  let failure=List.fold_left(fun failure(pass,_)->
    first_pass_cleanup failure(Render_pass.Private.destroy pass))None owner.passes in
  let failure=List.fold_left(fun failure command->first_metal_cleanup failure
    (Metal.Indirect_command_buffer.Render_command.destroy command))failure
    owner.commands in
  let failure=List.fold_left(fun failure encoder->first_metal_cleanup failure
    (Metal.Shader_argument_encoder.destroy encoder))failure owner.encoders in
  List.fold_left(fun failure resources->first_metal_cleanup failure
    (Metal.Render_encoder.destroy_prepared_resources resources))failure
    owner.resource_sets
let destroy_owner_back owner failure=
  let failure=List.fold_left(fun failure buffer->first_metal_cleanup failure
    (Metal.Buffer.destroy buffer))failure owner.buffers in
  List.fold_left(fun failure sampler->first_metal_cleanup failure
    (Metal.Sampler.destroy sampler))failure owner.samplers
let destroy_owner owner=destroy_owner_back owner(destroy_owner_front owner)
let owner_retired_bytes icb owner=
  List.fold_left(fun bytes(pass,_)->saturating_add bytes
    (Render_pass.Private.retained_bytes pass))
    (saturating_add(Metal.Indirect_command_buffer.allocated_size icb)
      owner.owner_bytes)owner.passes
let destroy_retired retired=
  let failure=Option.fold~none:None~some:destroy_owner_front retired.owner in
  let destroyed=
    if retired.icb_released then Ok()else
    let result=match retired.candidate with
      |None->Metal.Indirect_command_buffer.destroy retired.icb
      |Some candidate->Metal.Retained_render_plan.discard candidate in
    (match result with
     |Error _->()
     |Ok()->retired.icb_released<-true;retired.candidate<-None);
    result in
  let failure=first_metal_cleanup failure destroyed in
  Option.fold~none:failure
    ~some:(fun owner->destroy_owner_back owner failure)retired.owner
let remove_plan_owner c key=
  match Hashtbl.find_opt c.plan_owners key with
  |None->None
  |Some owner->
      assert(owner.owner_bytes<=c.owner_retained_bytes);
      Hashtbl.remove c.plan_owners key;
      c.plan_owner_order<-List.filter((<>)key)c.plan_owner_order;
      c.owner_retained_bytes<-
        Int64.sub c.owner_retained_bytes owner.owner_bytes;
      Some owner
let release_accounted_retired (c:control) (retired:retired)=
  assert(retired.retired_bytes<=c.retired_bytes);
  c.retired_bytes<-Int64.sub c.retired_bytes retired.retired_bytes
let create ?device:provided_device ?layer ?(retained_plan_capacity=64)
    ?(retained_plan_owner_byte_capacity=
      default_retained_plan_owner_byte_capacity)
    ?(classic_submission_byte_capacity=default_classic_submission_byte_capacity)
    ?(retained_metadata_byte_capacity=default_retained_metadata_byte_capacity)()=
  if retained_plan_capacity<1||retained_plan_capacity>1024 then invalid_arg
    "Ogpu_metal.Backend.create: retained plan capacity must be in [1,1024]";
  if retained_plan_owner_byte_capacity<=0L then invalid_arg
    "Ogpu_metal.Backend.create: retained plan owner byte capacity must be positive";
  if classic_submission_byte_capacity<=0L then invalid_arg
    "Ogpu_metal.Backend.create: classic submission byte capacity must be positive";
  if retained_metadata_byte_capacity<=0L then invalid_arg
    "Ogpu_metal.Backend.create: retained metadata byte capacity must be positive";
  let c={resources=Hashtbl.create 32;pipelines=Hashtbl.create 16;pipeline_tokens=Hashtbl.create 16;sampler_cache=Hashtbl.create 64;plan_owners=Hashtbl.create 64;plan_owner_order=[];owner_retained_bytes=0L;classic_invalidators=Hashtbl.create 4;active_queues=Hashtbl.create 4;completed_epochs=Hashtbl.create 4;retired=[];retired_bytes=0L;plan_cache=None;cleanup_error=None;device_live=false;next=1L;plan_builds=0L;plan_hits=0L;plan_misses=0L;plan_evictions=0L;plan_executions=0L;plan_capacity=retained_plan_capacity;owner_byte_capacity=retained_plan_owner_byte_capacity;classic_byte_capacity=classic_submission_byte_capacity;metadata_byte_capacity=retained_metadata_byte_capacity;layer}in
  let record_ogpu_cleanup error=
    if Option.is_none c.cleanup_error then c.cleanup_error<-Some error in
  let record_cleanup failure=Option.iter(fun error->record_ogpu_cleanup
    (Adapter.error~operation:"Ogpu_metal.Backend.cleanup"error))failure in
  let record_destroy_cleanup=Option.iter(function
    |Metal_cleanup error->record_cleanup(Some error)
    |Pass_cleanup error->record_ogpu_cleanup error)in
  let take_cleanup_error()=
    let failure=c.cleanup_error in c.cleanup_error<-None;failure in
  let account_retired retired=
    c.retired<-retired::c.retired;
    c.retired_bytes<-saturating_add c.retired_bytes retired.retired_bytes in
  let attempt_retired retired=
    match destroy_retired retired with
    |None->true
    |Some failure->record_destroy_cleanup(Some failure);false in
  let drain_retired ready=
    c.retired<-List.filter(fun retired->
      if not(ready retired)then true
      else if attempt_retired retired then begin
        release_accounted_retired c retired;false
      end else true)c.retired in
  let obtain_device()=match provided_device with Some device->Ok device|None->Device.system_default()in
  let create_device()=if c.device_live then error"Ogpu_metal.Backend.create_device"Ogpu.Error.Invalid_state"adapter already owns a live device"else match obtain_device()with Error _ as e->e|Ok device->c.device_live<-true;let device_token=token c in
    let handoff~key~generation:_ icb=
      c.plan_evictions<-Int64.succ c.plan_evictions;
      let owner:plan_owner option=Hashtbl.find_opt c.plan_owners key in
      let queue_token=Option.fold~none:0L
          ~some:(fun(owner:plan_owner)->owner.queue_token)owner in
      Option.iter(fun cache->cache.invalidate_retained_key key)
        (Hashtbl.find_opt c.classic_invalidators queue_token);
      let owner=remove_plan_owner c key in
      let epoch=Option.fold~none:0L
          ~some:(fun(owner:plan_owner)->owner.last_epoch)owner in
      let retired_bytes=match owner with
        |None->Metal.Indirect_command_buffer.allocated_size icb
        |Some owner->owner_retired_bytes icb owner in
      let retired={queue_token;epoch;icb;candidate=None;icb_released=false;
        owner;retired_bytes}in
      let completed=Option.value(Hashtbl.find_opt c.completed_epochs queue_token)
          ~default:0L in
      if epoch=0L||epoch<=completed||
         not(Hashtbl.mem c.active_queues queue_token)then begin
        if not(attempt_retired retired)then account_retired retired
      end else account_retired retired in
    (match Metal.Retained_render_plan.create~device:(Device.Private.metal device)~capacity:retained_plan_capacity~on_evict:handoff()with Ok cache->c.plan_cache<-Some cache|Error _->());
    let invalidate_resource id=Hashtbl.iter(fun _ cache->
      cache.invalidate_classic_resource id)c.classic_invalidators;
      match c.plan_cache with None->()|Some cache->let keys=Hashtbl.fold(fun key(owner:plan_owner) acc->if Array.exists(Int64.equal id)owner.dependencies then key::acc else acc)c.plan_owners[]in List.iter(fun key->match Metal.Retained_render_plan.invalidate cache key with Ok()->()|Error error->record_cleanup(Some error))keys in
    let create_buffer descriptor=match Buffer.create device~memory:Buffer.Shared descriptor with Error _ as e->e|Ok buffer->let id=token c in Hashtbl.add c.resources id(Buffer buffer);let read offset length=Buffer.read_bytes device buffer~offset~length in Ok{Ogpu.Backend.token=id;write=(fun offset bytes->Buffer.write_bytes device buffer~dst_offset:offset bytes);read;read_into=(fun offset destination destination_offset length->match read offset length with Error _ as e->e|Ok bytes->if destination_offset<0||length>Bytes.length destination-destination_offset then error"Ogpu_metal.Backend.buffer.read_into"Ogpu.Error.Invalid_argument"destination range is invalid"else(Bytes.blit bytes 0 destination destination_offset length;Ok()));destroy=(fun()->invalidate_resource id;match Buffer.destroy buffer with Error _ as e->e|Ok()->Hashtbl.remove c.resources id;Ok())}in
    let create_texture_format ~format ~host_read descriptor=match Texture.create device~memory:(if descriptor.Ogpu.Types.sample_count=1&&host_read then Texture.Shared else Device_local)~format descriptor with Error _ as e->e|Ok texture->let id=token c in Hashtbl.add c.resources id(Texture texture);let read offset length=if not host_read then error"Ogpu_metal.Backend.depth.read"Ogpu.Error.Unsupported"depth textures are not host readable"else if offset<>0L||descriptor.height<=0||length mod descriptor.height<>0 then error"Ogpu_metal.Backend.texture.read"Ogpu.Error.Invalid_argument"texture read range is invalid"else Texture.read_bytes device texture~mip_level:0~bytes_per_row:(length/descriptor.height)in let read_into offset destination destination_offset length=if not host_read then error"Ogpu_metal.Backend.depth.read_into"Ogpu.Error.Unsupported"depth textures are not host readable"else if offset<>0L||destination_offset<>0||length<>Bytes.length destination||descriptor.height<=0||length mod descriptor.height<>0 then error"Ogpu_metal.Backend.texture.read_into"Ogpu.Error.Invalid_argument"destination must exactly match the texture read range"else Texture.read_bytes_into device texture~mip_level:0~bytes_per_row:(length/descriptor.height)~destination in Ok{Ogpu.Backend.token=id;write=(fun _ _->error"Ogpu_metal.Backend.texture.write"Ogpu.Error.Unsupported"use a transfer pass for textures");read;read_into;destroy=(fun()->invalidate_resource id;match Texture.destroy texture with Error _ as e->e|Ok()->Hashtbl.remove c.resources id;Ok())}in
    let create_texture descriptor=create_texture_format~format:Texture.Rgba8_unorm~host_read:true descriptor in
    let create_depth_texture descriptor=create_texture_format~format:Texture.Depth32_float~host_read:false descriptor in
    let create_stencil_texture descriptor=create_texture_format~format:Texture.Stencil8~host_read:false descriptor in
    let invalidate_pipeline key id=Hashtbl.iter(fun _ cache->
      cache.invalidate_classic_pipeline id)c.classic_invalidators;
      match c.plan_cache with None->()|Some cache->let keys=Hashtbl.fold(fun plan_key(owner:plan_owner) acc->if List.mem key owner.pipeline_keys then plan_key::acc else acc)c.plan_owners[]in List.iter(fun plan_key->match Metal.Retained_render_plan.invalidate cache plan_key with Ok()->()|Error error->record_cleanup(Some error))keys in
    let compact_sampler_cache()=
      (* Cached pass descriptors borrow sampler wrappers between submissions.
         Drop those descriptors, and retained plans that embed them, before
         reclaiming cache entries. In-flight samplers reject destruction and
         remain in the bounded cache until a later compaction. *)
      Hashtbl.iter(fun _ cache->cache.clear_classics())c.classic_invalidators;
      Option.iter(fun cache->
        let keys=Hashtbl.fold(fun key _ acc->key::acc)c.plan_owners[]in
        List.iter(fun key->ignore(Metal.Retained_render_plan.invalidate cache key))keys)
        c.plan_cache;
      Hashtbl.filter_map_inplace(fun _ sampler->match Sampler.destroy sampler with Ok()->None|Error _->Some sampler)c.sampler_cache
    in
    let create_pipeline portable=match Hashtbl.find_opt c.pipelines(Ogpu.Pipeline.cache_key portable)with None->error"Ogpu_metal.Backend.create_pipeline"Ogpu.Error.Invalid_argument"portable pipeline was not registered with the Metal adapter"|Some pipeline->let id=token c in Hashtbl.add c.pipeline_tokens id pipeline;Ok{Ogpu.Backend.pipeline_token=id;destroy_pipeline=(fun()->invalidate_pipeline(Pipeline.key pipeline)id;match Pipeline.destroy pipeline with Error _ as e->e|Ok()->Hashtbl.remove c.pipeline_tokens id;Ok())}in
    let native_resource token=Hashtbl.find_opt c.resources token in
    let create_queue()=match Queue.create device with Error _ as e->e|Ok queue->let queue_token=token c in
      (* A prepared Scene_execution command is immutable and may be submitted
         for many frames.  Retain a bounded set of fully converted classic
         descriptors per queue; exact portable commands and resource/pipeline
         token lists make reuse safe across freshly allocated wrappers. *)
      let classic_submissions=ref[]in
      let classic_retained_bytes=ref 0L in
      let retire_classic entry=
        entry.classic_retired<-true;
        let completed=Queue.completed_epoch queue in
        match Render_pass.Private.destroy entry.classic_pass with
        |Error error->
            if entry.classic_epoch<=completed then record_ogpu_cleanup error;
            false
        |Ok()->
            assert(entry.classic_bytes<= !classic_retained_bytes);
            classic_retained_bytes:=Int64.sub !classic_retained_bytes
              entry.classic_bytes;
            true in
      let filter_classics keep=
        classic_submissions:=List.filter(fun entry->
          if not(keep entry)then entry.classic_retired<-true;
          not(entry.classic_retired&&retire_classic entry))
          !classic_submissions in
      let drop_oldest_classic()=
        match List.rev!classic_submissions with
        |[]->false
        |oldest::reversed->
            if retire_classic oldest then begin
              classic_submissions:=List.rev reversed;true
            end else false in
      let make_room_for_classic entry_bytes=
        if entry_bytes>c.classic_byte_capacity then false else
        let available=Int64.sub c.classic_byte_capacity entry_bytes in
        let rec make_room()=
          if List.length!classic_submissions<classic_submission_capacity&&
             !classic_retained_bytes<=available then true
          else if drop_oldest_classic()then make_room()else false in
        make_room()in
      let retained_identities:retained_identity list ref=ref[]in
      let retained_identity_byte_count=ref 0L in
      let retained_replays=Array.make retained_replay_capacity None in
      let retained_replay_length=ref 0 in
      let retained_replay_byte_count=ref 0L in
      let retire_identity entry=
        assert(entry.identity_bytes<= !retained_identity_byte_count);
        retained_identity_byte_count:=Int64.sub !retained_identity_byte_count
          entry.identity_bytes in
      let drop_retained_identities keep=
        let retained,rejected=List.partition keep !retained_identities in
        retained_identities:=retained;
        List.iter retire_identity rejected in
      let release_replay_pass ~record_failure entry=
        match Render_pass.Private.destroy entry.replay_pass with
        |Error error->if record_failure then record_ogpu_cleanup error;false
        |Ok()->
            Option.iter(fun(owner:plan_owner)->
              owner.passes<-List.filter(fun(candidate,_)->
                candidate!=entry.replay_pass)owner.passes)
              (Hashtbl.find_opt c.plan_owners entry.replay_key);
            true in
      let retire_replay entry=
        entry.replay_retired<-true;
        let completed=Queue.completed_epoch queue in
        if release_replay_pass
            ~record_failure:(entry.replay_epoch<=completed)entry then begin
          assert(entry.replay_bytes<= !retained_replay_byte_count);
          retained_replay_byte_count:=Int64.sub !retained_replay_byte_count
            entry.replay_bytes;
          true
        end else false in
      let drop_retained_replays keep=
        let write=ref 0 in
        for read=0 to !retained_replay_length-1 do
          match Array.unsafe_get retained_replays read with
          |Some entry->
              if not(keep entry)then entry.replay_retired<-true;
              if not(entry.replay_retired&&retire_replay entry)then begin
                if !write<>read then
                  Array.unsafe_set retained_replays !write(Some entry);
                incr write
              end
          |None->assert false
        done;
        for index= !write to !retained_replay_length-1 do
          Array.unsafe_set retained_replays index None
        done;
        retained_replay_length:= !write in
      let drop_oldest_identity()=
        match List.rev !retained_identities with
        |[]->false
        |oldest::reversed->
            retained_identities:=List.rev reversed;
            retire_identity oldest;true in
      let drop_oldest_replay()=
        if !retained_replay_length=0 then false else begin
          let index= !retained_replay_length-1 in
          let entry=Option.get(Array.unsafe_get retained_replays index)in
          if retire_replay entry then begin
            Array.unsafe_set retained_replays index None;
            retained_replay_length:=index;true
          end else false
        end in
      let retained_metadata_byte_count()=
        saturating_add !retained_identity_byte_count
          !retained_replay_byte_count in
      let make_room_for_identity bytes=
        if bytes>c.metadata_byte_capacity then false else
        let available=Int64.sub c.metadata_byte_capacity bytes in
        let room=ref true in
        while !room&&(List.length !retained_identities>=
            retained_identity_capacity||
            retained_metadata_byte_count()>available)do
          room:=drop_oldest_identity()
        done;
        !room&&List.length !retained_identities<retained_identity_capacity&&
        retained_metadata_byte_count()<=available in
      let make_room_for_replay bytes=
        if bytes>c.metadata_byte_capacity then false else
        let available=Int64.sub c.metadata_byte_capacity bytes in
        let room=ref true in
        while !room&&(!retained_replay_length>=retained_replay_capacity||
            retained_metadata_byte_count()>available)do
          room:=if drop_oldest_identity()then true else drop_oldest_replay()
        done;
        !room&& !retained_replay_length<retained_replay_capacity&&
        retained_metadata_byte_count()<=available in
      let retain_identity entry=
        if make_room_for_identity entry.identity_bytes then begin
          retained_identities:=entry::!retained_identities;
          retained_identity_byte_count:=Int64.add
            !retained_identity_byte_count entry.identity_bytes;
          true
        end else false in
      let retain_replay entry=
        if make_room_for_replay entry.replay_bytes then begin
          if !retained_replay_length>0 then
            Array.blit retained_replays 0 retained_replays 1
              !retained_replay_length;
          Array.unsafe_set retained_replays 0(Some entry);
          incr retained_replay_length;
          retained_replay_byte_count:=Int64.add !retained_replay_byte_count
            entry.replay_bytes;
          true
        end else false in
      let replay_admission_preflight bytes=
        if bytes>c.metadata_byte_capacity then false else
        let available=Int64.sub c.metadata_byte_capacity bytes
        and completed=Queue.completed_epoch queue in
        let rec simulate length retained index=
          if length<retained_replay_capacity&&retained<=available then true
          else if index<0 then false else
          match Array.unsafe_get retained_replays index with
          |None->false
          |Some entry when entry.replay_retired||entry.replay_epoch>completed->
              false
          |Some entry->simulate(length-1)
              (Int64.sub retained entry.replay_bytes)(index-1)in
        (* Identity entries are always removable without native cleanup and are
           selected before replay victims by [make_room_for_replay]. *)
        simulate !retained_replay_length !retained_replay_byte_count
          (!retained_replay_length-1)in
      let invalidate_retained_key key=
        drop_retained_identities(fun entry->entry.identity_key<>key);
        drop_retained_replays(fun entry->entry.replay_key<>key)in
      let clear_retained_metadata()=
        drop_retained_identities(fun _->false);
        drop_retained_replays(fun _->false)in
      let invalidate_owner_attachments id=
        Hashtbl.iter(fun _ (owner:plan_owner)->
          owner.passes<-List.filter(fun(pass,tokens)->
            if not(Array.exists(Int64.equal id)tokens)then true else
            match Render_pass.Private.destroy pass with
            |Ok()->false
            |Error error->
                if owner.last_epoch<=Queue.completed_epoch queue then
                  record_ogpu_cleanup error;
                true)owner.passes)
          c.plan_owners in
      let invalidate_classic_resource id=
        filter_classics(fun entry->not(List.exists(fun(_,token)->token=id)
          entry.classic_resources));
        drop_retained_replays(fun entry->
          not(Array.exists(Int64.equal id)entry.replay_attachment_tokens));
        invalidate_owner_attachments id
      and invalidate_classic_pipeline id=
        filter_classics(fun entry->not(List.mem id entry.classic_pipelines))in
      let retry_cleanup()=
        filter_classics(fun _->true);
        drop_retained_replays(fun _->true)in
      let cleanup_empty()=
        !classic_submissions=[]&& !retained_replay_length=0 in
      Hashtbl.add c.classic_invalidators queue_token
        {invalidate_classic_resource;invalidate_classic_pipeline;
         invalidate_retained_key;
         classic_entries=(fun()->List.length!classic_submissions);
         classic_retained_bytes=(fun()-> !classic_retained_bytes);
         retained_identity_entries=(fun()->List.length!retained_identities);
         retained_replay_entries=(fun()-> !retained_replay_length);
         retained_metadata_bytes=retained_metadata_byte_count;
         clear_classics=(fun()->filter_classics(fun _->false));
         clear_retained_metadata;retry_cleanup;cleanup_empty};
      let rec same_resources left right=match left,right with
        |[],[]->true|(left_id,left_token)::left,(right_id,right_token)::right->
          Int64.equal left_id right_id&&Int64.equal left_token right_token&&
          same_resources left right|_->false in
      let rec same_pipelines left right=match left,right with
        |[],[]->true|left::lefts,right::rights->Int64.equal left right&&
          same_pipelines lefts rights|_->false in
      let attachment_ids submission=
        let descriptor=Ogpu.Render_pass.descriptor
            (Ogpu.Render_pass.submission_pass submission)in
        let reversed=ref[]in
        Array.iter(function None->()|Some(color:Ogpu.Render_pass.color)->
          reversed:=color.texture.id::!reversed;
          Option.iter(fun(texture:Ogpu.Render_pass.texture)->
            reversed:=texture.id::!reversed)color.resolve)descriptor.colors;
        Option.iter(fun(depth:Ogpu.Render_pass.depth)->
          reversed:=depth.texture.id::!reversed)descriptor.depth;
        Option.iter(fun(stencil:Ogpu.Render_pass.stencil)->
          reversed:=stencil.texture.id::!reversed)descriptor.stencil;
        Array.of_list(List.rev!reversed)in
      let resolve_attachment_tokens ids resources=
        Array.map(fun id->Option.value(List.assoc_opt id resources)
          ~default:Int64.min_int)ids in
      let same_attachment_tokens ids tokens resources=
        let rec loop index=
          index=Array.length ids||
          (match List.assoc_opt ids.(index)resources with
           |Some token when Int64.equal token tokens.(index)->loop(index+1)
           |None|Some _->false)in
        Array.length ids=Array.length tokens&&loop 0 in
      let unused_presentation _=assert false in
      let submit_with ~presenting presentation command ~resources ~pipelines=
        let command_view=Ogpu.Backend.Private.command_view command in
        match command_view with
        |(Ogpu.Backend.Private.Transfer _|Compute _)when presenting->error"Ogpu_metal.Backend.submit_present"Ogpu.Error.Unsupported"combined presentation requires a render command"
        |Render submission when presenting&&Render_pass.Private.portable_requires_command4(Ogpu.Render_pass.submission_pass submission)->error"Ogpu_metal.Backend.submit_present"Ogpu.Error.Unsupported"combined presentation requires a classic render pass"
        |_->let find id=Option.bind(List.assoc_opt id resources)native_resource in
        let one_pipeline()=match pipelines with[id]->Hashtbl.find_opt c.pipeline_tokens id|_->None in
        let native_render_descriptor (descriptor:Ogpu.Render_pass.descriptor)=
          let fact usage (value:Ogpu.Render_pass.texture)=match find value.id with Some(Texture texture)->Render_pass.attachment device texture~usage|_->error"Ogpu_metal.Backend.render"Ogpu.Error.Invalid_argument"render attachment graph is incomplete"in
          let colors=Array.map(function None->Ok None|Some(color:Ogpu.Render_pass.color)->match fact Render_target color.texture with Error _ as e->e|Ok texture->(match color.resolve with None->Ok(Some{color with texture})|Some resolve->Result.map(fun resolve->Some{color with texture;resolve=Some resolve})(fact Resolve_target resolve)))descriptor.colors in
          if Array.exists Result.is_error colors then Array.find_opt Result.is_error colors|>Option.get|>Result.map(fun _->assert false)else let depth=match descriptor.depth with None->Ok None|Some(d:Ogpu.Render_pass.depth)->Result.map(fun texture->Some{d with texture})(fact Render_target d.texture)and stencil=match descriptor.stencil with None->Ok None|Some(s:Ogpu.Render_pass.stencil)->Result.map(fun texture->Some{s with texture})(fact Render_target s.texture)in match depth,stencil with Error e,_->Error e|_,Error e->Error e|Ok depth,Ok stencil->Ok{descriptor with colors=Array.map Result.get_ok colors;depth;stencil}in
        let result=match command_view with
        |Ogpu.Backend.Private.Transfer descriptions->let pass=Ogpu.Transfer_pass.create(Device.Private.handle device)in let b id=match find id with Some(Buffer x)->Ok x|_->error"Ogpu_metal.Backend.transfer"Ogpu.Error.Invalid_argument"buffer graph is incomplete"and t id=match find id with Some(Texture x)->Ok x|_->error"Ogpu_metal.Backend.transfer"Ogpu.Error.Invalid_argument"texture graph is incomplete"in let rec replay i=if i=Array.length descriptions then match Transfer_pass.create device pass~buffers:(List.filter_map(fun(_,tok)->match native_resource tok with Some(Buffer x)->Some x|_->None)resources)~textures:(List.filter_map(fun(_,tok)->match native_resource tok with Some(Texture x)->Some x|_->None)resources)with Error _ as e->e|Ok encoded->Queue.submit_transfer_pass queue encoded else let next=match descriptions.(i)with
          |Ogpu.Transfer_pass.Copy_buffer(a,ao,d,do_,n)->(match b a,b d with Ok a,Ok d->Ogpu.Transfer_pass.copy_buffer pass~src:(Result.get_ok(Transfer_pass.buffer device a))~src_offset:ao~dst:(Result.get_ok(Transfer_pass.buffer device d))~dst_offset:do_~length:n|Error e,_->Error e|_,Error e->Error e)
          |Fill_buffer(a,o,n,v)->(match b a with Error _ as e->e|Ok a->Ogpu.Transfer_pass.fill_buffer pass(Result.get_ok(Transfer_pass.buffer device a))~offset:o~length:n~value:v)
          |Buffer_to_texture(a,o,row,image,d,mip,origin,extent)->(match b a,t d with Ok a,Ok d->Ogpu.Transfer_pass.buffer_to_texture pass~src:(Result.get_ok(Transfer_pass.buffer device a))~offset:o~bytes_per_row:row~bytes_per_image:image~dst:(Result.get_ok(Transfer_pass.texture device d))~mip~origin~extent|Error e,_->Error e|_,Error e->Error e)
          |Texture_to_buffer(a,mip,origin,extent,d,o,row,image)->(match t a,b d with Ok a,Ok d->Ogpu.Transfer_pass.texture_to_buffer pass~src:(Result.get_ok(Transfer_pass.texture device a))~mip~origin~extent~dst:(Result.get_ok(Transfer_pass.buffer device d))~offset:o~bytes_per_row:row~bytes_per_image:image|Error e,_->Error e|_,Error e->Error e)
          |Copy_texture(a,am,ao,d,dm,do_,extent)->(match t a,t d with Ok a,Ok d->Ogpu.Transfer_pass.copy_texture pass~src:(Result.get_ok(Transfer_pass.texture device a))~src_mip:am~src_origin:ao~dst:(Result.get_ok(Transfer_pass.texture device d))~dst_mip:dm~dst_origin:do_~extent|Error e,_->Error e|_,Error e->Error e)in match next with Error _ as e->e|Ok()->replay(i+1)in replay 0
        |Compute description->(match one_pipeline()with None->error"Ogpu_metal.Backend.compute"Ogpu.Error.Invalid_argument"compute pipeline graph is incomplete"|Some pipeline->let slots=Array.to_list description.groups|>List.concat_map(fun(_,xs)->xs)|>List.map fst and ids=Array.to_list description.commands|>List.filter_map(function Ogpu.Command.Declare_resource r->Some r.resource_id|_->None)in if List.length slots<>List.length ids then error"Ogpu_metal.Backend.compute"Ogpu.Error.Invalid_argument"binding/resource cardinality differs"else let native_id id=match find id with Some(Buffer buffer)->Buffer.id buffer|_->id in let bindings=List.map2(fun index id->match find id with Some(Buffer buffer)->Ok{Compute_pass.id=Buffer.id buffer;index;buffer}|_->error"Ogpu_metal.Backend.compute"Ogpu.Error.Invalid_argument"compute buffer graph is incomplete")slots ids in if List.exists Result.is_error bindings then List.find Result.is_error bindings|>Result.map(fun _->assert false)else let description=Ogpu.Compute_pass.Private.map_resource_ids native_id description in match Compute_pass.create device(Ogpu.Compute_pass.Private.of_description description)~pipeline~bindings:(List.map Result.get_ok bindings)with Error _ as e->e|Ok encoded->Queue.submit_compute_pass queue encoded)
        |Render submission->
          let cached_classic=
            List.find_opt(fun entry->not entry.classic_retired&&
              entry.classic_command==command&&
              same_resources entry.classic_resources resources&&
              same_pipelines entry.classic_pipelines pipelines)
              !classic_submissions in
          (match cached_classic with
          |Some entry->
              (match submit_native_render~presenting presentation queue
                  entry.classic_pass with
               |Error _ as failure->failure
               |Ok receipt->entry.classic_epoch<-receipt.epoch;Ok receipt)
          |None->
          let rec find_retained index=
            if index= !retained_replay_length then None else
            match Array.unsafe_get retained_replays index with
            |Some entry when not entry.replay_retired&&
                entry.replay_command==command&&
                same_pipelines entry.replay_pipelines pipelines&&
                Hashtbl.mem c.plan_owners entry.replay_key->Some entry
            |Some _->find_retained(index+1)
            |None->assert false in
          let cached_retained=find_retained 0 in
          (match cached_retained with
          |Some replay->
              let key=replay.replay_key and template=replay.replay_pass
              and attachment_ids=replay.replay_attachment_ids
              and attachment_tokens=replay.replay_attachment_tokens in
              let owner=Hashtbl.find c.plan_owners key in
              if not(dependencies_live owner.dependencies resources)then begin
                drop_retained_replays(fun entry->entry.replay_key<>key);
                error"Ogpu_metal.Backend.render"Ogpu.Error.Stale_handle
                  "retained render dependencies changed without invalidation"
              end else if same_attachment_tokens attachment_ids
                  attachment_tokens resources then
                (match submit_native_render~presenting presentation queue template with
                 |Error _ as e->e
                 |Ok receipt->
                     c.plan_hits<-Int64.succ c.plan_hits;
                     c.plan_executions<-Int64.succ c.plan_executions;
                     owner.last_epoch<-receipt.epoch;
                     replay.replay_epoch<-receipt.epoch;
                     Ok receipt)
              else
              let replace_cached=
                replay.replay_epoch<=Queue.completed_epoch queue in
              let descriptor=Ogpu.Render_pass.descriptor
                  (Ogpu.Render_pass.submission_pass submission) in
              let portable_pass=Ogpu.Render_pass.submission_pass submission in
              let attachments=resources|>List.filter_map(fun(_,tok)->
                match native_resource tok with Some(Texture x)->Some x|_->None)in
              (match native_render_descriptor descriptor with Error _ as e->e
              |Ok descriptor->match Ogpu.Render_pass.create
                  ~raster_state:(Ogpu.Render_pass.raster_state portable_pass)
                  ?stencil_state:(Ogpu.Render_pass.stencil_state portable_pass)
                  (Device.Private.handle device)descriptor with Error _ as e->e
              |Ok pass->match Render_pass.create_empty device pass~attachments with
              |Error _ as e->e
              |Ok encoded->
                  (* A pass that cannot replace an in-flight cached attachment
                     belongs to this queue submission only. Queue completion
                     destroys nonpersistent passes, so it cannot accumulate in
                     the retained plan owner outside its byte ledgers. *)
                  let encoded=Render_pass.replay_indirect encoded ~template
                    ~persistent:replace_cached in
                  if replace_cached then Render_pass.Private.retain_encoding encoded;
                  (match submit_native_render~presenting presentation queue encoded with
                  |Error _ as e->
                      (match Render_pass.Private.destroy encoded with
                       |Ok()->()
                       |Error cleanup_error->
                           record_ogpu_cleanup cleanup_error;
                           owner.passes<-(encoded,
                             resolve_attachment_tokens attachment_ids resources)::
                             owner.passes;
                           Option.iter(fun cache->ignore
                             (Metal.Retained_render_plan.invalidate cache key))
                             c.plan_cache);
                      e
                  |Ok receipt->
                      let tokens=resolve_attachment_tokens attachment_ids resources in
                      owner.last_epoch<-receipt.epoch;
                      if replace_cached then begin
                        if release_replay_pass~record_failure:true replay then begin
                          owner.passes<-(encoded,tokens)::owner.passes;
                          replay.replay_pass<-encoded;
                          replay.replay_attachment_tokens<-tokens;
                          replay.replay_epoch<-receipt.epoch
                        end else begin
                          owner.passes<-(encoded,tokens)::owner.passes;
                          replay.replay_retired<-true;
                          Option.iter(fun cache->ignore
                            (Metal.Retained_render_plan.invalidate cache key))
                            c.plan_cache
                        end
                      end;
                      c.plan_hits<-Int64.succ c.plan_hits;
                      c.plan_executions<-Int64.succ c.plan_executions;
                      Ok receipt))
          |None->
          let sampler_binding(s:Ogpu.Render_pass.sampler_binding)=match Hashtbl.find_opt c.sampler_cache s.sampler with Some sampler->Ok{Render_pass.stage=(match s.stage with Ogpu.Command.Vertex->Render_pass.Vertex|Fragment->Fragment|_->assert false);index=s.index;sampler}|None->(if Hashtbl.length c.sampler_cache>=64 then compact_sampler_cache();if Hashtbl.length c.sampler_cache>=64 then error"Ogpu_metal.Backend.sampler"Ogpu.Error.Invalid_state"all bounded sampler entries are referenced by in-flight retained plans"else match Sampler.create device s.sampler with Error _ as e->e|Ok sampler->Hashtbl.add c.sampler_cache s.sampler sampler;Ok{Render_pass.stage=(match s.stage with Ogpu.Command.Vertex->Render_pass.Vertex|Fragment->Fragment|_->assert false);index=s.index;sampler})in
          let pipeline_by_key key=pipelines|>List.find_map(fun id->match Hashtbl.find_opt c.pipeline_tokens id with Some p when Pipeline.key p=key->Some p|_->None)in
          let convert(portable_draw:Ogpu.Render_pass.draw)=
            match pipeline_by_key portable_draw.pipeline_key with None->error"Ogpu_metal.Backend.render"Ogpu.Error.Invalid_argument"render pipeline graph is incomplete"|Some pipeline->
            let buffer_binding(b:Ogpu.Render_pass.buffer_binding)=match find b.buffer_id with Some(Buffer buffer)->Ok{Render_pass.stage=(match b.stage with Ogpu.Command.Vertex->Render_pass.Vertex|Fragment->Fragment|_->assert false);index=b.index;buffer;offset=b.offset}|_->error"Ogpu_metal.Backend.render"Ogpu.Error.Invalid_argument"render buffer graph is incomplete"and texture_binding(t:Ogpu.Render_pass.texture_binding)=match find t.texture_id with Some(Texture texture)->Ok{Render_pass.stage=(match t.stage with Ogpu.Command.Vertex->Render_pass.Vertex|Fragment->Fragment|_->assert false);index=t.index;texture}|_->error"Ogpu_metal.Backend.render"Ogpu.Error.Invalid_argument"render texture graph is incomplete"in
            let buffers=List.map buffer_binding portable_draw.buffers and textures=List.map texture_binding portable_draw.textures and samplers=List.map sampler_binding portable_draw.samplers in
            if List.exists Result.is_error buffers||List.exists Result.is_error textures||List.exists Result.is_error samplers then error"Ogpu_metal.Backend.render"Ogpu.Error.Invalid_argument"render binding graph is invalid"else
            let index=match portable_draw.index with None->Ok None|Some(kind,id,offset,count)->match find id with Some(Buffer buffer)->Ok(Some((match kind with Ogpu.Render_pass.Uint16->Render_pass.Uint16|Uint32->Uint32),buffer,offset,Int64.of_int count))|_->error"Ogpu_metal.Backend.render"Ogpu.Error.Invalid_argument"render index graph is incomplete"in
            Result.map(fun index->{Render_pass.pipeline;buffers=List.map Result.get_ok buffers;textures=List.map Result.get_ok textures;samplers=List.map Result.get_ok samplers;primitive=(match portable_draw.primitive with Ogpu.Render_pass.Triangle_list->Render_pass.Triangle_list|Triangle_strip->Triangle_strip);vertex_start=portable_draw.vertex_start;vertex_count=portable_draw.vertex_count;index})index in
          let draws=List.map convert(Ogpu.Render_pass.submission_draws submission)in
          if List.exists Result.is_error draws then(List.find Result.is_error draws|>Result.map(fun _->assert false))else
          let descriptor=Ogpu.Render_pass.descriptor(Ogpu.Render_pass.submission_pass submission)and attachments=resources|>List.filter_map(fun(_,tok)->match native_resource tok with Some(Texture x)->Some x|_->None)in
          let portable_pass=Ogpu.Render_pass.submission_pass submission in
          let native_draws=List.map Result.get_ok draws in
          let argument_pipeline(draw:Render_pass.draw)=Option.is_some(Pipeline.Private.argument_function draw.pipeline)in
          let exact_argument_abi(draw:Render_pass.draw)=
            let vertex index=List.filter(fun(binding:Render_pass.buffer_binding)->binding.stage=Render_pass.Vertex&&binding.index=index)draw.buffers in
            match draw.index,draw.textures,draw.samplers,Pipeline.Private.argument_function draw.pipeline with
            |None,[{stage=Render_pass.Fragment;index=0;_}],[{stage=Render_pass.Fragment;index=1;_}],Some _->
                List.length(vertex 0)=1&&List.length(vertex 6)<=1&&
                List.length draw.buffers=1+List.length(vertex 6)
            |_->false in
          let maybe_indirect encoded=
            let eligible draw=retained_plans_enabled&&exact_argument_abi draw in
            match c.plan_cache with None when List.exists argument_pipeline native_draws->error"Ogpu_metal.Backend.render"Ogpu.Error.Unsupported"retained plan cache is unavailable"|None->Ok(encoded,None,None,`None,None)|Some _ when native_draws=[]||not(List.for_all eligible native_draws)->Ok(encoded,None,None,`None,None)|Some cache->
            let portable_draws=Ogpu.Render_pass.submission_draws submission in
            let pending_identity=ref None in
            let key,generation=
              match List.find_opt(fun entry->
                entry.identity_draws=portable_draws&&
                same_pipelines entry.identity_pipelines pipelines)
                !retained_identities with
              |Some entry->entry.identity_key,entry.identity_generation
              |None->
                  let pipeline_identities=List.map(fun(draw:Render_pass.draw)->
                    Pipeline.Private.native_identity draw.pipeline)native_draws in
                  let generation=Int64.logand(List.fold_left(fun hash(id,value)->Int64.logxor(Int64.mul(Int64.logxor(Int64.mul hash 1099511628211L)id)1099511628211L)value)1469598103934665603L pipeline_identities)Int64.max_int in
                  let identity=Marshal.to_string(portable_draws,pipeline_identities)[]in
                  let key=Printf.sprintf"render:%Ld:%s"queue_token(Digest.to_hex(Digest.string identity))in
                  let identity_bytes=retained_identity_bytes portable_draws
                      pipelines key in
                  pending_identity:=Some{identity_draws=portable_draws;
                    identity_pipelines=pipelines;identity_key=key;
                    identity_generation=generation;identity_bytes};
                  key,generation in
            let made=ref None in
            let icb_descriptor=Metal.Indirect_command_buffer.descriptor~inherit_buffers:false~inherit_pipeline_state:false~max_vertex_buffer_bind_count:7~max_fragment_buffer_bind_count:2~command_types:[Metal.Indirect_command_buffer.Indirect_draw]()in
            let retained_resource_ids=
              Ogpu.Render_pass.submission_draws submission
              |>List.concat_map(fun(draw:Ogpu.Render_pass.draw)->
                List.map(fun(binding:Ogpu.Render_pass.buffer_binding)->binding.buffer_id)draw.buffers@
                List.map(fun(binding:Ogpu.Render_pass.texture_binding)->binding.texture_id)draw.textures@
                Option.fold~none:[]~some:(fun(_,id,_,_)->[id])draw.index)
              |>List.sort_uniq Int64.compare in
            let dependencies=resources|>List.filter_map(fun(id,token)->
              if List.mem id retained_resource_ids then Some token else None)
              |>List.sort_uniq Int64.compare|>Array.of_list
            and pipeline_keys=List.map(fun(draw:Render_pass.draw)->Pipeline.key draw.pipeline)native_draws|>List.sort_uniq String.compare in
            let unique id values=List.fold_left(fun kept value->
              if List.exists(fun old->id old=id value)kept then kept
              else value::kept)[]values|>List.rev in
            let vertex_buffers=native_draws|>List.concat_map
                (fun(draw:Render_pass.draw)->List.map
                  (fun(binding:Render_pass.buffer_binding)->binding.buffer)
                  draw.buffers)
              |>unique Buffer.id|>List.map Buffer.Private.metal
            and textures=native_draws|>List.map
                (fun(draw:Render_pass.draw)->(List.hd draw.textures).texture)
              |>unique Texture.id|>List.map Texture.Private.metal in
            let command_count=List.length native_draws in
            let prepared_encoders=ref None in
            let destroy_prepared_encoders()=
              Option.iter(List.iter(fun(_,encoder,_)->
                ignore(Metal.Shader_argument_encoder.destroy encoder)))
                !prepared_encoders;
              prepared_encoders:=None in
            let prepare_argument_encoders()=
              match !prepared_encoders with
              |Some prepared->Ok prepared
              |None->
                  let rec prepare reversed=function
                    |[]->
                        let prepared=List.rev reversed in
                        prepared_encoders:=Some prepared;Ok prepared
                    |(draw:Render_pass.draw)::rest->
                        let function_=Option.get
                            (Pipeline.Private.argument_function draw.pipeline)in
                        match Metal.Function.argument_encoder function_
                            ~buffer_index:1L with
                        |Error _ as failure->
                            List.iter(fun(_,encoder,_)->ignore
                              (Metal.Shader_argument_encoder.destroy encoder))
                              reversed;
                            failure
                        |Ok encoder->
                            let length=
                              Metal.Shader_argument_encoder.encoded_length
                                encoder in
                            prepare((draw,encoder,length)::reversed)rest in
                  prepare[]native_draws in
            let prospective_owner_bytes prepared=
              plan_owner_bytes~key~dependencies~pipeline_keys~command_count
                ~encoder_count:(List.length prepared)
                ~sampler_count:command_count
                ~argument_buffer_lengths:(List.map(fun(_,_,length)->length)
                  prepared)
                ~resource_set_count:3
                ~resource_reference_count:(List.length vertex_buffers+
                  command_count+List.length textures)in
            let expected_hit=
              match Hashtbl.find_opt c.plan_owners key with
              |Some owner->owner.generation=generation&&
                  owner.command_count=command_count
              |None->false in
            let build icb =
              match prepare_argument_encoders()with
              |Error _ as failure->failure
              |Ok prepared->
              let prospective_bytes=prospective_owner_bytes prepared in
              assert(prospective_bytes<=c.owner_byte_capacity);
              let commands=ref[] and buffers=ref[] and samplers=ref[]
              and resource_sets=ref[] in
              let fail e=List.iter(fun x->ignore(Metal.Indirect_command_buffer.Render_command.destroy x))!commands;let count=List.length!commands in if count>0 then ignore(Metal.Indirect_command_buffer.reset icb~location:0~length:count);destroy_prepared_encoders();List.iter(fun x->ignore(Metal.Render_encoder.destroy_prepared_resources x))!resource_sets;List.iter(fun x->ignore(Metal.Buffer.destroy x))!buffers;List.iter(fun x->ignore(Metal.Sampler.destroy x))!samplers;Error e in
              let configure command (draw:Render_pass.draw) argument_buffer =
                let pipeline=match Pipeline.Private.native draw.pipeline with Render pipeline->pipeline|Compute _->assert false in
                match Metal.Indirect_command_buffer.Render_command.set_pipeline command pipeline with Error _ as e->e|Ok()->
                let rec bind_vertices=function []->Ok()|(binding:Render_pass.buffer_binding)::rest->match Metal.Indirect_command_buffer.Render_command.set_vertex_buffer command~index:binding.index~offset:binding.offset(Buffer.Private.metal binding.buffer)with Error _ as e->e|Ok()->bind_vertices rest in
                match bind_vertices draw.buffers with Error _ as e->e|Ok()->
                match Metal.Indirect_command_buffer.Render_command.set_fragment_buffer command~index:1~offset:0L argument_buffer with Error _ as e->e|Ok()->
                Metal.Indirect_command_buffer.Render_command.draw_primitives command~primitive:(match draw.primitive with Triangle_list->Metal.Triangle|Triangle_strip->Metal.Triangle_strip)~vertex_start:draw.vertex_start~vertex_count:draw.vertex_count()
              in
              let rec loop i=function
              |[]->let buffers=List.rev!buffers in let prepare resources=match Metal.Render_encoder.prepare_resources(Device.Private.metal device)resources with Error _ as e->e|Ok prepared->resource_sets:=prepared::!resource_sets;Ok prepared in(match prepare(List.map(fun buffer->Metal.Render_encoder.Buffer_resource buffer)vertex_buffers)with Error e->fail e|Ok vertex_resources->match prepare(List.map(fun buffer->Metal.Render_encoder.Buffer_resource buffer)buffers)with Error e->fail e|Ok fragment_resources->match prepare(List.map(fun texture->Metal.Render_encoder.Texture_resource texture)textures)with Error e->fail e|Ok texture_resources->let encoders=List.map(fun(_,encoder,_)->encoder)prepared and argument_buffer_lengths=List.map Metal.Buffer.length buffers in assert(argument_buffer_lengths=List.map(fun(_,_,length)->length)prepared);let resource_sets=List.rev!resource_sets in assert(List.length resource_sets=3);let owner_bytes=plan_owner_bytes~key~dependencies~pipeline_keys~command_count~encoder_count:(List.length encoders)~sampler_count:(List.length!samplers)~argument_buffer_lengths~resource_set_count:(List.length resource_sets)~resource_reference_count:(List.length vertex_buffers+List.length buffers+List.length textures)in assert(owner_bytes=prospective_bytes);let owner={queue_token;generation;command_count;last_epoch=0L;dependencies;pipeline_keys;commands=List.rev!commands;samplers=List.rev!samplers;encoders;buffers;resource_sets;vertex_resources;fragment_resources;texture_resources;owner_bytes;passes=[]}in prepared_encoders:=None;made:=Some owner;Ok())
                |((draw:Render_pass.draw),encoder,length)::rest->
                  match Metal.Buffer.create~device:(Device.Private.metal device)~length~storage:Metal.Buffer.Shared()with Error e->ignore(Metal.Shader_argument_encoder.destroy encoder);fail e|Ok argument_buffer->
                  buffers:=argument_buffer::!buffers;
                  match Metal.Shader_argument_encoder.set_argument_buffer encoder argument_buffer~offset:0L()with Error e->fail e|Ok()->
                  let texture=(List.hd draw.textures).Render_pass.texture and classic_sampler=(List.hd draw.samplers).Render_pass.sampler in
                  match Metal.Shader_argument_encoder.set encoder~index:0L(Metal.Shader_argument_encoder.Texture(Texture.Private.metal texture))with Error e->fail e|Ok()->
                  match Sampler.Private.create_argument device(Sampler.Private.descriptor classic_sampler)with Error e->fail e|Ok sampler->samplers:=sampler::!samplers;
                  match Metal.Shader_argument_encoder.set encoder~index:1L(Metal.Shader_argument_encoder.Sampler sampler)with Error e->fail e|Ok()->
                  match Metal.Indirect_command_buffer.Render_command.at icb i with Error e->fail e|Ok command->
                  commands:=command::!commands;let configured=configure command draw argument_buffer in
                  match configured with Error e->fail e|Ok()->loop(i+1)rest
              in loop 0 prepared
            in
            let prepared=
              if expected_hit then Ok None else
              match prepare_argument_encoders()with
              |Error error->
                  Error(Adapter.error
                    ~operation:"Ogpu_metal.Backend.render_plan_owner"error)
              |Ok prepared->
                  let bytes=prospective_owner_bytes prepared in
                  if bytes>c.owner_byte_capacity then begin
                    destroy_prepared_encoders();
                    error"Ogpu_metal.Backend.render_plan_owner"
                      Ogpu.Error.Invalid_argument
                      "retained plan owner exceeds its byte capacity"
                  end else Ok(Some prepared)in
            match prepared with
            |Error _ as failure->failure
            |Ok _->
            (match Metal.Retained_render_plan.prepare cache~key
                ~generation~command_count~descriptor:icb_descriptor~build with
             |Error error->
                 destroy_prepared_encoders();
                 Option.iter(fun owner->record_destroy_cleanup(destroy_owner owner))
                   !made;
                 made:=None;
                 Error(Adapter.error~operation:"Ogpu_metal.Backend.render_plan"
                   error)
             |Ok(Metal.Retained_render_plan.Hit icb)->
                 destroy_prepared_encoders();
                 let owner=Hashtbl.find c.plan_owners key in
                 Ok(Render_pass.with_indirect encoded icb
                   ~vertex_resources:owner.vertex_resources
                   ~fragment_resources:owner.fragment_resources
                   ~texture_resources:owner.texture_resources,
                   Some key,Some icb,`Hit owner,!pending_identity)
             |Ok(Metal.Retained_render_plan.Candidate candidate)->
                 let owner=Option.get!made in
                 let icb=Metal.Retained_render_plan.candidate_buffer candidate in
                 Ok(Render_pass.with_indirect encoded icb
                   ~vertex_resources:owner.vertex_resources
                   ~fragment_resources:owner.fragment_resources
                   ~texture_resources:owner.texture_resources,
                   Some key,Some icb,`Candidate(cache,candidate,owner),
                   !pending_identity))in
          let retire_candidate ~epoch candidate owner=
            let icb=Metal.Retained_render_plan.candidate_buffer candidate in
            let retired={queue_token;epoch;icb;candidate=Some candidate;
              icb_released=false;owner=Some owner;
              retired_bytes=owner_retired_bytes icb owner}in
            if epoch=0L||epoch<=Queue.completed_epoch queue then begin
              if not(attempt_retired retired)then account_retired retired
            end else account_retired retired in
          let make_room_for_owner cache key bytes=
            if bytes>c.owner_byte_capacity then false else
            let available=Int64.sub c.owner_byte_capacity bytes in
            let resident_without_key()=
              Int64.sub c.owner_retained_bytes
                (Option.fold~none:0L~some:(fun(owner:plan_owner)->
                  owner.owner_bytes)(Hashtbl.find_opt c.plan_owners key))in
            let rec make_room()=
              if resident_without_key()<=available then true else
              match List.find_opt(fun oldest->oldest<>key&&
                  Hashtbl.mem c.plan_owners oldest)c.plan_owner_order with
              |None->
                  record_ogpu_cleanup(Ogpu.Error.make
                    "Ogpu_metal.Backend.render_plan_owner"
                    Ogpu.Error.Invalid_state
                    "retained plan owner order cannot satisfy its byte capacity");
                  false
              |Some oldest->
                  (match Metal.Retained_render_plan.invalidate cache oldest with
                   |Ok()->make_room()
                   |Error error->record_cleanup(Some error);false)in
            make_room()in
          let has_argument=List.exists argument_pipeline native_draws in
          let rendered=if has_argument&&not(List.for_all exact_argument_abi native_draws)then error"Ogpu_metal.Backend.render"Ogpu.Error.Invalid_argument"argument-buffer render batch has mixed or noncanonical bindings"else if has_argument&&not retained_plans_enabled then error"Ogpu_metal.Backend.render"Ogpu.Error.Unsupported"argument-buffer rendering requires retained ICB support"else match native_render_descriptor descriptor with Error _ as e->e|Ok descriptor->match Ogpu.Render_pass.create~raster_state:(Ogpu.Render_pass.raster_state portable_pass)?stencil_state:(Ogpu.Render_pass.stencil_state portable_pass)(Device.Private.handle device)descriptor with Error _ as e->e|Ok pass->match (if native_draws=[]then Render_pass.create_empty device pass~attachments else Render_pass.create_batch device pass~attachments native_draws)with Error _ as e->e|Ok encoded->match maybe_indirect encoded with Error _ as e->ignore(Render_pass.Private.destroy encoded);e|Ok(encoded,key,icb,plan_state,pending_identity)->let classic_bytes=classic_entry_bytes command encoded resources pipelines in let retain_classic=Option.is_none key&&classic_bytes<=c.classic_byte_capacity&&List.length!classic_submissions<classic_submission_capacity&& !classic_retained_bytes<=Int64.sub c.classic_byte_capacity classic_bytes in let pending_classic,pending_replay,encoding_persistent=match key,icb with
            |None,_ when retain_classic->
                Render_pass.Private.retain_encoding encoded;
                Some{classic_command=command;classic_resources=resources;
                  classic_pipelines=pipelines;classic_pass=encoded;classic_bytes;
                  classic_epoch=0L;classic_retired=false},None,true
            |None,_->None,None,false
            |Some key,Some _->
                let owner=match plan_state with
                  |`Hit owner|`Candidate(_,_,owner)->owner
                  |`None->assert false in
                let ids=attachment_ids submission in
                let tokens=resolve_attachment_tokens ids resources in
                let replay_bytes=retained_replay_bytes command pipelines key
                    encoded ids tokens in
                let entry={replay_command=command;replay_pipelines=pipelines;
                  replay_key=key;replay_pass=encoded;replay_attachment_ids=ids;
                  replay_attachment_tokens=tokens;replay_bytes;replay_epoch=0L;
                  replay_retired=false}in
                if replay_admission_preflight replay_bytes then begin
                  Render_pass.Private.retain_encoding encoded;
                  None,Some(entry,owner,tokens),true
                end else None,None,false
            |Some _,None->assert false in
            match submit_native_render~presenting presentation queue encoded with
            |Error _ as error->
                if encoding_persistent then
                  (match Render_pass.Private.destroy encoded with
                   |Ok()->()
                   |Error cleanup_error->
                       record_ogpu_cleanup cleanup_error;
                       Option.iter(fun entry->
                         entry.classic_retired<-true;
                         classic_submissions:=entry::!classic_submissions;
                         classic_retained_bytes:=Int64.add
                           !classic_retained_bytes entry.classic_bytes)
                         pending_classic;
                       Option.iter(fun(entry,owner,tokens)->
                         match plan_state with
                         |`Candidate _->
                             owner.passes<-(entry.replay_pass,tokens)::owner.passes
                         |`Hit _->
                             owner.passes<-(entry.replay_pass,tokens)::owner.passes;
                             Option.iter(fun cache->match
                               Metal.Retained_render_plan.invalidate cache
                                 entry.replay_key with
                               |Ok()->()
                               |Error error->record_cleanup(Some error))c.plan_cache
                         |`None->assert false)pending_replay)
                else ignore(Render_pass.Private.destroy encoded);
                (match plan_state with
                 |`None|`Hit _->()
                 |`Candidate(_,candidate,owner)->
                     retire_candidate~epoch:0L candidate owner);
                error
            |Ok receipt->
              let plan_active=match plan_state with
                |`None->true
                |`Hit owner->
                    owner.last_epoch<-receipt.epoch;
                    c.plan_hits<-Int64.succ c.plan_hits;
                    c.plan_executions<-Int64.succ c.plan_executions;
                    true
                |`Candidate(cache,candidate,owner)->
                    owner.last_epoch<-receipt.epoch;
                    if not(make_room_for_owner cache
                        (Option.get key)owner.owner_bytes)then begin
                      Option.iter(fun(entry,_,tokens)->
                        owner.passes<-(entry.replay_pass,tokens)::owner.passes)
                        pending_replay;
                      retire_candidate~epoch:receipt.epoch candidate owner;
                      false
                    end else
                      match Metal.Retained_render_plan.admit cache candidate with
                      |Error cleanup_error->
                          record_cleanup(Some cleanup_error);
                          Option.iter(fun(entry,_,tokens)->
                            owner.passes<-(entry.replay_pass,tokens)::owner.passes)
                            pending_replay;
                          retire_candidate~epoch:receipt.epoch candidate owner;
                          false
                      |Ok()->
                          let key=Option.get key in
                          assert(not(Hashtbl.mem c.plan_owners key));
                          Hashtbl.add c.plan_owners key owner;
                          c.plan_owner_order<-c.plan_owner_order@[key];
                          c.owner_retained_bytes<-Int64.add
                            c.owner_retained_bytes owner.owner_bytes;
                          c.plan_builds<-Int64.succ c.plan_builds;
                          c.plan_misses<-Int64.succ c.plan_misses;
                          c.plan_executions<-Int64.succ c.plan_executions;
                          true in
              Option.iter(fun entry->
                assert(make_room_for_classic entry.classic_bytes);
                entry.classic_epoch<-receipt.epoch;
                classic_submissions:=entry::!classic_submissions;
                classic_retained_bytes:=Int64.add !classic_retained_bytes
                  entry.classic_bytes)pending_classic;
              if plan_active then begin
                Option.iter(fun(entry,owner,tokens)->
                  entry.replay_epoch<-receipt.epoch;
                  if retain_replay entry then
                    owner.passes<-(entry.replay_pass,tokens)::owner.passes
                  else begin
                    match Render_pass.Private.destroy entry.replay_pass with
                    |Ok()->()
                    |Error cleanup_error->
                        if receipt.epoch<=Queue.completed_epoch queue then
                          record_ogpu_cleanup cleanup_error;
                        owner.passes<-(entry.replay_pass,tokens)::owner.passes;
                        Option.iter(fun cache->match
                          Metal.Retained_render_plan.invalidate cache
                            entry.replay_key with
                          |Ok()->()|Error error->record_cleanup(Some error))
                          c.plan_cache
                  end)pending_replay;
                if Option.is_some pending_replay then
                  Option.iter(fun entry->ignore(retain_identity entry))
                    pending_identity
              end;
              Ok receipt in rendered)) in
        Result.map(fun(receipt:Queue.receipt)->{Ogpu.Backend.epoch=receipt.epoch})result in
      let submit command ~resources ~pipelines=submit_with~presenting:false
        unused_presentation command~resources~pipelines in
      let submit_combined presentation command ~resources ~pipelines=
        submit_with~presenting:true presentation command~resources~pipelines in
      let active={queue;submit_combined;presentations=Array.init
        pending_presentation_capacity(fun _->Surface.Private.create_pending_presentation())}in
      Hashtbl.add c.active_queues queue_token active;
      let commit_completed_epoch epoch completion=
        Hashtbl.replace c.completed_epochs queue_token epoch;
        drain_retired(fun(retired:retired)->
          retired.queue_token=queue_token&&retired.epoch<=epoch);
        Option.iter(fun cache->cache.retry_cleanup())
          (Hashtbl.find_opt c.classic_invalidators queue_token);
        let cleanup=take_cleanup_error()in
        match completion,cleanup with
        |Error _ as e,_->e
        |Ok(),Some error->Error error
        |Ok(),None->Ok()in
      let complete_through epoch=
        let waited=Queue.wait_through queue epoch in
        let completed=Queue.completed_epoch queue in
        Surface.Private.complete_presentations_through active.presentations completed;
        commit_completed_epoch epoch waited in
      let submit_sync command ~resources ~pipelines=
        Queue.Private.arm_scoped_render queue;
        match submit command~resources~pipelines with
        |Error _ as e->ignore(Queue.Private.take_scoped_completion queue);e
        |Ok receipt->
            let completion=match Queue.Private.take_scoped_completion queue with
              |Some result->result
              |None->complete_through receipt.epoch in
            let completion=if Queue.completed_epoch queue>=receipt.epoch then
                commit_completed_epoch receipt.epoch completion else completion in
            Ok{Ogpu.Backend.receipt;completion}in
      let destroy_queue()=
        if not(Array.for_all Surface.Private.pending_presentation_available
          active.presentations)then
          error"Ogpu_metal.Backend.destroy_queue"Ogpu.Error.Invalid_state
            "queue has presentations in flight"
        else match Queue.destroy queue with Error _ as e->e|Ok()->
          Hashtbl.replace c.completed_epochs queue_token
            (Queue.completed_epoch queue);
          Option.iter(fun cache->
            let keys=Hashtbl.fold(fun key(owner:plan_owner) found->
              if owner.queue_token=queue_token then key::found else found)
              c.plan_owners[]in
            List.iter(fun key->match Metal.Retained_render_plan.invalidate
                cache key with
              |Ok()->()|Error error->record_cleanup(Some error))keys)c.plan_cache;
          filter_classics(fun _->false);
          clear_retained_metadata();
          retry_cleanup();
          drain_retired(fun(retired:retired)->
            retired.queue_token=queue_token);
          Surface.Private.clear_pending_presentations active.presentations;
          if cleanup_empty()then
            Hashtbl.remove c.classic_invalidators queue_token;
          Hashtbl.remove c.active_queues queue_token;
          Hashtbl.remove c.completed_epochs queue_token;
          (match take_cleanup_error()with None->Ok()|Some error->Error error)in
      Ok{Ogpu.Backend.queue_token;submit;submit_sync;complete_through;destroy_queue}in
    let create_surface configuration=
      match c.layer with
      |None->error"Ogpu_metal.Backend.create_surface"Ogpu.Error.Unsupported"adapter was created without a typed Metal layer"
      |Some layer->match Surface.create device~layer configuration with Error _ as e->e|Ok surface->
        let surface_token=token c and frames=Hashtbl.create 4 in
        let acquire_with acquire=match acquire surface with Error _ as e->e|Ok Surface.Timeout->Ok`Timeout|Ok Occluded->Ok`Occluded|Ok Device_lost->Ok`Device_lost|Ok(Acquired frame)->let frame_token=Surface.frame_id frame in Hashtbl.add frames frame_token frame;Ok(`Acquired{Ogpu.Backend.frame_token})in
        let acquire()=acquire_with Surface.acquire
        and acquire_sync()=acquire_with Surface.Private.acquire_scoped in
        let take f frame=match Hashtbl.find_opt frames frame.Ogpu.Backend.frame_token with None->error"Ogpu_metal.Backend.surface"Ogpu.Error.Invalid_state"frame token is stale"|Some native->match f surface native with Error _ as e->e|Ok()->Hashtbl.remove frames frame.frame_token;Ok()in
        let take_present queue source frame=match Hashtbl.find_opt frames frame.Ogpu.Backend.frame_token with None->error"Ogpu_metal.Backend.surface"Ogpu.Error.Invalid_state"frame token is stale"|Some native->match Surface.present_from surface native~queue~source with Error _ as e->e|Ok()->Hashtbl.remove frames frame.frame_token;Ok()in
        let present~queue~source frame=match Hashtbl.find_opt c.active_queues queue with None->error"Ogpu_metal.Backend.present"Ogpu.Error.Stale_handle"presentation queue token is stale"|Some active->match native_resource source with Some(Texture texture)->take_present active.queue texture frame|Some(Buffer _)->error"Ogpu_metal.Backend.present"Ogpu.Error.Invalid_argument"presentation source token is not a texture"|None->error"Ogpu_metal.Backend.present"Ogpu.Error.Stale_handle"presentation source token is stale"in
        let submit_present_common ~scoped ~queue~source command~resources~pipelines frame=
          match Hashtbl.find_opt c.active_queues queue with
          |None->error"Ogpu_metal.Backend.submit_present"Ogpu.Error.Stale_handle"presentation queue token is stale"
          |Some active->match native_resource source with
            |Some(Buffer _)->error"Ogpu_metal.Backend.submit_present"Ogpu.Error.Invalid_argument"presentation source token is not a texture"
            |None->error"Ogpu_metal.Backend.submit_present"Ogpu.Error.Stale_handle"presentation source token is stale"
            |Some(Texture texture)->match Hashtbl.find_opt frames frame.Ogpu.Backend.frame_token with
              |None->error"Ogpu_metal.Backend.submit_present"Ogpu.Error.Invalid_state"frame token is stale"
              |Some native->match Array.find_opt
                  Surface.Private.pending_presentation_available active.presentations with
                |None->error"Ogpu_metal.Backend.submit_present"Ogpu.Error.Invalid_state
                    "queue has the maximum presentations in flight"
                |Some pending->match Surface.Private.prepare_present pending surface native
                    ~source:texture with
                  |Error _ as e->e
                  |Ok()->
                    if scoped then Queue.Private.arm_scoped_render
                      ~on_committed:(fun epoch->
                        Surface.Private.commit_present_scoped pending~epoch;
                        Hashtbl.remove frames frame.frame_token)active.queue;
                    match active.submit_combined
                      ((if scoped then Surface.Private.presentation_encoder_scoped
                        else Surface.Private.presentation_encoder)pending)command
                      ~resources~pipelines with
                    |Error _ as e->Surface.Private.rollback_present pending;e
                    |Ok receipt->
                        if not scoped then begin
                          Surface.Private.commit_present pending~epoch:receipt.epoch;
                          Hashtbl.remove frames frame.frame_token
                        end;
                        Ok receipt in
        let submit_present=submit_present_common~scoped:false in
        let submit_present_sync~queue~source command~resources~pipelines frame=
          let active=Hashtbl.find_opt c.active_queues queue in
          match submit_present_common~scoped:true~queue~source command~resources
              ~pipelines frame with
          |Error _ as e->Option.iter(fun active->ignore
                (Queue.Private.take_scoped_completion active.queue))active;e
          |Ok receipt->
              let completion=match active with
                |None->error"Ogpu_metal.Backend.submit_present_sync"
                    Ogpu.Error.Stale_handle"presentation queue token is stale"
                |Some active->
                    (match Queue.Private.take_scoped_completion active.queue with
                     |Some result->result
                     |None->Queue.wait_through active.queue receipt.epoch) in
              Option.iter(fun active->Surface.Private.complete_presentations_through
                  active.presentations(Queue.completed_epoch active.queue))active;
              Hashtbl.replace c.completed_epochs queue receipt.epoch;
              drain_retired(fun(retired:retired)->
                retired.queue_token=queue&&retired.epoch<=receipt.epoch);
              Option.iter(fun cache->cache.retry_cleanup())
                (Hashtbl.find_opt c.classic_invalidators queue);
              let completion=match completion,take_cleanup_error()with
                |Error _ as failure,_->failure
                |Ok(),Some error->Error error
                |Ok(),None->Ok()in
              Ok{Ogpu.Backend.receipt;completion}in
        Ok{Ogpu.Backend.surface_token;configure=(fun x->Surface.configure surface x);acquire;acquire_sync;present;submit_present;submit_present_sync;discard=take Surface.discard;destroy_surface=(fun()->if Hashtbl.length frames<>0 then error"Ogpu_metal.Backend.destroy_surface"Ogpu.Error.Invalid_state"surface has outstanding frames"else if Surface.in_flight_presentations surface<>0 then error"Ogpu_metal.Backend.destroy_surface"Ogpu.Error.Invalid_state"surface has presentations in flight"else(Surface.destroy surface;Ok()))}in
    let destroy_device()=
      if Hashtbl.length c.active_queues<>0 then
        error"Ogpu_metal.Backend.destroy_device"Ogpu.Error.Invalid_state
          "device has active queues"
      else begin
        (match c.plan_cache with
         |None->()
         |Some cache->
             (match Metal.Retained_render_plan.destroy cache with
              |Ok()->c.plan_cache<-None
              |Error error->record_cleanup(Some error)));
        let empty_invalidators=Hashtbl.fold(fun queue cache empty->
          cache.clear_classics();cache.clear_retained_metadata();
          cache.retry_cleanup();
          if cache.cleanup_empty()then queue::empty else empty)
          c.classic_invalidators[]in
        List.iter(Hashtbl.remove c.classic_invalidators)empty_invalidators;
        drain_retired(fun _->true);
        let remaining=Hashtbl.fold(fun key _ keys->key::keys)c.plan_owners[]in
        List.iter(fun key->match Hashtbl.find_opt c.plan_owners key with
          |None->()
          |Some owner->
              (match destroy_owner owner with
               |None->ignore(remove_plan_owner c key)
               |Some failure->record_destroy_cleanup(Some failure)))remaining;
        Hashtbl.filter_map_inplace(fun _ sampler->
          match Sampler.destroy sampler with
          |Ok()->None
          |Error error->record_ogpu_cleanup error;Some sampler)c.sampler_cache;
        let destroyed=if c.device_live then Device.destroy device else Ok()in
        (match destroyed with Ok()->c.device_live<-false|Error _->());
        let cleanup=take_cleanup_error()in
        match destroyed,cleanup with
        |Error _ as failure,_->failure
        |Ok(),Some error->Error error
        |Ok(),None->Ok()
      end in
    Ok{Ogpu.Backend.device_token;device_handle=Device.Private.handle device;capabilities=Device.capabilities device;create_buffer;create_texture;create_depth_texture;create_stencil_texture;create_pipeline;create_queue;create_surface;destroy_device}in
  {Ogpu.Backend.create_device},c
