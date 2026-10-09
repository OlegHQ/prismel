let ok=function Ok value->value|Error d->failwith(Flow.Diagnostic.to_string d)
let ()=
  let module E=Flow.Eval in
  let module Image=Rays.Image in
  let module Native=Runtime_resources.Image in
  let lower width height=Flow.Syntax.parse(Printf.sprintf {|(workspace frozen
    (graph img :context image
      (let* [bias (* t 0.125)]
        (image/map (fn [uv] [bias uv.y (- 0.5 0.000000001) 1]) :width %d :height %d)))
    (graph frozen :context image (exact (ref img)))
    (graph picture :context draw [(image : image (image/noise :width 1 :height 1))]
      (draw/image image))
    (graph composed :context draw (ref picture :image (ref frozen))))|}width height)
    |> ok |> Flow_sop.Lower.workspace ~factories:Sop_catalog.Editor.factories |> ok in
  let resources=Workspace_resources.create()and gpu=Workspace_gpu.create()in
  let owner=Workspace_images.create ~domains:1 ~gpu resources in
  Workspace_gpu.qualification gpu;
  let state=E.create_state()in let original_stamp=E.state_stamp state in
  let _,handles=Ogpu.Impl.create_driver()in let before=handles()in
  let plan=ref(lower 65 17)in
  let bind lowered=plan:=lowered;Workspace_images.bind owner lowered in
  bind !plan;
  let value kind=let n=Array.find_opt(fun(n:E.node)->n.kind=kind)(!plan).plan.nodes |> Option.get in
    E.Deferred(Flow.Ty.image,n.id)in
  let payload kind time=Workspace_images.payload owner (!plan).plan ~state
    ~live:(Frame_input.at_time time)(value kind)in
  let image kind time=Workspace_images.image owner (!plan).plan ~state
    ~live:(Frame_input.at_time time)(value kind)in
  let bytes payload=Procedural.Image.Private.rgba8 payload |> Option.get in
  let held=ref None in
  Fun.protect ~finally:(fun()->Workspace_images.close owner;Workspace_resources.close resources;Workspace_gpu.close gpu)(fun()->
    let ordinary=payload "image/map" 0. |> ok in
    assert(Char.code(Bytes.get(bytes ordinary)2)=127 && resources.images_created=0);
    let first=payload "exact" 0. |> ok in
    held:=Some first;
    let saved_bytes=Bytes.copy(bytes first)in
    let frozen=image "exact" 0. |> ok and child=image "image/map" 0. |> ok in
    let native=Image.Private.resource child in
    assert(Char.code(Bytes.get saved_bytes 2)=128 && Image.Private.identity frozen<>Image.Private.identity child
      && Native.Private.readbacks native=1 && resources.images_created=2);
    assert(payload "exact" 0. |> ok == first);
    assert(payload "image/map" 0. |> ok == ordinary);
    assert(Native.Private.readbacks native=1);
    let drawing=Sketch_support.Drawing.prepare (!plan).plan
      (List.assoc "composed" (!plan).evaluated.results) |> ok in
    let scene=Sketch_support.Drawing.render_prepared ~state
      ~image:(Workspace_images.image owner (!plan).plan ~state ~live:(Frame_input.at_time 0.))
      drawing ~live:(Frame_input.at_time 0.) ~size:(65,17) |> ok in
    let render_saved()=
      let canvas=Rays.Canvas.create ~width:65 ~height:17 |> Result.get_ok in
      Fun.protect ~finally:(fun()->Rays.Canvas.destroy canvas)(fun()->
        Rays.Canvas.render canvas scene;
        let image=Rays.Canvas.to_image canvas |> Result.get_ok in
        Fun.protect ~finally:(fun()->Image.destroy image)(fun()->Image.Private.pixels image |> Result.get_ok))in
    let saved_scene=render_saved()in
    assert(saved_scene=saved_bytes);
    let second=payload "exact" 1. |> ok in
    assert(second!=first && bytes second<>saved_bytes && bytes first=saved_bytes);
    assert(Image.Private.identity(image "exact" 1. |> ok)<>Image.Private.identity frozen
      && Native.Private.readbacks native=2 && render_saved()=saved_scene);
    (* Expire a borrowed source without changing its published generation.
       Even a frozen-key hit must validate it before returning the payload. *)
    let texture=match Native.Private.gpu_snapshot native |> Result.get_ok with
      |Some(_,_,_,texture)->texture|None->assert false in
    let available=ref true in
    Native.Private.replace_gpu_source native ~width:65 ~height:17
      ~source:(fun()->if !available then Some texture else None) |> Result.get_ok;
    let third=payload "exact" 1. |> ok in
    let reads=Native.Private.readbacks native and created=resources.images_created
    and generation=Native.generation native in
    available:=false;
    for _=1 to 2 do
      assert(match payload "exact" 1. with Error d->d.Flow.Diagnostic.code="E_IMAGE"|Ok _->false)
    done;
    assert(Native.Private.readbacks native=reads && resources.images_created=created
      && Native.generation native=generation && E.state_stamp state=original_stamp);
    available:=true;
    assert(payload "exact" 1. |> ok == third && Native.Private.readbacks native=reads);
    assert(Result.is_error(payload "exact" Float.infinity));
    assert(E.state_stamp state=original_stamp && bytes first=saved_bytes);
    let recovered=payload "exact" 2. |> ok in
    assert(bytes recovered<>bytes second && render_saved()=saved_scene);
    bind(lower 17 5);
    let resized=payload "exact" 2. |> ok in
    assert(Procedural.Image.width resized=17 && Procedural.Image.height resized=5
      && resized!=recovered && bytes first=saved_bytes && render_saved()=saved_scene);
    bind(lower 17 5);
    let replanned=payload "exact" 2. |> ok in
    assert(replanned!=resized && bytes replanned=bytes resized && render_saved()=saved_scene);
    assert(E.state_stamp state=original_stamp));
  let saved=Option.get !held in
  assert(Char.code(Bytes.get(bytes saved)2)=128 && resources.images_created=resources.images_destroyed
    && handles()=before);
  print_endline "Frozen exact images: CPU127/GPU128, read-once versions, saved Scene, expiry/refusal/recovery, resize/replan, ref composition and owned close pass"

