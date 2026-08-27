let fail message=raise(Failure message)
let ok=function Ok value->value|Error e->fail(Ogpu.Error.to_string e)
let expect kind=function Error(e:Ogpu.Error.t)when e.kind=kind->()|_->fail"unexpected compute-pass result"
let build()=
  let device=Ogpu.Handle.create_device()and caps=Ogpu.Capabilities.minimum_m1 in let layout_entry={Ogpu.Binding.binding=0;kind=Buffer;visibility=[Compute]}in let layout=ok(Ogpu.Binding.create_layout[layout_entry])in let pipeline_layout=ok(Ogpu.Binding.create_pipeline_layout ~device ~capabilities:caps[0,layout])in let resource=Ogpu.Handle.create ~device in let group=ok(Ogpu.Binding.create_group pipeline_layout ~group:0[{binding=0;resource=Ogpu.Binding.buffer resource}])in
  let shader=ok(Ogpu.Shader.create{backend="mock";label=None;bytes=Bytes.of_string"compute";entry_points=[{name="main";stage=Compute}];bindings=[{group=0;binding=0;kind=Storage_buffer;visibility=[Compute]}]})in let pipeline=ok(Ogpu.Pipeline.create_compute caps{backend="mock";label=Some"compute";layout=pipeline_layout;shader;entry="main"})in
  let declared={Ogpu.Compute_pass.id=7L;access=Ogpu.Command.Read_write;stages=[Compute_stage]}in
  let snapshots=Ogpu.Binding.group_entries group in
  let bound_id=(List.hd snapshots).id in
  let declared={declared with id=bound_id}in
  let result=ok(Ogpu.Compute_pass.create device ~limits:caps.limits ~pipeline ~layout:pipeline_layout ~groups:[|0,group|]~resources:[|declared|]~dispatch:(Direct{x=4;y=2;z=1}))|>Ogpu.Compute_pass.describe in
  let commands=Array.map(function Ogpu.Command.Declare_resource value->Ogpu.Command.Declare_resource{value with resource_id=7L}|other->other)result.commands in {result with commands}
let ()=
  let sequential=build()and parallel=Domain.spawn build|>Domain.join in if sequential<>parallel then fail"compute descriptions differ across domains";
  let device=Ogpu.Handle.create_device()and caps=Ogpu.Capabilities.minimum_m1 in let buffer=Ogpu.Handle.create ~device in
  let shader=ok(Ogpu.Shader.create{backend="mock";label=None;bytes=Bytes.of_string"c";entry_points=[{name="main";stage=Compute}];bindings=[]})in let layout=ok(Ogpu.Binding.create_pipeline_layout ~device ~capabilities:caps[])in let pipeline=ok(Ogpu.Pipeline.create_compute caps{backend="mock";label=None;layout;shader;entry="main"})in
  expect Ogpu.Error.Invalid_argument(Ogpu.Compute_pass.create device ~limits:caps.limits ~pipeline ~layout ~groups:[||]~resources:[||]~dispatch:(Direct{x=0;y=1;z=1}));expect Ogpu.Error.Invalid_argument(Ogpu.Compute_pass.create device ~limits:caps.limits ~pipeline ~layout ~groups:[||]~resources:[||]~dispatch:(Indirect{buffer;buffer_size=12L;offset=2L}));Ogpu.Handle.destroy buffer;expect Ogpu.Error.Stale_handle(Ogpu.Compute_pass.create device ~limits:caps.limits ~pipeline ~layout ~groups:[||]~resources:[||]~dispatch:(Indirect{buffer;buffer_size=12L;offset=0L}));print_endline"OGPU compute-pass validation passed"
