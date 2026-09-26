open Ogpu_core
type queue_clock={mutable epoch:int64;mutable completed:int64;mutable deferred:(unit->(unit,Error.t)result)list}
(* Sentinel for a recorded event wait whose value is not reached yet. *)
let blocked_message="event value is not reached yet"
type texture_storage={descriptor:Types.texture_descriptor;levels:bytes array}
type control={mutable next:int64;queue_clocks:(int64,queue_clock)Hashtbl.t;memory:(int64,bytes)Hashtbl.t;texture_storage:(int64,texture_storage)Hashtbl.t;lost:bool;mutable fail_submission:bool;mutable fail_completion:bool;mutable fail_texture_after:int option;mutable fail_depth_after:int option;mutable fail_configure:bool;mutable trace:string list;mutable buffers:int;mutable textures:int;mutable pipelines:int;mutable queues:int;mutable surfaces:int}
let error op kind text=Error(Error.make op kind text)
let add c text=c.trace<-text::c.trace
let token c=let value=c.next in c.next<-Int64.succ value;value
let mip_extent value mip=max 1 (value lsr mip)
let texture_level_size (d:Types.texture_descriptor) mip=
  let texels=Int64.mul
    (Int64.of_int(mip_extent d.width mip))
    (Int64.mul (Int64.of_int(mip_extent d.height mip))
      (Int64.of_int(mip_extent d.depth mip))) in
  if texels>Int64.of_int(Sys.max_string_length/4) then None
  else Some(Int64.to_int texels*4)
(* Blit operations recorded by the mock encoder and replayed at commit. *)
type transfer=
  |Buffer_to_texture of int64*int64*int64*int64*int64*int*Types.origin*Types.extent
  |Texture_to_buffer of int64*int*Types.origin*Types.extent*int64*int64*int64*int64
  |Copy_texture of int64*int*Types.origin*int64*int*Types.origin*Types.extent
