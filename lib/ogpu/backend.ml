type token=int64
type command_view=
  |Transfer of Transfer_pass.description array
  |Compute of Compute_pass.description
  |Render of Render_pass.submission
type command={command_identity:int64;command_view:command_view;command_bytes:int64}
type receipt={epoch:int64}
type synchronous_submission={receipt:receipt;completion:(unit,Error.t)result}
type submission_cache_stats=
  { entries:int
  ; retained_bytes:int64
  ; entry_capacity:int
  ; byte_capacity:int64 }
type driver_resource={token:token;write:int64->bytes->(unit,Error.t)result;read:int64->int->(bytes,Error.t)result;read_into:int64->bytes->int->int->(unit,Error.t)result;destroy:unit->(unit,Error.t)result}
type driver_pipeline={pipeline_token:token;destroy_pipeline:unit->(unit,Error.t)result}
type driver_frame={frame_token:token}
type driver_surface={surface_token:token;configure:Surface.configuration->(unit,Error.t)result;acquire:unit->([`Acquired of driver_frame|`Timeout|`Occluded|`Device_lost],Error.t)result;acquire_sync:unit->([`Acquired of driver_frame|`Timeout|`Occluded|`Device_lost],Error.t)result;present:queue:token->source:token->driver_frame->(unit,Error.t)result;submit_present:queue:token->source:token->command->resources:(int64*token)list->pipelines:token list->driver_frame->(receipt,Error.t)result;submit_present_sync:queue:token->source:token->command->resources:(int64*token)list->pipelines:token list->driver_frame->(synchronous_submission,Error.t)result;discard:driver_frame->(unit,Error.t)result;destroy_surface:unit->(unit,Error.t)result}
type driver_queue={queue_token:token;submit:command->resources:(int64*token)list->pipelines:token list->(receipt,Error.t)result;submit_sync:command->resources:(int64*token)list->pipelines:token list->(synchronous_submission,Error.t)result;complete_through:int64->(unit,Error.t)result;destroy_queue:unit->(unit,Error.t)result}
type driver_device={device_token:token;device_handle:Handle.device;capabilities:Capabilities.t;create_buffer:Types.buffer_descriptor->(driver_resource,Error.t)result;create_texture:Types.texture_descriptor->(driver_resource,Error.t)result;create_depth_texture:Types.texture_descriptor->(driver_resource,Error.t)result;create_stencil_texture:Types.texture_descriptor->(driver_resource,Error.t)result;create_pipeline:Pipeline.t->(driver_pipeline,Error.t)result;create_queue:unit->(driver_queue,Error.t)result;create_surface:Surface.configuration->(driver_surface,Error.t)result;destroy_device:unit->(unit,Error.t)result}
type driver={create_device:unit->(driver_device,Error.t)result}
type device={raw:driver_device;handle:Handle.device;mutable children:int;mutable dead:bool;
  mutable queues:queue list}
and resource={raw:driver_resource;handle:unit Handle.t;device:device;mutable dead:bool;
  mutable last_submitted_queue:queue option}
and buffer={resource:resource;buffer_descriptor:Types.buffer_descriptor}
and texture={resource:resource;texture_descriptor:Types.texture_descriptor}
and pipeline={pipeline_driver:driver_pipeline;device:device;identity:int64;
  mutable dead:bool}
and submitted_resource=[`Buffer of buffer|`Texture of texture]
and cached_resource_key=Buffer_key of int64|Texture_key of int64
and submission_cache_entry=
  { cached_command_identity:int64
  ; mutable cached_resource_keys:cached_resource_key list
  ; mutable cached_tokens:(int64*token)list
  ; mutable cached_pipeline_keys:int64 list
  ; mutable cached_pipeline_tokens:token list
  ; mutable cached_bytes:int64 }
and queue={raw:driver_queue;device:device;mutable dead:bool;
  submission_cache:submission_cache_entry option array;
  mutable submission_cache_next:int;
  mutable submission_cache_retained_bytes:int64;
  submission_cache_byte_capacity:int64}
type surface={raw:driver_surface;device:device;mutable dead:bool;mutable frames:int;
  mutable configuration:Surface.configuration}
type frame={raw:driver_frame;surface:surface;mutable consumed:bool}
let error op kind text=Error(Error.make op kind text)
let next_private_identity=Atomic.make 1L
let fresh_private_identity ()=
  let rec reserve ()=
    let current=Atomic.get next_private_identity in
    if Int64.equal current Int64.max_int then
      invalid_arg"Ogpu.Backend private identity capacity exhausted"
    else if Atomic.compare_and_set next_private_identity current(Int64.succ current)
    then current
    else reserve()
  in
  reserve()
