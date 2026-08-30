type token=int64
type command=Transfer of Transfer_pass.description array|Compute of Compute_pass.description|Render of Render_pass.submission
type receipt={epoch:int64}
type synchronous_submission={receipt:receipt;completion:(unit,Error.t)result}
type driver_resource={token:token;write:int64->bytes->(unit,Error.t)result;read:int64->int->(bytes,Error.t)result;read_into:int64->bytes->int->int->(unit,Error.t)result;destroy:unit->(unit,Error.t)result}
type driver_pipeline={pipeline_token:token;destroy_pipeline:unit->(unit,Error.t)result}
type driver_frame={frame_token:token}
type driver_surface={surface_token:token;configure:Surface.configuration->(unit,Error.t)result;acquire:unit->([`Acquired of driver_frame|`Timeout|`Occluded|`Device_lost],Error.t)result;acquire_sync:unit->([`Acquired of driver_frame|`Timeout|`Occluded|`Device_lost],Error.t)result;present:queue:token->source:token->driver_frame->(unit,Error.t)result;submit_present:queue:token->source:token->command->resources:(int64*token)list->pipelines:token list->driver_frame->(receipt,Error.t)result;submit_present_sync:queue:token->source:token->command->resources:(int64*token)list->pipelines:token list->driver_frame->(synchronous_submission,Error.t)result;discard:driver_frame->(unit,Error.t)result;destroy_surface:unit->(unit,Error.t)result}
type driver_queue={queue_token:token;submit:command->resources:(int64*token)list->pipelines:token list->(receipt,Error.t)result;submit_sync:command->resources:(int64*token)list->pipelines:token list->(synchronous_submission,Error.t)result;complete_through:int64->(unit,Error.t)result;destroy_queue:unit->(unit,Error.t)result}
type driver_device={device_token:token;device_handle:Handle.device;capabilities:Capabilities.t;create_buffer:Types.buffer_descriptor->(driver_resource,Error.t)result;create_texture:Types.texture_descriptor->(driver_resource,Error.t)result;create_depth_texture:Types.texture_descriptor->(driver_resource,Error.t)result;create_stencil_texture:Types.texture_descriptor->(driver_resource,Error.t)result;create_pipeline:Pipeline.t->(driver_pipeline,Error.t)result;create_queue:unit->(driver_queue,Error.t)result;create_surface:Surface.configuration->(driver_surface,Error.t)result;destroy_device:unit->(unit,Error.t)result}
type driver={create_device:unit->(driver_device,Error.t)result}
type device={raw:driver_device;handle:Handle.device;mutable children:int;mutable dead:bool}
type resource={raw:driver_resource;handle:unit Handle.t;device:device;mutable dead:bool;
  mutable last_submitted_queue:queue option}
and buffer={resource:resource;buffer_descriptor:Types.buffer_descriptor}
and texture={resource:resource;texture_descriptor:Types.texture_descriptor}
and pipeline={pipeline_driver:driver_pipeline;device:device;mutable dead:bool}
and submitted_resource=[`Buffer of buffer|`Texture of texture]
and submission_cache_entry=
  { cached_command:command
  ; mutable cached_resources:submitted_resource list
  ; mutable cached_pairs:(int64*resource)list
  ; mutable cached_tokens:(int64*token)list
  ; mutable cached_pipelines:pipeline list
  ; mutable cached_pipeline_tokens:token list }
and queue={raw:driver_queue;device:device;mutable dead:bool;
  submission_cache:submission_cache_entry option array;
  mutable submission_cache_next:int}
type surface={raw:driver_surface;device:device;mutable dead:bool;mutable frames:int;
  mutable configuration:Surface.configuration}
