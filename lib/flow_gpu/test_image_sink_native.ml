module G=Flow_gpu
module B=Ogpu.Backend
module P=Procedural
module I=Runtime_resources.Image
let get=Test_program.ok
let resource=function Ok x->x|Error e->failwith(Format.asprintf "%a" Runtime_resources.pp_error e)
let execution=function Ok x->x|Error e->failwith(Format.asprintf "%a" Rays_execution.pp_error e)
let native=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let packed ~width ~height body =
  let forms=Flow.Syntax.parse ("(workspace image (graph g :context image (image/map (fn [uv] "^body^"))))") |> get in
  let w=match Flow.Workspace.check {Flow.Check.version=1;kinds=[]} forms with
    |Some w,[]->w|_,ds->failwith(String.concat "; "(List.map Flow.Diagnostic.to_string ds))in
  let evaluated=Flow.Eval.static w |> get in
  let fn=match List.assoc "function" evaluated.plan.nodes.(0).args with Flow.Eval.Fn f->f|_->assert false in
  let kernel=Flow_sop.Image_kernel.prepare ~identity:0 ~width ~height ~fn ~sources:[] [] |> get in
  let program=Flow_sop.Image_kernel.program kernel in
  let ir=Flow_ir.Executor.graph program in
  match ir.nodes.(ir.roots.(0)).kind with Flow_ir.Kernel{body=Packed_map p;_}->p,program|_->assert false
let () =
  let gpu=match Rays_execution.acquire_gpu()with Ok gpu->gpu
    |Error e->failwith(Format.asprintf "%a" Rays_execution.pp_error e)in
  Fun.protect ~finally:(fun()->Rays_execution.release_gpu gpu)(fun()->
    let cache=G.Pipelines.create ~clock:Unix.gettimeofday (Rays_execution.gpu_device gpu)in
    let sink=G.Image_sink.create gpu |> get in
    Fun.protect ~finally:(fun()->G.Image_sink.close sink;G.Pipelines.close cache)(fun()->
      print_endline "test,fixture,width,height,time,max_channel_difference,differing_channels,differing_pixels";
      List.iter(fun(name,body)->
        let p,program=packed ~width:65 ~height:3 body in
        let run=G.Run.create gpu cache (G.Emit.kernel p |> get)in
        Fun.protect ~finally:(fun()->G.Run.close run)(fun()->
          let previous=ref None in
          List.iter(fun time->
            let live=Frame_input.at_time time in
            let input=Flow_ir.Packed.Private.prepare p ~live |> get in
            let output=G.Run.dispatch run input |> get in
            let converted=G.Image_sink.convert sink ~width:65 ~height:3 output |> get in
            Option.iter(fun old->assert(G.Image_sink.texture old=None)) !previous;
            previous:=Some converted;
            let texture=G.Image_sink.texture converted |> Option.get in
            let actual=B.read_texture texture ~bytes_per_row:260 |> native in
            let values=match Flow_ir.Executor.force program ~live |> get with
              |Flow.Eval.Vec4_array xs->xs|_->assert false in
            let context=P.Context.create() |> Result.get_ok in
            let expected=P.Image.Private.of_vec4 ~context ~width:65 ~height:3 values
              |> Result.get_ok |> P.Image.Private.rgba8 |> Option.get in
            let maximum=ref 0 and channels=ref 0 and pixels=ref 0 in
            for pixel=0 to 194 do
              let different=ref false in
              for channel=0 to 3 do
                let i=4*pixel+channel in
                let d=abs(Char.code(Bytes.get actual i)-Char.code(Bytes.get expected i))in
                maximum:=max !maximum d;
                if d<>0 then(incr channels;different:=true)
              done;
              if !different then incr pixels
            done;
            Printf.printf "image_sink,%s,65,3,%.2f,%d,%d,%d\n%!"
              name time !maximum !channels !pixels;
            assert(!maximum<=1);
            if name="ties"then for i=0 to 194 do
              List.iteri(fun c n->assert(Char.code(Bytes.get actual(4*i+c))=n))[0;2;2;128]
            done;
            if name="clip"then assert(actual=expected);
            let creates=G.Image_sink.Private.buffer_creations sink,G.Image_sink.Private.texture_creations sink in
            ignore(G.Image_sink.convert sink ~width:65 ~height:3 output |> get);
            assert(creates=(G.Image_sink.Private.buffer_creations sink,G.Image_sink.Private.texture_creations sink));
            assert(G.Image_sink.texture converted=None);
            let stale=output in
            ignore(G.Run.dispatch run input |> get);
            assert(Result.is_error(G.Image_sink.convert sink ~width:65 ~height:3 stale))) [0.;0.5;1.]);
        assert(G.Image_sink.Private.buffer_creations sink=1 && G.Image_sink.Private.texture_creations sink=1))
        ["gradient","[uv.x uv.y 0.5 1]";
         "live","[(+ uv.x (* t 0.25)) uv.y 0.5 1]";
         "ties","[(/ 0.5 255) (/ 1.5 255) (/ 2.5 255) (/ 127.5 255)]";
         "clip","[(- uv.x 1) (+ uv.y 1) -1 2]"];
      let p,_=packed ~width:17 ~height:5 "[uv.x uv.y t 1]"in
      let run=G.Run.create gpu cache (G.Emit.kernel p |> get)in
      Fun.protect ~finally:(fun()->G.Run.close run)(fun()->
        let inputs=Flow_ir.Packed.Private.prepare p ~live:(Frame_input.at_time 0.25) |> get in
        let output=G.Run.dispatch run inputs |> get in
        let resized=G.Image_sink.convert sink ~width:17 ~height:5 output |> get in
        let texture=G.Image_sink.texture resized |> Option.get in
        let d=B.Private.texture_descriptor texture in assert(d.width=17 && d.height=5);
        assert(G.Image_sink.Private.buffer_creations sink=2 && G.Image_sink.Private.texture_creations sink=2);
        assert(Domain.join(Domain.spawn(fun()->G.Image_sink.texture resized=None)));
        G.Image_sink.close sink;G.Image_sink.close sink;
        assert(G.Image_sink.texture resized=None && Result.is_error(G.Image_sink.convert sink ~width:17 ~height:5 output))));
    Printf.eprintf "GPU image sink: odd-width pixels, ties-even/clipping, live colors, reuse, resize and stale generations pass\n%!")

