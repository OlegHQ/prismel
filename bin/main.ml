(* Test the new App and Window modules


(* Complex generative art state *)
type app_state = {
  counter : int;
  time : float;
  color_phase : float;
  spiral_phase : float;
  pulse_phase : float;
}

(* Initialize the application state *)
let init () = {
  counter = 0;
  time = 0.0;
  color_phase = 0.0;
  spiral_phase = 0.0;
  pulse_phase = 0.0;
}

(* Update the application state each frame *)
let update state dt = {
  counter = state.counter + 1;
  time = state.time +. dt;
  color_phase = state.color_phase +. (dt *. 1.5);
  spiral_phase = state.spiral_phase +. (dt *. 0.8);
  pulse_phase = state.pulse_phase +. (dt *. 3.0);
}

(* Helper function to create animated colors *)
let animated_color phase offset alpha =
  let r = int_of_float (127.0 +. 127.0 *. sin (phase +. offset)) in
  let g = int_of_float (127.0 +. 127.0 *. sin (phase +. offset +. 2.0)) in
  let b = int_of_float (127.0 +. 127.0 *. sin (phase +. offset +. 4.0)) in
  Color.rgba r g b alpha

(* Draw a spiral of shapes *)
let draw_spiral state cx cy =
  let num_shapes = 24 in
  let radius_base = 80.0 in
  for i = 0 to num_shapes - 1 do
    let angle = float_of_int i *. (2.0 *. Float.pi /. float_of_int num_shapes) +. state.spiral_phase in
    let radius = radius_base +. 40.0 *. sin (state.time +. float_of_int i *. 0.3) in
    let x = cx + int_of_float (radius *. cos angle) in
    let y = cy + int_of_float (radius *. sin angle) in
    let size = int_of_float (15.0 +. 10.0 *. sin (state.pulse_phase +. float_of_int i *. 0.5)) in
    let color = animated_color state.color_phase (float_of_int i *. 0.2) 180 in
    
    Graphics.push_matrix ();
    Graphics.translate ~dx:x ~dy:y;
    Graphics.rotate ~angle:(angle +. state.time *. 2.0);
    
    (* Alternate between different shapes *)
    (match i mod 4 with
    | 0 -> Graphics.circle ~center:(0, 0) ~radius:size ~filled:true ~color ()
    | 1 -> Graphics.rect ~pos:(-size/2, -size/2) ~w:size ~h:size ~filled:true ~color ()
    | 2 -> Graphics.triangle ~p1:(-size, size/2) ~p2:(size, size/2) ~p3:(0, -size) ~filled:true ~color ()
    | _ -> Graphics.polygon ~points:[(-size, 0); (0, -size); (size, 0); (0, size)] ~filled:true ~color ());
    
    Graphics.pop_matrix ();
  done

(* Draw geometric flowers *)
let draw_flower state cx cy =
  let num_petals = 8 in
  let petal_size = int_of_float (25.0 +. 15.0 *. sin state.pulse_phase) in
  let rotation_offset = state.time *. 0.5 in
  
  Graphics.push_matrix ();
  Graphics.translate ~dx:cx ~dy:cy;
  Graphics.rotate ~angle:rotation_offset;
  
  for i = 0 to num_petals - 1 do
    let angle = float_of_int i *. (2.0 *. Float.pi /. float_of_int num_petals) in
    let petal_x = int_of_float (35.0 *. cos angle) in
    let petal_y = int_of_float (35.0 *. sin angle) in
    let color = animated_color state.color_phase (float_of_int i *. 0.3) 150 in
    
    Graphics.push_matrix ();
    Graphics.translate ~dx:petal_x ~dy:petal_y;
    Graphics.rotate ~angle;
    Graphics.ellipse ~center:(0, 0) ~rx:petal_size ~ry:(petal_size/2) ~filled:true ~color ();
    Graphics.pop_matrix ();
  done;
  
  (* Center of flower *)
  let center_color = animated_color state.color_phase 1.0 255 in
  Graphics.circle ~center:(0, 0) ~radius:12 ~filled:true ~color:center_color ();
  
  Graphics.pop_matrix ()

(* Draw interconnected web *)
let draw_web state cx cy =
  let num_points = 12 in
  let radius = 120.0 in
  let points = ref [] in
  
  (* Generate points on circle *)
  for i = 0 to num_points - 1 do
    let angle = float_of_int i *. (2.0 *. Float.pi /. float_of_int num_points) +. state.spiral_phase *. 0.3 in
    let point_radius = radius +. 20.0 *. sin (state.time *. 2.0 +. float_of_int i *. 0.4) in
    let x = cx + int_of_float (point_radius *. cos angle) in
    let y = cy + int_of_float (point_radius *. sin angle) in
    points := (x, y) :: !points
  done;
  
  let points = List.rev !points in
  
  (* Draw connections between points *)
  let color = animated_color state.color_phase 0.0 100 in
  List.iteri (fun i (x1, y1) ->
    List.iteri (fun j (x2, y2) ->
      if i < j && (j - i) <= 3 then
        Graphics.line ~x1 ~y1 ~x2 ~y2 ~color ()
    ) points
  ) points;
  
  (* Draw points *)
  let point_color = animated_color state.color_phase 2.0 200 in
  List.iter (fun (x, y) ->
    Graphics.circle ~center:(x, y) ~radius:6 ~filled:true ~color:point_color ()
  ) points

(* Main draw function *)
let draw state =
  (* Dark animated background *)
  let bg_r = int_of_float (20.0 +. 15.0 *. sin (state.color_phase *. 0.3)) in
  let bg_g = int_of_float (15.0 +. 10.0 *. sin (state.color_phase *. 0.2)) in
  let bg_b = int_of_float (25.0 +. 20.0 *. sin (state.color_phase *. 0.4)) in
  let bg_color = Color.rgba bg_r bg_g bg_b 255 in
  Graphics.clear bg_color;
  
  let (w, h) = App.Utils.window_size () in
  let center_x = w / 2 in
  let center_y = h / 2 in
  
  (* Draw multiple layers of patterns *)
  
  (* Background web *)
  draw_web state center_x center_y;
  
  (* Orbiting flowers *)
  let num_flowers = 4 in
  for i = 0 to num_flowers - 1 do
    let orbit_angle = float_of_int i *. (2.0 *. Float.pi /. float_of_int num_flowers) +. state.time *. 0.4 in
    let orbit_radius = 180.0 in
    let flower_x = center_x + int_of_float (orbit_radius *. cos orbit_angle) in
    let flower_y = center_y + int_of_float (orbit_radius *. sin orbit_angle) in
    draw_flower state flower_x flower_y;
  done;
  
  (* Central spiral *)
  draw_spiral state center_x center_y;
  
  (* Decorative corner elements *)
  let corner_size = 40 in
  let corner_color = animated_color state.color_phase 5.0 120 in
  let corner_positions = [(corner_size, corner_size); (w - corner_size, corner_size); 
                         (corner_size, h - corner_size); (w - corner_size, h - corner_size)] in
  List.iter (fun (x, y) ->
    Graphics.push_matrix ();
    Graphics.translate ~dx:x ~dy:y;
    Graphics.rotate ~angle:(state.time *. 1.5);
    Graphics.rounded_rect ~pos:(-20, -20) ~w:40 ~h:40 ~radius:8 ~filled:false ~color:corner_color ();
    Graphics.line ~x1:(-15) ~y1:0 ~x2:15 ~y2:0 ~color:corner_color ();
    Graphics.line ~x1:0 ~y1:(-15) ~x2:0 ~y2:15 ~color:corner_color ();
    Graphics.pop_matrix ();
  ) corner_positions;
  
  Printf.printf "Frame %d, Time: %.2f, Shapes rendered\r%!" state.counter state.time

(* Handle events *)

(* Main entry point *)
let () =
  try
    let config = { Window.default_config with 
      width = 800; 
      height = 600; 
      title = "App & Window Test";
      resizable = true;
    } in
    
    Printf.printf "Starting App & Window test application...\n%!";
    
    let _final_state = App.run 
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
    exit 1 *)
