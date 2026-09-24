let fail message=raise(Failure message)
let ok=function Ok value->value|Error e->fail(Ogpu.Error.to_string e)
let expect kind=function Error(e:Ogpu.Error.t)when e.kind=kind->()|_->fail"unexpected sync result"
let ()=
  let d1=Ogpu.Handle.create_device()and d2=Ogpu.Handle.create_device()in
  let fence=ok(Ogpu.Sync.create_fence d1 ~initial:1L)and event=ok(Ogpu.Sync.create_event d1 ~initial:0L)in
  ignore(ok(Ogpu.Sync.signal_fence d1 fence 3L));expect Ogpu.Error.Invalid_argument(Ogpu.Sync.signal_fence d1 fence 2L);ignore(ok(Ogpu.Sync.wait_fence d1 fence 3L));expect Ogpu.Error.Invalid_state(Ogpu.Sync.wait_fence d1 fence 4L);expect Ogpu.Error.Cross_device(Ogpu.Sync.wait_fence d2 fence 1L);
  ignore(ok(Ogpu.Sync.signal_event d1 event 2L));ignore(ok(Ogpu.Sync.wait_event d1 event 2L));expect Ogpu.Error.Invalid_state(Ogpu.Sync.wait_event d1 event 3L);
  expect Ogpu.Error.Unsupported(Ogpu.Sync.create_query_set d1 ~supported:false ~kind:Timestamp ~count:4);let queries=ok(Ogpu.Sync.create_query_set d1 ~supported:true ~kind:Timestamp ~count:4)and destination=Ogpu.Handle.create ~device:d1 in
  ignore(ok(Ogpu.Sync.resolve d1 queries ~destination ~destination_size:64L ~first:1 ~count:2 ~destination_offset:8L ~completion_epoch:7L));
  List.iter(fun(first,count,offset)->expect Ogpu.Error.Invalid_argument(Ogpu.Sync.resolve d1 queries ~destination ~destination_size:32L ~first ~count ~destination_offset:offset ~completion_epoch:1L))[(-1,1,0L);(0,0,0L);(3,2,0L);(0,1,1L);(0,4,8L)];
  Ogpu.Sync.destroy_query_set queries;expect Ogpu.Error.Stale_handle(Ogpu.Sync.resolve d1 queries ~destination ~destination_size:64L ~first:0 ~count:1 ~destination_offset:0L ~completion_epoch:1L);
  Ogpu.Sync.destroy_fence fence;expect Ogpu.Error.Stale_handle(Ogpu.Sync.signal_fence d1 fence 4L);print_endline"OGPU synchronization validation passed"
