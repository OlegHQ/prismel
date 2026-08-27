open Prismel_next_execution
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a"pp_error e)
let check condition message=if not condition then failwith message
let geometry = Raster2.Render_ir.Geometry { vertices=[|2.;2.; 30.;2.; 2.;30.|]; indices=[|0;1;2|]; color=0x4080BFFFl }
let ir=Result.get_ok(Raster2.Render_ir.create[|Raster2.Render_ir.Clear 0x000000FFl;geometry|])
let configuration={default_configuration with logical_width=32;logical_height=32;drawable_width=32;drawable_height=32}
let () =
  let draws=get(scene2_ir ir)in
  let coordinator=get(create configuration)in
  get(push_event coordinator(Pointer_moved(3.,4.)));
  let first=get(step coordinator draws)in
  check(first.frame=1L&&first.time=1./.60.)"fixed frame facts";
  check(first.events=[Pointer_moved(3.,4.)])"ordered one-frame input";
  let pixels=get(capture coordinator)in
  check(Bytes.length pixels=32*32*4)"capture extent";
  get(resize coordinator~logical_width:16~logical_height:12~drawable_width:32~drawable_height:24);
  let second=get(step coordinator(scene2_ir ir|>get))in
  check(second.frame=2L&&second.logical_width=16&&second.drawable_width=32)"resize facts";
  check(second.events=[Resized(16,12)])"resize event";
  for _=1 to 600 do ignore(get(step coordinator draws))done;
  get(destroy coordinator);get(destroy coordinator);
  check(match step coordinator draws with Error e->e.kind=Destroyed|Ok _->false)"stale rejection";
  let bounded=get(create{configuration with max_events=64})in
  for index=1 to 100_000 do get(push_event bounded(Pointer_moved(float index,0.)))done;
  let bounded_facts=get(step bounded draws)in
  check(List.length bounded_facts.events<=64&&bounded_facts.dropped_events>0)"100k bounded input";
  get(destroy bounded);
  let stopped=ref false in
  check(match run configuration(fun _->raise Exit)~on_stop:(fun _->stopped:=true;Ok())with Error _->true|Ok _->false)"exception mapped";
  check !stopped"exception cleanup on_stop"