type frame={raw:driver_frame;surface:surface;mutable consumed:bool}
let error op kind text=Error(Error.make op kind text)
let create_device driver=match driver.create_device()with Error _ as e->e|Ok raw->match Capabilities.validate raw.capabilities with Error _ as e->e|Ok()->Ok{raw;handle=raw.device_handle;children=0;dead=false}
let capabilities (value:device)=value.raw.capabilities
let device_handle (value:device)=value.handle
let live op (device:device)=if device.dead then error op Error.Stale_handle"device is destroyed"else Ok()
let make_resource (device:device) raw={raw;handle=Handle.create~device:device.handle;
  device;dead=false;last_submitted_queue=None}
let create_buffer device descriptor=match live"Backend.create_buffer"device with Error _ as e->e|Ok()->match Types.validate_buffer device.raw.capabilities descriptor with Error _ as e->e|Ok()->match device.raw.create_buffer descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;buffer_descriptor=descriptor}
let create_texture device descriptor=match live"Backend.create_texture"device with Error _ as e->e|Ok()->match Types.validate_texture device.raw.capabilities descriptor with Error _ as e->e|Ok()->match device.raw.create_texture descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;texture_descriptor=descriptor}
let create_depth_texture device descriptor=match live"Backend.create_depth_texture"device with Error _ as e->e|Ok()->match Types.validate_texture device.raw.capabilities descriptor with Error _ as e->e|Ok() when not(List.mem Types.Render_attachment descriptor.usage)||List.exists(fun usage->usage<>Types.Render_attachment)descriptor.usage->error"Backend.create_depth_texture"Error.Invalid_argument"depth textures are render-attachment only"|Ok()->match device.raw.create_depth_texture descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;texture_descriptor=descriptor}
let create_stencil_texture device descriptor=match live"Backend.create_stencil_texture"device with Error _ as e->e|Ok()->match Types.validate_texture device.raw.capabilities descriptor with Error _ as e->e|Ok() when not(List.mem Types.Render_attachment descriptor.usage)||List.exists(fun usage->usage<>Types.Render_attachment)descriptor.usage->error"Backend.create_stencil_texture"Error.Invalid_argument"stencil textures are render-attachment only"|Ok()->match device.raw.create_stencil_texture descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;texture_descriptor=descriptor}
let adopt_pipeline device portable=match live"Backend.adopt_pipeline"device with Error _ as e->e|Ok()->match device.raw.create_pipeline portable with Error _ as e->e|Ok pipeline_driver->device.children<-device.children+1;Ok{pipeline_driver;device;dead=false}
let submission_cache_capacity=256
let create_queue device=match live"Backend.create_queue"device with Error _ as e->e|Ok()->match device.raw.create_queue()with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{raw;device;dead=false;submission_cache=Array.make submission_cache_capacity None;submission_cache_next=0}
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
let transfer pass=Result.map(fun x->Transfer x)(Transfer_pass.finish pass)
let compute pass=Compute(Compute_pass.describe pass)
let render pass draws=Result.map(fun submission->Render submission)(Render_pass.submit pass draws)
let resource_pair=function `Buffer(b:buffer)->Handle.id b.resource.handle,b.resource|`Texture(t:texture)->Handle.id t.resource.handle,t.resource
let rec same_resources left right=match left,right with
  |[],[]->true
  |`Buffer left::lefts,`Buffer right::rights when left==right->
      same_resources lefts rights
  |`Texture left::lefts,`Texture right::rights when left==right->
      same_resources lefts rights
  |_->false
let rec same_pipelines left right=match left,right with
  |[],[]->true
  |left::lefts,right::rights when left==right->same_pipelines lefts rights
  |_->false
let rec find_cached_command cache command index=
  if index=Array.length cache then None
  else match Array.unsafe_get cache index with
  |Some entry when entry.cached_command==command->Some entry
  |None|Some _->find_cached_command cache command(index+1)
let rec find_cached_resources cache resources index=
  if index=Array.length cache then None
  else match Array.unsafe_get cache index with
  |Some entry when same_resources resources entry.cached_resources->Some entry
  |None|Some _->find_cached_resources cache resources(index+1)