let ()=List.iter(fun(width,height,expected_reads)->
  let module E=Flow.Eval in
  let resources=Workspace_resources.create()and gpu=Workspace_gpu.create()in
  let owner=Workspace_images.create ~domains:1 ~gpu resources in
  Workspace_gpu.qualification gpu;
  let lowered=Flow.Syntax.parse(Printf.sprintf {|(workspace versions (graph img :context image
    (exact (image/map (fn [uv] [(* t 0.0078125) uv.y 0.5 1]) :width %d :height %d))))|}width height)
    |> ok |> Flow_sop.Lower.workspace ~factories:Sop_catalog.Editor.factories |> ok in
  Workspace_images.bind owner lowered;
  let n=Array.find_opt(fun(n:E.node)->n.kind="exact")lowered.plan.nodes |> Option.get in
  let child=Array.find_opt(fun(n:E.node)->n.kind="image/map")lowered.plan.nodes |> Option.get in
  let state=E.create_state()in
  let _,handles=Ogpu.Impl.create_driver()in let before=handles()in
  let held=ref [||]in
  Fun.protect ~finally:(fun()->Workspace_images.close owner;Workspace_resources.close resources;Workspace_gpu.close gpu)(fun()->
    let resolve frame=Workspace_images.payload owner lowered.plan ~state
      ~live:{(Frame_input.at_time(float frame))with frame}(E.Deferred(Flow.Ty.image,n.id))in
    held:=Array.init 63(fun frame->resolve frame |> ok);
    let source=Workspace_images.image owner lowered.plan ~state
      ~live:{(Frame_input.at_time 62.)with frame=62}(E.Deferred(Flow.Ty.image,child.id)) |> ok in
    let native=Rays.Image.Private.resource source in
    assert(resources.images_created=64 && Runtime_resources.Image.Private.readbacks native=expected_reads);
    for _=1 to 2 do
      assert(match resolve 63 with Error d->d.Flow.Diagnostic.code="E_IMAGE"|Ok _->false)
    done;
    assert(resources.images_created=64 && Runtime_resources.Image.Private.readbacks native=expected_reads);
    Array.iteri(fun frame payload->
      let bytes=Procedural.Image.Private.rgba8 payload |> Option.get in
      assert(Char.code(Bytes.get bytes 0)=int_of_float(Float.round(float frame*.0.0078125*.255.)))) !held);
  assert(resources.images_created=resources.images_destroyed && handles()=before);
  assert(Array.length !held=63 && Procedural.Image.width (!held).(0)=width);
  Printf.printf "Frozen exact capacity %dx%d: 63 pinned versions plus source, 65th resource refuses before readback, retained bytes survive close\n"width height)
  [7,3,0;65,17,63]
