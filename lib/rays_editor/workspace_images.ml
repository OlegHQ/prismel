open Rays
module E=Flow.Eval
module I=Flow_ir.Executor
module V=Flow.Value
module CPU=Procedural.Image
type stamp={serial:int;frame:Frame_input.t;state_stamp:string}
type snapshot={payload:CPU.t;stamp:stamp}
type entry={mutable image:Image.t option;mutable cpu:snapshot option;
  mutable texture:(Texture.t,string)result Lazy.t option;mutable borrowed:Texture.t option;
  mutable display:stamp option}
type t={resources:Workspace_resources.t;gpu:Workspace_gpu.t;domains:int;mutable plan:E.plan option;mutable serial:int;
  mutable qualification:(E.plan * Flow.Workspace.Paths.t * Flow.Workspace.path option array) option;
  mutable arguments:I.program option array;mutable drawings:Sketch_support.Drawing.prepared option array;
  mutable maps:(int * int * E.fn * Flow_sop.Image_kernel.t) option array;
  mutable resolved:entry option array;
  mutable entries:(string*entry)list}
let create ?(domains=Parallel.recommended_domains()) ~gpu resources={resources;gpu;domains;plan=None;serial=0;
  qualification=None;
  arguments=[||];drawings=[||];maps=[||];resolved=[||];entries=[]}
let error message=Flow.Diagnostic.error ~code:"E_IMAGE" message
let message result=Result.map_error error result
let (let*)=Result.bind
let bind t (lowered:Flow_sop.Lower.t) =
  if not(Option.fold ~none:false ~some:(fun (plan,approx,image_sites)->plan==lowered.plan
      && approx==lowered.approx && image_sites==lowered.image_sites)t.qualification)then begin
    t.qualification<-Some(lowered.plan,lowered.approx,lowered.image_sites);t.plan<-None
  end
let bytes_of_image image =
  match CPU.Private.rgba8 image with Some bytes->bytes|None->
    let rgba=CPU.Private.storage image in
    Bytes.init(Array.length rgba)(fun i->Char.chr(int_of_float(Float.round(rgba.(i)*.255.))))
let cpu_of_image image =
  let* bytes=message(Image.Private.pixels image)in
  let width,height=Image.get_size image in
  let rgba=Array.init(Bytes.length bytes)(fun i->float(Char.code(Bytes.get bytes i))/.255.)in
  Result.map_error(fun d->error d.Procedural.Diagnostic.message)(CPU.Private.of_owned_rgba ~width ~height rgba)
let texture payload=lazy(
  let bytes=bytes_of_image payload in
  Texture.Private.create_owned ~width:(CPU.width payload) ~height:(CPU.height payload)
    (Array.init(Bytes.length bytes/4)(fun i->let o=4*i in
      Color.rgba(Char.code(Bytes.get bytes o))(Char.code(Bytes.get bytes(o+1)))
        (Char.code(Bytes.get bytes(o+2)))(Char.code(Bytes.get bytes(o+3))))))
let prepare t plan =
  match t.plan with Some old when old==plan->Ok()|_->
    let programs=Array.map(fun(n:E.node)->if n.ty=Flow.Ty.image then
      Result.map Option.some (I.compile(E.Record n.args))else Ok None)plan.E.nodes in
    match Array.find_opt Result.is_error programs with Some(Error d)->Error d|_->
      t.plan<-Some plan;t.serial<-t.serial+1;t.arguments<-Array.map Result.get_ok programs;
      t.drawings<-Array.make(Array.length plan.nodes)None;
      t.maps<-Array.make(Array.length plan.nodes)None;
      t.resolved<-Array.make(Array.length plan.nodes)None;Ok()