let create_device driver=match driver.create_device()with Error _ as e->e|Ok raw->match Capabilities.validate raw.capabilities with Error _ as e->e|Ok()->Ok{raw;handle=raw.device_handle;children=0;dead=false;queues=[]}
let capabilities (value:device)=value.raw.capabilities
let device_handle (value:device)=value.handle
let live op (device:device)=if device.dead then error op Error.Stale_handle"device is destroyed"else Ok()
let make_resource (device:device) raw={raw;handle=Handle.create~device:device.handle;
  device;dead=false;last_submitted_queue=None}
let create_buffer device descriptor=match live"Backend.create_buffer"device with Error _ as e->e|Ok()->match Types.validate_buffer device.raw.capabilities descriptor with Error _ as e->e|Ok()->match device.raw.create_buffer descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;buffer_descriptor=descriptor}
let create_texture device descriptor=match live"Backend.create_texture"device with Error _ as e->e|Ok()->match Types.validate_texture device.raw.capabilities descriptor with Error _ as e->e|Ok()->match device.raw.create_texture descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;texture_descriptor=descriptor}
let create_depth_texture device descriptor=match live"Backend.create_depth_texture"device with Error _ as e->e|Ok()->match Types.validate_texture device.raw.capabilities descriptor with Error _ as e->e|Ok() when not(List.mem Types.Render_attachment descriptor.usage)||List.exists(fun usage->usage<>Types.Render_attachment)descriptor.usage->error"Backend.create_depth_texture"Error.Invalid_argument"depth textures are render-attachment only"|Ok()->match device.raw.create_depth_texture descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;texture_descriptor=descriptor}
let create_stencil_texture device descriptor=match live"Backend.create_stencil_texture"device with Error _ as e->e|Ok()->match Types.validate_texture device.raw.capabilities descriptor with Error _ as e->e|Ok() when not(List.mem Types.Render_attachment descriptor.usage)||List.exists(fun usage->usage<>Types.Render_attachment)descriptor.usage->error"Backend.create_stencil_texture"Error.Invalid_argument"stencil textures are render-attachment only"|Ok()->match device.raw.create_stencil_texture descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;texture_descriptor=descriptor}
let adopt_pipeline device portable=match live"Backend.adopt_pipeline"device with Error _ as e->e|Ok()->let identity=fresh_private_identity()in match device.raw.create_pipeline portable with Error _ as e->e|Ok pipeline_driver->device.children<-device.children+1;Ok{pipeline_driver;device;identity;dead=false}
let submission_cache_capacity=256
let default_submission_cache_byte_capacity=67_108_864L
let create_queue
    ?(submission_cache_byte_capacity=default_submission_cache_byte_capacity) device=
  let operation="Backend.create_queue"in
  if submission_cache_byte_capacity<=0L then
    error operation Error.Invalid_argument
      "submission cache byte capacity must be positive"
  else match live operation device with Error _ as e->e|Ok()->
    match device.raw.create_queue()with Error _ as e->e|Ok raw->
      device.children<-device.children+1;
      let queue={raw;device;dead=false;
        submission_cache=Array.make submission_cache_capacity None;
        submission_cache_next=0;submission_cache_retained_bytes=0L;
        submission_cache_byte_capacity}in
      device.queues<-queue::device.queues;
      Ok queue
