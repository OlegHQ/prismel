let fail message=raise(Failure message)
let ok=function Ok value->value|Error e->fail(Ogpu.Error.to_string e)
let expect kind=function Error(e:Ogpu.Error.t)when e.kind=kind->()|_->fail"unexpected submission result"
let ended()=let c=Ogpu.Command.begin_encoder()in ignore(Ogpu.Command.end_encoder c);c
let sequence()=let d=Ogpu.Handle.create_device()in let q=ok(Ogpu.Submission.create d)in Array.init 4(fun _->let r=ok(Ogpu.Submission.submit q(ended())~resources:[])in ignore(ok(Ogpu.Submission.complete_through q r.id));r.id)
let ()=
  let d1=Ogpu.Handle.create_device()and d2=Ogpu.Handle.create_device()in expect Ogpu.Error.Invalid_argument(Ogpu.Submission.create ~max_frames:0 d1);expect Ogpu.Error.Invalid_argument(Ogpu.Submission.create ~max_frames:4 d1);
  let q=ok(Ogpu.Submission.create d1)and foreign=Ogpu.Handle.create ~device:d2 in expect Ogpu.Error.Cross_device(Ogpu.Submission.submit q(ended())~resources:[foreign]);
  let resource=Ogpu.Handle.create ~device:d1 and command=ended()in let first=ok(Ogpu.Submission.submit q command ~resources:[resource])in expect Ogpu.Error.Invalid_state(Ogpu.Submission.submit q command ~resources:[]);
  ignore(ok(Ogpu.Submission.submit q(ended())~resources:[]));expect Ogpu.Error.Capacity(Ogpu.Submission.submit q(ended())~resources:[]);
  Ogpu.Handle.destroy resource;if Ogpu.Submission.retained_resource_count q<>1 then fail"submitted resource released early";ignore(ok(Ogpu.Submission.complete_through q first.id));if Ogpu.Submission.retained_resource_count q<>0 then fail"completion did not release resource";
  expect Ogpu.Error.Invalid_argument(Ogpu.Submission.complete_through q 0L);Ogpu.Submission.drain q;if Ogpu.Submission.in_flight q<>0 then fail"drain left submissions";Ogpu.Submission.lose_device q;expect Ogpu.Error.Device_lost(Ogpu.Submission.submit q(ended())~resources:[]);
  let sequential=sequence()and parallel=Domain.spawn sequence|>Domain.join in if sequential<>parallel then fail"submission ordering differs across domains";print_endline"OGPU bounded submission epochs and deferred release passed"
