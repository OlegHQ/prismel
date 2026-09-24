type frame_state=Live|Presented|Discarded|Stale
type t={device:Device.t;layer:Metal.Metal_layer.t;portable:Ogpu.Surface.t;presentation:Presentation.t;readable_drawables_for_test:bool;mutable frames:frame list;mutable in_flight_presentations:int;mutable destroy_pending:bool;mutable dead:bool}
and frame={surface:t;portable:Ogpu.Surface.frame;drawable:Metal.Drawable.t;texture:Metal.Texture.t;generation:int64;mutable state:frame_state}
type pending_payload={mutable owner:t;mutable frame:frame;mutable source:Texture.t}
type pending_presentation={mutable payload:pending_payload option;
  mutable active:bool;mutable epoch:int64;encode:Queue.presentation}
type acquire_result=Acquired of frame|Timeout|Occluded|Device_lost
let error op kind message=Error(Ogpu.Error.make op kind message)
let metal_config ~readable_drawables_for_test (value:Ogpu.Surface.configuration)=
  let format=match value.format with Bgra8_unorm->Ok Metal.Texture.Bgra8_unorm|Rgba8_unorm->error"Ogpu_metal.Surface.configure"Ogpu.Error.Invalid_argument"CAMetalLayer does not expose RGBA8 drawable format"in
  Result.map(fun format->{Metal.Metal_layer.width=value.physical_width;height=value.physical_height;format;framebuffer_only=not readable_drawables_for_test;maximum_drawables=max 2 value.max_acquired;allows_timeout=true;display_sync=(value.present_mode=Fifo);presents_with_transaction=false})format
