open Prismel
open Core

let draw time =
  Graphics.clear (Color.rgb 0 0 0);
  Graphics.push_matrix ();
  
  (* Get window dimensions for centering the rotation *)
  let (w, h) = App.Utils.window_size () in
  
  let center_x = w*2 / 2 in
  let center_y = h*2 / 2 in
  
  (* Move to center, rotate 90 degrees, then move back *)
  Graphics.translate ~dx:center_x ~dy:center_y;
  Graphics.rotate ~angle:(Float.pi /. 2.0); (* 90 degrees in radians *)
  Graphics.translate ~dx:(-center_x) ~dy:(-center_y);
  
  Graphics.scale ~sx:2. ~sy:2.;
  
 
  (for i = 0 to 500 do
    let cy = i  in
    let open Float.O in
    let i = (i |> float_of_int )*4. in
    let size = 50. + (40. * Math.sin ((time + (i * 0.0037)) * 1.)) in


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