let rec find_cached_pipelines cache pipelines index=
  if index=Array.length cache then None
  else match Array.unsafe_get cache index with
  |Some entry when same_pipelines pipelines entry.cached_pipelines->Some entry
  |None|Some _->find_cached_pipelines cache pipelines(index+1)
type prepared_submission=
  { prepared_resources:submitted_resource list
  ; prepared_pairs:(int64*resource)list
  ; prepared_tokens:(int64*token)list
  ; prepared_pipelines:pipeline list
  ; prepared_pipeline_tokens:token list
  ; reused_resources:bool
  ; reused_pipelines:bool
  ; cached_entry:submission_cache_entry option }
let prepare_submission op (queue:queue) command ~resources ~pipelines=
  match live op queue.device with Error _ as e->e
  |Ok()when queue.dead->error op Error.Stale_handle"queue is destroyed"
  |Ok()->
      let cached_entry=find_cached_command queue.submission_cache command 0 in
      let resource_entry=match cached_entry with
        |Some entry when same_resources resources entry.cached_resources->Some entry
        |Some _|None->find_cached_resources queue.submission_cache resources 0 in
      let reused_resources=Option.is_some resource_entry in
      let pairs=if reused_resources then
          (Option.get resource_entry).cached_pairs
        else List.map resource_pair resources in
      if List.exists(fun(_,r:token*resource)->r.dead)pairs||
         List.exists(fun(p:pipeline)->p.dead)pipelines then
        error op Error.Stale_handle"submitted graph contains a destroyed object"
      else if List.exists(fun(_,r:token*resource)->r.device!=queue.device)pairs||
              List.exists(fun(p:pipeline)->p.device!=queue.device)pipelines then
        error op Error.Cross_device"submitted graph contains a foreign object"
      else
        let resource_tokens=if reused_resources then
          (Option.get resource_entry).cached_tokens else
          List.map(fun(id,(resource:resource))->id,resource.raw.token)pairs in
        let pipeline_entry=match cached_entry with
          |Some entry when same_pipelines pipelines entry.cached_pipelines->Some entry
          |Some _|None->find_cached_pipelines queue.submission_cache pipelines 0 in
        let reused_pipelines=Option.is_some pipeline_entry in
        let pipeline_tokens=if reused_pipelines then
          (Option.get pipeline_entry).cached_pipeline_tokens
          else List.map(fun(pipeline:pipeline)->pipeline.pipeline_driver.pipeline_token)
            pipelines in
        Ok{prepared_resources=resources;prepared_pairs=pairs;
          prepared_tokens=resource_tokens;prepared_pipelines=pipelines;
          prepared_pipeline_tokens=pipeline_tokens;reused_resources;
          reused_pipelines;cached_entry}
let mark_submitted queue resource=match resource.last_submitted_queue with
  |Some previous when previous==queue->()
  |None|Some _->resource.last_submitted_queue<-Some queue
let commit_submission (queue:queue) command prepared=
  (match prepared.cached_entry with
   |Some entry->
       if not prepared.reused_resources then begin
         entry.cached_resources<-prepared.prepared_resources;
         entry.cached_pairs<-prepared.prepared_pairs;
         entry.cached_tokens<-prepared.prepared_tokens
       end;
       if not prepared.reused_pipelines then begin
         entry.cached_pipelines<-prepared.prepared_pipelines;
         entry.cached_pipeline_tokens<-prepared.prepared_pipeline_tokens
       end
   |None->
       let entry={cached_command=command;
         cached_resources=prepared.prepared_resources;
         cached_pairs=prepared.prepared_pairs;cached_tokens=prepared.prepared_tokens;
         cached_pipelines=prepared.prepared_pipelines;
         cached_pipeline_tokens=prepared.prepared_pipeline_tokens}in
       Array.unsafe_set queue.submission_cache queue.submission_cache_next(Some entry);
       queue.submission_cache_next<-(queue.submission_cache_next+1)mod
         Array.length queue.submission_cache);
  List.iter(fun(_,resource)->mark_submitted queue resource)
    prepared.prepared_pairs
