let fail message=raise(Failure message)
let ok=function Ok()->()|Error e->fail(Ogpu.Error.to_string e)
let invalid_state=function Error(e:Ogpu.Error.t)when e.kind=Ogpu.Error.Invalid_state->()|_->fail"expected invalid state"
let invalid_argument=function Error(e:Ogpu.Error.t)when e.kind=Ogpu.Error.Invalid_argument->()|_->fail"expected invalid argument"
let encode ()=
  let open Ogpu.Command in let value=begin_encoder()in
  ok(push_debug value"frame");ok(begin_pass value Transfer);
  ok(declare_resource value ~resource_id:1L ~access:Read ~stages:[Transfer_stage]);
  invalid_state(begin_pass value Render);ok(end_pass value);
  List.iter(fun pass->ok(begin_pass value pass);ok(declare_resource value ~resource_id:2L ~access:Read_write ~stages:(match pass with Render->[Vertex;Fragment]|Compute->[Compute_stage]|Acceleration->[Acceleration_stage]|Transfer->[Transfer_stage]));ok(end_pass value))[Render;Compute;Acceleration];
  ok(pop_debug value);ok(end_encoder value);ok(present value);descriptions value
let ()=
  let open Ogpu.Command in
  let initial=begin_encoder()in invalid_state(end_pass initial);invalid_state(present initial);invalid_state(declare_resource initial ~resource_id:1L ~access:Read ~stages:[Transfer_stage]);
  ok(begin_pass initial Compute);invalid_argument(declare_resource initial ~resource_id:0L ~access:Read ~stages:[Compute_stage]);invalid_argument(declare_resource initial ~resource_id:1L ~access:Read ~stages:[]);invalid_argument(declare_resource initial ~resource_id:1L ~access:Read ~stages:[Compute_stage;Compute_stage]);invalid_state(end_encoder initial);ok(end_pass initial);invalid_state(pop_debug initial);invalid_argument(push_debug initial"bad\000label");ok(end_encoder initial);invalid_state(end_encoder initial);ok(present initial);invalid_state(present initial);
  let sequential=encode()in let parallel=Domain.spawn encode|>Domain.join in
  if sequential<>parallel then fail"one-domain and multi-domain descriptions differ";
  print_endline"OGPU linear command state and deterministic description passed"
