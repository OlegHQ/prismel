type cleanup=unit->unit
type native_completion=Classic of Metal.Command_buffer.t|Command4 of Metal.Command4.Submission.t*Metal.Command4.Command_buffer.t*Metal.Command4.Allocator.t
type pending={epoch:int64;command:native_completion;cleanup:cleanup list;
  mutable encode_cleanup:cleanup list}
let drop_encode_cleanup pending=
  let cleanup=pending.encode_cleanup in
  pending.encode_cleanup<-[];
  List.iter(fun release->release())cleanup
type presentation=Metal.Command_buffer.t -> (unit,Ogpu.Error.t) result
type t={device:Device.t;metal:Metal.Command_queue.t;submission:Ogpu.Submission.t;mutable command4:Metal.Command4.Queue.t option;mutable pending:pending list;mutable fail_next:bool;mutable fail_next_completion:bool;mutable scoped_next_render:bool;mutable scoped_on_committed:(int64->unit)option;mutable scoped_completion:(unit,Ogpu.Error.t)result option;mutable dead:bool}
type receipt={epoch:int64}
type synchronous_submission={receipt:receipt;completion:(unit,Ogpu.Error.t)result}
type gpu_timing={supported:bool;duration_seconds:float;sample_count:int64}
type gpu_timing_accumulator={mutable supported:bool;mutable duration_seconds:float;mutable sample_count:int64;mutable queues:int}
let gpu_timings:(int64,gpu_timing_accumulator)Hashtbl.t=Hashtbl.create 4
let gpu_timing_for_device device=
  let id=Device.id device in
  match Hashtbl.find_opt gpu_timings id with
  |Some value->{supported=value.supported;duration_seconds=value.duration_seconds;sample_count=value.sample_count}
  |None->{supported=false;duration_seconds=0.;sample_count=0L}
let gpu_timing_total() : gpu_timing=
  Hashtbl.fold(fun _ (value:gpu_timing_accumulator) (total:gpu_timing)->
    {supported=total.supported||value.supported;
     duration_seconds=total.duration_seconds+.value.duration_seconds;
     sample_count=Int64.add total.sample_count value.sample_count})
    gpu_timings {supported=false;duration_seconds=0.;sample_count=0L}
let valid_gpu_duration duration=Float.is_finite duration&&duration>0.
let record_gpu_duration device duration=
  match Hashtbl.find_opt gpu_timings(Device.id device)with
  |Some value when valid_gpu_duration duration->value.supported<-true;value.duration_seconds<-value.duration_seconds+.duration;value.sample_count<-Int64.succ value.sample_count
  |_->()
let error op kind message=Error(Ogpu.Error.make op kind message)
let create ?(max_frames=3) device=let op="Ogpu_metal.Queue.create"in if Device.destroyed device then error op Ogpu.Error.Stale_handle"device is destroyed"else
  match Ogpu.Submission.create~max_frames(Device.Private.handle device)with Error _ as e->e|Ok submission->match Metal.Command_queue.create(Device.Private.metal device)with Error e->Error(Adapter.error~operation:op e)|Ok metal->let id=Device.id device in (match Hashtbl.find_opt gpu_timings id with Some timing->timing.queues<-timing.queues+1|None->Hashtbl.add gpu_timings id{supported=false;duration_seconds=0.;sample_count=0L;queues=1});Device.Private.attach_resource device;Ok{device;metal;submission;command4=None;pending=[];fail_next=false;fail_next_completion=false;scoped_next_render=false;scoped_on_committed=None;scoped_completion=None;dead=false}
let destroyed value=value.dead
let in_flight value=Ogpu.Submission.in_flight value.submission
let completed_epoch value=Ogpu.Submission.completed_epoch value.submission
let inject_next_error value=value.fail_next<-true
let inject_next_completion_error value=value.fail_next_completion<-true
let validate_buffer device buffer=match Buffer.descriptor device buffer with Ok _->Ok()|Error e->Error e
let validate_texture device texture=match Texture.descriptor device texture with Ok _->Ok()|Error e->Error e
let validate_operation device=function
  |Command.Private.Copy(a,ao,b,bo,n)->(match validate_buffer device a with Error _ as e->e|Ok()->match validate_buffer device b with Error _ as e->e|Ok()->let ad=Result.get_ok(Buffer.descriptor device a)and bd=Result.get_ok(Buffer.descriptor device b)in if ao>Int64.sub ad.size n||bo>Int64.sub bd.size n then error"Ogpu_metal.Queue.submit"Ogpu.Error.Invalid_argument"copy exceeds buffer"else Ok())
  |Command.Private.Compute(_,_,b,_)->validate_buffer device b
  |Command.Private.Dispatch(p,b,_)->(match Pipeline.validate device p with Error _ as e->e|Ok()->validate_buffer device b)
  |Command.Private.Clear(t,_)->validate_texture device t
  |Command.Private.Draw_triangle(p,t)->(match Pipeline.validate device p with Error _ as e->e|Ok()->validate_texture device t)