let create_surface device configuration=match live"Backend.create_surface"device with Error _ as e->e|Ok()->match Surface.create device.handle configuration with Error _ as e->e|Ok portable->Surface.destroy portable;(match device.raw.create_surface configuration with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{raw;device;dead=false;frames=0;configuration})
let transfer_buffer (value:buffer)=Transfer_pass.buffer~device:value.resource.device.handle value.resource.handle value.buffer_descriptor
let transfer_texture (value:texture)=Transfer_pass.texture~device:value.resource.device.handle value.resource.handle value.texture_descriptor
let binding_buffer (value:buffer)=Binding.buffer value.resource.handle
let binding_texture (value:texture)=Binding.texture value.resource.handle
let buffer_id (value:buffer)=Handle.id value.resource.handle
let texture_id (value:texture)=Handle.id value.resource.handle
let render_texture (value:texture) ~format ~usage={Render_pass.id=Handle.id value.resource.handle;handle=value.resource.handle;format;samples=value.texture_descriptor.sample_count;width=value.texture_descriptor.width;height=value.texture_descriptor.height;usage=[usage]}
let write_buffer (value:buffer) ~offset bytes=if value.resource.dead then error"Backend.write_buffer"Error.Stale_handle"buffer is destroyed"else value.resource.raw.write offset bytes
let read_buffer (value:buffer) ~offset ~length=if value.resource.dead then error"Backend.read_buffer"Error.Stale_handle"buffer is destroyed"else value.resource.raw.read offset length
let read_texture (value:texture) ~bytes_per_row=if value.resource.dead then error"Backend.read_texture"Error.Stale_handle"texture is destroyed"else if bytes_per_row<=0||value.texture_descriptor.height>max_int/bytes_per_row then error"Backend.read_texture"Error.Invalid_argument"row pitch is invalid"else value.resource.raw.read 0L(bytes_per_row*value.texture_descriptor.height)
let read_texture_into (value:texture) ~bytes_per_row ~destination=
  let operation="Backend.read_texture_into"in
  if value.resource.dead then error operation Error.Stale_handle"texture is destroyed"
  else if bytes_per_row<=0||value.texture_descriptor.height>max_int/bytes_per_row
  then error operation Error.Invalid_argument"row pitch is invalid"
  else let length=bytes_per_row*value.texture_descriptor.height in
    if Bytes.length destination<>length then
      error operation Error.Invalid_argument"destination length does not match texture extent"
    else value.resource.raw.read_into 0L destination 0 length
(* Commands own immutable snapshots whose size is useful to adapter caches.
   The generic queue cache retains only numeric identities and token maps. *)
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
let command_description_bytes=function
  |Command.Push_debug label->saturating_add 64L(accounted_string label)
  |Command.Declare_resource resource->
      saturating_add 128L(accounted_items(List.length resource.Command.stages)32L)
  |Command.Begin_encoder|Command.Begin_pass _|Command.End_pass _|Command.Pop_debug|
   Command.End_encoder|Command.Present->32L
let transfer_command_bytes descriptions=
  saturating_add 512L(accounted_items(Array.length descriptions)256L)
let compute_command_bytes (description:Compute_pass.description)=
  let bytes=saturating_add 512L(accounted_string description.pipeline_key)in
  let bytes=Array.fold_left(fun total(_,bindings)->
    total|>saturating_add 64L
      |>saturating_add(accounted_items(List.length bindings)96L))
    bytes description.groups in
  let bytes=match description.dispatch with
    |Compute_pass.Direct _->saturating_add bytes 64L
    |Compute_pass.Indirect _->saturating_add bytes 256L in
  Array.fold_left(fun total command->
    saturating_add total(command_description_bytes command))
    bytes description.commands
let sampler_binding_bytes (binding:Render_pass.sampler_binding)=
  saturating_add 384L(accounted_label binding.sampler.Types.label)
let render_draw_bytes (draw:Render_pass.draw)=
  let bytes=saturating_add 512L(accounted_string draw.pipeline_key)in
  let bytes=saturating_add bytes
    (accounted_items(List.length draw.buffers)128L)in
  let bytes=saturating_add bytes
    (accounted_items(List.length draw.textures)128L)in
  let bytes=List.fold_left(fun total binding->
    saturating_add total(sampler_binding_bytes binding))bytes draw.samplers in
  match draw.index with None->bytes|Some _->saturating_add bytes 128L
let render_command_bytes submission=
  let pass=Render_pass.submission_pass submission in
  let descriptor=Render_pass.descriptor pass in
  let bytes=saturating_add 1_024L
    (accounted_items(Array.length descriptor.Render_pass.colors)1_024L)in
  let bytes=if Option.is_some descriptor.depth then saturating_add bytes 1_024L
    else bytes in
  let bytes=if Option.is_some descriptor.stencil then saturating_add bytes 1_024L
    else bytes in
  List.fold_left(fun total draw->saturating_add total(render_draw_bytes draw))
    bytes(Render_pass.submission_draws submission)
let command_view_bytes=function
  |Transfer descriptions->transfer_command_bytes descriptions
  |Compute description->compute_command_bytes description
  |Render submission->render_command_bytes submission
let snapshot_compute_description (description:Compute_pass.description)=
  {description with
   groups=Array.map(fun(index,bindings)->index,List.map Fun.id bindings)
     description.groups;
   commands=Array.copy description.commands}
let snapshot_command_view=function
  |Transfer descriptions->Transfer(Array.copy descriptions)
  |Compute description->Compute(snapshot_compute_description description)
  |Render submission->Render(Render_pass.Private.snapshot_submission submission)
