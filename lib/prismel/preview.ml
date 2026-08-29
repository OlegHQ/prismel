let session : Prismel_next_execution.t option ref=ref None
let last_capture=ref Bytes.empty
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"Prismel_next_execution.pp_error e)
let start ?(width=800)?(height=600)?(title="Prismel preview")()=
  if width<=0||height<=0 then invalid_arg"Preview.start: dimensions must be positive";
  match!session with Some _->()|None->let configuration={Prismel_next_execution.default_configuration with logical_width=width;logical_height=height;drawable_width=width;drawable_height=height;title}in
  let value=get(Prismel_next_execution.create configuration)in session:=Some value;
  Scene.Private.install_renderer(fun scene->
    let facts=get(Prismel_next_execution.presentation_facts value)in
    let density=max 1(int_of_float(Float.round facts.pixel_density))in
    match Native_scene_lowering.render~execution:value~density
      ~width:facts.logical_width~height:facts.logical_height scene with
    |Ok _->()
    |Error error->
        failwith(Format.asprintf"Preview.render: %a"Native_scene_lowering.pp_error error))
let is_open()=Option.is_some!session
let step scene=if Option.is_none!session then start();let events=Event.poll_events()in Scene.render scene;
  (match!session with Some value->last_capture:=get(Prismel_next_execution.capture value)|None->());events
let show scene=ignore(step scene)
let stop()=match!session with None->()|Some value->ignore(Prismel_next_execution.destroy value);session:=None;last_capture:=Bytes.empty