let rec validate_all device=function []->Ok()|x::xs->match validate_operation device x with Error _ as e->e|Ok()->validate_all device xs
let retain_all operations=
  let retained=ref[]in let keep retain release=match retain()with Error _ as failure->failure|Ok()->retained:=release::!retained;Ok()in
  let rec loop=function
    |[]->Ok(List.rev!retained)
    |operation::rest->let resources=match operation with
      |Command.Private.Copy(a,_,b,_,_)->[(fun()->keep(fun()->Buffer.Private.retain_submission a)(fun()->Buffer.Private.release_submission a));(fun()->keep(fun()->Buffer.Private.retain_submission b)(fun()->Buffer.Private.release_submission b))]
      |Compute(_,_,b,_)->[(fun()->keep(fun()->Buffer.Private.retain_submission b)(fun()->Buffer.Private.release_submission b))]
      |Dispatch(p,b,_)->[(fun()->keep(fun()->Pipeline.Private.retain_submission p)(fun()->Pipeline.Private.release_submission p));(fun()->keep(fun()->Buffer.Private.retain_submission b)(fun()->Buffer.Private.release_submission b))]
      |Clear(t,_)->[(fun()->keep(fun()->Texture.Private.retain_submission t)(fun()->Texture.Private.release_submission t))]
      |Draw_triangle(p,t)->[(fun()->keep(fun()->Pipeline.Private.retain_submission p)(fun()->Pipeline.Private.release_submission p));(fun()->keep(fun()->Texture.Private.retain_submission t)(fun()->Texture.Private.release_submission t))]in
      let rec each=function []->loop rest|retain::tail->match retain()with Ok()->each tail|Error _ as failure->failure in each resources in
  match loop operations with Ok _ as success->success|Error _ as failure->List.iter(fun release->release())!retained;failure
let encode command operations =
  let op="Ogpu_metal.Queue.submit"in
  let cleanup=ref[]in let add f=cleanup:=f::!cleanup in
  let rec loop=function
    |[]->Ok(!cleanup)
    |Command.Private.Copy(a,ao,b,bo,n)::rest->(match Metal.Blit_encoder.create command with Error e->Error(Adapter.error~operation:op e)|Ok encoder->(match Metal.Blit_encoder.copy_buffer encoder~source:(Buffer.Private.metal a)~source_offset:ao~destination:(Buffer.Private.metal b)~destination_offset:bo~length:n with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Blit_encoder.end_encoding encoder with Error e->Error(Adapter.error~operation:op e)|Ok()->loop rest))
    |Command.Private.Compute(source,entry,buffer,threads)::rest->(match Metal.Library.compile_source~device:(Metal.Command_buffer.device command)source with Error e->Error(Adapter.error~operation:op e)|Ok library->add(fun()->ignore(Metal.Library.destroy library));match Metal.Function.find~library entry with Error e->Error(Adapter.error~operation:op e)|Ok function_->add(fun()->ignore(Metal.Function.destroy function_));match Metal.Compute_pipeline.create function_ with Error e->Error(Adapter.error~operation:op e)|Ok pipeline->add(fun()->ignore(Metal.Compute_pipeline.destroy pipeline));match Metal.Compute_encoder.create command with Error e->Error(Adapter.error~operation:op e)|Ok encoder->(match Metal.Compute_encoder.set_pipeline encoder pipeline with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Compute_encoder.set_buffer encoder~index:0~offset:0L(Buffer.Private.metal buffer)with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Compute_encoder.dispatch_threads encoder~threads:(threads,1,1)~threadgroup:(min threads 64,1,1)with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Compute_encoder.end_encoding encoder with Error e->Error(Adapter.error~operation:op e)|Ok()->loop rest))
    |Command.Private.Dispatch(pipeline,buffer,threads)::rest->(match Pipeline.Private.native pipeline with Render _->error op Ogpu.Error.Invalid_argument"render pipeline used for compute dispatch"|Compute pipeline->match Metal.Compute_encoder.create command with Error e->Error(Adapter.error~operation:op e)|Ok encoder->(match Metal.Compute_encoder.set_pipeline encoder pipeline with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Compute_encoder.set_buffer encoder~index:0~offset:0L(Buffer.Private.metal buffer)with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Compute_encoder.dispatch_threads encoder~threads:(threads,1,1)~threadgroup:(min threads 64,1,1)with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Compute_encoder.end_encoding encoder with Error e->Error(Adapter.error~operation:op e)|Ok()->loop rest))
    |Command.Private.Clear(texture,color)::rest->(match Metal.Render_encoder.create command~target:(Texture.Private.metal texture)~clear:color()with Error e->Error(Adapter.error~operation:op e)|Ok encoder->match Metal.Render_encoder.end_encoding encoder with Error e->Error(Adapter.error~operation:op e)|Ok()->loop rest)
    |Command.Private.Draw_triangle(pipeline,texture)::rest->(match Pipeline.Private.native pipeline with Compute _->error op Ogpu.Error.Invalid_argument"compute pipeline used for render draw"|Render pipeline->match Metal.Render_encoder.create command~target:(Texture.Private.metal texture)~clear:(0.,0.,0.,1.)()with Error e->Error(Adapter.error~operation:op e)|Ok encoder->match Metal.Render_encoder.set_pipeline encoder pipeline with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Render_encoder.draw_triangles encoder~first:0~count:3()with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Render_encoder.end_encoding encoder with Error e->Error(Adapter.error~operation:op e)|Ok()->loop rest)
  in loop operations
