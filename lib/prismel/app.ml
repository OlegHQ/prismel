open Tsdl

(* Framework configuration *)
type config = Window.config

(* Framework state *)
type 'a framework_state = {
  window : Window.t;
  running : bool;
  user_state : 'a;
}

(* Global framework state *)
let framework_running = ref false
let quit_requested = ref false

(* Request framework shutdown *)
let request_quit () =
  quit_requested := true

(* Check if framework is running *)
let is_running () = !framework_running

(* Initialize the selected presentation target and Prismel-owned audio. *)
let init_sdl ?(config = Window.default_config) () =
  (match Backend.start ~width:config.width ~height:config.height
      ~title:config.title ~resizable:config.resizable with
   | Ok _ -> ()
   | Error message -> failwith message);
  match Audio.init () with
  | Ok () -> ()
  | Error message ->
      Printf.eprintf "Warning: audio disabled: %s\n%!" message

(* Cleanup SDL and all subsystems *)
let cleanup_sdl () =
  Audio.shutdown ();
  Backend.stop ()

let cleanup_graphics () =
  if Window.exists () then begin
    let renderer = Window.get_renderer () in
    Renderer3d.release_renderer renderer;
    Font.release_renderer renderer
  end;
  Font.shutdown ();
  Window.destroy ()

(* Process a single frame *)
let process_frame window user_state update_fn draw_fn after_draw_fn event_fn =
  (* Deltas belong to application frames, not individual SDL motion events. *)
  Input.begin_frame ();
  (* Poll and handle events *)
  let (new_user_state, events) = Event.handle_events user_state event_fn in
  
  (* Check for quit conditions *)
  let should_quit = !quit_requested || 
    List.exists (function Event.WindowClosed -> true | _ -> false) events in
  
  if should_quit then
    { window; running = false; user_state = new_user_state }
  else begin
    (* Update timing *)
    Time.update ();
    let dt = Time.get_delta_time () in
    
    (* Update user state *)
    let updated_state = update_fn new_user_state dt in
    
    (* Clear screen and draw *)
    let renderer = Window.get_renderer () in
    (match Sdl.render_clear renderer with
    | Error (`Msg e) -> Printf.printf "Warning: Render clear failed: %s\n%!" e
    | Ok () -> ());
    
    (* Call user draw function *)
    draw_fn updated_state;
    Option.iter (fun after_draw -> after_draw updated_state) after_draw_fn;
    
    (* Present through the selected native, headless, or web target. *)
    let logical_width, logical_height = Window.size () in
    (match Backend.present renderer ~logical_width ~logical_height with
     | Ok () -> ()
     | Error message ->
         Printf.eprintf "Prismel presentation warning: %s\n%!" message);
    
    (* Frame rate limiting *)
    Time.limit_frame_rate ();
    
    { window; running = true; user_state = updated_state }
  end

(* Main application loop *)
let rec main_loop framework_state update_fn draw_fn after_draw_fn event_fn =
  if framework_state.running then
    let new_framework_state = process_frame 
      framework_state.window 
      framework_state.user_state 
      update_fn 
      draw_fn 
      after_draw_fn
      event_fn in
    main_loop new_framework_state update_fn draw_fn after_draw_fn event_fn
  else
    framework_state.user_state

(* Main entry point - run the framework *)
let run 
    ?(config = Window.default_config) 
    ~init 
    ~update 
    ~draw 
    ?after_draw
    ?on_event 
    ?on_stop
    () =
  
  if !framework_running then
    failwith "Framework is already running. Only one instance is supported.";
  
  framework_running := true;
  quit_requested := false;
  
  try
    (* Initialize SDL and subsystems *)
    init_sdl ~config ();
    
    (* Initialize timing system *)
    Time.init ();
    Time.set_vsync config.vsync;
    
    (* Create window *)
    let window = Window.create ~config () in
    if not (Backend.is_displayless ()) then Window.show ();
    let _, mouse = Sdl.get_mouse_state () in
    Input.reset ~mouse;
    Sdl.start_text_input ();
    
    (* Initialize graphics and image subsystems with the renderer *)
    let renderer = Window.get_renderer () in
    Graphics.init renderer;
    Image.Private.set_renderer renderer;
    
    (* Initialize user state *)
    let initial_user_state = init () in
    
    (* Create initial framework state *)
    let initial_framework_state = {
      window;
      running = true;
      user_state = initial_user_state;
    } in
    
    (* Run main loop *)
    let final_user_state = main_loop 
      initial_framework_state 
      update 
      draw 
      after_draw
      on_event in

    Option.iter (fun stop -> stop final_user_state) on_stop;
    
    (* Cleanup *)
    Sdl.stop_text_input ();
    cleanup_graphics ();
    cleanup_sdl ();
    framework_running := false;
    
    (* Return final state *)
    final_user_state
    
  with
  | e ->
    (* Ensure cleanup on exception *)
    (try Sdl.stop_text_input () with _ -> ());
    (try cleanup_graphics () with _ -> ());
    (try cleanup_sdl () with _ -> ());
    framework_running := false;
    raise e

(* Convenience function to run with minimal configuration *)
let run_simple 
    ?(width = 800) 
    ?(height = 600) 
    ?(title = "Creative Coding")
    ~init 
    ~update 
    ~draw 
    ?after_draw
    ?on_event 
    ?on_stop
    () =
  let config = { Window.default_config with width; height; title } in
  run ~config ~init ~update ~draw ?after_draw ?on_event ?on_stop ()

(* Get current window (for accessing from user code) *)
let get_window () = 
  if Window.exists () then Window.get_current ()
  else failwith "No window available. Framework not running."

(* Get current renderer (for accessing from user code) *)  
let get_renderer () =
  if Window.exists () then Window.get_renderer ()
  else failwith "No renderer available. Framework not running."

(* Utility functions for common operations *)
module Utils = struct
  (* Get current window dimensions *)
  let window_size () = Window.size ()
  let window_width () = Window.width ()
  let window_height () = Window.height ()
  
  (* Get current time and delta time *)
  let time () = Time.now ()
  let delta_time () = Time.get_delta_time ()
  let frame_rate () = Time.get_frame_rate ()
  
  (* Set frame rate and vsync *)
  let set_frame_rate fps = Time.set_frame_rate fps
  let set_vsync enabled = Time.set_vsync enabled
end
