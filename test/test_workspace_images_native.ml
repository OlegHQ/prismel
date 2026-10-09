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
