open Tsdl
open Tsdl_ttf

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

(* Initialize SDL and all subsystems *)
let init_sdl () =
  (* Initialize SDL video and audio *)
  match Sdl.init Sdl.Init.(video + audio + events) with
  | Error (`Msg e) -> failwith ("SDL initialization failed: " ^ e)  
  | Ok () ->
    (* Initialize SDL_image *)
    let img_flags = Tsdl_image.Image.Init.(jpg + png) in
    let img_result = Tsdl_image.Image.init img_flags in
    if not (Tsdl_image.Image.Init.test img_result img_flags) then
      Printf.printf "Warning: Some image formats may not be supported\n%!";
    
    (* Initialize SDL_ttf *)
    (match Ttf.init () with
    | Error (`Msg e) -> Printf.printf "Warning: TTF initialization failed: %s\n%!" e
    | Ok () -> ());
    
    (* Initialize audio (SDL_mixer would go here if we had it) *)
    ()

(* Cleanup SDL and all subsystems *)
let cleanup_sdl () =
  Ttf.quit ();
  Tsdl_image.Image.quit ();
  Sdl.quit ()

(* Process a single frame *)
let process_frame window user_state update_fn draw_fn event_fn =
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
    
    (* Present the frame *)
    Sdl.render_present renderer;
    
    (* Frame rate limiting *)
    Time.limit_frame_rate ();
    
    { window; running = true; user_state = updated_state }
  end

(* Main application loop *)
let rec main_loop framework_state update_fn draw_fn event_fn =
  if framework_state.running then
    let new_framework_state = process_frame 
      framework_state.window 
      framework_state.user_state 
      update_fn 
      draw_fn 
      event_fn in
    main_loop new_framework_state update_fn draw_fn event_fn
  else
    framework_state.user_state

(* Main entry point - run the framework *)
let run 
    ?(config = Window.default_config) 
    ~init 
    ~update 
    ~draw 
    ?on_event 
    () =
  
  if !framework_running then
    failwith "Framework is already running. Only one instance is supported.";
  
  framework_running := true;
  quit_requested := false;
  
  try
    (* Initialize SDL and subsystems *)
    init_sdl ();
    
    (* Initialize timing system *)
    Time.init ();
    
    (* Create window *)
    let window = Window.create ~config () in
    Window.show ();
    
    (* Initialize graphics and image subsystems with the renderer *)
    let renderer = Window.get_renderer () in
    Graphics.init renderer;
    Image.set_renderer renderer;
    
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
      on_event in
    
    (* Cleanup *)
    Window.destroy ();
    cleanup_sdl ();
    framework_running := false;
    
    (* Return final state *)
    final_user_state
    
  with
  | e ->
    (* Ensure cleanup on exception *)
    (try Window.destroy () with _ -> ());
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
    ?on_event 
    () =
  let config = { Window.default_config with width; height; title } in
  run ~config ~init ~update ~draw ?on_event ()

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
