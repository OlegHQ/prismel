module E=Flow.Eval
module Editor=Rays_editor.Editor3
let ok=function Ok value->value|Error d->failwith(Flow.Diagnostic.to_string d)
let load text=match Rays_editor.Workspace.load text with Ok doc->doc|Error ds->
  failwith(String.concat "; "(List.map Flow.Diagnostic.to_string ds))
let editor doc=Result.get_ok(Editor.create ~workspace:doc ~await:true ~domains:1
  ~prepare:(fun _ _->Ok()) ~scene3:(fun _ ()->Rays.Scene3.empty)())
let workspace producer=load("(workspace images (graph img :context image "^producer^
  ") (graph picture :context draw (draw/image (ref img) :at [1 2 0] :scale 2.0 :angle 0.1)))")
let ()=
  let doc=workspace "(image/noise :width 2 :height 2 :frequency 0.3 :seed 31)"in
  let evaluated=ok(E.static doc.checked)in
  let value=List.assoc "img" evaluated.results in
  let owner=editor doc in
  Fun.protect ~finally:(fun()->Editor.close owner)(fun()->
    let image=ok(Editor.Private.image owner value)in
    assert(Rays.Image.get_size image=(2,2));
    assert(ok(Editor.Private.image owner value)==image);
    let oracle=Result.get_ok(Rays.Image.Private.pixels image)in
    let ui=Pxui.Ui.create()in
    Fun.protect ~finally:(fun()->Pxui.Ui.destroy ui)(fun()->
      let frame:Rays.Frame.t={width=32;height=32;size=32,32;drawable_width=32;drawable_height=32;
        drawable_size=32,32;pixel_scale=1.,1.;time=0.;dt=0.;fps=60.;count=0;
        mouse=0.,0.;mouse_delta=0.,0.;keys=[];mouse_buttons=[];events=[]}in
      Pxui.Ui.frame ui frame(fun ui->
        let box=Pxui.Ui.box ui ~w:(Px 16.) ~h:(Px 16.) "image"in
        Pxui.Ui.draw ui box(fun paint(x,y,w,h)->Pxui.Ui.Paint.image paint ~x ~y ~w ~h image));
      assert(Pxui.Ui.scene ui<>[]));
    assert(Result.get_ok(Rays.Image.Private.pixels image)=oracle);
    let prepared=ok(Sketch_support.Drawing.prepare evaluated.plan(List.assoc "picture" evaluated.results))in
    let commands=ref None in
    List.iter(fun(reference,domains)->Rays.Parallel.run ~domains(fun()->
      let scene=ok(Sketch_support.Drawing.render_prepared ~reference ~image:(Editor.Private.image owner)
        prepared ~live:(Frame_input.at_time 0.) ~size:(32,32))in
      let actual=Rays.Scene.Private.commands scene in
      assert(Array.exists(function Scene_command.Render_ir.Image _->true|_->false)actual);
      (match !commands with None->commands:=Some actual|Some expected->assert(actual=expected));
      assert(Result.get_ok(Rays.Image.Private.pixels image)=oracle);
      ())) [false,1;false,1;false,1;false,8;true,1;true,8];
    assert(Editor.Private.image_stats owner=(1,0)));
  assert(Editor.Private.image_stats owner=(1,1));
  let doc=load "(workspace images (graph a :context image (image/load \"sdl3_image_fixtures/sample.png\")) \
    (graph b :context image (image/load \"sdl3_image_fixtures/sample.png\")) \
    (graph picture :context draw (draw/merge (draw/image (ref a)) (draw/image (ref b)))))"in
  let owner=editor doc in
  Fun.protect ~finally:(fun()->Editor.close owner)(fun()->
    let evaluated=ok(E.static doc.checked)in
    let a=ok(Editor.Private.image owner(List.assoc "a" evaluated.results))in
    let b=ok(Editor.Private.image owner(List.assoc "b" evaluated.results))in
    assert(a==b && Editor.Private.image_stats owner=(1,0)));
  assert(Editor.Private.image_stats owner=(1,1));
  let doc=workspace "(image/load \"sdl3_image_fixtures/sample.png\")"in
  let owner=editor doc in
  let evaluated=ok(E.static doc.checked)in
  Fun.protect ~finally:(fun()->Editor.close owner)(fun()->
    let first=ok(Editor.Private.image owner(List.assoc "img" evaluated.results))in
    assert(ok(Editor.Private.image owner(List.assoc "img" evaluated.results))==first);
    assert(Editor.Private.image_stats owner=(1,0)));
  assert(Editor.Private.image_stats owner=(1,1));
  let doc=workspace "(image/load \"missing-rgbaa-image-file.png\")"in
  let owner=editor doc in
  Fun.protect ~finally:(fun()->Editor.close owner)(fun()->
    let evaluated=ok(E.static doc.checked)in
    assert(match Editor.Private.image owner(List.assoc "img" evaluated.results)with
      |Error d->d.Flow.Diagnostic.code="E_IMAGE"|Ok _->false);
    assert(Editor.Private.image_stats owner=(0,0)));
  print_endline "images: two-pixel CPU noise, six drawing modes, one load/upload, exact ownership and missing-file diagnostic passed"