let snapshot_command view=
  let command_view=snapshot_command_view view in
  {command_identity=fresh_private_identity();command_view;
   command_bytes=command_view_bytes command_view}
let transfer pass=Result.map(fun descriptions->snapshot_command(Transfer descriptions))
    (Transfer_pass.finish pass)
let compute pass=snapshot_command(Compute(Compute_pass.describe pass))
let render pass draws=Result.map(fun submission->snapshot_command(Render submission))
    (Render_pass.submit pass draws)
let submission_cache_entry_bytes resources pipelines=
  512L|>saturating_add(accounted_items(List.length resources)128L)
  |>saturating_add(accounted_items(List.length pipelines)96L)
let resource_key=function
  |`Buffer(buffer:buffer)->Buffer_key(Handle.id buffer.resource.handle)
  |`Texture(texture:texture)->Texture_key(Handle.id texture.resource.handle)
let resource_token=function
  |`Buffer(buffer:buffer)->Handle.id buffer.resource.handle,buffer.resource.raw.token
  |`Texture(texture:texture)->
      Handle.id texture.resource.handle,texture.resource.raw.token
let rec same_resources resources keys=match resources,keys with
  |[],[]->true
  |`Buffer(buffer:buffer)::resources,Buffer_key id::keys
      when Int64.equal(Handle.id buffer.resource.handle)id->
      same_resources resources keys
  |`Texture(texture:texture)::resources,Texture_key id::keys
      when Int64.equal(Handle.id texture.resource.handle)id->
      same_resources resources keys
  |_->false
let rec same_pipelines pipelines keys=match pipelines,keys with
  |[],[]->true
  |pipeline::pipelines,key::keys when Int64.equal pipeline.identity key->
      same_pipelines pipelines keys
  |_->false
let rec find_cached_command cache command index=
  if index=Array.length cache then None
  else match Array.unsafe_get cache index with
  |Some entry when Int64.equal entry.cached_command_identity
      command.command_identity->Some entry
  |None|Some _->find_cached_command cache command(index+1)
let rec find_cached_resources cache resources index=
  if index=Array.length cache then None
  else match Array.unsafe_get cache index with
  |Some entry when same_resources resources entry.cached_resource_keys->Some entry
  |None|Some _->find_cached_resources cache resources(index+1)
let rec find_cached_pipelines cache pipelines index=
  if index=Array.length cache then None
  else match Array.unsafe_get cache index with
  |Some entry when same_pipelines pipelines entry.cached_pipeline_keys->Some entry
  |None|Some _->find_cached_pipelines cache pipelines(index+1)
let rec find_exact_cached cache command resources pipelines index=
  if index=Array.length cache then -1
  else match Array.unsafe_get cache index with
  |Some entry when Int64.equal entry.cached_command_identity
      command.command_identity&&
      same_resources resources entry.cached_resource_keys&&
      same_pipelines pipelines entry.cached_pipeline_keys->index
  |None|Some _->find_exact_cached cache command resources pipelines(index+1)
let rec submitted_resource_dead (resources:submitted_resource list)=match resources with
  |[]->false
  |`Buffer(buffer:buffer)::rest->buffer.resource.dead||submitted_resource_dead rest
  |`Texture(texture:texture)::rest->texture.resource.dead||submitted_resource_dead rest
let rec submitted_resource_foreign device (resources:submitted_resource list)=
  match resources with
  |[]->false
  |`Buffer(buffer:buffer)::rest->buffer.resource.device!=device||
      submitted_resource_foreign device rest
  |`Texture(texture:texture)::rest->texture.resource.device!=device||
      submitted_resource_foreign device rest
let rec submitted_pipeline_dead (pipelines:pipeline list)=match pipelines with
  |[]->false|pipeline::rest->pipeline.dead||submitted_pipeline_dead rest
let rec submitted_pipeline_foreign device (pipelines:pipeline list)=match pipelines with
  |[]->false|pipeline::rest->pipeline.device!=device||
      submitted_pipeline_foreign device rest
let submitted_graph_status (queue:queue) (resources:submitted_resource list)
    (pipelines:pipeline list)=
  if submitted_resource_dead resources||submitted_pipeline_dead pipelines then 1
  else if submitted_resource_foreign queue.device resources||
          submitted_pipeline_foreign queue.device pipelines then 2
  else 0
