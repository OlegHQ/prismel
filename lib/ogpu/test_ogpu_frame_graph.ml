open Ogpu.Frame_graph
let fail message=raise(Failure message)
let ok=function Ok value->value|Error e->fail(Ogpu.Error.to_string e)
let expect kind=function Error(e:Ogpu.Error.t)when e.kind=kind->()|_->fail"unexpected frame-graph result"
let build tracking=
  let device=Ogpu.Handle.create_device()in let handle=Ogpu.Handle.create ~device in let resources=[|{Ogpu.Frame_graph.id=1L;handle;initialized=true}|]in
  let read={Ogpu.Frame_graph.resource_id=1L;access=Ogpu.Command.Read;stages=[Compute_stage]}and write={Ogpu.Frame_graph.resource_id=1L;access=Ogpu.Command.Write;stages=[Compute_stage]}in
  let passes=[|{Ogpu.Frame_graph.id=10;kind=Compute;accesses=[|read|];depends_on=[||];barriers=[||];native=None};{id=20;kind=Compute;accesses=[|write|];depends_on=[||];barriers=(match tracking with Safe->[||]|Untracked->[|1L|]);native=None}|]in ok(Ogpu.Frame_graph.compile device ~tracking ~resources ~passes)
let ()=
  let schedule=build Safe in if Array.map(fun value->value.Ogpu.Frame_graph.id)schedule<>[|10;20|]then fail"safe schedule order changed";
  let device=Ogpu.Handle.create_device()in let handle=Ogpu.Handle.create ~device in let resources=[|{Ogpu.Frame_graph.id=1L;handle;initialized=true}|]and access={Ogpu.Frame_graph.resource_id=1L;access=Ogpu.Command.Write;stages=[Compute_stage]}in let passes=[|{Ogpu.Frame_graph.id=1;kind=Compute;accesses=[|access|];depends_on=[||];barriers=[||];native=None};{id=2;kind=Compute;accesses=[|access|];depends_on=[||];barriers=[||];native=None}|]in
  expect Ogpu.Error.Invalid_argument(Ogpu.Frame_graph.compile device ~tracking:Untracked ~resources ~passes);
  let uninitialized=[|{Ogpu.Frame_graph.id=2L;handle;initialized=false}|]in expect Ogpu.Error.Invalid_argument(Ogpu.Frame_graph.compile device ~tracking:Safe ~resources:uninitialized ~passes:[|{passes.(0)with accesses=[|{access with resource_id=2L;access=Read}|]}|]);
  let cycle=[|{passes.(0)with depends_on=[|2|]};{passes.(1)with depends_on=[|1|]}|]in expect Ogpu.Error.Invalid_argument(Ogpu.Frame_graph.compile device ~tracking:Safe ~resources ~passes:cycle);
  let sequential=build Safe and parallel=Domain.spawn(fun()->build Safe)|>Domain.join in if sequential<>parallel then fail"frame-graph schedules differ across domains";print_endline"OGPU frame-graph hazard validation passed"