let create_common ~readable_drawables_for_test device~layer config=let op="Ogpu_metal.Surface.create"in if Device.destroyed device then error op Ogpu.Error.Stale_handle"device is destroyed"else if not(Metal.Device.same(Device.Private.metal device)(Metal.Metal_layer.device layer))then error op Ogpu.Error.Cross_device"layer belongs to another device"else match Ogpu.Surface.create(Device.Private.handle device)config with Error _ as e->e|Ok portable->match metal_config~readable_drawables_for_test config with Error _ as e->Ogpu.Surface.destroy portable;e|Ok native->match Presentation.create device with Error _ as e->Ogpu.Surface.destroy portable;e|Ok presentation->match Metal.Metal_layer.configure layer native with Error e->Presentation.destroy presentation;Ogpu.Surface.destroy portable;Error(Adapter.error~operation:op e)|Ok()->Device.Private.attach_resource device;Ok{device;layer;portable;presentation;readable_drawables_for_test;frames=[];in_flight_presentations=0;destroy_pending=false;dead=false}
let create device~layer config=create_common~readable_drawables_for_test:false device~layer config
let destroyed value=value.dead||value.destroy_pending
let generation value=Ogpu.Surface.generation value.portable
let outstanding value=List.length value.frames
let in_flight_presentations value=value.in_flight_presentations
let frame_id (value:frame)=Ogpu.Surface.frame_id value.portable
let frame_generation (value:frame)=value.generation
let frame_texture (value:frame)=match value.state with Live->Ok value.texture|Presented|Discarded|Stale->error"Ogpu_metal.Surface.frame_texture"Ogpu.Error.Stale_handle"frame is consumed or stale"
let release frame=ignore(Metal.Texture.destroy frame.texture);ignore(Metal.Drawable.destroy frame.drawable)
let stale_frames value=List.iter(fun frame->if frame.state=Live then(frame.state<-Stale;release frame))value.frames;value.frames<-[]
let teardown value=if not value.dead then(stale_frames value;Presentation.destroy value.presentation;Ogpu.Surface.destroy value.portable;value.destroy_pending<-false;value.dead<-true;Device.Private.detach_resource value.device)
let preflight_portable value config=match Ogpu.Surface.create(Device.Private.handle value.device)config with Error _ as e->e|Ok probe->Ogpu.Surface.destroy probe;Ok()
let configure value config=let op="Ogpu_metal.Surface.configure"in if destroyed value then error op Ogpu.Error.Stale_handle"surface is destroyed"else if value.in_flight_presentations<>0 then error op Ogpu.Error.Invalid_state"surface has presentations in flight"else match metal_config~readable_drawables_for_test:value.readable_drawables_for_test config with Error _ as e->e|Ok native->match preflight_portable value config with Error _ as e->e|Ok()->match Metal.Metal_layer.configure value.layer native with Error e->Error(Adapter.error~operation:op e)|Ok()->stale_frames value;Ogpu.Surface.configure value.portable config
let resize value~logical_width~logical_height~physical_width~physical_height=let current=Metal.Metal_layer.config value.layer in let format=if current.format=Metal.Texture.Bgra8_unorm then Ogpu.Surface.Bgra8_unorm else Rgba8_unorm in let config={Ogpu.Surface.logical_width;logical_height;physical_width;physical_height;format;present_mode=(if current.display_sync then Fifo else Immediate);max_acquired=current.maximum_drawables}in configure value config
let set_availability value availability=Ogpu.Surface.set_availability value.portable availability
let acquire_common ~scoped value=let op="Ogpu_metal.Surface.acquire"in if destroyed value then error op Ogpu.Error.Stale_handle"surface is destroyed"else match Ogpu.Surface.acquire value.portable with Error _ as e->e|Ok Timeout->Ok Timeout|Ok Occluded->Ok Occluded|Ok Device_lost->Ok Device_lost|Ok(Acquired portable)->match (if scoped then Metal.Drawable.Private.acquire_scoped value.layer else Metal.Drawable.acquire value.layer)with Error e->ignore(Ogpu.Surface.discard value.portable portable);Error(Adapter.error~operation:op e)|Ok(Error Metal.Drawable.Timeout_or_unavailable)->ignore(Ogpu.Surface.discard value.portable portable);Ok Timeout|Ok(Ok drawable)->match (if scoped then Metal.Drawable.Private.texture_scoped drawable else Metal.Drawable.texture drawable)with Error e->ignore(Metal.Drawable.destroy drawable);ignore(Ogpu.Surface.discard value.portable portable);Error(Adapter.error~operation:op e)|Ok texture->let frame={surface=value;portable;drawable;texture;generation=generation value;state=Live}in value.frames<-frame::value.frames;Ok(Acquired frame)
let acquire=acquire_common~scoped:false
let validate op value frame=if destroyed value then error op Ogpu.Error.Stale_handle"surface is destroyed"else if frame.surface!=value then error op Ogpu.Error.Cross_device"frame belongs to another surface"else if frame.generation<>generation value||frame.state=Stale then error op Ogpu.Error.Stale_handle"frame generation is stale"else match frame.state with Live->Ok()|Presented|Discarded->error op Ogpu.Error.Invalid_state"frame was already consumed"|Stale->error op Ogpu.Error.Stale_handle"frame generation is stale"
let remove value frame=value.frames<-List.filter(fun candidate->candidate!=frame)value.frames
let commit_presented value (frame:frame)=let result=Ogpu.Surface.present value.portable frame.portable in frame.state<-Presented;remove value frame;result
let render_source_into_frame ?present op value frame ~queue source=match validate op value frame with Error _ as e->e|Ok()->match Presentation.render value.presentation~queue:(Queue.Private.metal queue)?present~source:(Texture.Private.metal source)~target:frame.texture()with Error _ as e->e|Ok Presentation.Completed->Ok()|Ok(Presentation.Committed_with_error e)->Error e
let present_from value frame ~queue ~source=
  let op="Ogpu_metal.Surface.present_from"in
  match validate op value frame with Error _ as e->e|Ok()->
  let committed=ref false and portable_error=ref None in
  let on_commit()=
    committed:=true;
    match commit_presented value frame with
    |Ok()->()
    |Error e->portable_error:=Some e in
  match Presentation.render value.presentation~queue:(Queue.Private.metal queue)
          ~present:frame.drawable~source:(Texture.Private.metal source)
          ~target:frame.texture~on_commit()with
  |Error _ as e->e
  |Ok outcome->
    if !committed then release frame;
    match !portable_error,outcome with
    |Some e,_->Error e
    |None,Presentation.Completed->Ok()
    |None,Presentation.Committed_with_error e->Error e
let encode_present ?(scoped=false) pending commands=
  match pending.active,pending.payload with
  |true,Some{owner=value;frame;source}->
      Presentation.encode_classic ~scoped value.presentation commands
        ~present:frame.drawable ~source:(Texture.Private.metal source)
        ~target:frame.texture ()
  |_->error"Ogpu_metal.Surface.encode_present"Ogpu.Error.Invalid_state
      "presentation slot is not prepared"
let create_pending_presentation()=
  let rec pending={payload=None;active=false;epoch=0L;
    encode=(fun commands->encode_present pending commands)}in
  pending