let execute_transfer c resources description =
  let op="Backend_mock.transfer" in
  let range bytes offset length =
    offset>=0L && length>=0L &&
    offset<=Int64.of_int(Bytes.length bytes) &&
    length<=Int64.sub (Int64.of_int(Bytes.length bytes)) offset in
  let product a b=
    if a<0L || b<0L || (b<>0L && a>Int64.div Int64.max_int b)
    then None else Some(Int64.mul a b) in
  let sum a b=
    if a<0L || b<0L || a>Int64.sub Int64.max_int b
    then None else Some(Int64.add a b) in
  let buffer_region bytes offset row image (extent:Types.extent)=
    let width=Int64.of_int extent.width in
    let height=Int64.of_int extent.height in
    let depth=Int64.of_int extent.depth in
    if width<=0L || height<=0L || depth<=0L then false
    else match product width 4L,product row height with
      |Some pixels,Some minimum_image
        when row>=pixels && image>=minimum_image->
          (match product image (Int64.pred depth),
                 product row (Int64.pred height) with
           |Some slices,Some rows->
               (match sum slices rows with
                |None->false
                |Some span->match sum span pixels with
                  |None->false
                  |Some span->range bytes offset span)
           |_->false)
      |_->false in
  let bytes id=
    match List.assoc_opt id resources with
    |None->error op Error.Invalid_argument"command resource is absent"
    |Some token->match Hashtbl.find_opt c.memory token with
      |Some bytes->Ok bytes
      |None->error op Error.Stale_handle"command resource is destroyed" in
  let texture id=
    match List.assoc_opt id resources with
    |None->error op Error.Invalid_argument"command resource is absent"
    |Some token->match Hashtbl.find_opt c.texture_storage token with
      |Some storage->Ok storage
      |None->error op Error.Invalid_argument"resource is not a color texture" in
  let valid_region storage mip (origin:Types.origin)
      (extent:Types.extent)=
    mip>=0 && mip<Array.length storage.levels &&
    let width=mip_extent storage.descriptor.width mip in
    let height=mip_extent storage.descriptor.height mip in
    let depth=mip_extent storage.descriptor.depth mip in
    origin.x>=0 && origin.y>=0 && origin.z>=0 &&
    extent.width>0 && extent.height>0 && extent.depth>0 &&
    origin.x<=width-extent.width &&
    origin.y<=height-extent.height &&
    origin.z<=depth-extent.depth in
  let texture_offset storage mip (origin:Types.origin)=
    let width=mip_extent storage.descriptor.width mip in
    let height=mip_extent storage.descriptor.height mip in
    ((origin.z*height+origin.y)*width+origin.x)*4 in
  let copy_rows ~source ~source_offset ~source_row ~source_image
      ~target ~target_offset ~target_row ~target_image
      (extent:Types.extent)=
    for z=0 to extent.depth-1 do
      for y=0 to extent.height-1 do
        Bytes.blit source (source_offset+z*source_image+y*source_row)
          target (target_offset+z*target_image+y*target_row)
          (extent.width*4)
      done
    done in
  begin match description with
          |Buffer_to_texture(src,offset,row,image,dst,mip,
              origin,extent)->
              Result.bind (bytes src) (fun source->
                Result.bind (texture dst) (fun target->
                  if not(valid_region target mip origin extent &&
                    buffer_region source offset row image extent) then
                    error op Error.Invalid_argument"texture upload range is invalid"
                  else begin
                    let width=mip_extent target.descriptor.width mip in
                    let height=mip_extent target.descriptor.height mip in
                    copy_rows ~source ~source_offset:(Int64.to_int offset)
                      ~source_row:(Int64.to_int row)
                      ~source_image:(Int64.to_int image)
                      ~target:target.levels.(mip)
                      ~target_offset:(texture_offset target mip origin)
                      ~target_row:(width*4) ~target_image:(width*height*4)
                      extent;
                    Ok()
                  end))
          |Texture_to_buffer(src,mip,origin,extent,dst,
              offset,row,image)->
              Result.bind (texture src) (fun source->
                Result.bind (bytes dst) (fun target->
                  if not(valid_region source mip origin extent &&
                    buffer_region target offset row image extent) then
                    error op Error.Invalid_argument"texture readback range is invalid"
                  else begin
                    let width=mip_extent source.descriptor.width mip in
                    let height=mip_extent source.descriptor.height mip in
                    copy_rows ~source:source.levels.(mip)
                      ~source_offset:(texture_offset source mip origin)
                      ~source_row:(width*4) ~source_image:(width*height*4)
                      ~target ~target_offset:(Int64.to_int offset)
                      ~target_row:(Int64.to_int row)
                      ~target_image:(Int64.to_int image) extent;
                    Ok()
                  end))
          |Copy_texture(src,src_mip,src_origin,dst,dst_mip,
              dst_origin,extent)->
              Result.bind (texture src) (fun source->
                Result.bind (texture dst) (fun target->
                  if not(valid_region source src_mip src_origin extent &&
                    valid_region target dst_mip dst_origin extent) then
                    error op Error.Invalid_argument"texture copy range is invalid"
                  else begin
                    let source_bytes=source.levels.(src_mip) in
                    (* ponytail: self-copy snapshots one whole mip; stage only
                       the touched rows if large mock textures need less memory. *)
                    let source_bytes=if source_bytes==target.levels.(dst_mip)
                      then Bytes.copy source_bytes else source_bytes in
                    let src_width=mip_extent source.descriptor.width src_mip in
                    let src_height=mip_extent source.descriptor.height src_mip in
                    let dst_width=mip_extent target.descriptor.width dst_mip in
                    let dst_height=mip_extent target.descriptor.height dst_mip in
                    copy_rows ~source:source_bytes
                      ~source_offset:(texture_offset source src_mip src_origin)
                      ~source_row:(src_width*4)
                      ~source_image:(src_width*src_height*4)
                      ~target:target.levels.(dst_mip)
                      ~target_offset:(texture_offset target dst_mip dst_origin)
                      ~target_row:(dst_width*4)
                      ~target_image:(dst_width*dst_height*4) extent;
                    Ok()
                  end))
  end
