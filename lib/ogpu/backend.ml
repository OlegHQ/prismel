type token=int64
type command=Transfer of Transfer_pass.description array|Compute of Compute_pass.description|Render of Render_pass.submission
type receipt={epoch:int64}
type driver_resource={token:token;write:int64->bytes->(unit,Error.t)result;read:int64->int->(bytes,Error.t)result;destroy:unit->(unit,Error.t)result}
type driver_pipeline={pipeline_token:token;destroy_pipeline:unit->(unit,Error.t)result}
type driver_frame={frame_token:token}
type driver_surface={surface_token:token;configure:Surface.configuration->(unit,Error.t)result;acquire:unit->([`Acquired of driver_frame|`Timeout|`Occluded|`Device_lost],Error.t)result;present:driver_frame->(unit,Error.t)result;discard:driver_frame->(unit,Error.t)result;destroy_surface:unit->(unit,Error.t)result}
type driver_queue={queue_token:token;submit:command->resources:(int64*token)list->pipelines:token list->(receipt,Error.t)result;complete_through:int64->(unit,Error.t)result;destroy_queue:unit->(unit,Error.t)result}
type driver_device={device_token:token;device_handle:Handle.device;capabilities:Capabilities.t;create_buffer:Types.buffer_descriptor->(driver_resource,Error.t)result;create_texture:Types.texture_descriptor->(driver_resource,Error.t)result;create_depth_texture:Types.texture_descriptor->(driver_resource,Error.t)result;create_pipeline:Pipeline.t->(driver_pipeline,Error.t)result;create_queue:unit->(driver_queue,Error.t)result;create_surface:Surface.configuration->(driver_surface,Error.t)result;destroy_device:unit->(unit,Error.t)result}
type driver={create_device:unit->(driver_device,Error.t)result}
type device={raw:driver_device;handle:Handle.device;mutable children:int;mutable dead:bool}
type resource={raw:driver_resource;handle:unit Handle.t;device:device;mutable dead:bool}
type buffer={resource:resource;buffer_descriptor:Types.buffer_descriptor}
type texture={resource:resource;texture_descriptor:Types.texture_descriptor}
type pipeline={pipeline_driver:driver_pipeline;device:device;mutable dead:bool}
type queue={raw:driver_queue;device:device;mutable dead:bool}
type surface={raw:driver_surface;device:device;mutable dead:bool;mutable frames:int}
type frame={raw:driver_frame;surface:surface;mutable consumed:bool}
let error op kind text=Error(Error.make op kind text)
let create_device driver=match driver.create_device()with Error _ as e->e|Ok raw->match Capabilities.validate raw.capabilities with Error _ as e->e|Ok()->Ok{raw;handle=raw.device_handle;children=0;dead=false}
let capabilities (value:device)=value.raw.capabilities
let device_handle (value:device)=value.handle
let live op (device:device)=if device.dead then error op Error.Stale_handle"device is destroyed"else Ok()
let make_resource (device:device) raw={raw;handle=Handle.create~device:device.handle;device;dead=false}
let create_buffer device descriptor=match live"Backend.create_buffer"device with Error _ as e->e|Ok()->match Types.validate_buffer device.raw.capabilities descriptor with Error _ as e->e|Ok()->match device.raw.create_buffer descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;buffer_descriptor=descriptor}
let create_texture device descriptor=match live"Backend.create_texture"device with Error _ as e->e|Ok()->match Types.validate_texture device.raw.capabilities descriptor with Error _ as e->e|Ok()->match device.raw.create_texture descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;texture_descriptor=descriptor}
let create_depth_texture device descriptor=match live"Backend.create_depth_texture"device with Error _ as e->e|Ok()->match Types.validate_texture device.raw.capabilities descriptor with Error _ as e->e|Ok() when not(List.mem Types.Render_attachment descriptor.usage)||List.exists(fun usage->usage<>Types.Render_attachment)descriptor.usage->error"Backend.create_depth_texture"Error.Invalid_argument"depth textures are render-attachment only"|Ok()->match device.raw.create_depth_texture descriptor with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{resource=make_resource device raw;texture_descriptor=descriptor}
let adopt_pipeline device portable=match live"Backend.adopt_pipeline"device with Error _ as e->e|Ok()->match device.raw.create_pipeline portable with Error _ as e->e|Ok pipeline_driver->device.children<-device.children+1;Ok{pipeline_driver;device;dead=false}
let create_queue device=match live"Backend.create_queue"device with Error _ as e->e|Ok()->match device.raw.create_queue()with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{raw;device;dead=false}
let create_surface device configuration=match live"Backend.create_surface"device with Error _ as e->e|Ok()->match Surface.create device.handle configuration with Error _ as e->e|Ok portable->Surface.destroy portable;(match device.raw.create_surface configuration with Error _ as e->e|Ok raw->device.children<-device.children+1;Ok{raw;device;dead=false;frames=0})
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
let transfer pass=Result.map(fun x->Transfer x)(Transfer_pass.finish pass)
let compute pass=Compute(Compute_pass.describe pass)
let render pass draws=Result.map(fun submission->Render submission)(Render_pass.submit pass draws)
let resource_pair=function `Buffer(b:buffer)->Handle.id b.resource.handle,b.resource|`Texture(t:texture)->Handle.id t.resource.handle,t.resource
let submit (queue:queue) command ~resources ~pipelines=let op="Backend.submit"in match live op queue.device with Error _ as e->e|Ok()when queue.dead->error op Error.Stale_handle"queue is destroyed"|Ok()->let pairs=List.map resource_pair resources in if List.exists(fun(_,r:token*resource)->r.dead)pairs||List.exists(fun(p:pipeline)->p.dead)pipelines then error op Error.Stale_handle"submitted graph contains a destroyed object"else if List.exists(fun(_,r:token*resource)->r.device!=queue.device)pairs||List.exists(fun(p:pipeline)->p.device!=queue.device)pipelines then error op Error.Cross_device"submitted graph contains a foreign object"else queue.raw.submit command~resources:(List.map(fun(id,(r:resource))->id,r.raw.token)pairs)~pipelines:(List.map(fun(p:pipeline)->p.pipeline_driver.pipeline_token)pipelines)
let complete_through (queue:queue) epoch=if queue.dead then error"Backend.complete_through"Error.Stale_handle"queue is destroyed"else queue.raw.complete_through epoch
let configure (surface:surface) value=if surface.dead then error"Backend.configure"Error.Stale_handle"surface is destroyed"else if surface.frames<>0 then error"Backend.configure"Error.Invalid_state"surface has acquired frames"else surface.raw.configure value
let acquire (surface:surface)=if surface.dead then error"Backend.acquire"Error.Stale_handle"surface is destroyed"else match surface.raw.acquire()with Error _ as e->e|Ok(`Acquired raw)->surface.frames<-surface.frames+1;Ok(`Acquired{raw;surface;consumed=false})|Ok`Timeout->Ok`Timeout|Ok`Occluded->Ok`Occluded|Ok`Device_lost->Ok`Device_lost
let consume op action (frame:frame)=if frame.consumed then error op Error.Invalid_state"frame is already consumed"else if frame.surface.dead then error op Error.Stale_handle"surface is destroyed"else match action frame.raw with Error _ as e->e|Ok()->frame.consumed<-true;frame.surface.frames<-frame.surface.frames-1;Ok()
let present frame=consume"Backend.present"frame.surface.raw.present frame
let discard frame=consume"Backend.discard"frame.surface.raw.discard frame
let destroy_resource (resource:resource)=if resource.dead then Ok()else match resource.raw.destroy()with Error _ as e->e|Ok()->resource.dead<-true;Handle.destroy resource.handle;resource.device.children<-resource.device.children-1;Ok()
let destroy_buffer (value:buffer)=destroy_resource value.resource
let destroy_texture (value:texture)=destroy_resource value.resource
let destroy_pipeline (value:pipeline)=if value.dead then Ok()else match value.pipeline_driver.destroy_pipeline()with Error _ as e->e|Ok()->value.dead<-true;value.device.children<-value.device.children-1;Ok()
let destroy_queue (value:queue)=if value.dead then Ok()else match value.raw.destroy_queue()with Error _ as e->e|Ok()->value.dead<-true;value.device.children<-value.device.children-1;Ok()
let destroy_surface (value:surface)=if value.dead then Ok()else if value.frames<>0 then error"Backend.destroy_surface"Error.Invalid_state"surface has acquired frames"else match value.raw.destroy_surface()with Error _ as e->e|Ok()->value.dead<-true;value.device.children<-value.device.children-1;Ok()
let destroy_device (value:device)=if value.dead then Ok()else if value.children<>0 then error"Backend.destroy_device"Error.Invalid_state"device has live children"else match value.raw.destroy_device()with Error _ as e->e|Ok()->value.dead<-true;Ok()
