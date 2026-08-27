open Ogpu.Descriptor_arena
let get=function Ok value->value|Error value->failwith(Ogpu.Error.to_string value)
let expect kind=function Error value when value.Ogpu.Error.kind=kind->()|Error value->failwith(Ogpu.Error.to_string value)|Ok _->failwith"unexpected arena success"
let receipt id : Ogpu.Submission.receipt={id;commands=[||]}
let sequence()=
  let device=Ogpu.Handle.create_device()in let arena=get(create~device~capacity:8)in
  let a=get(allocate device arena~count:3)and b=get(allocate device arena~count:2)in
  let result=Array.to_list(slots a),Array.to_list(slots b)in
  ignore(get(reset arena~completed_epoch:0L));ignore(get(destroy arena));Ogpu.Handle.destroy_device device;result
let ()=
  let expected=sequence()in let workers=Array.init 4(fun _->Domain.spawn sequence)in Array.iter(fun worker->if Domain.join worker<>expected then failwith"descriptor slot domain drift")workers;
  let device=Ogpu.Handle.create_device()and foreign=Ogpu.Handle.create_device()in let arena=get(create~device~capacity:4)in
  expect Ogpu.Error.Invalid_argument(allocate device arena~count:0);expect Ogpu.Error.Invalid_argument(allocate device arena~count:5);
  let first=get(allocate device arena~count:2)in if slots first<>[|0;1|]then failwith"first slot ordering drift";
  expect Ogpu.Error.Cross_device(validate foreign first);ignore(get(mark_submitted first(receipt 2L)));
  expect Ogpu.Error.Invalid_state(release first);ignore(get(reset arena~completed_epoch:1L));
  if live_count arena<>1||pending_count arena<>1 then failwith"early submitted reset";
  let second=get(allocate device arena~count:2)in if slots second<>[|2;3|]then failwith"pending slots were reused";
  expect Ogpu.Error.Capacity(allocate device arena~count:1);ignore(get(reset arena~completed_epoch:2L));
  expect Ogpu.Error.Stale_handle(validate device first);
  let reused=get(allocate device arena~count:2)in if slots reused<>[|0;1|]then failwith"lowest slot reuse drift";
  if generations reused=[|1L;1L|]then failwith"slot generations did not advance";
  ignore(get(release reused));expect Ogpu.Error.Stale_handle(release second);
  for epoch=3 to 100002 do
    let value=get(allocate device arena~count:4)in ignore(get(mark_submitted value(receipt(Int64.of_int epoch))));
    ignore(get(reset arena~completed_epoch:(Int64.of_int epoch)))
  done;
  if live_count arena<>0||pending_count arena<>0||metadata_count arena<>4 then failwith"100k arena metadata plateau drift";
  expect Ogpu.Error.Invalid_argument(reset arena~completed_epoch:1L);ignore(get(destroy arena));
  expect Ogpu.Error.Stale_handle(allocate device arena~count:1);Ogpu.Handle.destroy_device device;Ogpu.Handle.destroy_device foreign;
  print_endline"OGPU descriptor arena: epochs/generations, 100k plateau, 4-domain exact ok"
