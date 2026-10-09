let ok=function Ok value->value|Error d->failwith(Flow.Diagnostic.to_string d)
let ()=
  let _,handles=Ogpu.Impl.create_driver()in
  let before=handles()in
  let owner=Workspace_gpu.create()in
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
    assert(try ignore(Workspace_gpu.image owner ~key:"raised" ~width:65 ~height:17 value
      ~publish:(fun _->failwith "publication raised"));false with Failure message->message="publication raised");
    assert(handles()=native_handles);
    let outputs=Array.init 63(fun i->publish("accepted:"^string_of_int i) |> ok)in
    assert(Result.is_error(publish "over-capacity"));
    assert(Array.for_all(fun output->Option.is_some(Flow_gpu.Image_sink.texture output))outputs);
    assert(Option.is_some(Flow_gpu.Image_sink.texture held));
    assert(Result.is_error(Workspace_gpu.image owner ~key:"held" ~width:65 ~height:17 value
      ~publish:(fun _->Error(Flow.Diagnostic.error ~code:"E_TEST" "update refused"))));
    assert(Flow_gpu.Image_sink.texture held=None);
    assert(Option.is_some(Flow_gpu.Image_sink.texture(publish "held" |> ok))));
  assert(handles()=before);
  print_endline "Workspace GPU sinks: failed conversions/publications/exceptions retain no slots or handles, 64 pinned sites remain live, failed updates invalidate and retry"
