open Prismel_next_api
let ()=
  Input.reset~mouse:(0,0);Input.press_key(Input.KeyChar 'a');Input.update_mouse_pos 3 4;Input.update_mouse_pos 5 7;
  if not(Input.is_key_down(Input.KeyChar 'a'))||Input.mouse_delta()<>(5,7)then failwith"input";
  Input.begin_frame();if Input.mouse_delta()<>(0,0)then failwith"input frame reset";
  let push=Event.Private.push in ignore(Result.get_ok(push(Runtime_next_input.Pointer_pressed(Left,2.,3.))));
  ignore(Result.get_ok(push(Runtime_next_input.Pointer_moved(4.,8.))));let events=Event.poll_events()in
  if List.length events<>2||Input.mouse_pos()<>(4,8)||Input.mouse_delta()<>(-1,1)then failwith"typed event translation";
  let frame={Frame.width=4;height=3;size=(4,3);drawable_width=8;drawable_height=6;drawable_size=(8,6);pixel_scale=(2.,2.);time=1.;dt=0.5;fps=2.;count=1;mouse=(4,8);mouse_delta=(-1,1);keys=Input.keys_down();mouse_buttons=Input.mouse_buttons_down();events}in
  if not(Frame.mouse_down Input.LeftButton frame)||not(Frame.has_event(function Event.MouseMoved _->true|_->false)frame)then failwith"frame";
  Time.init();Time.set_time_scale 0.5;Unix.sleepf 0.001;Time.update();if Time.get_delta_time()<=0.||Time.get_time_scale()<>0.5 then failwith"time";
  let fired=ref false in Time.Scheduler.delay_call 0.(fun()->fired:=true);Time.Scheduler.update();if not !fired then failwith"scheduler";
  print_endline"prismel_next_api batch C: Event/Input/Frame/Time semantic fixtures passed"
