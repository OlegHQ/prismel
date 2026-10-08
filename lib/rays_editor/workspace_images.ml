open Rays
module E=Flow.Eval
module I=Flow_ir.Executor
module V=Flow.Value
module CPU=Procedural.Image
type entry={image:Image.t;mutable payload:CPU.t;mutable texture:(Texture.t,string)result Lazy.t;
  mutable frame:Frame_input.t option}
type t={resources:Workspace_resources.t;mutable plan:E.plan option;mutable serial:int;
  mutable arguments:I.program option array;mutable drawings:Sketch_support.Drawing.prepared option array;
  mutable entries:(string*entry)list}
let create resources={resources;plan=None;serial=0;arguments=[||];drawings=[||];entries=[]}
let error message=Flow.Diagnostic.error ~code:"E_IMAGE" message
let message result=Result.map_error error result
let (let*)=Result.bind
let bytes_of_image image =
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
      t.drawings<-Array.make(Array.length plan.nodes)None;Ok()
let rec resolve t ~state ~live plan value =
  if not(Domain.is_main_domain())then Error(error "Image resources must resolve on the initial domain.")else
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
          |_->V.fail "E_IMAGE" "Unknown image producer."in
        let dynamic=List.exists(fun(_,v)->E.is_live v)node.args || (node.kind="image/render"
          && Array.exists(fun(n:E.node)->List.exists(fun(_,v)->E.is_live v)n.args)plan.nodes)in
        let previous=List.assoc_opt key t.entries in
        (match previous with Some entry when not dynamic || Option.fold ~none:false ~some:(Frame_input.equal live)entry.frame->Ok entry
        |_->
          let* ()=if previous=None && List.length t.entries>=64 then Error(error "A workspace owns at most 64 image snapshots.")else Ok()in
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
              let* image=match previous with
                |Some entry->message(Image.upload_rgba ~into:entry.image ~width ~height ~rgba:(bytes_of_image payload)())
                |None->Workspace_resources.image t.resources key(fun()->Image.upload_rgba ~width ~height ~rgba:(bytes_of_image payload)())in
              Ok(image,payload)
          |"image/render"->
              let width=int "width" (fst live.Frame_input.size)and height=int "height" (snd live.size)in
              if width<=0||height<=0||width>Sys.max_string_length/4/height then Error(error "Image dimensions exceed native storage bounds.")else
              let drawing=List.assoc "drawing" args in
              let* prepared=match t.drawings.(id)with Some p->Ok p|None->
                Result.map(fun p->t.drawings.(id)<-Some p;p)(Sketch_support.Drawing.prepare plan drawing)in
              let* scene=Sketch_support.Drawing.render_prepared ~state
                ~image:(fun value->Result.map(fun entry->entry.image)(resolve t ~state ~live plan value))
                prepared ~live ~size:(width,height)in
              let* canvas=message(Canvas.create ~width ~height)in
              Fun.protect ~finally:(fun()->Canvas.destroy canvas)(fun()->
                Canvas.render canvas scene;
                let* image=match previous with
                  |Some entry->Result.map(fun()->entry.image)(message(Canvas.Private.copy_to_image canvas entry.image))
                  |None->Workspace_resources.image t.resources key(fun()->Canvas.to_image canvas)in
                let* payload=cpu_of_image image in Ok(image,payload))
          |_->assert false in
          let entry=match previous with
            |Some entry->entry.payload<-payload;entry.texture<-texture payload;entry.frame<-Some live;entry
            |None->{image;payload;texture=texture payload;frame=Some live}in
          if previous=None then t.entries<-(key,entry)::t.entries;Ok entry)
    |_->Error(error "Expected an image value.")
    with V.Fail(code,message,span)->Error(Flow.Diagnostic.error ?span ~code message)
      |Invalid_argument message|Failure message->Error(error message))
let image t ~state ~live plan value=Result.map(fun entry->entry.image)(resolve t ~state ~live plan value)
let payload t plan ~state ~live value=Result.map(fun entry->entry.payload)(resolve t ~state ~live plan value)
let texture t ~state ~live plan value=Result.bind(resolve t ~state ~live plan value)(fun entry->message(Lazy.force entry.texture))