let () =
  let forms=Flow.Syntax.parse "(workspace image
    (defn render :context image [(bias : float)]
      (let* [picture (image/map (fn [uv] [(+ uv.x bias) uv.y (* t 0.5) 1]))] picture))
    (defn invoke :context image [(alias : fn)] (alias 0.125))
    (graph g :context image (invoke :alias render)))" |> get in
  let w=match Flow.Workspace.check Flow.Check.{version=1;kinds=[]} forms with
    |Some w,[]->w|_,ds->failwith(String.concat "; "(List.map Flow.Diagnostic.to_string ds))in
  let lowered=Flow_sop.Lower.of_checked ~factories:[] w |> get in
  let node=Array.find_opt(fun(n:Flow.Eval.node)->n.kind="image/map")lowered.plan.nodes |> Option.get in
  let path=lowered.image_sites.(node.id) |> Option.get in
  assert(path=["def:render";"picture"] && path<>node.site);
  let fn=match List.assoc "function" node.args with Flow.Eval.Fn fn->fn|_->assert false in
  let program=Flow_sop.Image_kernel.prepare ~path ~approx:lowered.approx
    ~site:(node.inst,node.site,node.iter) ~identity:0 ~width:65 ~height:17 ~fn ~sources:[] []
    |> get |> Flow_sop.Image_kernel.program in
  let gpu=match Rays_execution.acquire_gpu()with Ok gpu->gpu
    |Error e->failwith(Format.asprintf "%a" Rays_execution.pp_error e)in
  Fun.protect ~finally:(fun()->Rays_execution.release_gpu gpu)(fun()->
    let host=G.Host.create ~clock:Unix.gettimeofday gpu in
    let sink=G.Image_sink.create gpu |> get in
    let image=ref None and snapshots=ref []in
    Fun.protect ~finally:(fun()->
      Option.iter(fun image->resource(I.destroy image)) !image;
      List.iter(fun(_,_,lease)->I.Private.release_snapshot lease) !snapshots;
      G.Image_sink.close sink;G.Host.close host)(fun()->
      Flow_ir.Gpu.with_backend(G.Host.backend host)(fun()->
        List.iter(fun time->
          let live=Frame_input.at_time time in
          let output=match Flow_ir.Executor.try_display ~policy:Qualification program ~live |> get with
            |Some(Gpu output)->output|_->assert false in
          let converted=G.Image_sink.convert sink ~width:65 ~height:17
            (G.Host.output host output |> Option.get) |> get in
          let source()=G.Image_sink.texture converted in
          let current=match !image with
            |None->let before=Gc.allocated_bytes()in
                let current=resource(I.Private.of_gpu ~width:65 ~height:17 ~source)in
                assert(Gc.allocated_bytes()-.before<4096.);
                image:=Some current;current
            |Some current->
                assert(Result.is_error(I.Private.gpu_snapshot current));
                let identity=I.identity current and generation=I.generation current
                and readbacks=I.Private.readbacks current in
                resource(I.Private.replace_gpu_source current ~width:65 ~height:17 ~source);
                assert(I.identity current=identity && I.generation current=generation+1);
                assert(I.Private.readbacks current=readbacks);current in
          assert(I.Private.cpu_storage_bytes current=0);
          (match resource(I.Private.gpu_snapshot current)with
           |Some(w,h,_,texture)->assert((w,h)=(65,17)
              && Option.fold ~none:false ~some:((==)texture)(source()))
           |None->assert false);
          let actual=B.read_texture(G.Image_sink.texture converted |> Option.get) ~bytes_per_row:260 |> native in
          let values=match Flow_ir.Executor.force program ~live |> get with
            |Flow.Eval.Vec4_array xs->xs|_->assert false in
          let context=P.Context.create() |> Result.get_ok in
          let expected=P.Image.Private.of_vec4 ~context ~width:65 ~height:17 values
            |> Result.get_ok |> P.Image.Private.rgba8 |> Option.get in
          let maximum=ref 0 and channels=ref 0 and pixels=ref 0 in
          for pixel=0 to 65*17-1 do
            let different=ref false in
            for channel=0 to 3 do
              let i=4*pixel+channel in
              let d=abs(Char.code(Bytes.get actual i)-Char.code(Bytes.get expected i))in
              maximum:=max !maximum d;
              if d<>0 then(incr channels;different:=true)
            done;
            if !different then incr pixels
          done;
          Printf.printf "image_sink,qualified_named,65,17,%.2f,%d,%d,%d\n%!"
            time !maximum !channels !pixels;
          assert(!maximum<=1);
          let before=I.Private.readbacks current in
          let published=resource(I.pixels current)in
          assert(published=actual && I.Private.readbacks current=before+1);
          let _,_,_,bytes,lease=resource(I.Private.borrow_snapshot current)in
          assert(bytes=actual && I.Private.readbacks current=before+2);
          snapshots:=(bytes,Bytes.copy bytes,lease):: !snapshots;
          assert(I.Private.cpu_storage_bytes current=0);
          List.iter(fun(bytes,saved,_)->assert(bytes=saved)) !snapshots;
          Printf.printf "image_sink,published_named,65,17,%.2f,%d,%d,%d\n%!"
            time !maximum !channels !pixels) [0.;0.5;1.]);
      let current=Option.get !image in
      let canvas=Rays.Canvas.create ~width:65 ~height:17 |> Result.get_ok in
      Fun.protect ~finally:(fun()->Rays.Canvas.destroy canvas)(fun()->
        let image=Rays.Image.Private.of_resource current in
        let node=Rays.Scene.image image ~at:(0,0)()in
        let builder=Scene_command.Display_list.Builder.create()in
        Scene_command.Display_list.Builder.image builder ~resource_id:1
          ~source:{x=0.;y=0.;width=65.;height=17.}
          ~destination:{x=0.;y=0.;width=65.;height=17.};
        let segment=Scene_command.Display_list.Builder.publish builder
          ~id:(Scene_command.Display_list.fresh_id()) ~version:0L |> Result.get_ok in
        let snapshot canvas=let image=Rays.Canvas.to_image canvas |> Result.get_ok in
          Fun.protect ~finally:(fun()->Rays.Image.destroy image)(fun()->
            Rays.Image.Private.pixels image |> Result.get_ok)in
        List.iteri(fun index scene->
        let rendering=Rays.Scene.Private.stage_native_render ~width:65 ~height:17 scene |> Result.get_ok in
        if List.length scene>1 || (match rendering.layers with [Scene2_segment _]->true|_->false)
        then assert(rendering.resources=[]);
        let coordinator=execution(Rays_execution.create_offscreen {Rays_execution.default_configuration with
          logical_width=65;logical_height=17;drawable_width=65;drawable_height=17})in
        Fun.protect ~finally:(fun()->execution(Rays_execution.destroy coordinator))(fun()->
          let staged=Rays.Scene.Private.stage_native ~width:65 ~height:17 scene |> Result.get_ok in
          let lower()=Rays_execution.lower_scene2 coordinator ~density:1
            ~resource:(fun id->List.assoc_opt id staged.resources) staged.scene2 in
          ignore(execution(lower()));ignore(execution(lower()));
          Rays.Canvas.render canvas scene;Rays.Canvas.render canvas scene;
          let old_pixels=snapshot canvas in
          let before=I.Private.readbacks current and generation=I.generation current in
          let output=Flow_ir.Gpu.with_backend(G.Host.backend host)(fun()->
            match Flow_ir.Executor.try_display ~policy:Qualification program
              ~live:(Frame_input.at_time(0.25+.float index*.0.125)) |> get with
            |Some(Gpu output)->output|_->assert false)in
          let converted=G.Image_sink.convert sink ~width:65 ~height:17 (G.Host.output host output |> Option.get) |> get in
          assert(I.generation current=generation);
          assert(match lower()with Error{kind=Resource;_}->true|_->false);
          let failed=try Rays.Canvas.render canvas scene;false with Failure _->true in
          assert(failed && I.Private.readbacks current=before);
          resource(I.Private.replace_gpu_source current ~width:65 ~height:17
            ~source:(fun()->G.Image_sink.texture converted));
          assert(I.generation current=generation+1);
          ignore(execution(lower()));Rays.Canvas.render canvas scene;
          let pixels=snapshot canvas in assert(pixels<>old_pixels);
          let fresh=Rays.Canvas.create ~width:65 ~height:17 |> Result.get_ok in
          Fun.protect ~finally:(fun()->Rays.Canvas.destroy fresh)(fun()->
            Rays.Canvas.render fresh scene;assert(snapshot fresh=pixels))))
          [[node];[Rays.Scene.Private.display_list ~images:[1,image] segment];
           [node;Rays.Scene.Private.layer_break;node]]);
      let p,_=packed ~width:17 ~height:5 "[uv.x uv.y t 1]"in
      let cache=G.Pipelines.create ~clock:Unix.gettimeofday (Rays_execution.gpu_device gpu)in
      let run=G.Run.create gpu cache (G.Emit.kernel p |> get)in
      Fun.protect ~finally:(fun()->G.Run.close run;G.Pipelines.close cache)(fun()->
        let output=G.Run.dispatch run (Flow_ir.Packed.Private.prepare p ~live:(Frame_input.at_time 0.25) |> get) |> get in
        let converted=G.Image_sink.convert sink ~width:17 ~height:5 output |> get in
        let identity=I.identity current in
        resource(I.Private.replace_gpu_source current ~width:17 ~height:5
          ~source:(fun()->G.Image_sink.texture converted));
        assert(I.identity current=identity && resource(I.size current)=(17,5));
        assert(I.Private.cpu_storage_bytes current=0);
        G.Image_sink.close sink;
        assert(Result.is_error(I.Private.gpu_snapshot current) && Result.is_error(I.pixels current)))));
  Printf.eprintf "GPU image qualification/publication: named-call selection, exact channel parity, zero publication CPU storage/reads and retained snapshots pass\n%!"