let submit (queue:queue) command ~resources ~pipelines=
  let op="Backend.submit"in
  match prepare_submission op queue command~resources~pipelines with
  |Error _ as e->e
  |Ok prepared->match queue.raw.submit command
      ~resources:prepared.prepared_tokens
      ~pipelines:prepared.prepared_pipeline_tokens with
      |Error _ as e->e
      |Ok receipt->commit_submission queue command prepared;Ok receipt
let submit_sync (queue:queue) command ~resources ~pipelines=
  let op="Backend.submit_sync" in
  match prepare_submission op queue command~resources~pipelines with
  |Error _ as e->e
  |Ok prepared->match queue.raw.submit_sync command
      ~resources:prepared.prepared_tokens
      ~pipelines:prepared.prepared_pipeline_tokens with
    |Error _ as e->e
    |Ok admitted->commit_submission queue command prepared;Ok admitted
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
  |Ok()->match prepare_submission op queue command~resources~pipelines with
    |Error _ as e->e
    |Ok prepared->match frame.surface.raw.submit_present
        ~queue:queue.raw.queue_token~source:source.resource.raw.token command
        ~resources:prepared.prepared_tokens
        ~pipelines:prepared.prepared_pipeline_tokens frame.raw with
      |Error _ as e->e
      |Ok receipt->
          commit_submission queue command prepared;
          mark_submitted queue source.resource;
          consume_present frame;
          Ok receipt
let submit_present_sync (queue:queue) command ~resources ~pipelines
    ~(source:texture) (frame:frame)=
  let op="Backend.submit_present_sync" in
  match validate_present op queue source frame with
  |Error _ as e->e
  |Ok()->match prepare_submission op queue command~resources~pipelines with
    |Error _ as e->e
    |Ok prepared->match frame.surface.raw.submit_present_sync
        ~queue:queue.raw.queue_token~source:source.resource.raw.token command
        ~resources:prepared.prepared_tokens
        ~pipelines:prepared.prepared_pipeline_tokens frame.raw with
      |Error _ as e->e
      |Ok admitted->
          (* Admission, not successful completion, commits portable ownership
             and consumes the presentation exactly once. *)
          commit_submission queue command prepared;
          mark_submitted queue source.resource;
          consume_present frame;
          Ok admitted
let discard frame=consume"Backend.discard"frame.surface.raw.discard frame
let destroy_resource (resource:resource)=if resource.dead then Ok()else match resource.raw.destroy()with Error _ as e->e|Ok()->resource.dead<-true;Handle.destroy resource.handle;resource.device.children<-resource.device.children-1;Ok()
let destroy_buffer (value:buffer)=destroy_resource value.resource
let destroy_texture (value:texture)=destroy_resource value.resource
let destroy_pipeline (value:pipeline)=if value.dead then Ok()else match value.pipeline_driver.destroy_pipeline()with Error _ as e->e|Ok()->value.dead<-true;value.device.children<-value.device.children-1;Ok()
let destroy_queue (value:queue)=if value.dead then Ok()else match value.raw.destroy_queue()with Error _ as e->e|Ok()->value.dead<-true;Array.fill value.submission_cache 0(Array.length value.submission_cache)None;value.device.children<-value.device.children-1;Ok()
let destroy_surface (value:surface)=if value.dead then Ok()else if value.frames<>0 then error"Backend.destroy_surface"Error.Invalid_state"surface has acquired frames"else match value.raw.destroy_surface()with Error _ as e->e|Ok()->value.dead<-true;value.device.children<-value.device.children-1;Ok()
let destroy_device (value:device)=if value.dead then Ok()else if value.children<>0 then error"Backend.destroy_device"Error.Invalid_state"device has live children"else match value.raw.destroy_device()with Error _ as e->e|Ok()->value.dead<-true;Ok()
module Private=struct
  let submission_cache_stats queue=
    Array.fold_left(fun count->function None->count|Some _->count+1)0
      queue.submission_cache,
    Array.length queue.submission_cache
end