let ()=
  let doc=workspace "(image/load \"unused.png\")"in
  let lowered=ok(Flow_sop.Lower.of_checked ~factories:Sop_catalog.Editor.factories doc.checked)in
  let graph=List.hd lowered.graphs in
  let lane=Flow_sop.Value_lane.create()in
  assert(match Flow_sop.Value_lane.resolve lane ~time:0. graph.network with
    |Error d->d.Flow.Diagnostic.code="E_IMAGE"|Ok _->false);
  let payload=Result.get_ok(Procedural.Image.create ~width:1 ~height:1 ~rgba:[|0.2;0.3;0.4;1.|])in
  let calls=ref 0 in
  Flow_sop.Lower.with_images(fun _ ~state:_ ~live:_ _->incr calls;Ok payload)(fun()->
    Flow_sop.Value_lane.reset lane;
    let resolved=ok(Flow_sop.Value_lane.resolve lane ~time:1. graph.network)in
    let node=Result.get_ok(Procedural.Edit_graph.compile_node resolved.geometry ~node_id:(Option.get graph.root))in
    let session=Result.get_ok(Procedural.Session.create ~max_entries:16 ~max_payload_bytes:65536)in
    Fun.protect ~finally:(fun()->Procedural.Session.close session)(fun()->
      List.iter(fun domains->let context=Result.get_ok(Procedural.Context.create ~domains())in
        let output=Result.get_ok(Procedural.Session.cook session ~context node)in
        assert(Result.get_ok(Procedural.Payload.image output.payload)==payload)) [1;8]));
  assert(!calls=1);
  print_endline "images: resources snapshot before worker submission, exact one/eight-domain payload identity passed"

let ()=
  let texture=Rays.Scene3.textured(Rays.Texture.init ~width:2 ~height:2(fun ~x:_ ~y:_->Rays.Color.white))in
  let scene=Rays.Scene3.create ~samples:4 ~ambient:Rays.Color.red
    [Rays.Scene3.translate (Rays.Vec3.create 2. 3. 4.)
      [Rays.Scene3.with_blend Add [Rays.Scene3.with_depth(Rays.Scene3.depth_state ~write:false())
        [Rays.Scene3.plane ~cull:Cull_front ~width:2. ~height:3.()]]]]in
  let textured=Rays.Scene3.Private.with_texture texture scene in
  List.iter2(fun original textured->
    assert(textured.Rays.Scene3.Private.texture=Some texture);
    assert({textured with texture=None}=original))
    (Rays.Scene3.Private.drawings scene)(Rays.Scene3.Private.drawings textured);
  assert(Rays.Scene3.Private.samples textured=4 && Rays.Scene3.Private.ambient textured=Rays.Color.red);
  print_endline "Scene image textures preserve affine, cull, blend, depth and scene settings"

let () =
  List.iter (fun producer ->
  let document = load ("(workspace image_oracle (graph image :context image " ^ producer ^ ")" ^ {|
    (graph grid :context sop
      (sop/attr_from_image (sop/grid :rows 2 :columns 2 :uv_attribute "uv") (ref image)))
    (graph picture :context draw (draw/image (ref image)))
    (graph scene :context scene (scene/geometry (ref grid) :texture (ref image))))|}) in
  Workspace_parity.check ~commands:true ~factories:Sop_catalog.Editor.factories
    ~name:"image_oracle" document;
  if String.starts_with ~prefix:"(image/noise" producer then begin
    let owner = editor document in
    Fun.protect ~finally:(fun () -> Editor.close owner) (fun () ->
      let evaluated = ok (E.static document.checked) in
      let pixels time = Editor.Private.with_images ~plan:evaluated.plan
        ~live:(Frame_input.at_time time) owner (fun ~image ~texture:_ ->
          Rays.Image.Private.pixels (ok (image (List.assoc "image" evaluated.results))) |> Result.get_ok) in
      assert (pixels 0. <> pixels 10.));
    let created, destroyed = Editor.Private.image_stats owner in
    assert (created > 0 && created = destroyed)
  end)
    ["(image/noise :width 2 :height 2 :frequency (+ 0.3 (* 0.01 t)) :seed 31)";
     "(image/load \"sdl3_image_fixtures/sample.png\")"]
