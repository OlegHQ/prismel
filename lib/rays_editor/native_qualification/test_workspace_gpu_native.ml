let ok=function Ok value->value|Error d->failwith(Flow.Diagnostic.to_string d)
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
