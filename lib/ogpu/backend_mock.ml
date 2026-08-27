type control={mutable next:int64;mutable epoch:int64;mutable completed:int64;mutable lost:bool;mutable trace:string list;mutable buffers:int;mutable textures:int;mutable pipelines:int;mutable queues:int;mutable surfaces:int}
let error op kind text=Error(Error.make op kind text)
let add c text=c.trace<-text::c.trace
let token c=let value=c.next in c.next<-Int64.succ value;value
let create ?(capabilities=Capabilities.minimum_m1)()=
  let c={next=1L;epoch=0L;completed=0L;lost=false;trace=[];buffers=0;textures=0;pipelines=0;queues=0;surfaces=0}in
  let resource kind count set=let id=token c in set(count+1);add c(Printf.sprintf"create-%s:%Ld"kind id);Ok{Backend.token=id;destroy=(fun()->set((if kind="buffer"then c.buffers else c.textures)-1);add c(Printf.sprintf"destroy-%s:%Ld"kind id);Ok())}in
  let create_device()=let device_token=token c in Ok{Backend.device_token;capabilities;
    create_buffer=(fun _->resource"buffer"c.buffers(fun n->c.buffers<-n));
    create_texture=(fun _->resource"texture"c.textures(fun n->c.textures<-n));
    create_pipeline=(fun p->let id=token c in c.pipelines<-c.pipelines+1;add c("pipeline:"^Pipeline.cache_key p);Ok{pipeline_token=id;destroy_pipeline=(fun()->c.pipelines<-c.pipelines-1;Ok())});
    create_queue=(fun()->let id=token c in c.queues<-c.queues+1;Ok{queue_token=id;submit=(fun command~resources~pipelines->if c.lost then error"Backend_mock.submit"Error.Device_lost"injected device loss"else let ids=List.map fst resources in let required=match command with Backend.Transfer ops->Array.to_list ops|>List.concat_map(function Transfer_pass.Copy_buffer(a,_,b,_,_)->[a;b]|Fill_buffer(a,_,_,_)->[a]|Buffer_to_texture(a,_,_,_,b,_,_,_)->[a;b]|Texture_to_buffer(a,_,_,_,b,_,_,_)->[a;b]|Copy_texture(a,_,_,b,_,_,_)->[a;b])|Compute d->Array.to_list d.Compute_pass.commands|>List.filter_map(function Command.Declare_resource r->Some r.resource_id|_->None)|Render d->Array.to_list d.Render_pass.colors|>List.filter_map(function None->None|Some(a:Render_pass.color)->Some a.texture.id)in if List.exists(fun id->not(List.mem id ids))required then error"Backend_mock.submit"Error.Invalid_argument"command resource is absent"else if(match command with Transfer _->false|Compute _|Render _->pipelines=[])then error"Backend_mock.submit"Error.Invalid_argument"pipeline is absent"else(c.epoch<-Int64.succ c.epoch;add c(Printf.sprintf"submit:%Ld"c.epoch);Ok{Backend.epoch=c.epoch}));complete_through=(fun epoch->if epoch<=c.completed||epoch>c.epoch then error"Backend_mock.complete"Error.Invalid_argument"epoch is invalid"else(c.completed<-epoch;add c(Printf.sprintf"complete:%Ld"epoch);Ok()));destroy_queue=(fun()->c.queues<-c.queues-1;Ok())});
    create_surface=(fun _->let id=token c and frame=ref 0L in c.surfaces<-c.surfaces+1;Ok({surface_token=id;configure=(fun _->Ok());acquire=(fun()->if c.lost then Ok`Device_lost else(frame:=Int64.succ !frame;Ok(`Acquired({Backend.frame_token = !frame}:Backend.driver_frame))));present=(fun _->add c"present";Ok());discard=(fun _->add c"discard";Ok());destroy_surface=(fun()->c.surfaces<-c.surfaces-1;Ok())}:Backend.driver_surface));destroy_device=(fun()->add c"destroy-device";Ok())}in
  {Backend.create_device},c
let inject_device_loss c=c.lost<-true
let trace c=List.rev c.trace
let live_counts c=c.buffers,c.textures,c.pipelines,c.queues,c.surfaces