let transfer_one=execute_transfer
let create ?(capabilities=Caps.minimum_m1)()=
  let capabilities={capabilities with Caps.compute_pipeline=false;render_pipeline=false;ray_tracing=false;function_tables=false;ray_tracing_curves=false;
    heaps=false;residency_sets=false;fences=true;event_synchronization=true;timestamp_queries=false;
    mesh_shaders=false;tile_shaders=false;dynamic_libraries=false;binary_archives=false;sparse_memory=false;metal_fx=false} in
  (* Fences are satisfied by the mock's serial execution; events are host counters. *)
  let fences:(int64,unit)Hashtbl.t=Hashtbl.create 4 and events:(int64,int64 ref)Hashtbl.t=Hashtbl.create 4 in
  let unsupported op=error("Backend_mock."^op)Error.Unsupported"mock backend leaves this feature unsupported" in
  let fence_call op token=if Hashtbl.mem fences token then Ok()else error("Backend_mock."^op)Error.Stale_handle"fence is destroyed" in
  (* Runs recorded operations in order; an event wait that is not yet
     satisfied parks the rest until the host polls, completes, or waits. *)
  let run_ops clock ops=
    let rec go=function
      |[]->Ok()
      |op::rest->(match op()with
        |Ok()->go rest
        |Error(e:Error.t)when e.message==blocked_message->clock.deferred<-clock.deferred@(op::rest);Ok()
        |Error _ as failure->failure)in
    go ops in
  let run_deferred clock=
    let ops=clock.deferred in clock.deferred<-[];
    match run_ops clock ops with
    |Ok()when clock.deferred<>[]->error"Backend_mock.complete"Error.Invalid_state"mock cannot block on an unsignaled event"
    |result->result in

  let c={next=1L;queue_clocks=Hashtbl.create 4;memory=Hashtbl.create 16;texture_storage=Hashtbl.create 8;lost=false;fail_submission=false;fail_completion=false;fail_texture_after=None;fail_depth_after=None;fail_configure=false;trace=[];buffers=0;textures=0;pipelines=0;queues=0;surfaces=0}in
  let drain_all()=Hashtbl.iter(fun _ clock->ignore(run_deferred clock))c.queue_clocks in
  let should_fail field=match field with Some 0->true|None|Some _->false in
  let advance field=match field with None->None|Some 0->None|Some remaining->Some(remaining-1)in
  let resource kind count set size=let id=token c and bytes=Bytes.make size '\000' in Hashtbl.add c.memory id bytes;set(count+1);add c(Printf.sprintf"create-%s:%Ld"kind id);let range offset length=offset>=0L&&length>=0&&length<=size&&offset<=Int64.of_int(size-length)in let read_into offset destination destination_offset length=if not(range offset length)||destination_offset<0||length>Bytes.length destination-destination_offset then error"Backend_mock.read_into"Error.Invalid_argument"range"else(Bytes.blit bytes(Int64.to_int offset)destination destination_offset length;Ok())in Ok{Backend.token=id;write=(fun offset source->if not(range offset(Bytes.length source))then error"Backend_mock.write"Error.Invalid_argument"range"else(Bytes.blit source 0 bytes(Int64.to_int offset)(Bytes.length source);Ok()));read=(fun offset length->if not(range offset length)then error"Backend_mock.read"Error.Invalid_argument"range"else Ok(Bytes.sub bytes(Int64.to_int offset)length));read_into;destroy=(fun()->Hashtbl.remove c.memory id;Hashtbl.remove c.texture_storage id;set((if kind="buffer"then c.buffers else c.textures)-1);add c(Printf.sprintf"destroy-%s:%Ld"kind id);Ok())}in
  let create_device()=let device_token=token c and device_handle=Handle.create_device()in Ok{Backend.device_token;device_handle;capabilities;
    create_buffer=(fun _memory d->resource"buffer"c.buffers(fun n->c.buffers<-n)(Int64.to_int d.Types.size));
    create_library=(fun _shader ~dynamic:_->
      let id=token c in
      c.pipelines<-c.pipelines+1;
      add c(Printf.sprintf"create-library:%Ld"id);
      Ok{Backend.library_token=id;
        create_compute_pipeline_in=(fun ~entry:_ ~constants:_ ~interface:_ ~linked:_ ~archives:_ ~archive_only:_->
          error"Backend_mock.create_compute_pipeline_in"Error.Unsupported
            "mock backend does not execute compute shaders");
        destroy_library=(fun()->c.pipelines<-c.pipelines-1;
          add c(Printf.sprintf"destroy-library:%Ld"id);Ok())});
    create_accel=(fun _->error"Backend_mock.create_accel"Error.Unsupported
      "mock backend has no ray tracing");
    create_sampler=(fun _->
      let id=token c in
      c.pipelines<-c.pipelines+1;
      add c(Printf.sprintf"create-sampler:%Ld"id);
      Ok{Backend.sampler_token=id;destroy_sampler=(fun()->c.pipelines<-c.pipelines-1;
        add c(Printf.sprintf"destroy-sampler:%Ld"id);Ok())});
    create_render_pipeline=(fun _ _->error"Backend_mock.create_render_pipeline"Error.Unsupported
      "mock backend does not rasterize");
    create_icb=(fun ~max_commands:_->error"Backend_mock.create_icb"Error.Unsupported
      "mock backend does not rasterize");
    create_argument=(fun ~pipeline:_ _ ~index:_->error"Backend_mock.create_argument"Error.Unsupported
      "mock backend does not rasterize");
    (* The mock mirrors Metal's documented instance record layouts. *)
    instance_layout=(function
      |Backend.Default_instances->[|64;0;48;52;56;60;-1;-1;-1;-1;-1;-1;-1|]
      |User_id_instances->[|68;0;48;52;56;60;64;-1;-1;-1;-1;-1;-1|]
      |Motion_instances->[|44;-1;8;12;16;20;24;0;4;28;32;36;40|]);
    create_texture=(fun d->
      let operation="Backend_mock.create_texture" in
      if should_fail c.fail_texture_after then begin
        c.fail_texture_after<-None;
        error operation Error.Capacity"injected texture allocation failure"
      end else begin
        c.fail_texture_after<-advance c.fail_texture_after;
        match texture_level_size d 0 with
        |None->error operation Error.Capacity"texture exceeds mock byte capacity"
        |Some size->
            match resource"texture"c.textures(fun n->c.textures<-n)size with
            |Error _ as failure->failure
            |Ok raw->
                (try
                   let levels=Array.init d.mip_levels (fun mip->
                     if mip=0 then Hashtbl.find c.memory raw.token
                     else match texture_level_size d mip with
                       |None->raise Out_of_memory
                       |Some size->Bytes.make size '\000') in
                   Hashtbl.add c.texture_storage raw.token
                     {descriptor=d;levels};
                   Ok raw
                 with Out_of_memory ->
                   ignore(raw.destroy());
                   error operation Error.Capacity
                     "texture exceeds mock byte capacity")
      end);
    create_depth_texture=(fun _d->if should_fail c.fail_depth_after then(c.fail_depth_after<-None;error"Backend_mock.create_depth_texture"Error.Capacity"injected depth allocation failure")else(c.fail_depth_after<-advance c.fail_depth_after;let id=token c in c.textures<-c.textures+1;add c(Printf.sprintf"create-depth-texture:%Ld"id);Ok{Backend.token=id;write=(fun _ _->error"Backend_mock.depth.write"Error.Unsupported"depth textures are not host writable");read=(fun _ _->error"Backend_mock.depth.read"Error.Unsupported"depth textures are not host readable");read_into=(fun _ _ _ _->error"Backend_mock.depth.read_into"Error.Unsupported"depth textures are not host readable");destroy=(fun()->c.textures<-c.textures-1;add c(Printf.sprintf"destroy-depth-texture:%Ld"id);Ok())}));
    create_stencil_texture=(fun _d->let id=token c in c.textures<-c.textures+1;add c(Printf.sprintf"create-stencil-texture:%Ld"id);Ok{Backend.token=id;write=(fun _ _->error"Backend_mock.stencil.write"Error.Unsupported"stencil textures are not host writable");read=(fun _ _->error"Backend_mock.stencil.read"Error.Unsupported"stencil textures are not host readable");read_into=(fun _ _ _ _->error"Backend_mock.stencil.read_into"Error.Unsupported"stencil textures are not host readable");destroy=(fun()->c.textures<-c.textures-1;add c(Printf.sprintf"destroy-stencil-texture:%Ld"id);Ok())});
    create_queue=(fun()->
      let id=token c and clock={epoch=0L;completed=0L;deferred=[]} in
      let run=run_ops clock and run_deferred()=run_deferred clock in
      c.queues<-c.queues+1;
      Hashtbl.add c.queue_clocks id clock;
      let complete_through epoch=
        if epoch<=clock.completed||epoch>clock.epoch then
          error"Backend_mock.complete"Error.Invalid_argument"epoch is invalid"
        else match run_deferred()with Error _ as failure->failure|Ok()->begin
          clock.completed<-epoch;
          add c(Printf.sprintf"complete:%Ld"epoch);
          if c.fail_completion then begin
            c.fail_completion<-false;
            error"Backend_mock.complete"Error.Device_lost
              "injected terminal completion failure"
          end else Ok()
        end in
      let poll_through epoch=
        if epoch<=0L then
          error"Backend_mock.poll"Error.Invalid_argument"epoch is invalid"
        else if epoch<=clock.completed then Ok true
        else if clock.deferred<>[]&&(match run_deferred()with Ok()->clock.deferred<>[]|Error _->false) then Ok false
        else Result.map(fun()->true)(complete_through epoch) in
      let begin_commands()=
        let commands=token c and ops=ref[] in
        let blit_range bytes offset length=
          offset>=0L&&length>0L&&offset<=Int64.sub(Int64.of_int(Bytes.length bytes))length in
        let blit_encoder()=
          Ok{Backend.copy_buffer=(fun ~src ~src_offset ~dst ~dst_offset ~length->
              ops:=(fun()->
                match Hashtbl.find_opt c.memory src,Hashtbl.find_opt c.memory dst with
                |Some source,Some target when blit_range source src_offset length&&
                                             blit_range target dst_offset length->
                    Bytes.blit source(Int64.to_int src_offset)target(Int64.to_int dst_offset)
                      (Int64.to_int length);Ok()
                |Some _,Some _->error"Backend_mock.copy_buffer"Error.Invalid_argument
                    "buffer copy range is invalid"
                |_->error"Backend_mock.copy_buffer"Error.Stale_handle
                    "command resource is destroyed")::!ops;Ok());
            fill_buffer=(fun token ~offset ~length ~value->
              ops:=(fun()->match Hashtbl.find_opt c.memory token with
                |Some target when blit_range target offset length->
                    Bytes.fill target(Int64.to_int offset)(Int64.to_int length)(Char.chr value);Ok()
                |Some _->error"Backend_mock.fill_buffer"Error.Invalid_argument"buffer fill range is invalid"
                |None->error"Backend_mock.fill_buffer"Error.Stale_handle"command resource is destroyed")::!ops;Ok());
            buffer_to_texture=(fun ~src ~offset ~bytes_per_row ~bytes_per_image ~dst ~mip ~origin ~extent->
              ops:=(fun()->transfer_one c[src,src;dst,dst]
                (Buffer_to_texture(src,offset,bytes_per_row,bytes_per_image,dst,mip,origin,extent)))::!ops;Ok());
            texture_to_buffer=(fun ~src ~mip ~origin ~extent ~dst ~offset ~bytes_per_row ~bytes_per_image->
              ops:=(fun()->transfer_one c[src,src;dst,dst]
                (Texture_to_buffer(src,mip,origin,extent,dst,offset,bytes_per_row,bytes_per_image)))::!ops;Ok());
            copy_texture=(fun ~src ~src_mip ~src_origin ~dst ~dst_mip ~dst_origin ~extent->
              ops:=(fun()->transfer_one c[src,src;dst,dst]
                (Copy_texture(src,src_mip,src_origin,dst,dst_mip,dst_origin,extent)))::!ops;Ok());
            blit_update_fence=fence_call"blit_update_fence";blit_wait_fence=fence_call"blit_wait_fence";
            resolve_timestamps=(fun _ ~first:_ ~count:_ ~dst:_ ~offset:_->unsupported"resolve_timestamps");
            end_blit=(fun()->Ok())}in
        let blit_encoder=function None->blit_encoder()|Some _->unsupported"blit_encoder.timestamps" in
        let event_op op token value signal=
          match Hashtbl.find_opt events token with
          |None->error("Backend_mock."^op)Error.Stale_handle"event is destroyed"
          |Some cell->
              ops:=(fun()->
                if signal then(if value> !cell then cell:=value;Ok())
                else if !cell>=value then Ok()
                else error("Backend_mock."^op)Error.Invalid_state blocked_message)::!ops;Ok() in
        let render_encoder _target=
          error"Backend_mock.render_encoder"Error.Unsupported
            "mock backend does not rasterize"in
        let commit_present ~source (frame:Backend.driver_frame)=
          let operation="Backend_mock.commit_present"in
          if c.fail_submission then begin
            c.fail_submission<-false;
            error operation Error.Invalid_state"injected submission failure"
          end
          else if c.lost then error operation Error.Device_lost"injected device loss"
          else match run(List.rev !ops)with
            |Error _ as failure->failure
            |Ok()->
                clock.epoch<-Int64.succ clock.epoch;
                add c(Printf.sprintf"commit-present:%Ld:%Ld:%Ld:%Ld"commands source frame.frame_token clock.epoch);
                Ok{Backend.epoch=clock.epoch}in
        let commit()=
          let operation="Backend_mock.commit"in
          if c.fail_submission then begin
            c.fail_submission<-false;
            error operation Error.Invalid_state"injected submission failure"
          end
          else if c.lost then error operation Error.Device_lost"injected device loss"
          else match run(List.rev !ops)with
            |Error _ as failure->failure
            |Ok()->
                clock.epoch<-Int64.succ clock.epoch;
                add c(Printf.sprintf"commit:%Ld:%Ld"commands clock.epoch);
                Ok{Backend.epoch=clock.epoch}in
        Ok{Backend.commands_token=commands;
          compute_encoder=(fun _->error"Backend_mock.compute_encoder"Error.Unsupported
            "mock backend does not execute compute shaders");
          accel_encoder=(fun()->error"Backend_mock.accel_encoder"Error.Unsupported
            "mock backend has no ray tracing");
          blit_encoder;render_encoder=(fun _ target->render_encoder target);
          commands_use_residency=(fun _->unsupported"commands_use_residency");
          map_tiles=(fun _ ~mip:_ ~region:_ ~map:_->unsupported"map_tiles");
          upscale=(fun _ ~src:_ ~dst:_->unsupported"upscale");
          commands_signal_event=(fun token value->event_op"commands_signal_event"token value true);
          commands_wait_event=(fun token value->event_op"commands_wait_event"token value false);
          commit;commit_present;abandon=(fun()->ops:=[];Ok())}in
      Ok{queue_token=id;complete_through;poll_through;
        completed_epoch=(fun()->clock.completed);
        begin_commands;
        queue_add_residency=(fun _->unsupported"queue_add_residency");
        queue_remove_residency=(fun _->unsupported"queue_remove_residency");
        gpu_duration=(fun _->None);
        gpu_timing=(fun()->{Backend.timing_supported=false;gpu_seconds=0.;gpu_samples=0L});
        destroy_queue=(fun()->c.queues<-c.queues-1;Hashtbl.remove c.queue_clocks id;Ok())});
    create_surface=(fun _->
      let id=token c and frame=ref 0L in
      c.surfaces<-c.surfaces+1;
      let acquire()=if c.lost then Ok`Device_lost else(frame:=Int64.succ !frame;Ok(`Acquired({Backend.frame_token = !frame}:Backend.driver_frame)))in Ok({surface_token=id;configure=(fun _->if c.fail_configure then(c.fail_configure<-false;error"Backend_mock.configure"Error.Invalid_state"injected configure failure")else Ok());acquire;acquire_sync=acquire;discard=(fun _->add c"discard";Ok());destroy_surface=(fun()->c.surfaces<-c.surfaces-1;Ok())}:Backend.driver_surface));create_heap=(fun _->unsupported"create_heap");heap_placement=(fun _->unsupported"heap_placement");
    create_residency=(fun ~capacity:_ ~label:_->unsupported"create_residency");
    create_fence=(fun()->let id=token c in Hashtbl.replace fences id();add c(Printf.sprintf"create-fence:%Ld"id);
      Ok{Backend.fence_token=id;destroy_fence=(fun()->Hashtbl.remove fences id;add c(Printf.sprintf"destroy-fence:%Ld"id);Ok())});
    create_event=(fun()->let id=token c and cell=ref 0L in Hashtbl.replace events id cell;add c(Printf.sprintf"create-event:%Ld"id);
      let live op=if Hashtbl.mem events id then Ok()else error("Backend_mock."^op)Error.Stale_handle"event is destroyed" in
      Ok{Backend.event_token=id;
        event_value=(fun()->Result.map(fun()-> !cell)(live"event_value"));
        event_signal=(fun value->Result.map(fun()->cell:=value)(live"event_signal"));
        event_wait=(fun value ~timeout_ms:_->Result.map(fun()->drain_all(); !cell>=value)(live"event_wait"));
        destroy_event=(fun()->Hashtbl.remove events id;add c(Printf.sprintf"destroy-event:%Ld"id);Ok())});
    create_timestamps=(fun ~count:_->unsupported"create_timestamps");
    timestamp_reference=(fun()->unsupported"timestamp_reference");
    create_mesh_pipeline=(fun _->unsupported"create_mesh_pipeline");
    create_tile_pipeline=(fun _->unsupported"create_tile_pipeline");
    create_dynamic_library=(fun ~install_name:_ _->unsupported"create_dynamic_library");
    create_archive=(fun ~path:_->unsupported"create_archive");
    create_sparse_texture=(fun ~heap:_ _->unsupported"create_sparse_texture");
    texture_tile=(fun _->unsupported"texture_tile");
    create_upscaler=(fun ~input:_ ~output:_->unsupported"create_upscaler");
    destroy_device=(fun()->Handle.destroy_device device_handle;add c"destroy-device";Ok())}in
  {Backend.create_device},c
let live_counts c=c.buffers,c.textures,c.pipelines,c.queues,c.surfaces