let submit value command =let op="Ogpu_metal.Queue.submit"in if value.dead then error op Ogpu.Error.Stale_handle"queue is destroyed"else if value.fail_next then(value.fail_next<-false;error op Ogpu.Error.Device_lost"injected submission failure")else let operations=Command.Private.operations command in
  match validate_all value.device operations with Error _ as e->e|Ok()->match retain_all operations with Error _ as e->e|Ok retained->
  let rollback failure=List.iter(fun release->release())retained;failure in
match Ogpu.Submission.Private.submit_epoch value.submission(Command.Private.portable command)~resources:[]with Error _ as e->rollback e|Ok epoch->match Metal.Command_buffer.create value.metal()with Error e->rollback(Error(Adapter.error~operation:op e))|Ok native->match encode native operations with Error e->ignore(Metal.Command_buffer.destroy native);rollback(Error e)|Ok cleanup->match Metal.Command_buffer.commit native with Error e->ignore(Metal.Command_buffer.destroy native);rollback(Error(Adapter.error~operation:op e))|Ok()->value.pending<-value.pending@[{epoch=epoch;command=Classic native;cleanup=retained@cleanup;encode_cleanup=[]}];Ok{epoch=epoch}
let command4_queue value=match value.command4 with Some queue->Ok queue|None->match Metal.Command4.Queue.create_default(Device.Private.metal value.device)with Error e->Error(Adapter.error~operation:"Ogpu_metal.Queue.command4" e)|Ok queue->value.command4<-Some queue;Ok queue
let no_presentation _=assert false
let submit_render_pass_common ~presenting presentation value pass =
  let op = "Ogpu_metal.Queue.submit_render_pass" in
  let requires_command4 = Render_pass.Private.requires_command4 pass in
  if value.dead then
    error op Ogpu.Error.Stale_handle "queue is destroyed"
  else if presenting && requires_command4 then
    error op Ogpu.Error.Unsupported
      "combined presentation requires a classic render pass"
  else if value.fail_next then begin
    value.fail_next <- false;
    error op Ogpu.Error.Device_lost "injected submission failure"
  end else if requires_command4 then
    match command4_queue value with
    | Error _ as failure -> failure
    | Ok queue ->
        (match Render_pass.Private.retain pass with
         | Error _ as failure -> failure
         | Ok retained ->
             let rollback failure =
               List.iter (fun release -> release ()) retained;
               failure
             in
             match Metal.Command4.Allocator.create (Device.Private.metal value.device) with
             | Error native_error ->
                 rollback (Error (Adapter.error ~operation:op native_error))
             | Ok allocator ->
                 (match Metal.Command4.Command_buffer.create allocator
                          ~label:"ogpu-metal-render-pass" () with
                  | Error native_error ->
                      ignore (Metal.Command4.Allocator.destroy allocator);
                      rollback (Error (Adapter.error ~operation:op native_error))
                  | Ok native ->
                      let destroy_native () =
                        ignore (Metal.Command4.Command_buffer.destroy native);
                        ignore (Metal.Command4.Allocator.destroy allocator)
                      in
                      match Render_pass.Private.encode_command4 native pass with
                      | Error submission_error ->
                          destroy_native ();
                          rollback (Error submission_error)
                      | Ok cleanup ->
                          let abort failure =
                            destroy_native ();
                            List.iter (fun release -> release ()) cleanup;
                            rollback failure
                          in
                          (match Metal.Command4.Command_buffer.end_recording native with
                           | Error native_error ->
                               abort (Error (Adapter.error ~operation:op native_error))
                           | Ok () ->
                               let portable = Ogpu.Command.begin_encoder () in
                               (match Render_pass.Private.encode_portable pass portable with
                                | Error submission_error ->
                                    abort (Error submission_error)
                                | Ok () ->
                                    (match Ogpu.Command.end_encoder portable with
                                     | Error submission_error ->
                                         abort (Error submission_error)
                                     | Ok () ->
                                         (match Ogpu.Submission.Private.submit_epoch
                                                  value.submission portable ~resources:[] with
                                          | Error _ as failure ->
                                              abort failure
                                          | Ok epoch ->
                                              (match Metal.Command4.Queue.commit queue [native] with
                                               | Error native_error ->
                                                   abort
                                                     (Error (Adapter.error ~operation:op native_error))
                                               | Ok submission ->
                                                   value.pending <- value.pending @
                                                     [{epoch;
                                                       command=Command4
                                                         (submission,native,allocator);
                                                       cleanup=retained @ cleanup;
                                                       encode_cleanup=[]}];
                                                   Ok {epoch})))))))
  else
    match Render_pass.Private.retain pass with
    | Error _ as failure -> failure
    | Ok retained ->
        let rollback failure =
          List.iter (fun release -> release ()) retained;
          failure
        in
        (* Classic render submission has an explicit queue-owned terminal
           teardown in [wait_through].  Do not attach a GC finalizer to this
           short-lived wrapper: a blocking native wait may otherwise promote
           it and its descriptor/encoder graph into the major heap. *)
        match Metal.Command_buffer.Private.create_scoped value.metal () with
        | Error native_error ->
            rollback (Error (Adapter.error ~operation:op native_error))
        | Ok native ->
            (match Render_pass.Private.encode native pass with
             | Error submission_error ->
                 ignore (Metal.Command_buffer.destroy native);
                 rollback (Error submission_error)
             | Ok cleanup ->
                 let abort failure =
                   ignore (Metal.Command_buffer.destroy native);
                   List.iter (fun release -> release ()) cleanup;
                   rollback failure
                 in
                 let presented =
                   if presenting then presentation native else Ok()
                 in
                 (match presented with
                  | Error _ as failure ->
                      abort failure
                  | Ok () ->
                      let portable = Ogpu.Command.begin_encoder () in
                      (match Render_pass.Private.encode_portable pass portable with
                       | Error submission_error ->
                           abort (Error submission_error)
                       | Ok () ->
                           (match Ogpu.Command.end_encoder portable with
                            | Error submission_error ->
                                abort (Error submission_error)
                            | Ok () ->
                                (match Ogpu.Submission.Private.submit_epoch
                                         value.submission portable ~resources:[] with
                                 | Error _ as failure ->
                                     abort failure
                                 | Ok epoch ->
                                     (match Metal.Command_buffer.commit native with
                                      | Error native_error ->
                                          abort
                                            (Error (Adapter.error ~operation:op native_error))
                                      | Ok () ->
                                          value.pending <- value.pending @
                                            [{epoch;command=Classic native;
                                              cleanup=retained;
                                              encode_cleanup=cleanup}];
                                          Ok {epoch}))))))