type prepared_submission=
  { prepared_resource_keys:cached_resource_key list
  ; prepared_tokens:(int64*token)list
  ; prepared_pipeline_keys:int64 list
  ; prepared_pipeline_tokens:token list
  ; cached_entry:submission_cache_entry option }
let prepare_submission op (queue:queue) command ~resources ~pipelines=
  match live op queue.device with Error _ as e->e
  |Ok()when queue.dead->error op Error.Stale_handle"queue is destroyed"
  |Ok()->
      match submitted_graph_status queue resources pipelines with
      |1->error op Error.Stale_handle
          "submitted graph contains a destroyed object"
      |2->error op Error.Cross_device
          "submitted graph contains a foreign object"
      |_->
        let cached_entry=find_cached_command queue.submission_cache command 0 in
        let resource_entry=match cached_entry with
          |Some entry when same_resources resources entry.cached_resource_keys->
              Some entry
          |Some _|None->find_cached_resources queue.submission_cache resources 0 in
        let reused_resources=Option.is_some resource_entry in
        let resource_keys=if reused_resources then
            (Option.get resource_entry).cached_resource_keys
          else List.map resource_key resources in
        let resource_tokens=if reused_resources then
          (Option.get resource_entry).cached_tokens else
          List.map resource_token resources in
        let pipeline_entry=match cached_entry with
          |Some entry when same_pipelines pipelines entry.cached_pipeline_keys->
              Some entry
          |Some _|None->find_cached_pipelines queue.submission_cache pipelines 0 in
        let reused_pipelines=Option.is_some pipeline_entry in
        let pipeline_keys=if reused_pipelines then
            (Option.get pipeline_entry).cached_pipeline_keys
          else List.map(fun(pipeline:pipeline)->pipeline.identity)pipelines in
        let pipeline_tokens=if reused_pipelines then
          (Option.get pipeline_entry).cached_pipeline_tokens
          else List.map(fun(pipeline:pipeline)->pipeline.pipeline_driver.pipeline_token)
            pipelines in
        Ok{prepared_resource_keys=resource_keys;prepared_tokens=resource_tokens;
          prepared_pipeline_keys=pipeline_keys;
          prepared_pipeline_tokens=pipeline_tokens;cached_entry}
let mark_submitted queue resource=match resource.last_submitted_queue with
  |Some previous when previous==queue->()
  |None|Some _->resource.last_submitted_queue<-Some queue
let rec mark_submitted_resources queue= function
  |[]->()
  |`Buffer(buffer:buffer)::rest->mark_submitted queue buffer.resource;
      mark_submitted_resources queue rest
  |`Texture(texture:texture)::rest->mark_submitted queue texture.resource;
      mark_submitted_resources queue rest
let advance_cache_index cache index=(index+1)mod Array.length cache
let retire_cache_slot (queue:queue) index=
  match Array.unsafe_get queue.submission_cache index with
  |None->()
  |Some entry->
      queue.submission_cache_retained_bytes<-
        Int64.sub queue.submission_cache_retained_bytes entry.cached_bytes;
      Array.unsafe_set queue.submission_cache index None
let make_submission_cache_room (queue:queue) ~protected required_bytes=
  let available=Int64.sub queue.submission_cache_byte_capacity required_bytes in
  let rec evict scanned=
    if queue.submission_cache_retained_bytes<=available then()
    else if scanned=Array.length queue.submission_cache then
      failwith"Ogpu.Backend submission cache accounting invariant"
    else
      let index=queue.submission_cache_next in
      queue.submission_cache_next<-
        advance_cache_index queue.submission_cache index;
      (match Array.unsafe_get queue.submission_cache index with
       |Some entry when(match protected with Some keep->keep==entry|None->false)->()
       |None->()
       |Some _->retire_cache_slot queue index);
      evict(scanned+1)
  in
  evict 0
let update_cached_entry entry prepared bytes=
  entry.cached_resource_keys<-prepared.prepared_resource_keys;
  entry.cached_tokens<-prepared.prepared_tokens;
  entry.cached_pipeline_keys<-prepared.prepared_pipeline_keys;
  entry.cached_pipeline_tokens<-prepared.prepared_pipeline_tokens;
  entry.cached_bytes<-bytes
