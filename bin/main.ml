(* Test the new Core and Window modules *)
open Ocaml_graphics_test

(* Simple application state *)
type app_state = {
  counter : int;
  color_phase : float;
}

(* Initialize the application state *)
let init () = {
  counter = 0;
  color_phase = 0.0;
}

(* Update the application state each frame *)
let update state dt = {
  counter = state.counter + 1;
  color_phase = state.color_phase +. (dt *. 2.0);
}

(* Draw the current state *)
let draw state =
  (* Calculate animated color *)
  let r = int_of_float (127.0 +. 127.0 *. sin state.color_phase) in
  let g = int_of_float (127.0 +. 127.0 *. sin (state.color_phase +. 1.0)) in
  let b = int_of_float (127.0 +. 127.0 *. sin (state.color_phase +. 2.0)) in
  
  (* Create animated background color *)
  let bg_color = Color.rgba r g b 255 in
  
  (* Clear with animated background color *)
  Graphics.clear bg_color;
  
  (* Draw a simple rectangle in the center *)
  let (w, h) = Core.Utils.window_size () in
  let rect_x = w / 2 - 50 in
  let rect_y = h / 2 - 50 in
  
  (* Draw white rectangle *)
  Graphics.rect ~pos:(rect_x, rect_y) ~w:100 ~h:100 ~filled:false ~color:Color.white ();
  
  Printf.printf "Frame %d, Phase: %.2f\r%!" state.counter state.color_phase

(* Handle events *)
let handle_event state event =
  match event with
  | Event.KeyPressed Input.Escape -> 
    Printf.printf "\nEscape pressed, quitting...\n%!";
    Core.request_quit ();
    state
  | Event.KeyPressed (Input.KeyChar 'q') -> 
    Printf.printf "\nQ pressed, quitting...\n%!";
    Core.request_quit ();
    state
  | Event.WindowClosed ->
    Printf.printf "\nWindow closed\n%!";
    state
  | _ -> state

(* Main entry point *)
let () =
  try
    let config = { Window.default_config with 
      width = 800; 
      height = 600; 
      title = "Core & Window Test";
      resizable = true;
    } in
    
    Printf.printf "Starting Core & Window test application...\n%!";
    
    let _final_state = Core.run 
      ~config 
      ~init 
      ~update 
      ~draw 
      ~on_event:handle_event 
      () in
    
    Printf.printf "Application finished successfully.\n%!"
    
  with
  | Failure msg -> 
    Printf.printf "Error: %s\n%!" msg;
    exit 1
  | e -> 
    Printf.printf "Unexpected error: %s\n%!" (Printexc.to_string e);
    exit 1
