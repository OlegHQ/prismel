let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" Prismel_next_execution.pp_error error)

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
  let config : Prismel_next_execution.configuration =
    { logical_width = 64; logical_height = 64;
      drawable_width = 64; drawable_height = 64;
      title = "scene2-ir-benchmark"; vsync = false } in
  let execution = get (Prismel_next_execution.create_offscreen config) in
  let retained = make_ir () in
  let copies = Array.init 50 (fun _ -> make_ir ()) in
  let changing = Array.init 50 changing_ir in
  let streaming = Array.init 50 streaming_ir in
  if Scene_command.Render_ir.Private.identity retained =
      Scene_command.Render_ir.Private.identity copies.(0) then
    failwith "distinct IR values share an identity";
  let lower ir = get (Prismel_next_execution.lower_scene2 execution ~density:1
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
  get (Prismel_next_execution.destroy execution)