let submit_render_pass_async value pass=
  submit_render_pass_common~presenting:false no_presentation value pass
let submit_render_pass_present_async value presentation pass=
  submit_render_pass_common~presenting:true presentation value pass
let submit_typed value op retain encode=if value.dead then error op Ogpu.Error.Stale_handle"queue is destroyed"else match retain()with Error _ as e->e|Ok retained->let rollback e=List.iter(fun f->f())retained;e in match Metal.Command_buffer.create value.metal()with Error e->rollback(Error(Adapter.error~operation:op e))|Ok native->match encode native with Error e->ignore(Metal.Command_buffer.destroy native);rollback(Error e)|Ok()->let portable=Ogpu.Command.begin_encoder()in(match Ogpu.Command.end_encoder portable with Error e->ignore(Metal.Command_buffer.destroy native);rollback(Error e)|Ok()->match Ogpu.Submission.Private.submit_epoch value.submission portable~resources:[]with Error _ as e->ignore(Metal.Command_buffer.destroy native);rollback e|Ok epoch->match Metal.Command_buffer.commit native with Error e->ignore(Metal.Command_buffer.destroy native);rollback(Error(Adapter.error~operation:op e))|Ok()->value.pending<-value.pending@[{epoch=epoch;command=Classic native;cleanup=retained;encode_cleanup=[]}];Ok{epoch=epoch})
let submit_transfer_pass value pass=submit_typed value"Ogpu_metal.Queue.submit_transfer_pass"(fun()->Transfer_pass.Private.retain pass)(fun command->Transfer_pass.Private.encode command pass)
let submit_compute_pass value pass=submit_typed value"Ogpu_metal.Queue.submit_compute_pass"(fun()->Compute_pass.Private.retain pass)(fun command->Compute_pass.Private.encode command pass)
let wait_through value epoch =
  let op = "Ogpu_metal.Queue.wait_through" in
  if epoch <= completed_epoch value || epoch > Int64.of_int max_int then
    error op Ogpu.Error.Invalid_argument "completion epoch is invalid"
  else
    let ready,later =
      List.partition (fun (pending:pending) -> pending.epoch <= epoch) value.pending
    in
    if ready = [] then
      error op Ogpu.Error.Invalid_argument "epoch was not submitted"
    else
      let finish pending =
        match pending.command with
        | Classic command ->
            let outcome =
              match Metal.Command_buffer.wait_until_completed command with
              | Error native_error ->
                  Error (Adapter.error ~operation:op native_error)
              | Ok () ->
                  (match Metal.Command_buffer.diagnostics command with
                   | Ok diagnostics
                     when diagnostics.gpu_end_time >= diagnostics.gpu_start_time ->
                       record_gpu_duration value.device
                         (diagnostics.gpu_end_time -. diagnostics.gpu_start_time)
                   | Ok _ | Error _ -> ());
                  Ok ()
            in
            (* [wait_until_completed] returns only after a terminal native
               status, including its error result, so both the native handle
               and all submission-owned cleanup are safe to release. *)
            ignore (Metal.Command_buffer.destroy command);
            outcome
        | Command4 (submission,command,allocator) ->
            let outcome =
              match Metal.Command4.Submission.wait submission with
              | Error native_error ->
                  Error (Adapter.error ~operation:op native_error)
              | Ok () ->
                  (match Metal.Command4.Submission.feedback submission with
                   | Ok feedback ->
                       record_gpu_duration value.device feedback.gpu_duration
                   | Error _ -> ());
                  Ok ()
            in
            (* Command4.Submission.wait likewise records a terminal outcome
               before returning either branch. *)
            ignore (Metal.Command4.Submission.destroy submission);
            ignore (Metal.Command4.Command_buffer.destroy command);
            ignore (Metal.Command4.Allocator.destroy allocator);
            outcome
      in
      let inject_completion_error = ref value.fail_next_completion in
      value.fail_next_completion <- false;
      let rec complete_all first_error = function
        | [] -> first_error
        | pending::rest ->
            let outcome = finish pending in
            List.iter (fun release -> release ()) pending.encode_cleanup;
            List.iter (fun release -> release ()) pending.cleanup;
            let outcome =
              if !inject_completion_error then begin
                inject_completion_error := false;
                error op Ogpu.Error.Device_lost
                  "injected terminal completion failure"
              end else outcome
            in
            let first_error =
              match first_error,outcome with
              | None,Error failure -> Some failure
              | (Some _ as first),_ -> first
              | None,Ok () -> None
            in
            complete_all first_error rest
      in
      let first_error = complete_all None ready in
      value.pending <- later;
      let portable = Ogpu.Submission.complete_through value.submission epoch in
      match first_error,portable with
      | Some failure,_ -> Error failure
      | None,result -> result
