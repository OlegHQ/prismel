type control={mutable next:int64;mutable epoch:int64;mutable completed:int64;mutable lost:bool;mutable fail_completion:bool;mutable fail_texture_after:int option;mutable fail_depth_after:int option;mutable fail_configure:bool;mutable trace:string list;mutable buffers:int;mutable textures:int;mutable pipelines:int;mutable queues:int;mutable surfaces:int}
let error op kind text=Error(Error.make op kind text)
let add c text=c.trace<-text::c.trace
let token c=let value=c.next in c.next<-Int64.succ value;value
let render_trace submission =
  let depth=match (Render_pass.descriptor(Render_pass.submission_pass submission)).Render_pass.depth with None->"nodepth"|Some attachment->Printf.sprintf"depth:%Ld:%s:%g"attachment.texture.id(match attachment.load with Clear->"clear"|Load->"load"|Dont_care->"discard")attachment.clear in
  let raster=Render_pass.raster_state(Render_pass.submission_pass submission)in
  let cull=match raster.cull with Cull_none->"none"|Cull_front->"front"|Cull_back->"back"and comparison=match raster.depth_compare with Never->"never"|Less->"less"|Equal->"equal"|Less_equal->"le"|Greater->"greater"|Not_equal->"ne"|Greater_equal->"ge"|Always->"always"in
  Printf.sprintf"%s:%s:%s:%b:"depth cull comparison raster.depth_write^(Render_pass.submission_draws submission
  |> List.map (fun (draw : Render_pass.draw) ->
         let index =
           match draw.index with
           | None -> "none"
           | Some (Uint16, id, offset, count) ->
               Printf.sprintf "u16:%Ld:%Ld:%d" id offset count
           | Some (Uint32, id, offset, count) ->
               Printf.sprintf "u32:%Ld:%Ld:%d" id offset count
         in
         Printf.sprintf "%s:%s:%d:%d:%s" draw.pipeline_key
           (match draw.primitive with Triangle_list -> "list" | Triangle_strip -> "strip")
           draw.vertex_start draw.vertex_count index)
  |> String.concat ";")
let required_resources=function
  |Backend.Transfer ops->Array.to_list ops|>List.concat_map(function
      |Transfer_pass.Copy_buffer(a,_,b,_,_)->[a;b]
      |Fill_buffer(a,_,_,_)->[a]
      |Buffer_to_texture(a,_,_,_,b,_,_,_)->[a;b]
      |Texture_to_buffer(a,_,_,_,b,_,_,_)->[a;b]
      |Copy_texture(a,_,_,b,_,_,_)->[a;b])
  |Compute description->Array.to_list description.Compute_pass.commands
      |>List.filter_map(function Command.Declare_resource r->Some r.resource_id|_->None)
  |Render submission->
      let descriptor=Render_pass.descriptor(Render_pass.submission_pass submission)in
      (Array.to_list descriptor.Render_pass.colors|>List.filter_map(function
        |None->None|Some(attachment:Render_pass.color)->Some attachment.texture.id))@
      (Render_pass.submission_draws submission|>List.concat_map(fun(draw:Render_pass.draw)->
        List.map(fun(binding:Render_pass.buffer_binding)->binding.buffer_id)draw.buffers@
        List.map(fun(binding:Render_pass.texture_binding)->binding.texture_id)draw.textures@
        match draw.index with None->[]|Some(_,id,_,_)->[id]))
let pipeline_graph_valid command pipelines=match command with
  |Backend.Transfer _->true
  |Compute _->pipelines<>[]
  |Render submission->
      List.length pipelines=List.length(List.sort_uniq String.compare
        (List.map(fun(draw:Render_pass.draw)->draw.pipeline_key)
          (Render_pass.submission_draws submission)))
