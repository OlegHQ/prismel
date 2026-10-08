module G=Flow_ir.Gpu
module H=Flow_gpu.Host
module X=Rays_execution
module P=X.Private
module Sinks=Lru.Make(struct
  type t=int * float * int32 * int32 * float
  let equal=(=)
  let hash=Hashtbl.hash
end)
type t={mutable owner:(X.gpu * H.t)option; sinks:P.gpu_circles Sinks.t;
  mutable backend:G.backend option; mutable closed:bool; mutable policy:G.policy}
let create ()={owner=None;sinks=Sinks.create ~release:(fun _->P.close_gpu_circles)64;
  backend=None;closed=false;policy=G.Measured}
let qualification t=
  if t.closed || not(Domain.is_main_domain())then invalid_arg "Workspace_gpu.qualification: open initial-domain owner required";
  t.policy<-G.Qualification
let policy t=t.policy
let error message=Flow.Diagnostic.error ~code:"E_GPU" message
let native result=Result.map_error(fun e->error e.X.message)result
let owner t =
  if t.closed || not(Domain.is_main_domain())then Error(error "Workspace GPU resources require their open initial-domain owner.")else
  match t.owner with Some owner->Ok owner|None->
    Result.map(fun gpu->let owner=gpu,H.create ~clock:Unix.gettimeofday gpu in
      t.owner<-Some owner;owner)(native(X.acquire_gpu()))
let backend t = match t.backend with Some backend->backend|None->
  let backend:G.backend={cost=(fun _ ~count:_->None);
    prepare=(fun packed->Result.bind(owner t)(fun(_,host)->(H.backend host).prepare packed))}in
  t.backend<-Some backend;backend
let with_backend t run=G.with_backend ~policy:t.policy (backend t)run
let circles t (value:G.value) ~radius ~fill ~stroke ~stroke_width =
  Result.bind(owner t)(fun(gpu,host)->
    match H.output host value with
    |None->Error(error "The drawing's GPU producer was closed or superseded.")
    |Some _->
      let key=value.identity,radius,fill,stroke,stroke_width in
      let sink=match Sinks.find_opt t.sinks key with Some sink->Ok sink|None->
        Result.map(fun sink->Sinks.add t.sinks key sink;sink)(native(P.create_gpu_circles gpu))in
      Result.bind sink(fun sink->native(P.gpu_circles sink
        ~source:(fun()->Option.bind(H.output host value)Flow_gpu.Run.buffer)
        ~count:value.count ~radius ~fill ~stroke ~stroke_width)))
let close t=
  if not(Domain.is_main_domain())then invalid_arg "Workspace_gpu.close: initial domain required";
  if not t.closed then begin
  Sinks.clear t.sinks;
  Option.iter(fun(gpu,host)->H.close host;X.release_gpu gpu)t.owner;
  t.owner<-None;t.closed<-true
end