let finish_scoped_render value receipt =
  match List.rev value.pending with
  |({epoch;command=Classic command;cleanup;_} as pending)::rest
    when epoch=receipt.epoch->
      (* Only the classic R10 lane is detached before the blocking wait. *)
      value.pending<-List.rev rest;
      (* Drop command-buffer resource retains first so encode-owned
         depth/sampler objects and the scoped presentation drawable can be
         destroyed.  The native command buffer still retains those objects
         through terminal completion. *)
      let released_references=
        Metal.Command_buffer.Private.release_committed_references command in
      drop_encode_cleanup pending;
      Option.iter(fun notify->notify receipt.epoch)value.scoped_on_committed;
      value.scoped_on_committed<-None;
      let completion=
        Fun.protect
          ~finally:(fun()->
            List.iter(fun release->release())cleanup;
            ignore(Metal.Command_buffer.destroy command))
          (fun()->
            let outcome=match Metal.Command_buffer.wait_until_completed command with
              |Error native_error->Error(Adapter.error
                  ~operation:"Ogpu_metal.Queue.submit_render_pass_sync" native_error)
              |Ok()->Ok()in
            let outcome=match released_references,outcome with
              |Error native_error,_->Error(Adapter.error
                  ~operation:"Ogpu_metal.Queue.submit_render_pass_sync"
                  native_error)
              |Ok(),outcome->outcome in
            let outcome=if value.fail_next_completion then begin
                value.fail_next_completion<-false;
                error"Ogpu_metal.Queue.submit_render_pass_sync"
                  Ogpu.Error.Device_lost"injected terminal completion failure"
              end else outcome in
            let portable=Ogpu.Submission.complete_through value.submission epoch in
            match outcome,portable with Error _ as e,_->e|Ok(),result->result)in
      Ok{receipt;completion}
  |{epoch;command=Command4 _;_}::_ when epoch=receipt.epoch->
      (* Command4 owns a submission/command/allocator triple.  Preserve its
         established terminal teardown and injected-completion behavior. *)
      Ok{receipt;completion=wait_through value epoch}
  |_->error"Ogpu_metal.Queue.submit_render_pass_sync"Ogpu.Error.Invalid_state
      "render admission was not the terminal pending command"
