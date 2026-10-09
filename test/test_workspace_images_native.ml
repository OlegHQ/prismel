module E=Flow.Eval
let ok=function Ok value->value|Error d->failwith(Flow.Diagnostic.to_string d)
let load text=match Rays_editor.Workspace.load text with Ok doc->doc|Error diagnostics->
  failwith(String.concat "; "(List.map Flow.Diagnostic.to_string diagnostics))
let () =
  let exercise ~stateful =
    let bias=if stateful then "(state [previous 0.0] (+ previous 0.2))" else "(* t 0.1)"in
    let channel=if stateful then "0.5" else "bias"in
    let scale=if stateful then " :scale (+ 1 (ref bias))" else ""in
    let doc=load("(workspace mapped
      (graph bias :context value "^bias^")
      (graph img :context image (let* [bias (ref bias)]
        (image/map (fn [uv] [uv.x uv.y "^channel^" 1]) :width 65 :height 3)))
      (graph drawing :context draw (draw/image (ref img)"^scale^"))
      (graph rendered :context image (image/render (ref drawing) :width 65 :height 3)))")in
    let owner=Result.get_ok(Rays_editor.Editor3.create ~workspace:doc ~await:true ~domains:1
      ~prepare:(fun _ _->Ok()) ~scene3:(fun _ ()->Rays.Scene3.empty)())in
    Fun.protect ~finally:(fun()->Rays_editor.Editor3.close owner)(fun()->
      let evaluated=ok(E.static doc.checked)in
      let image_value=List.assoc "rendered" evaluated.results in
      let snapshot state live=Rays_editor.Editor3.Private.with_images ~plan:evaluated.plan ~state ~live owner
        (fun ~image ~texture:_->let image=ok(image image_value)in
          image,Result.get_ok(Rays.Image.Private.pixels image))in
      let state=E.create_state()in
      let live0=Frame_input.at_time 0. and live1={(Frame_input.at_time 1.)with frame=1}in
      if stateful then ignore(ok(E.run ~state ~live:live0 ~time:0. doc.checked));
      let first,zero=snapshot state live0 in
      if stateful then ignore(ok(E.run ~state ~live:live1 ~time:1. doc.checked));
      let second,one=snapshot state live1 in
      assert(first==second && zero<>one);
      if stateful then begin
        let fresh=E.create_state()in
        ignore(ok(E.run ~state:fresh ~live:live1 ~time:1. doc.checked));
        let _,different=snapshot fresh live1 in
        assert(different<>one);
        let _,restored=snapshot state live1 in assert(restored=one)
      end;
      assert(Rays_editor.Editor3.Private.image_stats owner=(2,0)));
    assert(Rays_editor.Editor3.Private.image_stats owner=(2,2))in
  exercise ~stateful:false;exercise ~stateful:true;
  print_endline "Native nested image/map: frame and same-frame state captures refresh rendered pixels"
let ()=
  let doc=load "(workspace rendered (graph drawing :context draw \
    (draw/merge (draw/background \"#102030\") (draw/circle [4 4 0] 2 :fill \"#a0b0c0\"))) \
    (graph rendered :context image (image/render (ref drawing) :width 8 :height 8)) \
    (graph picture :context draw (draw/image (ref rendered))))"in
  let owner=Result.get_ok(Rays_editor.Editor3.create ~workspace:doc ~await:true ~domains:1
    ~prepare:(fun _ _->Ok()) ~scene3:(fun _ ()->Rays.Scene3.empty)())in
  Fun.protect ~finally:(fun()->Rays_editor.Editor3.close owner)(fun()->
    let evaluated=ok(E.static doc.checked)in
    let image=ok(Rays_editor.Editor3.Private.image owner(List.assoc "rendered" evaluated.results))in
    let expected=Result.get_ok(Rays.Image.Private.pixels image)in
    assert(Rays.Image.get_size image=(8,8));
    assert(ok(Rays_editor.Editor3.Private.image owner(List.assoc "rendered" evaluated.results))==image);
    assert(Rays_editor.Editor3.Private.image_stats owner=(1,0));
    List.iter(fun domains->Rays.Parallel.run ~domains(fun()->
      let fresh=Result.get_ok(Rays_editor.Editor3.create ~workspace:doc ~await:true ~domains
        ~prepare:(fun _ _->Ok()) ~scene3:(fun _ ()->Rays.Scene3.empty)())in
      Fun.protect ~finally:(fun()->Rays_editor.Editor3.close fresh)(fun()->
        let actual=ok(Rays_editor.Editor3.Private.image fresh(List.assoc "rendered" evaluated.results))in
        assert(Result.get_ok(Rays.Image.Private.pixels actual)=expected))))[1;8]);
  assert(Rays_editor.Editor3.Private.image_stats owner=(1,1));
  let directory ()=Filename.temp_dir "rays-rendered-image-" ""in
  let first=directory()and second=directory()in
  let remove path=Array.iter(fun name->Sys.remove(Filename.concat path name))(Sys.readdir path);Unix.rmdir path in
  Fun.protect ~finally:(fun()->remove first;remove second)(fun()->
    List.iter(fun directory->ok(Rays_editor.Workspace.export ~graph:"picture" ~fps:60
      ~directory ~frames:2 doc))[first;second];
    Array.iter(fun name->assert(In_channel.with_open_bin(Filename.concat first name)In_channel.input_all=
      In_channel.with_open_bin(Filename.concat second name)In_channel.input_all))(Sys.readdir first));
  print_endline "Native Canvas image snapshots: repeat cache, exact one/eight-domain bytes and close ownership passed"