open Prismel
open Core

let draw time =
  Graphics.clear (Color.rgb 0 0 0);
  Graphics.push_matrix ();
  Graphics.scale ~sx:2. ~sy:2.;
 
  (for i = 0 to 250 do
    let cy = i * 2 in
    let open Float.O in
    let i = (i |> float_of_int )*4. in
    let size = 50. + (40. * Math.sin ((time + (i * 0.00737)) * 1.)) in


    let offset =  i * 0.01 in
    let st = Math.sin ((time + offset) ) in
    let cx = 250. + (200. * st) in 

   let color = Color.rgb 
   ((127. + 127. * Math.sin(i * 0.01)) |> int_of_float)
   ((127. + 127. * Math.sin(i * 0.011)) |> int_of_float)
   ((127. + 127. * Math.sin(i * 0.012) ) |> int_of_float)
   in
   let size = size |> int_of_float in

    (* Graphics.rect ~pos:(cx |> int_of_float, cy) ~w:size ~h:size ~color () *)
    Graphics.circle ~center:(cx |> int_of_float, cy ) ~radius:size ~filled:true ~color ()
  done);

  Graphics.pop_matrix ()


let handle_event state event =
  match event with
  | Event.KeyPressed Input.Escape ->
      Printf.printf "\nEscape pressed, quitting...\n%!";
      App.request_quit ();
      state
  | Event.KeyPressed (Input.KeyChar 'q') ->
      Printf.printf "\nQ pressed, quitting...\n%!";
      App.request_quit ();
      state
  | Event.WindowClosed ->
      Printf.printf "\nWindow closed\n%!";
      state
  | _ -> state

let () =
  let size = 500 in
  let conf = { Window.default_config with width = size; height = size } in
  App.Utils.set_frame_rate 60;
  let _ =
    App.run ~config:conf
      ~init:(fun () -> 0.0)
      ~update:(fun x dt -> x +. dt)
      ~draw () ~on_event:handle_event
  in
  ()

