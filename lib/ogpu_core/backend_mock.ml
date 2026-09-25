type queue_clock={mutable epoch:int64;mutable completed:int64}
type texture_storage={descriptor:Types.texture_descriptor;levels:bytes array}
type control={mutable next:int64;queue_clocks:(int64,queue_clock)Hashtbl.t;memory:(int64,bytes)Hashtbl.t;texture_storage:(int64,texture_storage)Hashtbl.t;mutable lost:bool;mutable fail_submission:bool;mutable fail_completion:bool;mutable fail_texture_after:int option;mutable fail_depth_after:int option;mutable fail_configure:bool;mutable trace:string list;mutable buffers:int;mutable textures:int;mutable pipelines:int;mutable queues:int;mutable surfaces:int}
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
           (match draw.primitive with Point_list->"points"|Line_list->"lines"
            |Triangle_list -> "list" | Triangle_strip -> "strip")
           draw.vertex_start draw.vertex_count index)
  |> String.concat ";")
let required_resources command=match Backend.Private.command_view command with
  |Backend.Private.Transfer ops->Array.to_list ops|>List.concat_map(function
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
let pipeline_graph_valid command pipelines=
  match Backend.Private.command_view command with
  |Backend.Private.Transfer _->true
  |Compute _->pipelines<>[]
  |Render submission->
      List.length pipelines=List.length(List.sort_uniq String.compare
        (List.map(fun(draw:Render_pass.draw)->draw.pipeline_key)
          (Render_pass.submission_draws submission)))
let execute_transfers c resources command =
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
  let buffer_region bytes offset row image (extent:Transfer_pass.extent)=
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
  let valid_region storage mip (origin:Transfer_pass.origin)
      (extent:Transfer_pass.extent)=
    mip>=0 && mip<Array.length storage.levels &&
    let width=mip_extent storage.descriptor.width mip in
    let height=mip_extent storage.descriptor.height mip in
    let depth=mip_extent storage.descriptor.depth mip in
    origin.x>=0 && origin.y>=0 && origin.z>=0 &&
    extent.width>0 && extent.height>0 && extent.depth>0 &&
    origin.x<=width-extent.width &&
    origin.y<=height-extent.height &&
    origin.z<=depth-extent.depth in
  let texture_offset storage mip (origin:Transfer_pass.origin)=
    let width=mip_extent storage.descriptor.width mip in
    let height=mip_extent storage.descriptor.height mip in
    ((origin.z*height+origin.y)*width+origin.x)*4 in
  let copy_rows ~source ~source_offset ~source_row ~source_image
      ~target ~target_offset ~target_row ~target_image
      (extent:Transfer_pass.extent)=
    for z=0 to extent.depth-1 do
      for y=0 to extent.height-1 do
        Bytes.blit source (source_offset+z*source_image+y*source_row)
          target (target_offset+z*target_image+y*target_row)
          (extent.width*4)
      done
    done in
  match Backend.Private.command_view command with
  |Backend.Private.Transfer descriptions->
      Array.fold_left (fun result description->
        Result.bind result (fun()->match description with
          |Transfer_pass.Copy_buffer(src,src_offset,dst,dst_offset,length)->
              Result.bind (bytes src) (fun source->
                Result.bind (bytes dst) (fun target->
                  if not(range source src_offset length &&
                    range target dst_offset length) then
                    error op Error.Invalid_argument"buffer copy range is invalid"
                  else begin
                    Bytes.blit source (Int64.to_int src_offset)
                      target (Int64.to_int dst_offset) (Int64.to_int length);
                    Ok()
                  end))
          |Transfer_pass.Fill_buffer(id,offset,length,value)->
              Result.bind (bytes id) (fun target->
                if not(range target offset length) || value<0 || value>255
                then error op Error.Invalid_argument"buffer fill is invalid"
                else begin
                  Bytes.fill target (Int64.to_int offset) (Int64.to_int length)
                    (Char.chr value);
                  Ok()
                end)
          |Transfer_pass.Buffer_to_texture(src,offset,row,image,dst,mip,
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
          |Transfer_pass.Texture_to_buffer(src,mip,origin,extent,dst,
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
          |Transfer_pass.Copy_texture(src,src_mip,src_origin,dst,dst_mip,
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
                  end)))) (Ok()) descriptions
  |Backend.Private.Compute _|Backend.Private.Render _->Ok()
let mock_submit c clock ~operation ~commit command ~resources ~pipelines=
  if c.fail_submission then begin
    c.fail_submission<-false;
    error operation Error.Invalid_state"injected submission failure"
  end
  else if c.lost then error operation Error.Device_lost"injected device loss"
  else
    let ids=List.map fst resources in
    if List.exists(fun id->not(List.mem id ids))(required_resources command)then
      error operation Error.Invalid_argument"command resource is absent"
    else if not(pipeline_graph_valid command pipelines)then
      error operation Error.Invalid_argument"pipeline graph differs from draws"
    else match execute_transfers c resources command with
    |Error _ as failure->failure
    |Ok()->
      (match Backend.Private.command_view command with
       |Render submission->add c("render:"^render_trace submission)
       |Transfer _|Compute _->());
      clock.epoch<-Int64.succ clock.epoch;
      add c(commit clock.epoch);
      Ok{Backend.epoch=clock.epoch}
let create ?(capabilities=Caps.minimum_m1)()=
  let c={next=1L;queue_clocks=Hashtbl.create 4;memory=Hashtbl.create 16;texture_storage=Hashtbl.create 8;lost=false;fail_submission=false;fail_completion=false;fail_texture_after=None;fail_depth_after=None;fail_configure=false;trace=[];buffers=0;textures=0;pipelines=0;queues=0;surfaces=0}in
  let should_fail field=match field with Some 0->true|None|Some _->false in
  let advance field=match field with None->None|Some 0->None|Some remaining->Some(remaining-1)in
  let resource kind count set size=let id=token c and bytes=Bytes.make size '\000' in Hashtbl.add c.memory id bytes;set(count+1);add c(Printf.sprintf"create-%s:%Ld"kind id);let range offset length=offset>=0L&&length>=0&&length<=size&&offset<=Int64.of_int(size-length)in let read_into offset destination destination_offset length=if not(range offset length)||destination_offset<0||length>Bytes.length destination-destination_offset then error"Backend_mock.read_into"Error.Invalid_argument"range"else(Bytes.blit bytes(Int64.to_int offset)destination destination_offset length;Ok())in Ok{Backend.token=id;write=(fun offset source->if not(range offset(Bytes.length source))then error"Backend_mock.write"Error.Invalid_argument"range"else(Bytes.blit source 0 bytes(Int64.to_int offset)(Bytes.length source);Ok()));read=(fun offset length->if not(range offset length)then error"Backend_mock.read"Error.Invalid_argument"range"else Ok(Bytes.sub bytes(Int64.to_int offset)length));read_into;destroy=(fun()->Hashtbl.remove c.memory id;Hashtbl.remove c.texture_storage id;set((if kind="buffer"then c.buffers else c.textures)-1);add c(Printf.sprintf"destroy-%s:%Ld"kind id);Ok())}in
  let create_device()=let device_token=token c and device_handle=Handle.create_device()in Ok{Backend.device_token;device_handle;capabilities;
    create_buffer=(fun d->resource"buffer"c.buffers(fun n->c.buffers<-n)(Int64.to_int d.Types.size));
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
    create_pipeline=(fun p->let id=token c in c.pipelines<-c.pipelines+1;add c("pipeline:"^Pipeline.cache_key p);Ok{pipeline_token=id;destroy_pipeline=(fun()->c.pipelines<-c.pipelines-1;Ok())});
    create_queue=(fun()->
      let id=token c and clock={epoch=0L;completed=0L} in
      c.queues<-c.queues+1;
      Hashtbl.add c.queue_clocks id clock;
      let complete_through epoch=
        if epoch<=clock.completed||epoch>clock.epoch then
          error"Backend_mock.complete"Error.Invalid_argument"epoch is invalid"
        else begin
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
        else Result.map(fun()->true)(complete_through epoch) in
      let submit command~resources~pipelines=
        mock_submit c clock ~operation:"Backend_mock.submit"
          ~commit:(fun epoch->Printf.sprintf"submit:%Ld"epoch)
          command~resources~pipelines in
      let submit_sync command~resources~pipelines=
        match submit command~resources~pipelines with
        |Error _ as e->e
        |Ok receipt->Ok{Backend.receipt;completion=complete_through receipt.epoch}in
      Ok{queue_token=id;submit;submit_sync;complete_through;poll_through;
        completed_epoch=(fun()->clock.completed);
        destroy_queue=(fun()->c.queues<-c.queues-1;Hashtbl.remove c.queue_clocks id;Ok())});
    create_surface=(fun _->
      let id=token c and frame=ref 0L in
      c.surfaces<-c.surfaces+1;
      let submit_present~queue~source command~resources~pipelines frame=
        match Hashtbl.find_opt c.queue_clocks queue with
        |None->error"Backend_mock.submit_present"Error.Stale_handle
          "queue is destroyed"
        |Some clock->mock_submit c clock ~operation:"Backend_mock.submit_present"
          ~commit:(fun epoch->Printf.sprintf"submit-present:%Ld:%Ld:%Ld:%Ld"
            queue source frame.Backend.frame_token epoch)
          command~resources~pipelines in
      let submit_present_sync~queue~source command~resources~pipelines frame=
        match submit_present~queue~source command~resources~pipelines frame with
        |Error _ as e->e
        |Ok receipt->
            let clock=Hashtbl.find c.queue_clocks queue in
            clock.completed<-receipt.epoch;
            add c(Printf.sprintf"complete:%Ld"receipt.epoch);
            let completion=if c.fail_completion then begin
              c.fail_completion<-false;
              error"Backend_mock.complete"Error.Device_lost
                "injected terminal completion failure"
            end else Ok()in
            Ok{Backend.receipt;completion}in
      let acquire()=if c.lost then Ok`Device_lost else(frame:=Int64.succ !frame;Ok(`Acquired({Backend.frame_token = !frame}:Backend.driver_frame)))in Ok({surface_token=id;configure=(fun _->if c.fail_configure then(c.fail_configure<-false;error"Backend_mock.configure"Error.Invalid_state"injected configure failure")else Ok());acquire;acquire_sync=acquire;present=(fun ~queue ~source _->add c(Printf.sprintf"present:%Ld:%Ld"queue source);Ok());submit_present;submit_present_sync;discard=(fun _->add c"discard";Ok());destroy_surface=(fun()->c.surfaces<-c.surfaces-1;Ok())}:Backend.driver_surface));destroy_device=(fun()->Handle.destroy_device device_handle;add c"destroy-device";Ok())}in
  {Backend.create_device},c
let inject_device_loss c=c.lost<-true
let fail_next_submission c=c.fail_submission<-true
let fail_texture_allocation_after c count=if count<0 then invalid_arg"negative allocation count"else c.fail_texture_after<-Some count
let fail_depth_allocation_after c count=if count<0 then invalid_arg"negative allocation count"else c.fail_depth_after<-Some count
let fail_next_configure c=c.fail_configure<-true
let inject_next_completion_error c=c.fail_completion<-true
let trace c=List.rev c.trace
let clear_trace c=c.trace<-[]
let live_counts c=c.buffers,c.textures,c.pipelines,c.queues,c.surfaces
