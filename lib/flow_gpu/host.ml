module B=Ogpu.Backend
module G=Flow_ir.Gpu
module Cache=Lru.Make(struct type t=string let equal=String.equal let hash=Hashtbl.hash end)
type runner={identity:int;run:Run.t;mutable stamp:int64;mutable output:Run.output option}
type t={gpu:Rays_execution.gpu;pipelines:Pipelines.t;runners:runner Cache.t;
  mutable closed:bool;domain:Domain.id;cost:Flow_ir.Packed.t -> count:int -> float option}
let next=Atomic.make 1
let create ?(cost=fun _ ~count:_->None) ~clock gpu =
  {gpu;pipelines=Pipelines.create ~clock(Rays_execution.gpu_device gpu);
    runners=Cache.create ~release:(fun _ runner->runner.output<-None;Run.close runner.run)64;
    closed=false;domain=Domain.self();cost}
let live t=not t.closed && Domain.self()=t.domain
let error message=Error(Flow.Diagnostic.error ~code:"E_GPU" message)
let output t (value:G.value)=
  if not(live t)then None else
  Option.bind(Cache.find_first t.runners(fun _ runner->runner.identity=value.identity))(fun runner->
    if runner.stamp<>value.stamp then None else
    Option.bind runner.output(fun output->if Run.count output<>value.count || Run.width output<>value.width
      || Run.buffer output=None then None else Some output))
let backend t : G.backend =
  {cost=(fun packed ~count->if live t then t.cost packed ~count else None);
   prepare=(fun packed->if not(live t)then error "GPU host is closed or called from another domain."else
     Result.bind (Emit.kernel packed)(fun msl->
     Result.map(fun _compiled->
       (* Each prepared producer owns an output generation. Sharing only its
          shader source would overwrite an earlier drawing's borrowed output. *)
       let key=string_of_int(Atomic.fetch_and_add next 1)in
       let runner ()=match Cache.find_opt t.runners key with Some runner->runner|None->
         let runner={identity=Atomic.fetch_and_add next 1;run=Run.create t.gpu t.pipelines msl;stamp=0L;output=None}in
         Cache.add t.runners key runner;runner in
       ignore(runner());
       {G.run=(fun inputs->if not(live t)then error "GPU host is closed or called from another domain."else
          let runner=runner()in
          Result.map(fun output->runner.output<-Some output;runner.stamp<-Int64.succ runner.stamp;
            G.{identity=runner.identity;count=Run.count output;width=Run.width output;stamp=runner.stamp})
            (Run.dispatch runner.run inputs));
        readback=(fun value->match output t value with None->error "GPU output was closed or superseded."
          |Some output->Run.readback output)}) (Pipelines.get t.pipelines msl)))}
let close t=if not t.closed then begin Cache.clear t.runners;Pipelines.close t.pipelines;t.closed<-true end
