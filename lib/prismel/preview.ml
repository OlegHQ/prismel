let session : Prismel_next_execution.t option ref=ref None
let last_capture=ref Bytes.empty
let last_scene : Scene.t option ref = ref None
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"Prismel_next_execution.pp_error e)
let draw_of_entry(entry:Scene_execution.scene3_entry)=
  Prismel_next_execution.prepared_draw
    ~family:(match entry.family with Scene3->Scene3|Scene3_textured->Scene3_textured
      |Scene3_shadow->Scene3_shadow|Scene3_stencil->Scene3_stencil
      |Scene3_textured_stencil->Scene3_textured_stencil
      |Scene3_shadow_stencil->Scene3_shadow_stencil|Scene2->Scene2
      |Scene2_textured->Scene2_textured)
    ~blend:(match entry.blend with Replace->Replace|Alpha->Alpha|Add->Add
      |Multiply->Multiply|Screen->Screen|Subtract->Subtract)
    ?texture:entry.texture ?auxiliary:entry.auxiliary ~samples:entry.samples
    entry.draw
let start ?(width=800)?(height=600)?(title="Prismel preview")()=
  if width<=0||height<=0 then invalid_arg"Preview.start: dimensions must be positive";
  match!session with Some _->()|None->let configuration={Prismel_next_execution.default_configuration with logical_width=width;logical_height=height;drawable_width=width;drawable_height=height;title}in
  let value=get(Prismel_next_execution.create configuration)in session:=Some value;
  Scene.Private.install_renderer(fun scene->
    last_scene:=Some scene;
    let facts=get(Prismel_next_execution.presentation_facts value)in
    let staged=Result.get_ok(Scene.Private.stage_native
      ~width:facts.logical_width~height:facts.logical_height scene)in
    let density=max 1(int_of_float(Float.round facts.pixel_density))in
    let draws=List.concat_map(function
      |Scene.Private.Scene2_layer(ir,resources)->
          get(Prismel_next_execution.lower_scene2 value~density
            ~resource:(fun id->List.assoc_opt id resources)ir)
      |Scene.Private.Scene3_layer prepared->
          Array.to_list prepared.Scene_execution.entries|>List.map draw_of_entry)
      staged.layers in
    ignore(get(Prismel_next_execution.step~clear:staged.clear value draws)))
let is_open()=Option.is_some!session
let step scene=if Option.is_none!session then start();let events=Event.poll_events()in Scene.render scene;
  (match!session with Some value->last_capture:=get(Prismel_next_execution.capture value)|None->());events
let show scene=ignore(step scene)
let stop()=match!session with None->()|Some value->Option.iter Scene.Private.release !last_scene;last_scene:=None;ignore(Prismel_next_execution.destroy value);session:=None;last_capture:=Bytes.empty