let ()=if Array.mem "--capture-budget" Sys.argv then begin
  let module E=Flow.Eval in
  let module P=Procedural in
  let geometry count=
    let positions=Rdk.Packed.Float3.Builder.create count in
    Rdk.Packed.Float3.Builder.set positions 0 0.03125 0. 0.;
    Rdk.Geometry.create ~positions:(Rdk.Packed.Float3.Builder.freeze positions)
      ~topology:(Rdk.Topology.empty ~point_count:count)() |> Result.get_ok in
  let large=geometry(64*1024*1024/24+1)in
  assert(Rdk.Geometry.payload_bytes large>64*1024*1024);
  let lower geometry=
    let factory=P.Edit_graph.factory ~key:"capture_budget" ~label:"Capture budget" ~category:["Test"]
      ~arity:0(function []->P.Node.Private.make ~operation:"capture_budget" ~version:1 ~parameters:""
        ~cook_mode:Generator ~dependencies:P.Context.Dependencies.static ~inputs:[||]
        (fun ~node_id:_ _ _->Ok{P.Node.Private.payload=P.Payload.Geometry geometry;diagnostics=[];instances=None})
        |_->assert false)in
    Flow.Syntax.parse {|(workspace budget (graph mesh :context sop
      (let* [geo (sop/capture_budget) p (array/nth (sop/attr geo :P) 0)
        img (image/map (fn [uv] [(+ uv.x (+ p.x (* t 0.015625))) uv.y 0.5 1]) :width 65 :height 17)] geo)))|}
      |> ok |> Flow_sop.Lower.workspace ~factories:(factory::Sop_catalog.Editor.factories) |> ok in
  let resources=Workspace_resources.create()and gpu=Workspace_gpu.create()in
  let owner=Workspace_images.create ~domains:1 ~gpu resources in
  Workspace_gpu.qualification gpu;
  let _,handles=Ogpu.Impl.create_driver()in let before=handles()in
  Fun.protect ~finally:(fun()->Workspace_resources.close resources;Workspace_images.close owner;Workspace_gpu.close gpu)(fun()->
    let run lowered time=
      Workspace_images.bind owner lowered;
      let node=Array.find_opt(fun(n:E.node)->n.kind="image/map")lowered.Flow_sop.Lower.plan.nodes |> Option.get in
      let image=Workspace_images.image owner ~state:(E.create_state()) ~live:(Frame_input.at_time time)
        lowered.plan(E.Deferred(Flow.Ty.image,node.id)) |> ok in
      let bytes=Rays.Image.Private.pixels image |> Result.get_ok in
      assert(Char.code(Bytes.get bytes 0)=int_of_float(Float.round((0.5/.65.+.0.03125+.time*.0.015625)*.255.)))in
    let large_lowered=lower large in run large_lowered 0.;run large_lowered 1.;
    assert(Workspace_images.capture_stats owner=(1,0,0,2,2));
    let small_lowered=lower(geometry 1)in run small_lowered 0.;run small_lowered 1.;
    let metadata,data,bytes,cooks,flattens=Workspace_images.capture_stats owner in
    assert(metadata=1 && data=1 && bytes<=64*1024*1024 && cooks=3 && flattens=3);
    let host,_,_,_,_=Workspace_gpu.image_stats gpu in assert(host.status_reads=4));
  assert(handles()=before && Workspace_images.capture_stats owner=(0,0,0,3,3));
  print_endline "Capture byte budget: unchanged oversized geometry executes uncached across live pixels, smaller captures resume caching, counters survive clean close"