let mock_submit c ~operation ~commit command ~resources ~pipelines=
  if c.lost then error operation Error.Device_lost"injected device loss"
  else
    let ids=List.map fst resources in
    if List.exists(fun id->not(List.mem id ids))(required_resources command)then
      error operation Error.Invalid_argument"command resource is absent"
    else if not(pipeline_graph_valid command pipelines)then
      error operation Error.Invalid_argument"pipeline graph differs from draws"
    else begin
      (match command with
       |Render submission->add c("render:"^render_trace submission)
       |Transfer _|Compute _->());
      c.epoch<-Int64.succ c.epoch;
      add c(commit c.epoch);
      Ok{Backend.epoch=c.epoch}
    end
let create ?(capabilities=Capabilities.minimum_m1)()=
  let c={next=1L;epoch=0L;completed=0L;lost=false;fail_completion=false;fail_texture_after=None;fail_depth_after=None;fail_configure=false;trace=[];buffers=0;textures=0;pipelines=0;queues=0;surfaces=0}in
  let should_fail field=match field with Some 0->true|None|Some _->false in
  let advance field=match field with None->None|Some 0->None|Some remaining->Some(remaining-1)in
  let resource kind count set size=let id=token c and bytes=Bytes.make size '\000' in set(count+1);add c(Printf.sprintf"create-%s:%Ld"kind id);let range offset length=offset>=0L&&length>=0&&length<=size&&offset<=Int64.of_int(size-length)in let read_into offset destination destination_offset length=if not(range offset length)||destination_offset<0||length>Bytes.length destination-destination_offset then error"Backend_mock.read_into"Error.Invalid_argument"range"else(Bytes.blit bytes(Int64.to_int offset)destination destination_offset length;Ok())in Ok{Backend.token=id;write=(fun offset source->if not(range offset(Bytes.length source))then error"Backend_mock.write"Error.Invalid_argument"range"else(Bytes.blit source 0 bytes(Int64.to_int offset)(Bytes.length source);Ok()));read=(fun offset length->if not(range offset length)then error"Backend_mock.read"Error.Invalid_argument"range"else Ok(Bytes.sub bytes(Int64.to_int offset)length));read_into;destroy=(fun()->set((if kind="buffer"then c.buffers else c.textures)-1);add c(Printf.sprintf"destroy-%s:%Ld"kind id);Ok())}in
  let create_device()=let device_token=token c and device_handle=Handle.create_device()in Ok{Backend.device_token;device_handle;capabilities;
    create_buffer=(fun d->resource"buffer"c.buffers(fun n->c.buffers<-n)(Int64.to_int d.Types.size));
    create_texture=(fun d->if should_fail c.fail_texture_after then(c.fail_texture_after<-None;error"Backend_mock.create_texture"Error.Capacity"injected texture allocation failure")else(c.fail_texture_after<-advance c.fail_texture_after;resource"texture"c.textures(fun n->c.textures<-n)(d.Types.width*d.height*4)));
    create_depth_texture=(fun _d->if should_fail c.fail_depth_after then(c.fail_depth_after<-None;error"Backend_mock.create_depth_texture"Error.Capacity"injected depth allocation failure")else(c.fail_depth_after<-advance c.fail_depth_after;let id=token c in c.textures<-c.textures+1;add c(Printf.sprintf"create-depth-texture:%Ld"id);Ok{Backend.token=id;write=(fun _ _->error"Backend_mock.depth.write"Error.Unsupported"depth textures are not host writable");read=(fun _ _->error"Backend_mock.depth.read"Error.Unsupported"depth textures are not host readable");read_into=(fun _ _ _ _->error"Backend_mock.depth.read_into"Error.Unsupported"depth textures are not host readable");destroy=(fun()->c.textures<-c.textures-1;add c(Printf.sprintf"destroy-depth-texture:%Ld"id);Ok())}));
    create_stencil_texture=(fun _d->let id=token c in c.textures<-c.textures+1;add c(Printf.sprintf"create-stencil-texture:%Ld"id);Ok{Backend.token=id;write=(fun _ _->error"Backend_mock.stencil.write"Error.Unsupported"stencil textures are not host writable");read=(fun _ _->error"Backend_mock.stencil.read"Error.Unsupported"stencil textures are not host readable");read_into=(fun _ _ _ _->error"Backend_mock.stencil.read_into"Error.Unsupported"stencil textures are not host readable");destroy=(fun()->c.textures<-c.textures-1;add c(Printf.sprintf"destroy-stencil-texture:%Ld"id);Ok())});
    create_pipeline=(fun p->let id=token c in c.pipelines<-c.pipelines+1;add c("pipeline:"^Pipeline.cache_key p);Ok{pipeline_token=id;destroy_pipeline=(fun()->c.pipelines<-c.pipelines-1;Ok())});
    create_queue=(fun()->let id=token c in c.queues<-c.queues+1;let complete_through epoch=if epoch<=c.completed||epoch>c.epoch then error"Backend_mock.complete"Error.Invalid_argument"epoch is invalid"else(c.completed<-epoch;add c(Printf.sprintf"complete:%Ld"epoch);if c.fail_completion then(c.fail_completion<-false;error"Backend_mock.complete"Error.Device_lost"injected terminal completion failure")else Ok())in let submit command~resources~pipelines=mock_submit c~operation:"Backend_mock.submit"~commit:(fun epoch->Printf.sprintf"submit:%Ld"epoch)command~resources~pipelines in let submit_sync command~resources~pipelines=match submit command~resources~pipelines with Error _ as e->e|Ok receipt->Ok{Backend.receipt;completion=complete_through receipt.epoch}in Ok{queue_token=id;submit;submit_sync;complete_through;destroy_queue=(fun()->c.queues<-c.queues-1;Ok())});
    create_surface=(fun _->let id=token c and frame=ref 0L in c.surfaces<-c.surfaces+1;let submit_present~queue~source command~resources~pipelines frame=mock_submit c~operation:"Backend_mock.submit_present"~commit:(fun epoch->Printf.sprintf"submit-present:%Ld:%Ld:%Ld:%Ld"queue source frame.Backend.frame_token epoch)command~resources~pipelines in let submit_present_sync~queue~source command~resources~pipelines frame=match submit_present~queue~source command~resources~pipelines frame with Error _ as e->e|Ok receipt->c.completed<-receipt.epoch;add c(Printf.sprintf"complete:%Ld"receipt.epoch);let completion=if c.fail_completion then(c.fail_completion<-false;error"Backend_mock.complete"Error.Device_lost"injected terminal completion failure")else Ok()in Ok{Backend.receipt;completion}in let acquire()=if c.lost then Ok`Device_lost else(frame:=Int64.succ !frame;Ok(`Acquired({Backend.frame_token = !frame}:Backend.driver_frame)))in Ok({surface_token=id;configure=(fun _->if c.fail_configure then(c.fail_configure<-false;error"Backend_mock.configure"Error.Invalid_state"injected configure failure")else Ok());acquire;acquire_sync=acquire;present=(fun ~queue ~source _->add c(Printf.sprintf"present:%Ld:%Ld"queue source);Ok());submit_present;submit_present_sync;discard=(fun _->add c"discard";Ok());destroy_surface=(fun()->c.surfaces<-c.surfaces-1;Ok())}:Backend.driver_surface));destroy_device=(fun()->Handle.destroy_device device_handle;add c"destroy-device";Ok())}in
  {Backend.create_device},c
let inject_device_loss c=c.lost<-true
let fail_texture_allocation_after c count=if count<0 then invalid_arg"negative allocation count"else c.fail_texture_after<-Some count
let fail_depth_allocation_after c count=if count<0 then invalid_arg"negative allocation count"else c.fail_depth_after<-Some count
let fail_next_configure c=c.fail_configure<-true
let inject_next_completion_error c=c.fail_completion<-true
let trace c=List.rev c.trace
let clear_trace c=c.trace<-[]
let live_counts c=c.buffers,c.textures,c.pipelines,c.queues,c.surfaces
