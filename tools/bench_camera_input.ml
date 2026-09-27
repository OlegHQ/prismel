open Prismel

let frame events : Frame.t =
  let mouse = List.fold_left (fun point -> function
    | Event.MouseMoved point -> point | _ -> point) (800., 100.) events in {
  width = 900; height = 640; size = 900, 640;
  drawable_width = 900; drawable_height = 640; drawable_size = 900, 640;
  pixel_scale = 1., 1.; time = 0.; dt = 0.; fps = 60.; count = 0;
  mouse; mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events }

let measure name create update events =
  let input = frame events and iterations = 500_000 in
  let value = ref (create ()) in
  Gc.full_major ();
  let allocated = Gc.allocated_bytes () and started = Unix.gettimeofday () in
  for _ = 1 to iterations do value := update !value input done;
  Printf.printf "%s,%d,%.6f,%.0f\n%!" name iterations
    (Unix.gettimeofday () -. started) (Gc.allocated_bytes () -. allocated)

let () =
  print_endline "camera_case,frames,elapsed_s,allocated_bytes";
  for _ = 1 to 3 do
    List.iter (fun (name, events) ->
      measure ("3D_" ^ name)
        (fun () -> Easy_camera.create ~inertia:false ~control_area:(0, 0, 450, 640) ())
        Easy_camera.update events;
      measure ("2D_" ^ name)
        (fun () -> Easy_camera2.create ~inertia:false ~control_area:(0, 0, 450, 640) ())
        Easy_camera2.update events)
      ["idle", []; "wheel_view", [Event.MouseMoved (100., 100.);
        Event.MouseScrolled (0., 0.000001)];
        "wheel_crossing", [Event.MouseMoved (100., 100.);
        Event.MouseScrolled (0., 0.000001); Event.MouseMoved (800., 100.)]]
  done