let ()=
  let module Editor=Rays_editor.Editor3 in
  let module P=Procedural in
  let module I=Runtime_resources.Image in
  let _,handles=Ogpu.Impl.create_driver()in
  let before=handles()in
  let source=Filename.temp_file "rays-workspace-gpu-image-" ".rays"in
  let text width height body=Printf.sprintf
    "(workspace resident (graph image :context image (let* [bias (* t 0.5)] (image/map (fn [uv] %s) :width %d :height %d))))"
    body width height in
  let initial=text 65 17 "[uv.x uv.y bias 1]"in
  Out_channel.with_open_bin source(fun ch->output_string ch initial);
  let doc=load initial in
  let owner=ref(Result.get_ok(Editor.create ~workspace:doc ~await:true ~domains:1
    ~source:(Rays_editor.Source.at ~file:source ~digest:(Editor_document.Contexts.sha256 initial))
    ~prepare:(fun _ _->Ok()) ~scene3:(fun _ ()->Rays.Scene3.empty)()))in
  Fun.protect ~finally:(fun()->Editor.close !owner;Sys.remove source)(fun()->
    Editor.Private.gpu_qualification !owner;
    let value()=let plan=Editor.Private.image_plan !owner in
      let node=Array.find_opt(fun(n:E.node)->n.kind="image/map")plan.nodes |> Option.get in
      plan,node,E.Deferred(Flow.Ty.image,node.id)in
    let live time=Frame_input.at_time time in
    let exact time=let _,_,value=value()in
      Editor.Private.image_payload ~live:(live time) !owner value |> ok in
    let resolve time=let _,_,value=value()in
      Editor.Private.with_images ~live:(live time) !owner(fun ~image ~texture->
        ok(image value),ok(texture value))in
    let rgba payload=P.Image.Private.rgba8 payload |> Option.get in
    let saved=exact 0. in let saved_bytes=Bytes.copy(rgba saved)in
    assert(Editor.Private.image_stats !owner=(0,0));
    let image,texture=resolve 0. in
    let identity=Rays.Texture.Private.identity texture in
    let resource=Rays.Image.Private.resource image in
    assert(I.Private.cpu_storage_bytes resource=0 && I.Private.readbacks resource=0);
    let generation=I.generation resource in
    assert(exact 0.==saved && I.generation resource=generation);
    print_endline "test,width,height,time,max_channel_difference,differing_channels,differing_pixels";
    let canvas=Rays.Canvas.create ~width:65 ~height:17 |> Result.get_ok in
    Fun.protect ~finally:(fun()->Rays.Canvas.destroy canvas)(fun()->
      let mesh=Rays.Mesh.plane ~width:(2.*.65./.17.) ~height:2.()in
      let camera=Rays.Camera.orthographic ~height:2. ~at:(Rays.Vec3.create 0. 0. 2.) ~target:Rays.Vec3.zero()in
      let scene source_image texture=Rays.Scene.[clear Rays.Color.black;
        image source_image ~at:(0,0)();Private.layer_break;
        view3d ~viewport:(33,0,32,17) ~camera(Rays.Scene3.create ~ambient:Rays.Color.white
          [Rays.Scene3.mesh ~material:(Rays.Material.matte Rays.Color.white) ~cull:Cull_none
            ~texture:(Rays.Scene3.textured ~filter:Nearest texture) mesh])]in
      let snapshot()=let image=Rays.Canvas.to_image canvas |> Result.get_ok in
        Fun.protect ~finally:(fun()->Rays.Image.destroy image)(fun()->Rays.Image.Private.pixels image |> Result.get_ok)in
      let verify time=
        let actual_image,actual_texture=resolve time in
        assert(actual_image==image && Rays.Texture.Private.identity actual_texture=identity);
        assert(I.Private.cpu_storage_bytes resource=0 && I.Private.readbacks resource=0);
        let generation=I.generation resource in
        let payload=exact time in
        assert(I.generation resource=generation && I.Private.readbacks resource=0);
        assert(rgba saved=saved_bytes);
        let _,node,_=value()in
        let width,height=Rays.Image.get_size image in
        let fn=match List.assoc "function" node.args with E.Fn fn->fn|_->assert false in
        let kernel=Flow_sop.Image_kernel.prepare ~identity:0 ~width ~height ~fn ~sources:[] [] |> ok in
        List.iter(fun domains->
          let context=P.Context.create ~input:(live time) ~time ~domains() |> Result.get_ok in
          let session=P.Session.create ~max_entries:0 ~max_payload_bytes:0 |> Result.get_ok in
          Fun.protect ~finally:(fun()->P.Session.close session)(fun()->
            let cooked=P.Session.cook session ~context(Flow_sop.Image_kernel.node kernel) |> Result.get_ok in
            assert(rgba(P.Payload.image cooked.payload |> Result.get_ok)=rgba payload)))[1;8];
        let displayed=scene actual_image actual_texture in
        Rays.Canvas.render canvas displayed;Rays.Canvas.render canvas displayed;
        let uploaded=(Rays.Canvas.Private.native_stats canvas).uploaded_bytes in
        Rays.Canvas.render canvas displayed;
        assert((Rays.Canvas.Private.native_stats canvas).uploaded_bytes=uploaded);
        let actual=snapshot()in
        let reference=Rays.Image.upload_rgba ~width ~height ~rgba:(rgba payload)() |> Result.get_ok in
        Fun.protect ~finally:(fun()->Rays.Image.destroy reference)(fun()->
          let texture=Rays.Texture.init ~width ~height(fun ~x ~y->let o=(y*width+x)*4 in
            let bytes=rgba payload in Rays.Color.rgba(Char.code(Bytes.get bytes o))
              (Char.code(Bytes.get bytes(o+1)))(Char.code(Bytes.get bytes(o+2)))(Char.code(Bytes.get bytes(o+3))))in
          Rays.Canvas.render canvas(scene reference texture);
          let expected=snapshot()in
          let maximum=ref 0 and channels=ref 0 and pixels=ref 0 in
          Bytes.iteri(fun i c->let difference=abs(Char.code c-Char.code(Bytes.get expected i))in
            maximum:=max !maximum difference;if difference<>0 then incr channels)actual;
          for pixel=0 to Bytes.length actual/4-1 do
            if List.exists(fun channel->let i=pixel*4+channel in
              Bytes.get actual i<>Bytes.get expected i)[0;1;2;3]then incr pixels
          done;
          Printf.printf "workspace_gpu_image,%d,%d,%.2f,%d,%d,%d\n%!"
            width height time !maximum !channels !pixels;
          assert(!maximum<=1));
        assert(I.Private.readbacks resource=0)in
      verify 0.;verify 1.;
      let frame time={Rays.Frame.width=65;height=17;size=65,17;drawable_width=65;drawable_height=17;
        drawable_size=65,17;pixel_scale=1.,1.;time;dt=0.;fps=60.;count=int_of_float time;
        mouse=0.,0.;mouse_delta=0.,0.;keys=[];mouse_buttons=[];events=[]}in
      let reload time text=
        Out_channel.with_open_bin source(fun ch->output_string ch text);
        owner:=Editor.update !owner(frame time)in
      reload 10.(text 35 33 "[uv.y uv.x (* t 0.5) 1]");
      verify 0.5;
      assert(Rays.Image.get_size image=(35,33));
      assert(Editor.Private.image_stats !owner=(1,0));
      reload 20.(text 65 3 "[uv.x uv.y 0.5 1]");
      let cpu_image,cpu_texture=resolve 0. in
      assert(cpu_image==image && Rays.Texture.Private.image cpu_texture=None);
      assert(Result.get_ok(I.Private.gpu_snapshot resource)=None);
      reload 30.(text 65 17 "[uv.x uv.y (* t 0.5) 1]");
      verify 0.5;
      reload 40.(text 65 17 "[(if (> uv.x 0) 0 (* (* uv.x 1e20) (* uv.x 1e20))) uv.y 0.5 1]");
      let _,_,value=value()in
      List.iter(fun time->
        let failed=Editor.Private.with_images ~live:(live time) !owner(fun ~image ~texture:_->image value)in
        assert(match failed with Error d->d.Flow.Diagnostic.code="E_KERNEL"|Ok _->false))[0.;0.];
      assert(I.Private.readbacks resource=0);
      reload 50.(text 65 17 "[uv.x uv.y 0.5 1]");
      verify 0.5;
      assert(rgba saved=saved_bytes)));
  assert(Editor.Private.image_stats !owner=(1,1));
  assert(handles()=before);
  print_endline "Workspace GPU images: exact-first independent CPU snapshots, live display, mesh/image parity, replan/resize, authority transitions and ownership pass"