let commit_submission (queue:queue) command prepared ~resources ~pipelines=
  let bytes=submission_cache_entry_bytes resources pipelines in
  (if bytes<=queue.submission_cache_byte_capacity then
    match prepared.cached_entry with
    |Some entry->
        queue.submission_cache_retained_bytes<-
          Int64.sub queue.submission_cache_retained_bytes entry.cached_bytes;
        make_submission_cache_room queue~protected:(Some entry)bytes;
        update_cached_entry entry prepared bytes;
        queue.submission_cache_retained_bytes<-
          Int64.add queue.submission_cache_retained_bytes bytes
    |None->
        let index=queue.submission_cache_next in
        queue.submission_cache_next<-
          advance_cache_index queue.submission_cache index;
        retire_cache_slot queue index;
        make_submission_cache_room queue~protected:None bytes;
        let entry={cached_command_identity=command.command_identity;
          cached_resource_keys=prepared.prepared_resource_keys;
          cached_tokens=prepared.prepared_tokens;
          cached_pipeline_keys=prepared.prepared_pipeline_keys;
          cached_pipeline_tokens=prepared.prepared_pipeline_tokens;
          cached_bytes=bytes}in
        Array.unsafe_set queue.submission_cache index(Some entry);
        queue.submission_cache_retained_bytes<-
          Int64.add queue.submission_cache_retained_bytes bytes);
  mark_submitted_resources queue resources
let submit (queue:queue) command ~resources ~pipelines=
  let op="Backend.submit"in
  if queue.device.dead then error op Error.Stale_handle"device is destroyed"
  else if queue.dead then error op Error.Stale_handle"queue is destroyed"
  else
    let cached=find_exact_cached queue.submission_cache command resources
      pipelines 0 in
    if cached<0 then match prepare_submission op queue command~resources~pipelines with
      |Error _ as e->e
      |Ok prepared->match queue.raw.submit command
          ~resources:prepared.prepared_tokens
          ~pipelines:prepared.prepared_pipeline_tokens with
        |Error _ as e->e
        |Ok receipt->commit_submission queue command prepared~resources~pipelines;
            Ok receipt
    else
      let entry=Option.get(Array.unsafe_get queue.submission_cache cached)in
      match submitted_graph_status queue resources pipelines with
      |1->error op Error.Stale_handle
          "submitted graph contains a destroyed object"
      |2->error op Error.Cross_device
          "submitted graph contains a foreign object"
      |_->match queue.raw.submit command~resources:entry.cached_tokens
          ~pipelines:entry.cached_pipeline_tokens with
        |Error _ as e->e
        |Ok receipt->mark_submitted_resources queue resources;Ok receipt
let submit_sync (queue:queue) command ~resources ~pipelines=
  let op="Backend.submit_sync" in
  if queue.device.dead then error op Error.Stale_handle"device is destroyed"
  else if queue.dead then error op Error.Stale_handle"queue is destroyed"
  else
    let cached=find_exact_cached queue.submission_cache command resources
      pipelines 0 in
    if cached<0 then match prepare_submission op queue command~resources~pipelines with
      |Error _ as e->e
      |Ok prepared->match queue.raw.submit_sync command
          ~resources:prepared.prepared_tokens
          ~pipelines:prepared.prepared_pipeline_tokens with
        |Error _ as e->e
        |Ok admitted->commit_submission queue command prepared~resources~pipelines;
            Ok admitted
    else
      let entry=Option.get(Array.unsafe_get queue.submission_cache cached)in
      match submitted_graph_status queue resources pipelines with
      |1->error op Error.Stale_handle
          "submitted graph contains a destroyed object"
      |2->error op Error.Cross_device
          "submitted graph contains a foreign object"
      |_->match queue.raw.submit_sync command~resources:entry.cached_tokens
          ~pipelines:entry.cached_pipeline_tokens with
        |Error _ as e->e
        |Ok admitted->mark_submitted_resources queue resources;Ok admitted
let complete_through (queue:queue) epoch=if queue.dead then error"Backend.complete_through"Error.Stale_handle"queue is destroyed"else queue.raw.complete_through epoch
let configure (surface:surface) value=
  if surface.dead then error"Backend.configure"Error.Stale_handle"surface is destroyed"
  else if surface.frames<>0 then error"Backend.configure"Error.Invalid_state"surface has acquired frames"
  else match surface.raw.configure value with
    |Error _ as e->e
    |Ok()->surface.configuration<-value;Ok()
