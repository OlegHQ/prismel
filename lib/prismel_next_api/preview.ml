let session : Prismel_next_execution.t option ref=ref None
let last_capture=ref Bytes.empty
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"Prismel_next_execution.pp_error e)
let target()=match Runtime_next_compat.selected_target()with Ok Native->Prismel_next_execution.Native|Ok Headless->Headless|Ok Web->Web|Error e->invalid_arg e
let start ?(width=640)?(height=480)?(title="Prismel Preview")()=
  match!session with Some _->()|None->let configuration={Prismel_next_execution.default_configuration with target=target();logical_width=width;logical_height=height;drawable_width=width;drawable_height=height;title}in
  let value=get(Prismel_next_execution.create configuration)in session:=Some value;
  Scene.Private.install_renderer(fun scene->let ir=Result.get_ok(Scene.Private.to_ir scene)in let resources=Scene.Private.resources scene in
    let draws=get(Prismel_next_execution.lower_scene2 value~density:1~resource:(fun id->List.assoc_opt id resources)ir)in ignore(get(Prismel_next_execution.step value draws)))
let is_open()=Option.is_some!session
let step scene=if Option.is_none!session then start();let events=Event.poll_events()in Scene.render scene;
  (match!session with Some value->last_capture:=get(Prismel_next_execution.capture value)|None->());events
let show scene=ignore(step scene)
let stop()=match!session with None->()|Some value->ignore(Prismel_next_execution.destroy value);session:=None;last_capture:=Bytes.empty