end
let ()=
  let module E=Flow.Eval in
  let module P=Procedural in
  let bindings=List.init 65(fun i->Printf.sprintf
    "g%d (sop/box :consolidate_points true :center [0.015625 0 0]) p%d (array/sum (sop/attr g%d :P))"i i i)
    |> String.concat " "in
  let sum=List.init 65(fun i->Printf.sprintf "p%d"(64-i)) |> String.concat " "in
  let text=Printf.sprintf {|(workspace capacity (graph mesh :context sop
    (let* [%s total (reduce + [0 0 0] (list %s))
           img (image/map (fn [uv] [(+ (+ uv.x (* t 0.015625)) total.x) uv.y 0.5 1]) :width 65 :height 17)
           last (image/map (fn [uv] [(+ (+ uv.x (* t 0.015625)) p64.x) uv.y 0.5 1]) :width 65 :height 17)] g0)))|}bindings sum in
  let lowered=Flow.Syntax.parse text |> ok |> Flow_sop.Lower.workspace ~factories:Sop_catalog.Editor.factories |> ok in
  let resources=Workspace_resources.create()and gpu=Workspace_gpu.create()in
  let owner=Workspace_images.create ~domains:1 ~gpu resources in
  Workspace_images.bind owner lowered;Workspace_gpu.qualification gpu;
  let state=E.create_state()in
  let display name time=
    let node=Array.find_opt(fun(n:E.node)->n.kind="image/map" && n.site=["mesh";name])lowered.plan.nodes |> Option.get in
    Workspace_images.image owner ~state ~live:(Frame_input.at_time time)lowered.plan(E.Deferred(Flow.Ty.image,node.id)) |> ok in
  Fun.protect ~finally:(fun()->Workspace_resources.close resources;Workspace_images.close owner;Workspace_gpu.close gpu)(fun()->
    ignore(display "img" 0.);
    let metadata,data,bytes,cooks,flattens=Workspace_images.capture_stats owner in
    Printf.printf "capture_capacity,metadata=%d,data=%d,bytes=%d,cooks=%d,flattens=%d\n%!"metadata data bytes cooks flattens;
    assert(metadata=64 && data=64 && bytes<=64*1024*1024 && cooks=65 && flattens=65);
    ignore(display "last" 1.);
    let _,_,_,later_cooks,later_flattens=Workspace_images.capture_stats owner in
    assert(later_cooks=cooks && later_flattens=flattens);
    let host,_,_,_,_=Workspace_gpu.image_stats gpu in assert(host.status_reads=2);
    let exact=Workspace_images.payload owner lowered.plan ~state ~live:(Frame_input.at_time 1.)
      (E.Deferred(Flow.Ty.image,(Array.find_opt(fun(n:E.node)->n.site=["mesh";"last"] && n.kind="image/map")lowered.plan.nodes |> Option.get).id)) |> ok in
    let bytes=P.Image.Private.rgba8 exact |> Option.get in assert(Char.code(Bytes.get bytes 0)=38));
  assert(Workspace_images.capture_stats owner=(0,0,0,65,65));
  print_endline "Capture capacity: one image with 65 sources keeps bounded owned data, static reuse survives metadata eviction, exact cooks leave display counters unchanged"
let ()=
  let module E=Flow.Eval in
  let module L=Flow_sop.Lower in
  let module N=Flow_sop.Network in
  let module P=Procedural in
  let forms=Flow.Syntax.parse {|(workspace cycle
    (graph mesh :context sop
      (let* [geo (sop/box :consolidate_points true :center [0.015625 0 0])
             p (reduce + [0 0 0] (sop/attr geo :P))
             img (image/map (fn [uv] [(+ uv.x p.x) uv.y 0.5 1]) :width 7 :height 3)] geo)))|} |> ok in
  let lowered=L.workspace ~factories:Sop_catalog.Editor.factories forms |> ok in
  let graph=List.hd lowered.graphs in
  let image_node=Array.find_opt(fun(n:E.node)->n.kind="image/map")lowered.plan.nodes |> Option.get in
  let id=N.Int_map.find image_node.id lowered.compiled in
  let template=P.Edit_graph.find graph.network.geometry ~node_id:id |> Option.get in
  let image_callback=N.Int_map.find id graph.network.frame_nodes in
  let root=Option.get graph.root in
  let frames=N.Int_map.add root(fun ~network state live node->
    Result.map(fun _->node)(image_callback ~network state live template))graph.network.frame_nodes in
  let cyclic=N.with_frame_nodes frames graph.network in
  let state=E.create_state()in
  let stamp=E.state_stamp state in
  let _,handles=Ogpu.Impl.create_driver()in
  let before=handles()in
  let run fail=
    let resources=Workspace_resources.create()and gpu=Workspace_gpu.create()in
    let owner=Workspace_images.create ~domains:1 ~gpu resources in
    Workspace_images.bind owner lowered;
    Fun.protect ~finally:(fun()->Workspace_resources.close resources;Workspace_images.close owner;Workspace_gpu.close gpu)(fun()->
      let resolve network=Workspace_images.payload owner ~context:L.{compiled=lowered.compiled;network}
        lowered.plan ~state ~live:(Frame_input.at_time 0.)(E.Deferred(Flow.Ty.image,image_node.id))in
      if fail then for _=1 to 2 do
        assert(match resolve cyclic with Error d->d.Flow.Diagnostic.code="E_IMAGE_CYCLE"|Ok _->false);
        assert(E.state_stamp state=stamp && resources.images_created=0)
      done;
      let result=resolve graph.network |> ok in
      assert(E.state_stamp state=stamp && resources.images_created=0);
      P.Image.Private.rgba8 result |> Option.get |> Bytes.copy)in
  assert(run true=run false && handles()=before);
  print_endline "Workspace capture cycles: typed repeated resolver re-entry, unchanged caller state, acyclic recovery and clean close pass"