let acquire (surface:surface)=if surface.dead then error"Backend.acquire"Error.Stale_handle"surface is destroyed"else match surface.raw.acquire()with Error _ as e->e|Ok(`Acquired raw)->surface.frames<-surface.frames+1;Ok(`Acquired{raw;surface;consumed=false})|Ok`Timeout->Ok`Timeout|Ok`Occluded->Ok`Occluded|Ok`Device_lost->Ok`Device_lost
let acquire_sync (surface:surface)=if surface.dead then error"Backend.acquire_sync"Error.Stale_handle"surface is destroyed"else match surface.raw.acquire_sync()with Error _ as e->e|Ok(`Acquired raw)->surface.frames<-surface.frames+1;Ok(`Acquired{raw;surface;consumed=false})|Ok`Timeout->Ok`Timeout|Ok`Occluded->Ok`Occluded|Ok`Device_lost->Ok`Device_lost
let consume op action (frame:frame)=if frame.consumed then error op Error.Invalid_state"frame is already consumed"else if frame.surface.dead then error op Error.Stale_handle"surface is destroyed"else match action frame.raw with Error _ as e->e|Ok()->frame.consumed<-true;frame.surface.frames<-frame.surface.frames-1;Ok()
let validate_present op (queue:queue) (source:texture) (frame:frame)=
  if frame.consumed then error op Error.Invalid_state"frame is already consumed"
  else if frame.surface.dead then error op Error.Stale_handle"surface is destroyed"
  else if queue.dead then error op Error.Stale_handle"queue is destroyed"
  else if source.resource.dead then error op Error.Stale_handle"source texture is destroyed"
  else if queue.device!=frame.surface.device then
    error op Error.Cross_device"queue belongs to a different device"
  else if source.resource.device!=frame.surface.device then
    error op Error.Cross_device"source texture belongs to a different device"
  else if match source.resource.last_submitted_queue with
    |Some producer when not producer.dead&&producer!=queue->true
    |None|Some _->false then
    error op Error.Invalid_state
      "source texture was last submitted through a different live queue"
  else
    let descriptor=source.texture_descriptor
    and configuration=frame.surface.configuration in
    if descriptor.width<>configuration.physical_width||
       descriptor.height<>configuration.physical_height then
      error op Error.Invalid_argument
        "source texture extent does not match the configured physical surface extent"
    else if descriptor.sample_count<>1 then
      error op Error.Invalid_argument"source texture must have sample_count=1"
    else if not(List.mem Types.Texture_binding descriptor.usage)then
      error op Error.Invalid_argument"source texture must have Texture_binding usage"
    else Ok()
let consume_present frame=
  frame.consumed<-true;
  frame.surface.frames<-frame.surface.frames-1
let present ~(queue:queue) ~(source:texture) (frame:frame)=
  let op="Backend.present"in
  match validate_present op queue source frame with
  |Error _ as e->e
  |Ok()->match frame.surface.raw.present~queue:queue.raw.queue_token
      ~source:source.resource.raw.token frame.raw with
      |Error _ as e->e
      |Ok()->consume_present frame;Ok()
let submit_present (queue:queue) command ~resources ~pipelines
    ~(source:texture) (frame:frame)=
  let op="Backend.submit_present"in
  match validate_present op queue source frame with
  |Error _ as e->e
  |Ok()->
      let cached=find_exact_cached queue.submission_cache command resources
        pipelines 0 in
      if cached<0 then match prepare_submission op queue command~resources~pipelines with
        |Error _ as e->e
        |Ok prepared->match frame.surface.raw.submit_present
            ~queue:queue.raw.queue_token~source:source.resource.raw.token command
            ~resources:prepared.prepared_tokens
            ~pipelines:prepared.prepared_pipeline_tokens frame.raw with
          |Error _ as e->e
          |Ok receipt->
              commit_submission queue command prepared~resources~pipelines;
              mark_submitted queue source.resource;
              consume_present frame;
              Ok receipt
      else
        let entry=Option.get(Array.unsafe_get queue.submission_cache cached)in
        match submitted_graph_status queue resources pipelines with
        |1->error op Error.Stale_handle
            "submitted graph contains a destroyed object"
        |2->error op Error.Cross_device
            "submitted graph contains a foreign object"
        |_->match frame.surface.raw.submit_present
            ~queue:queue.raw.queue_token~source:source.resource.raw.token command
            ~resources:entry.cached_tokens
            ~pipelines:entry.cached_pipeline_tokens frame.raw with
          |Error _ as e->e
          |Ok receipt->
              mark_submitted_resources queue resources;
              mark_submitted queue source.resource;
              consume_present frame;
              Ok receipt