let pending_presentation_available value=not value.active
let prepare_present pending value frame ~source=
  let op="Ogpu_metal.Surface.prepare_present"in
  if not(pending_presentation_available pending)then
    error op Ogpu.Error.Capacity"bounded presentation slot is already in use"
  else match validate op value frame with Error _ as e->e|Ok()->
  match Texture.descriptor value.device source,Texture.format value.device source with
  |(Error _ as e),_->e|_,(Error _ as e)->e
  |Ok descriptor,Ok format->
    if format<>Texture.Rgba8_unorm then error op Ogpu.Error.Invalid_argument"presentation source must use RGBA8 format"
    else if descriptor.sample_count<>1||not(List.mem Ogpu.Types.Texture_binding descriptor.usage)then error op Ogpu.Error.Invalid_argument"presentation source must be single-sample and texture-bindable"
    else let target=Metal.Texture.descriptor frame.texture in
      if descriptor.width<>target.width||descriptor.height<>target.height then error op Ogpu.Error.Invalid_argument"presentation source and drawable extents differ"
      else match Texture.Private.retain_submission source with Error _ as e->e|Ok()->
        (match pending.payload with
         |None->pending.payload<-Some{owner=value;frame;source}
         |Some payload->payload.owner<-value;payload.frame<-frame;
             payload.source<-source);
        pending.active<-true;pending.epoch<-0L;Ok()
let presentation_encoder pending=pending.encode
let presentation_encoder_scoped pending commands=encode_present~scoped:true pending commands
let clear_pending pending=pending.active<-false;pending.epoch<-0L
let rollback_present pending=
  match pending.active,pending.payload with
  |true,Some{source;_}when pending.epoch=0L->
      Texture.Private.release_submission source;clear_pending pending
  |_->()
let commit_present pending ~epoch=
  match pending.active,pending.payload with
  |true,Some{owner=value;frame;_}when pending.epoch=0L->
      ignore(Ogpu.Surface.present value.portable frame.portable);
      frame.state<-Presented;remove value frame;
      value.in_flight_presentations<-value.in_flight_presentations+1;
      pending.epoch<-epoch
  |_->()
let commit_present_scoped pending ~epoch:_=
  match pending.active,pending.payload with
  |true,Some{owner=value;frame;source}when pending.epoch=0L->
      ignore(Ogpu.Surface.present value.portable frame.portable);
      frame.state<-Presented;remove value frame;
      (* A successfully committed retained-reference command buffer now owns
         the native drawable, texture, and source until terminal completion.
         The synchronous lane can therefore drop its scoped OCaml wrappers
         before entering the blocking wait. *)
      release frame;Texture.Private.release_submission source;
      clear_pending pending;pending.payload<-None
  |_->()
let complete_present pending=
  match pending.active,pending.payload with
  |true,Some{owner=value;frame;source}when pending.epoch<>0L->
      release frame;Texture.Private.release_submission source;
      value.in_flight_presentations<-value.in_flight_presentations-1;
      clear_pending pending;
      if value.in_flight_presentations=0&&value.destroy_pending then teardown value
  |_->()
let complete_presentations_through pending epoch=
  Array.iter(fun slot->if slot.epoch<>0L&&slot.epoch<=epoch then complete_present slot)
    pending
let clear_pending_presentations pending=
  Array.iter(fun slot->if not slot.active then slot.payload<-None)pending
let discard value frame=let op="Ogpu_metal.Surface.discard"in match validate op value frame with Error _ as e->e|Ok()->match Ogpu.Surface.discard value.portable frame.portable with Error _ as e->e|Ok()->frame.state<-Discarded;remove value frame;release frame;Ok()
let destroy value=if not(destroyed value)then if value.in_flight_presentations=0 then teardown value else(stale_frames value;value.destroy_pending<-true)
module Private=struct
  let acquire_scoped=acquire_common~scoped:true
  let create_readable device~layer config=create_common~readable_drawables_for_test:true device~layer config
  let render_for_test value ~queue ~source ~target=let op="Ogpu_metal.Surface.Private.render_for_test"in if destroyed value then error op Ogpu.Error.Stale_handle"surface is destroyed"else match Presentation.render value.presentation~queue:(Queue.Private.metal queue)~source:(Texture.Private.metal source)~target:(Texture.Private.metal target)()with Error _ as e->e|Ok Presentation.Completed->Ok()|Ok(Presentation.Committed_with_error e)->Error e
  let render_source_into_frame value frame ~queue ~source=render_source_into_frame"Ogpu_metal.Surface.Private.render_source_into_frame"value frame~queue source
  let copy_frame_for_test value frame ~queue ~target=let op="Ogpu_metal.Surface.Private.copy_frame_for_test"in match validate op value frame with Error _ as e->e|Ok()->Presentation.copy value.presentation~queue:(Queue.Private.metal queue)~source:frame.texture~target:(Texture.Private.metal target)
  type nonrec pending_presentation=pending_presentation
  let create_pending_presentation=create_pending_presentation
  let pending_presentation_available=pending_presentation_available
  let prepare_present=prepare_present
  let presentation_encoder=presentation_encoder
  let presentation_encoder_scoped=presentation_encoder_scoped
  let rollback_present=rollback_present
  let commit_present=commit_present
  let commit_present_scoped=commit_present_scoped
  let complete_presentations_through=complete_presentations_through
  let clear_pending_presentations=clear_pending_presentations
end
