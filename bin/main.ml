(* bin/main.ml *)
open Tsdl

let delay = 16 (* ~60 FPS *)

let () =
  match Sdl.init Sdl.Init.video with
  | Error (`Msg e) -> failwith ("SDL init failed: " ^ e)
  | Ok () -> (
      match Sdl.create_window ~w:800 ~h:600 "Moving Box!" Sdl.Window.shown with
      | Error (`Msg e) ->
          Sdl.quit ();
          failwith ("Window creation failed: " ^ e)
      | Ok window -> (
          match
            Sdl.create_renderer window ~index:(-1)
              ~flags:Sdl.Renderer.accelerated
          with
          | Error (`Msg e) ->
              Sdl.destroy_window window;
              Sdl.quit ();
              failwith ("Renderer creation failed: " ^ e)
          | Ok renderer ->
              let event = Sdl.Event.create () in

              let box = Sdl.Rect.create ~x:100 ~y:100 ~w:50 ~h:50 in
              let vx = ref 4 in
              let vy = ref 3 in

              let rec loop () =
                (* Poll quit *)
                let quit =
                  if Sdl.poll_event (Some event) then
                    Sdl.Event.get event Sdl.Event.typ = Sdl.Event.quit
                  else false
                in

                (* Update position *)
                let x = Sdl.Rect.x box + !vx in
                let y = Sdl.Rect.y box + !vy in

                (* Bounce on walls *)
                if x < 0 || x + Sdl.Rect.w box > 800 then vx := - !vx;
                if y < 0 || y + Sdl.Rect.h box > 600 then vy := - !vy;

                Sdl.Rect.set_x box (Sdl.Rect.x box + !vx);
                Sdl.Rect.set_y box (Sdl.Rect.y box + !vy);

                (* Clear screen *)
                Sdl.set_render_draw_color renderer 20 20 30 255 |> ignore;
                Sdl.render_clear renderer |> ignore;

                (* Draw animated box *)
                Sdl.set_render_draw_color renderer 255 165 0 255 |> ignore;
                Sdl.render_fill_rect renderer (Some box) |> ignore;

                Sdl.render_present renderer;

                Sdl.delay (Int32.of_int delay) |> ignore;

                if quit then () else loop ()
              in

              loop ();
              Sdl.destroy_renderer renderer;
              Sdl.destroy_window window;
              Sdl.quit ()))