let rec resolve ?(pending=0) t ~display ~state ~live plan value =
  if not(Domain.is_main_domain())then Error(error "Image resources must resolve on the initial domain.")else
  if t.resources.closed then Error(error "Workspace image resources are closed.")else
  let* ()=prepare t plan in
  E.transaction state(fun()->try
    match value with
    |E.Deferred(Flow.Ty.Named "image",id)when id>=0 && id<Array.length plan.nodes->
        let* forced=I.force ~state (Option.get t.arguments.(id)) ~live in
        let args=match forced with E.Record args->args|_->assert false in
        let int key default=Option.fold ~none:default ~some:V.int_of(List.assoc_opt key args)in
        let number key default=Option.fold ~none:default ~some:V.num(List.assoc_opt key args)in
        let node=plan.nodes.(id)in
        let key=match node.kind with
          |"image/load"->(match List.assoc "path" args with E.Text path->"load:"^path|_->V.fail "E_IMAGE" "Image path is text.")
          |"image/noise" when List.exists(fun(_,v)->E.is_live v)node.args->Printf.sprintf "noise:%d:%d" t.serial id
          |"image/noise"->"noise:"^Marshal.to_string args [Marshal.No_sharing]
          |"image/render"->Printf.sprintf "render:%d:%d" t.serial id
          |"image/map"->"map:"^Marshal.to_string(node.inst,node.site,node.iter)[Marshal.No_sharing]
          |_->V.fail "E_IMAGE" "Unknown image producer."in
        let plan_dependent predicate=node.kind="image/render"
          && Array.exists(fun(n:E.node)->List.exists(fun(_,v)->predicate v)n.args)plan.nodes in
        let stateful=List.exists(fun(_,v)->E.state_dependent v)node.args || plan_dependent E.state_dependent in
        let dynamic=List.exists(fun(_,v)->E.is_live v || E.frame_dependent v)node.args || stateful
          || plan_dependent(fun v->E.is_live v || E.frame_dependent v)in
        let previous=List.assoc_opt key t.entries in
        let state_stamp=if stateful then E.state_stamp state else "" in
        let stamp={serial=t.serial;frame=live;state_stamp}in
        let valid (old:stamp)=(node.kind<>"image/map" || (old.serial=t.serial && Option.is_some t.maps.(id)))
          && (not dynamic || (Frame_input.equal live old.frame && old.state_stamp=state_stamp))in
        let result=(match previous with Some entry when
          (if display then Option.fold ~none:false ~some:valid entry.display
           else Option.fold ~none:false ~some:(fun cpu->valid cpu.stamp)entry.cpu)->Ok entry
        |_->
          let* ()=if previous=None && List.length t.entries+pending>=64 then Error(error "A workspace owns at most 64 image snapshots.")else Ok()in
          let pending=pending+(if previous=None then 1 else 0)in
          let entry=match previous with Some entry->entry|None->
            {image=None;cpu=None;texture=None;borrowed=None;display=None}in
          if display then entry.display<-None;
          let upload ~width ~height payload=
            match entry.image with
            |Some image->message(Image.upload_rgba ~into:image ~width ~height ~rgba:(bytes_of_image payload)())
            |None->Workspace_resources.image t.resources key(fun()->Image.upload_rgba ~width ~height ~rgba:(bytes_of_image payload)())in
          let* ()=if node.kind="image/map" then begin
            let width=int "width" 256 and height=int "height" 256 in
            let fn=match List.assoc "function" args with E.Fn fn->fn
              |_->V.fail "E_IMAGE" "Image map needs a pixel function."in
            let* prepared=match t.maps.(id)with
              |Some(w,h,f,p)when w=width && h=height && f==fn->Ok p
              |_->
                  let sources=Flow_sop.Attribute_kernel.sources(E.Fn fn)in
                  if sources<>[] then Error(error "Captured geometry needs a cooked image-kernel source resolver.")else
                  let path,approx=match t.qualification with
                    |Some(bound,approx,image_sites)when bound==plan->image_sites.(id),approx
                    |_->None,Flow.Workspace.Paths.empty in
                  Result.map(fun p->t.maps.(id)<-Some(width,height,fn,p);p)
                    (Flow_sop.Image_kernel.prepare ?path ~approx ~site:(node.inst,node.site,node.iter)
                      ~identity:(Procedural.Node.Private.fresh_id()) ~width ~height ~fn ~sources:[] [])in
            let cook()=match entry.cpu with Some cpu when valid cpu.stamp->Ok cpu.payload|_->
              let source=Flow_sop.Image_kernel.node ~state:(E.fork_state state) prepared in
              let* context=Result.map_error error(Procedural.Context.create ~input:live ~time:live.t
                ~frame:(Int64.of_int live.frame) ~domains:t.domains())in
              let* session=Result.map_error error(Procedural.Session.create ~max_entries:0 ~max_payload_bytes:0)in
              let* payload=Fun.protect ~finally:(fun()->Procedural.Session.close session)(fun()->
                let* cooked=Result.map_error(fun d->error d.Procedural.Diagnostic.message)
                  (Procedural.Session.cook session ~context source)in
                Result.map_error(fun d->error d.Procedural.Diagnostic.message)(Procedural.Payload.image cooked.payload))in
              entry.cpu<-Some{payload;stamp};Ok payload in
            if not display then Result.map ignore(cook())else
            let* selected=Workspace_gpu.with_backend t.gpu(fun()->
              I.try_display ~state (Flow_sop.Image_kernel.program prepared) ~live)in
            match selected with
            |None->let* payload=cook()in let* image=upload ~width ~height payload in
                entry.image<-Some image;entry.texture<-Some(texture payload);Ok()
            |Some(Cpu _)->Error(error "Image display unexpectedly requested a GPU readback.")
            |Some(Gpu value)->
                Workspace_gpu.image t.gpu ~key ~width ~height value ~publish:(fun output->
                let source()=Flow_gpu.Image_sink.texture output in
                let* image=match entry.image with
                  |None->Workspace_resources.image t.resources key(fun()->
                      match Runtime_resources.Image.Private.of_gpu ~width ~height ~source with
                      |Error error->Error(Format.asprintf "%a" Runtime_resources.pp_error error)
                      |Ok image->let accepted=ref false in
                        Fun.protect ~finally:(fun()->if not !accepted then ignore(Runtime_resources.Image.destroy image))(fun()->
                          Result.map(fun view->entry.borrowed<-Some view;accepted:=true;Image.Private.of_resource image)
                            (Texture.Private.of_image image)))
                  |Some image->Result.map(fun()->image)
                      (Result.map_error(fun e->error(Format.asprintf "%a" Runtime_resources.pp_error e))
                        (Runtime_resources.Image.Private.replace_gpu_source (Image.Private.resource image)
                          ~width ~height ~source))in
                let* borrowed=match entry.borrowed with Some view->Ok view|None->
                  message(Texture.Private.of_image(Image.Private.resource image))in
                entry.image<-Some image;entry.borrowed<-Some borrowed;
                entry.texture<-Some(lazy(Ok borrowed));Ok())
          end else begin
          entry.display<-None;
          let* image,payload=match node.kind with
          |"image/load"->let path=match List.assoc "path" args with E.Text path->path|_->assert false in
              let* image=Workspace_resources.image t.resources key (fun()->Image.load path)in
              let* payload=cpu_of_image image in Ok(image,payload)
          |"image/noise"->
              let width=int "width" 256 and height=int "height" 256 in
              let frequency=number "frequency" (number "freq" 0.02)and seed=int "seed" 0 in
              let* ()=if not(Float.is_finite frequency)||frequency<0. then Error(error "Noise frequency must be finite and nonnegative.")else Ok()in
              let source=Procedural.Image_nodes.noise ~width ~height ~frequency ~seed ()in
              let* context=Result.map_error error(Procedural.Context.create ())in
              let* cooked=Result.map_error(fun d->error d.Procedural.Diagnostic.message)
                (Procedural.Node.Private.cook source context [||])in
              let* payload=Result.map_error(fun d->error d.Procedural.Diagnostic.message)(Procedural.Payload.image cooked.payload)in
              let* image=upload ~width ~height payload in
              Ok(image,payload)
          |"image/render"->
              let width=int "width" (fst live.Frame_input.size)and height=int "height" (snd live.size)in
              if width<=0||height<=0||width>Sys.max_string_length/4/height then Error(error "Image dimensions exceed native storage bounds.")else
              let drawing=List.assoc "drawing" args in
              let* prepared=match t.drawings.(id)with Some p->Ok p|None->
                Result.map(fun p->t.drawings.(id)<-Some p;p)(Sketch_support.Drawing.prepare plan drawing)in
              let temporary=ref[]in
              Fun.protect ~finally:(fun()->List.iter Image.destroy !temporary)(fun()->
              let* scene=Sketch_support.Drawing.render_prepared ~state
                ~image:(fun value->
                  let* child=resolve ~pending t ~display:false ~state ~live plan value in
                  let payload=(Option.get child.cpu).payload in
                  let width=CPU.width payload and height=CPU.height payload in
                  match child.image with
                  |Some image when Runtime_resources.Image.Private.gpu_snapshot
                      (Image.Private.resource image)=Ok None->
                      child.display<-None;
                      message(Image.upload_rgba ~into:image ~width ~height ~rgba:(bytes_of_image payload)())
                  |None->
                      let key=fst(List.find(fun(_,candidate)->candidate==child)t.entries)in
                      let* image=Workspace_resources.image t.resources key(fun()->
                        Image.upload_rgba ~width ~height ~rgba:(bytes_of_image payload)())in
                      child.image<-Some image;Ok image
                  |Some _->let* image=message(Image.upload_rgba ~width ~height ~rgba:(bytes_of_image payload)())in
                      temporary:=image:: !temporary;Ok image)
                prepared ~live ~size:(width,height)in
              let* canvas=message(Canvas.create ~width ~height)in
              Fun.protect ~finally:(fun()->Canvas.destroy canvas)(fun()->
                Canvas.render canvas scene;
                let* image=match entry.image with
                  |Some image->Result.map(fun()->image)(message(Canvas.Private.copy_to_image canvas image))
                  |None->Workspace_resources.image t.resources key(fun()->Canvas.to_image canvas)in
                let* payload=cpu_of_image image in Ok(image,payload)))
          |_->assert false in
          entry.cpu<-Some{payload;stamp};entry.image<-Some image;
          entry.texture<-Some(texture payload);Ok()end in
          if display then entry.display<-Some stamp;
          if previous=None then t.entries<-(key,entry)::t.entries;Ok entry)in
        Result.map(fun entry->t.resolved.(id)<-Some entry;entry)result
    |_->Error(error "Expected an image value.")
    with V.Fail(code,message,span)->Error(Flow.Diagnostic.error ?span ~code message)
      |Invalid_argument message|Failure message->Error(error message))
let image t ~state ~live plan value=Result.map(fun entry->Option.get entry.image)(resolve t ~display:true ~state ~live plan value)
let payload t plan ~state ~live value=Result.map(fun entry->(Option.get entry.cpu).payload)(resolve t ~display:false ~state ~live plan value)
let texture t ~state ~live plan value=Result.bind(resolve t ~display:true ~state ~live plan value)(fun entry->message(Lazy.force(Option.get entry.texture)))
let peek t plan id=if t.resources.closed || not(Option.fold ~none:false ~some:((==)plan)t.plan)
  || id<0 || id>=Array.length t.resolved then None else Option.bind t.resolved.(id)(fun entry->entry.image)
let close t=t.plan<-None;t.qualification<-None;t.arguments<-[||];t.drawings<-[||];
  t.maps<-[||];t.resolved<-[||];t.entries<-[]