let ()=
  let _,handles=Ogpu.Impl.create_driver()in
  let before=handles()in
  let owner=Workspace_gpu.create()in
  let rejects_worker()=Domain.join(Domain.spawn(fun()->
    try ignore(Workspace_gpu.image_stats owner);false with Invalid_argument _->true))in
  assert(rejects_worker());
  Fun.protect ~finally:(fun()->Workspace_gpu.close owner)(fun()->
    Workspace_gpu.qualification owner;
    let forms=Flow.Syntax.parse "(workspace test (graph image :context image
      (image/map (fn [uv] [uv.x uv.y 0.5 1]))))" |> ok in
    let checked=match Flow.Workspace.check Flow.Check.{version=1;kinds=[]} forms with
      |Some w,[]->w|_,ds->failwith(String.concat "; "(List.map Flow.Diagnostic.to_string ds))in
    let lowered=Flow_sop.Lower.of_checked ~factories:[] checked |> ok in
    let node=lowered.plan.nodes.(0)in
    let fn=match List.assoc "function" node.args with Flow.Eval.Fn fn->fn|_->assert false in
    let program=Flow_sop.Image_kernel.prepare ~path:(Option.get lowered.image_sites.(0))
      ~approx:lowered.approx ~site:(node.inst,node.site,node.iter)
      ~identity:0 ~width:65 ~height:17 ~fn ~sources:[] [] |> ok |> Flow_sop.Image_kernel.program in
    let value=Workspace_gpu.with_backend owner(fun()->
      match Flow_ir.Executor.try_display program ~live:(Frame_input.at_time 0.) |> ok with
      |Some(Gpu value)->value|_->assert false)in
    let publish key=Workspace_gpu.image owner ~key ~width:65 ~height:17 value ~publish:Result.ok in
    let held=publish "held" |> ok in
    let native_handles=handles()in
    for i=0 to 79 do
      let key=string_of_int i in
      assert(Result.is_error(Workspace_gpu.image owner ~key:("bad-shape:"^key)
        ~width:65 ~height:18 value ~publish:Result.ok));
      assert(Result.is_error(Workspace_gpu.image owner ~key:("bad-publication:"^key)
        ~width:65 ~height:17 value ~publish:(fun _->Error(Flow.Diagnostic.error ~code:"E_TEST" "publication refused"))));
      assert(Option.is_some(Flow_gpu.Image_sink.texture held));
      assert(handles()=native_handles)
    done;
    let host,created,closed,buffers,textures=Workspace_gpu.image_stats owner in
    assert(created=161 && closed=160 && buffers=81 && textures=81
      && host.status_reads=1 && host.readback_bytes=0);
    assert(try ignore(Workspace_gpu.image owner ~key:"raised" ~width:65 ~height:17 value
      ~publish:(fun _->failwith "publication raised"));false with Failure message->message="publication raised");
    assert(handles()=native_handles);
    let _,created,closed,buffers,textures=Workspace_gpu.image_stats owner in
    assert(created=162 && closed=161 && buffers=82 && textures=82);
    let outputs=Array.init 63(fun i->publish("accepted:"^string_of_int i) |> ok)in
    assert(Result.is_error(publish "over-capacity"));
    assert(Array.for_all(fun output->Option.is_some(Flow_gpu.Image_sink.texture output))outputs);
    assert(Option.is_some(Flow_gpu.Image_sink.texture held));
    assert(Result.is_error(Workspace_gpu.image owner ~key:"held" ~width:65 ~height:17 value
      ~publish:(fun _->Error(Flow.Diagnostic.error ~code:"E_TEST" "update refused"))));
    assert(Flow_gpu.Image_sink.texture held=None);
    assert(Option.is_some(Flow_gpu.Image_sink.texture(publish "held" |> ok)));
    let before,created,closed,buffers,textures=Workspace_gpu.image_stats owner in
    assert(created=225 && closed=161 && buffers=145 && textures=145);
    Workspace_gpu.close owner;Workspace_gpu.close owner;
    let after,created,closed,after_buffers,after_textures=Workspace_gpu.image_stats owner in
    assert(created=225 && closed=225 && after_buffers=buffers && after_textures=textures);
    assert(after.status_reads=before.status_reads && after.buffer_creations=before.buffer_creations
      && after.input_uploads=before.input_uploads && after.input_uploaded_bytes=before.input_uploaded_bytes
      && after.readback_bytes=before.readback_bytes && after.runners_created=after.runners_released));
  assert(handles()=before);
  assert(rejects_worker());
  print_endline "Workspace GPU sinks: failed conversions/publications/exceptions retain no slots or handles, 64 pinned sites remain live, failed updates invalidate and retry"
