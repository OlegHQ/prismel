type cleanup=unit->unit
type pending={epoch:int64;command:Metal.Command_buffer.t;cleanup:cleanup list}
type t={device:Device.t;metal:Metal.Command_queue.t;submission:Ogpu.Submission.t;mutable pending:pending list;mutable fail_next:bool;mutable dead:bool}
type receipt={epoch:int64}
let error op kind message=Error(Ogpu.Error.make op kind message)
let create ?(max_frames=3) device=let op="Ogpu_metal.Queue.create"in if Device.destroyed device then error op Ogpu.Error.Stale_handle"device is destroyed"else
  match Ogpu.Submission.create~max_frames(Device.Private.handle device)with Error _ as e->e|Ok submission->match Metal.Command_queue.create(Device.Private.metal device)with Error e->Error(Adapter.error~operation:op e)|Ok metal->Device.Private.attach_resource device;Ok{device;metal;submission;pending=[];fail_next=false;dead=false}
let destroyed value=value.dead
let in_flight value=Ogpu.Submission.in_flight value.submission
let completed_epoch value=Ogpu.Submission.completed_epoch value.submission
let inject_next_error value=value.fail_next<-true
let validate_buffer device buffer=match Buffer.descriptor device buffer with Ok _->Ok()|Error e->Error e
let validate_texture device texture=match Texture.descriptor device texture with Ok _->Ok()|Error e->Error e
let validate_operation device=function
  |Command.Private.Copy(a,ao,b,bo,n)->(match validate_buffer device a with Error _ as e->e|Ok()->match validate_buffer device b with Error _ as e->e|Ok()->let ad=Result.get_ok(Buffer.descriptor device a)and bd=Result.get_ok(Buffer.descriptor device b)in if ao>Int64.sub ad.size n||bo>Int64.sub bd.size n then error"Ogpu_metal.Queue.submit"Ogpu.Error.Invalid_argument"copy exceeds buffer"else Ok())
  |Command.Private.Compute(_,_,b,_)->validate_buffer device b
  |Command.Private.Clear(t,_)->validate_texture device t
let rec validate_all device=function []->Ok()|x::xs->match validate_operation device x with Error _ as e->e|Ok()->validate_all device xs
let encode command operations =
  let op="Ogpu_metal.Queue.submit"in
  let cleanup=ref[]in let add f=cleanup:=f::!cleanup in
  let rec loop=function
    |[]->Ok(!cleanup)
    |Command.Private.Copy(a,ao,b,bo,n)::rest->(match Metal.Blit_encoder.create command with Error e->Error(Adapter.error~operation:op e)|Ok encoder->(match Metal.Blit_encoder.copy_buffer encoder~source:(Buffer.Private.metal a)~source_offset:ao~destination:(Buffer.Private.metal b)~destination_offset:bo~length:n with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Blit_encoder.end_encoding encoder with Error e->Error(Adapter.error~operation:op e)|Ok()->loop rest))
    |Command.Private.Compute(source,entry,buffer,threads)::rest->(match Metal.Library.compile_source~device:(Metal.Command_buffer.device command)source with Error e->Error(Adapter.error~operation:op e)|Ok library->add(fun()->ignore(Metal.Library.destroy library));match Metal.Function.find~library entry with Error e->Error(Adapter.error~operation:op e)|Ok function_->add(fun()->ignore(Metal.Function.destroy function_));match Metal.Compute_pipeline.create function_ with Error e->Error(Adapter.error~operation:op e)|Ok pipeline->add(fun()->ignore(Metal.Compute_pipeline.destroy pipeline));match Metal.Compute_encoder.create command with Error e->Error(Adapter.error~operation:op e)|Ok encoder->(match Metal.Compute_encoder.set_pipeline encoder pipeline with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Compute_encoder.set_buffer encoder~index:0~offset:0L(Buffer.Private.metal buffer)with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Compute_encoder.dispatch_threads encoder~threads:(threads,1,1)~threadgroup:(min threads 64,1,1)with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Compute_encoder.end_encoding encoder with Error e->Error(Adapter.error~operation:op e)|Ok()->loop rest))
    |Command.Private.Clear(texture,color)::rest->(match Metal.Render_encoder.create command~target:(Texture.Private.metal texture)~clear:color()with Error e->Error(Adapter.error~operation:op e)|Ok encoder->match Metal.Render_encoder.end_encoding encoder with Error e->Error(Adapter.error~operation:op e)|Ok()->loop rest)
  in loop operations
let submit value command =let op="Ogpu_metal.Queue.submit"in if value.dead then error op Ogpu.Error.Stale_handle"queue is destroyed"else if value.fail_next then(value.fail_next<-false;error op Ogpu.Error.Device_lost"injected submission failure")else let operations=Command.Private.operations command in
  match validate_all value.device operations with Error _ as e->e|Ok()->match Ogpu.Submission.submit value.submission(Command.Private.portable command)~resources:[]with Error _ as e->e|Ok receipt->match Metal.Command_buffer.create value.metal()with Error e->Error(Adapter.error~operation:op e)|Ok native->match encode native operations with Error e->ignore(Metal.Command_buffer.destroy native);Error e|Ok cleanup->match Metal.Command_buffer.commit native with Error e->ignore(Metal.Command_buffer.destroy native);Error(Adapter.error~operation:op e)|Ok()->value.pending<-value.pending@[{epoch=receipt.id;command=native;cleanup}];Ok{epoch=receipt.id}
let wait_through value epoch=let op="Ogpu_metal.Queue.wait_through"in if epoch<=completed_epoch value||epoch>Int64.of_int(max_int)then error op Ogpu.Error.Invalid_argument"completion epoch is invalid"else
  let ready,later=List.partition(fun (p:pending)->p.epoch<=epoch)value.pending in
  if ready=[] then error op Ogpu.Error.Invalid_argument"epoch was not submitted"else
  let rec wait=function []->Ok()|p::ps->match Metal.Command_buffer.wait_until_completed p.command with Error e->Error(Adapter.error~operation:op e)|Ok()->(match Metal.Command_buffer.status p.command with Ok Metal.Command_buffer.Completed->ignore(Metal.Command_buffer.destroy p.command);List.iter(fun f->f())p.cleanup;wait ps|Ok(Metal.Command_buffer.Error message)->error op Ogpu.Error.Device_lost message|Ok _->error op Ogpu.Error.Invalid_state"command did not complete"|Error e->Error(Adapter.error~operation:op e))in
  match wait ready with Error _ as e->e|Ok()->value.pending<-later;Ogpu.Submission.complete_through value.submission epoch
let destroy value=let op="Ogpu_metal.Queue.destroy"in if value.dead then Ok()else if value.pending<>[]then error op Ogpu.Error.Invalid_state"queue has commands in flight"else match Metal.Command_queue.destroy value.metal with Error e->Error(Adapter.error~operation:op e)|Ok()->value.dead<-true;Device.Private.detach_resource value.device;Ok()