let submit_render_pass_sync value pass=
  match submit_render_pass_async value pass with Error _ as e->e|Ok receipt->
    finish_scoped_render value receipt
let submit_render_pass_present_sync value presentation pass=
  match submit_render_pass_present_async value presentation pass with Error _ as e->e
  |Ok receipt->finish_scoped_render value receipt
let submit_render_pass value pass=
  if value.scoped_next_render then begin
    value.scoped_next_render<-false;
    match submit_render_pass_sync value pass with
    |Error _ as e->e
    |Ok admitted->value.scoped_completion<-Some admitted.completion;
        Ok admitted.receipt
  end else submit_render_pass_async value pass
let submit_render_pass_present value presentation pass=
  if value.scoped_next_render then begin
    value.scoped_next_render<-false;
    match submit_render_pass_present_sync value presentation pass with
    |Error _ as e->e
    |Ok admitted->value.scoped_completion<-Some admitted.completion;
        Ok admitted.receipt
  end else submit_render_pass_present_async value presentation pass
let destroy value=let op="Ogpu_metal.Queue.destroy"in if value.dead then Ok()else if value.pending<>[]then error op Ogpu.Error.Invalid_state"queue has commands in flight"else match Metal.Command_queue.destroy value.metal with Error e->Error(Adapter.error~operation:op e)|Ok()->(match value.command4 with None->()|Some queue->ignore(Metal.Command4.Queue.destroy queue));let id=Device.id value.device in (match Hashtbl.find_opt gpu_timings id with Some timing when timing.queues>1->timing.queues<-timing.queues-1|Some _->Hashtbl.remove gpu_timings id|None->());value.dead<-true;Device.Private.detach_resource value.device;Ok()
module Private=struct
  let metal value=value.metal
  let gpu_timing_total=gpu_timing_total
  let gpu_timing_entry_count()=Hashtbl.length gpu_timings
  let valid_gpu_duration=valid_gpu_duration
  let arm_scoped_render ?on_committed value=
    value.scoped_next_render<-true;value.scoped_on_committed<-on_committed;
    value.scoped_completion<-None
  let take_scoped_completion value=
    value.scoped_next_render<-false;
    value.scoped_on_committed<-None;
    let result=value.scoped_completion in value.scoped_completion<-None;result
end
