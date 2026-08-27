open Ogpu.Device_lifecycle
let get=function Ok value->value|Error value->failwith(Ogpu.Error.to_string value)
let expect kind=function Error value when value.Ogpu.Error.kind=kind->()|Error value->failwith(Ogpu.Error.to_string value)|Ok _->failwith"unexpected lifecycle success"
let phase_name=function Surface_frames->"surface"|Submissions->"submission"|Descriptor_arenas->"arena"|Transfer_rings->"ring"|Caches->"cache"|Resources->"resource"
let ordered()=
  let device=Ogpu.Handle.create_device()in let lifecycle=get(create~device~capacity:6)in let seen=ref[]in
  List.iter(fun phase->get(register device lifecycle~phase~label:(phase_name phase)(fun _->seen:=!seen@[phase];Ok())))
    [Resources;Caches;Surface_frames;Transfer_rings;Submissions;Descriptor_arenas];
  let report=get(transition lifecycle~reason:Shutdown~policy:Drain)in ignore(get(destroy lifecycle));Ogpu.Handle.destroy_device device;
  !seen,report.callbacks
let ()=
  let expected=ordered()in let workers=Array.init 4(fun _->Domain.spawn ordered)in Array.iter(fun worker->if Domain.join worker<>expected then failwith"lifecycle domain order drift")workers;
  let device=Ogpu.Handle.create_device()and foreign=Ogpu.Handle.create_device()in let lifecycle=get(create~device~capacity:8)in let seen=ref[]in
  let add phase label action=get(register device lifecycle~phase~label(fun policy->seen:=!seen@[label,policy];action()))in
  add Resources"resource"(fun()->Ok());add Surface_frames"surface"(fun()->Ok());
  add Submissions"submission-failure"(fun()->Error(Ogpu.Error.make"drain"Ogpu.Error.Device_lost"injected"));
  add Caches"cache-exception"(fun()->raise(Failure"injected"));add Descriptor_arenas"arena"(fun()->Ok());
  expect Ogpu.Error.Cross_device(register foreign lifecycle~phase:Resources~label:"foreign"(fun _->Ok()));
  let report=get(transition lifecycle~reason:Device_lost~policy:Abandon)in
  if report.callbacks<>5||List.length report.failures<>2 then failwith"failure aggregation drift";
  if List.map fst!seen<>["surface";"submission-failure";"arena";"cache-exception";"resource"]then failwith"shutdown order drift";
  let again=get(transition lifecycle~reason:Shutdown~policy:Drain)in if again<>report||List.length!seen<>5 then failwith"terminal transition was not idempotent";
  expect Ogpu.Error.Invalid_state(register device lifecycle~phase:Resources~label:"late"(fun _->Ok()));ignore(get(destroy lifecycle));
  for _=1 to 100000 do
    let value=get(create~device~capacity:1)in get(register device value~phase:Resources~label:"one"(fun _->Ok()));ignore(get(transition value~reason:Shutdown~policy:Drain));
    if registered_count value<>0||metadata_count value<>1 then failwith"lifecycle metadata growth";ignore(get(destroy value))
  done;
  Ogpu.Handle.destroy_device device;Ogpu.Handle.destroy_device foreign;
  print_endline"OGPU device lifecycle: ordered loss drain, failures, 100k plateau, 4-domain exact ok"