let ()=
  let module Editor=Rays_editor.Editor3 in
  let module P=Procedural in
  let module I=Runtime_resources.Image in
  let doc=load "(workspace nested_exact
    (graph img :context image (image/map (fn [uv] [uv.x uv.y 0.499999999 1]) :width 65 :height 17))
    (graph drawing :context draw (draw/image (ref img)))
    (graph rendered :context image (image/render (ref drawing) :width 65 :height 17)))"in
  let owner domains=Result.get_ok(Editor.create ~workspace:doc ~await:true ~domains
    ~prepare:(fun _ _->Ok()) ~scene3:(fun _ ()->Rays.Scene3.empty)())in
  let display=owner 1 in
  Fun.protect ~finally:(fun()->Editor.close display)(fun()->
    Editor.Private.gpu_qualification display;
    let value owner kind=let plan=Editor.Private.image_plan owner in
      let node=Array.find_opt(fun(n:E.node)->n.kind=kind)plan.nodes |> Option.get in
      E.Deferred(Flow.Ty.image,node.id)in
    let image=Editor.Private.with_images display(fun ~image ~texture:_->ok(image(value display "image/map")))in
    let resource=Rays.Image.Private.resource image in
    assert(I.Private.cpu_storage_bytes resource=0);
    let generation=I.generation resource in
    let actual=Editor.Private.image_payload display(value display "image/render") |> ok in
    let rgba image=match P.Image.Private.rgba8 image with Some bytes->bytes|None->
      let values=P.Image.Private.storage image in
      Bytes.init(Array.length values)(fun i->Char.chr(int_of_float(Float.round(values.(i)*.255.))))in
    let bytes=rgba actual in
    for i=0 to 65*17-1 do assert(Bytes.get bytes(i*4+2)=Char.chr 127)done;
    List.iter(fun domains->let oracle=owner domains in
      Fun.protect ~finally:(fun()->Editor.close oracle)(fun()->
        let expected=Editor.Private.image_payload oracle(value oracle "image/render") |> ok in
        assert(rgba expected=bytes)))[1;8];
    assert(I.generation resource=generation && I.Private.readbacks resource=0
      && I.Private.cpu_storage_bytes resource=0));
  print_endline "Nested image/render exactness: CPU rounding survives an already-resident GPU child without reading or replacing it"

let ()=
  let module Editor=Rays_editor.Editor3 in
  let doc=load "(workspace stamp (graph img :context image
    (image/noise :width 4 :height 4 :frequency (+ 0.1 (* t 0.01)) :seed 31)))"in
  let owner=Result.get_ok(Editor.create ~workspace:doc ~await:true ~domains:1
    ~prepare:(fun _ _->Ok()) ~scene3:(fun _ ()->Rays.Scene3.empty)())in
  Fun.protect ~finally:(fun()->Editor.close owner)(fun()->
    let node=(Editor.Private.image_plan owner).nodes.(0)in
    let value=E.Deferred(Flow.Ty.image,node.id)in
    let display time=Editor.Private.with_images ~live:(Frame_input.at_time time) owner(fun ~image ~texture:_->
      let image=ok(image value)in Rays.Image.Private.pixels image |> Result.get_ok)in
    let first=display 0. in
    ignore(ok(Editor.Private.image_payload ~live:(Frame_input.at_time 10.) owner value));
    assert(display 0.=first));
  print_endline "Legacy image stamps: display A, exact B, display A restores A pixels"