let submit_present_sync (queue:queue) command ~resources ~pipelines
    ~(source:texture) (frame:frame)=
  let op="Backend.submit_present_sync" in
  match validate_present op queue source frame with
  |Error _ as e->e
  |Ok()->
      let cached=find_exact_cached queue.submission_cache command resources
        pipelines 0 in
      if cached<0 then match prepare_submission op queue command~resources~pipelines with
        |Error _ as e->e
        |Ok prepared->match frame.surface.raw.submit_present_sync
            ~queue:queue.raw.queue_token~source:source.resource.raw.token command
            ~resources:prepared.prepared_tokens
            ~pipelines:prepared.prepared_pipeline_tokens frame.raw with
          |Error _ as e->e
          |Ok admitted->
              (* Admission, not successful completion, commits portable
                 ownership and consumes the presentation exactly once. *)
              commit_submission queue command prepared~resources~pipelines;
              mark_submitted queue source.resource;
              consume_present frame;
              Ok admitted
      else
        let entry=Option.get(Array.unsafe_get queue.submission_cache cached)in
        match submitted_graph_status queue resources pipelines with
        |1->error op Error.Stale_handle
            "submitted graph contains a destroyed object"
        |2->error op Error.Cross_device
            "submitted graph contains a foreign object"
        |_->match frame.surface.raw.submit_present_sync
            ~queue:queue.raw.queue_token~source:source.resource.raw.token command
            ~resources:entry.cached_tokens
            ~pipelines:entry.cached_pipeline_tokens frame.raw with
          |Error _ as e->e
          |Ok admitted->
              mark_submitted_resources queue resources;
              mark_submitted queue source.resource;
              consume_present frame;
              Ok admitted
let discard frame=consume"Backend.discard"frame.surface.raw.discard frame
let resource_key_has_id id=function
  |Buffer_key cached|Texture_key cached->Int64.equal id cached
let purge_submission_cache (device:device) predicate=
  List.iter(fun queue->
    Array.iteri(fun index->function
      |Some entry when predicate entry->retire_cache_slot queue index
      |None|Some _->())queue.submission_cache)device.queues
let purge_resource device id=
  purge_submission_cache device(fun entry->
    List.exists(resource_key_has_id id)entry.cached_resource_keys)
let purge_pipeline device identity=
  purge_submission_cache device(fun entry->
    List.exists(Int64.equal identity)entry.cached_pipeline_keys)
let destroy_resource (resource:resource)=if resource.dead then Ok()else match resource.raw.destroy()with Error _ as e->e|Ok()->let id=Handle.id resource.handle in resource.dead<-true;Handle.destroy resource.handle;purge_resource resource.device id;resource.device.children<-resource.device.children-1;Ok()
let destroy_buffer (value:buffer)=destroy_resource value.resource
let destroy_texture (value:texture)=destroy_resource value.resource
let destroy_pipeline (value:pipeline)=if value.dead then Ok()else match value.pipeline_driver.destroy_pipeline()with Error _ as e->e|Ok()->value.dead<-true;purge_pipeline value.device value.identity;value.device.children<-value.device.children-1;Ok()
let destroy_queue (value:queue)=if value.dead then Ok()else match value.raw.destroy_queue()with Error _ as e->e|Ok()->value.dead<-true;Array.fill value.submission_cache 0(Array.length value.submission_cache)None;value.submission_cache_retained_bytes<-0L;value.device.queues<-List.filter(fun queue->queue!=value)value.device.queues;value.device.children<-value.device.children-1;Ok()
let destroy_surface (value:surface)=if value.dead then Ok()else if value.frames<>0 then error"Backend.destroy_surface"Error.Invalid_state"surface has acquired frames"else match value.raw.destroy_surface()with Error _ as e->e|Ok()->value.dead<-true;value.device.children<-value.device.children-1;Ok()
let destroy_device (value:device)=if value.dead then Ok()else if value.children<>0 then error"Backend.destroy_device"Error.Invalid_state"device has live children"else match value.raw.destroy_device()with Error _ as e->e|Ok()->value.dead<-true;Ok()
module Private=struct
  type nonrec command_view=command_view=
    |Transfer of Transfer_pass.description array
    |Compute of Compute_pass.description
    |Render of Render_pass.submission
  let command_view command=command.command_view
  let snapshot_command=snapshot_command
  let command_retained_bytes command=command.command_bytes
  let submission_cache_stats queue=
    {entries=Array.fold_left(fun count->function None->count|Some _->count+1)0
       queue.submission_cache;
     retained_bytes=queue.submission_cache_retained_bytes;
     entry_capacity=Array.length queue.submission_cache;
     byte_capacity=queue.submission_cache_byte_capacity}
  let submission_cache_contains queue command ~resources ~pipelines=
    find_exact_cached queue.submission_cache command resources pipelines 0>=0
end
