module G=Flow_ir.Gpu
module H=Flow_gpu.Host
module X=Rays_execution
module P=X.Private
module Sinks=Lru.Make(struct
  type t=int * float * int32 * int32 * float
  let equal=(=)
  let hash=Hashtbl.hash
end)
module Images=Lru.Make(struct type t=string let equal=String.equal let hash=Hashtbl.hash end)
type image_stats={mutable created:int;mutable closed:int;mutable buffers:int;mutable textures:int}
let close_image stats sink=
  stats.closed<-stats.closed+1;
  stats.buffers<-stats.buffers+Flow_gpu.Image_sink.Private.buffer_creations sink;
  stats.textures<-stats.textures+Flow_gpu.Image_sink.Private.texture_creations sink;
  Flow_gpu.Image_sink.close sink
type t={mutable owner:(X.gpu * H.t)option; sinks:P.gpu_circles Sinks.t;
  images:Flow_gpu.Image_sink.t Images.t;
  image_stats:image_stats;mutable closed_host:H.Private.stats;
  mutable backend:G.backend option; mutable closed:bool; mutable policy:G.policy}
let create ()=let image_stats={created=0;closed=0;buffers=0;textures=0}in
  {owner=None;sinks=Sinks.create ~release:(fun _->P.close_gpu_circles)64;
  images=Images.create ~release:(fun _->close_image image_stats)64;
  image_stats;closed_host=H.Private.zero;
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
  (* The measured cost is the Flow IR table's native GPU row;
     placement compares it with the CPU kernel tier. *)
  let backend:G.backend={cost=(fun _ ~count->Some(Flow_ir.Cost.estimate Gpu ~count));
    prepare=(fun packed->Result.bind(owner t)(fun(_,host)->(H.backend host).prepare packed))}in
  t.backend<-Some backend;backend
let with_backend t run=G.with_backend ~policy:t.policy (backend t)run
let image t ~key ~width ~height ~publish value=
  Result.bind(owner t)(fun(gpu,host)->match H.output host value with
    |None->Error(error "The image's GPU producer was closed or superseded.")
    |Some output->
        let convert sink=Result.bind(Flow_gpu.Image_sink.convert sink ~width ~height output)publish in
        match Images.find_opt t.images key with
        |Some sink->convert sink
        |None when Images.length t.images>=64->Error(error "A workspace owns at most 64 GPU image sinks.")
        |None->Result.bind(Flow_gpu.Image_sink.create gpu)(fun sink->
            t.image_stats.created<-t.image_stats.created+1;
            let committed=ref false in
            Fun.protect ~finally:(fun()->if not !committed then close_image t.image_stats sink)(fun()->
              Result.map(fun result->Images.add t.images key sink;committed:=true;result)(convert sink))))
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
let image_stats t=
  if not(Domain.is_main_domain())then invalid_arg "Workspace_gpu.image_stats: initial domain required";
  let host=Option.fold ~none:t.closed_host ~some:(fun(_,host)->H.Private.stats host)t.owner in
  let buffers=ref t.image_stats.buffers and textures=ref t.image_stats.textures in
  Images.iter t.images(fun _ sink->
    buffers:= !buffers+Flow_gpu.Image_sink.Private.buffer_creations sink;
    textures:= !textures+Flow_gpu.Image_sink.Private.texture_creations sink);
  host,t.image_stats.created,t.image_stats.closed,!buffers,!textures
let close t=
  if not(Domain.is_main_domain())then invalid_arg "Workspace_gpu.close: initial domain required";
  if not t.closed then begin
  Sinks.clear t.sinks;
  Images.clear t.images;
  Option.iter(fun(gpu,host)->H.close host;t.closed_host<-H.Private.stats host;X.release_gpu gpu)t.owner;
  t.owner<-None;t.closed<-true
end
