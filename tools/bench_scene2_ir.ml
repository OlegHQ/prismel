let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" Prismel_execution.pp_error error)

let command index : Scene_command.Render_ir.command =
  let x = float (index mod 32) in
  Geometry { vertices = [|x;0.;x+.1.;0.;x;1.|];
    indices = [|0;1;2|]; color = 0xffffffffl }

let make_ir () =
  let commands = Array.init 1024 command in
  match Scene_command.Render_ir.create commands with
  | Ok value -> value
  | Error _ -> failwith "benchmark IR is invalid"

let changing_ir frame =
  let transform : Scene_command.Render_ir.transform =
    { xx=1.; xy=0.; yx=0.; yy=1.; tx=float frame /. 100.; ty=0. } in
  let commands = Array.init 50 (fun index ->
    if index=0 then Scene_command.Render_ir.Push_transform transform
    else if index=49 then Scene_command.Render_ir.Pop_transform
    else command (index-1)) in
  match Scene_command.Render_ir.create commands with
  | Ok value -> value
  | Error _ -> failwith "changing benchmark IR is invalid"

let streaming_ir frame =
  let commands = Array.init 48 (fun index ->
    match command index with
    | Scene_command.Render_ir.Geometry geometry ->
        let vertices = Array.map ((+.) (float frame)) geometry.vertices in
        Scene_command.Render_ir.Geometry { geometry with vertices }
    | _ -> assert false) in
  match Scene_command.Render_ir.create commands with
  | Ok value -> value
  | Error _ -> failwith "streaming benchmark IR is invalid"

let percentile values fraction =
  let sorted = Array.copy values in
  Array.sort Float.compare sorted;
  sorted.(int_of_float (ceil (fraction *. float (Array.length sorted))) - 1)

let () =
  let config : Prismel_execution.configuration =
    { logical_width = 64; logical_height = 64;
      drawable_width = 64; drawable_height = 64;
      title = "scene2-ir-benchmark"; vsync = false } in
  let execution = get (Prismel_execution.create_offscreen config) in
  let retained = make_ir () in
  let copies = Array.init 50 (fun _ -> make_ir ()) in
  let changing = Array.init 50 changing_ir in
  let streaming = Array.init 50 streaming_ir in
  if Scene_command.Render_ir.Private.identity retained =
      Scene_command.Render_ir.Private.identity copies.(0) then
    failwith "distinct IR values share an identity";
  let lower ir = get (Prismel_execution.lower_scene2 execution ~density:1
    ~resource:(fun _ -> None) ir) in
  if lower retained <> lower copies.(0) then
    failwith "equivalent IR values lowered differently";
  let measure name commands calls pick =
    for index = 0 to 2 do
      ignore (lower (pick index))
    done;
    Gc.full_major ();
    let allocated = Gc.allocated_bytes () in
    let samples = Array.make 50 0. in
    for index = 0 to Array.length samples - 1 do
      let started = Unix.gettimeofday () in
      for _ = 1 to calls do
        ignore (lower (pick index))
      done;
      samples.(index) <- (Unix.gettimeofday () -. started) /. float calls
    done;
    Printf.printf "%s,%d,50,%d,%.9f,%.9f,%.0f\n%!" name commands calls
      (percentile samples 0.5) (percentile samples 0.95)
      ((Gc.allocated_bytes () -. allocated) /. (50. *. float calls)) in
  print_endline "mode,commands,frames,calls_per_frame,p50_s,p95_s,allocated_bytes_per_call";
  measure "retained" 1024 1000 (fun _ -> retained);
  measure "equivalent" 1024 1 (fun index -> copies.(index));
  measure "changing" 48 1 (fun index -> changing.(index));
  measure "streaming" 48 1 (fun index -> streaming.(index));
  (* Whole frames: lowering plus native submission to the offscreen target. *)
  let frame ir = get (Prismel_execution.step execution (lower ir)) in
  let measure_frame name commands run =
    for index = 0 to 2 do run index done;
    Gc.full_major ();
    let allocated = Gc.allocated_bytes () in
    let samples = Array.make 50 0. in
    for index = 0 to Array.length samples - 1 do
      let started = Unix.gettimeofday () in
      run index;
      samples.(index) <- Unix.gettimeofday () -. started
    done;
    Printf.printf "%s,%d,50,1,%.9f,%.9f,%.0f\n%!" name commands
      (percentile samples 0.5) (percentile samples 0.95)
      ((Gc.allocated_bytes () -. allocated) /. 50.) in
  measure_frame "frame_retained" 1024 (fun _ -> frame retained);
  measure_frame "frame_equivalent" 1024 (fun index -> frame copies.(index));
  measure_frame "frame_changing" 48 (fun index -> frame changing.(index));
  measure_frame "frame_streaming" 48 (fun index -> frame streaming.(index));
  (* PXUI publishes a fresh, usually content-identical instance table every
     frame: 2048 rects over 8 clipped batches. *)
  let ui_table () =
    let builder = Scene_command.Ui_batch.Builder.create () in
    for group = 0 to 7 do
      Scene_command.Ui_batch.Builder.set_clip builder
        (Some { x = 0.; y = float (group * 8); width = 64.; height = 8. });
      for index = 0 to 255 do
        Scene_command.Ui_batch.Builder.rect builder ~x:(float (index mod 64))
          ~y:(float (group * 8)) ~width:1. ~height:1. ~color:0xffffffffl ()
      done
    done;
    Scene_command.Ui_batch.Builder.publish builder in
  let ui_frame table =
    let submission = get (Prismel_execution.Private.begin_submission execution) in
    let batch = get (Prismel_execution.Private.lower_ui submission ~density:1
      ~resource:(fun _ -> None) table) in
    get (Prismel_execution.Private.step submission [ batch ]) in
  measure_frame "frame_ui_fresh" 2048 (fun _ -> ui_frame (ui_table ()));
  let table = ui_table () in
  measure_frame "frame_ui_retained" 2048 (fun _ -> ui_frame table);
  get (Prismel_execution.destroy execution)
