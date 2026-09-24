open Ogpu.Instance
let fail message=raise(Failure message)
let ok=function Ok value->value|Error e->fail(Ogpu.Error.to_string e)
let expect kind=function Error(e:Ogpu.Error.t)when e.kind=kind->()|_->fail"unexpected instance result"
let limits=Ogpu.Capabilities.minimum_m1.limits
let profiles=[{Ogpu.Instance.backend_id="m1";name="Minimum M1";priority=10;capabilities=[Timestamp_queries;Unknown"future.m1"];limits};{backend_id="m3";name="M3+";priority=20;capabilities=[Ray_tracing;Metal_fx;Timestamp_queries;Unknown"future.m3"];limits}]
let enumerate()=let instance=ok(Ogpu.Instance.create profiles)in ok(Ogpu.Instance.adapters instance)|>Array.map(fun adapter->Ogpu.Instance.adapter_id adapter,(Ogpu.Instance.adapter_descriptor adapter).backend_id)
let ()=
  let instance=ok(Ogpu.Instance.create profiles)in let adapters=ok(Ogpu.Instance.adapters instance)in if Array.map(fun value->(Ogpu.Instance.adapter_descriptor value).backend_id)adapters<>[|"m3";"m1"|]then fail"adapter ordering changed";
  let m3=ok(Ogpu.Instance.select instance ~required:[Ray_tracing])in let descriptor=Ogpu.Instance.adapter_descriptor m3 in if not(List.mem(Unknown"future.m3")descriptor.capabilities)then fail"unknown capability was lost";
  expect Ogpu.Error.No_adapter(Ogpu.Instance.select instance ~required:[Unknown"absent"]);let device=ok(Ogpu.Instance.request_device m3 ~required:[Ray_tracing])in if Ogpu.Handle.device_destroyed(Ogpu.Instance.device_handle device)then fail"new device is stale";
  let m1=adapters.(1)in expect Ogpu.Error.Unsupported(Ogpu.Instance.request_device m1 ~required:[Ray_tracing]);Ogpu.Instance.destroy_adapter m3;if not(Ogpu.Handle.device_destroyed(Ogpu.Instance.device_handle device))then fail"adapter destroy did not destroy device";expect Ogpu.Error.Stale_handle(Ogpu.Instance.request_device m3 ~required:[]);
  let sequential=enumerate()and parallel=Domain.spawn enumerate|>Domain.join in if sequential<>parallel then fail"adapter enumeration differs across domains";Ogpu.Instance.destroy instance;Ogpu.Instance.destroy instance;expect Ogpu.Error.Stale_handle(Ogpu.Instance.adapters instance);print_endline"OGPU deterministic instance and adapter selection passed"
