open Wap

let integer_env name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let width = integer_env "PRISMEL_WAP_BENCH_WIDTH" 640
let height = integer_env "PRISMEL_WAP_BENCH_HEIGHT" 360
let frames = integer_env "PRISMEL_WAP_BENCH_FRAMES" 120

let set_pixel pixels index red green blue =
  let offset = index * 4 in
  Bigarray.Array1.unsafe_set pixels offset red;
  Bigarray.Array1.unsafe_set pixels (offset + 1) green;
  Bigarray.Array1.unsafe_set pixels (offset + 2) blue;
  Bigarray.Array1.unsafe_set pixels (offset + 3) 255

let static_ui _frame pixels =
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let red, green, blue =
        if x >= width / 8 && x < width * 7 / 8
           && y >= height / 5 && y < height * 4 / 5
        then 24, 31, 43
        else 8, 11, 18
      in
      set_pixel pixels ((y * width) + x) red green blue
    done
  done

let moving_sprite frame pixels =
  let center_x = 24 + (frame * 7 mod max 1 (width - 48))
  and center_y = height / 2 and radius = 20 in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let dx = x - center_x and dy = y - center_y in
      if (dx * dx) + (dy * dy) <= radius * radius then
        set_pixel pixels ((y * width) + x) 64 190 235
      else set_pixel pixels ((y * width) + x) 8 11 18
    done
  done

let noisy frame pixels =
  let state = ref (Int32.of_int (frame + 1)) in
  let next () =
    state := Int32.add (Int32.mul !state 1664525l) 1013904223l;
    Int32.to_int (Int32.shift_right_logical !state 24)
  in
  for index = 0 to (width * height) - 1 do
    set_pixel pixels index (next ()) (next ()) (next ())
  done

let run name fill compress_frames =
  let server =
    start ~config:{ default_config with
      interface = "127.0.0.1"; port = 0; compress_frames;
    } ()
    |> function Ok server -> server | Error message -> failwith message
  in
  Fun.protect ~finally:(fun () -> stop server) (fun () ->
    let encode_seconds = ref 0. in
    for frame = 0 to frames - 1 do
      let pixels = acquire_frame server ~length:(width * height * 4) in
      fill frame pixels;
      let started = Unix.gettimeofday () in
      publish_frame server ~drawable_width:width ~drawable_height:height
        ~logical_width:width ~logical_height:height pixels;
      encode_seconds := !encode_seconds +. Unix.gettimeofday () -. started
    done;
    let measured = stats server in
    let ratio =
      if measured.source_bytes_submitted = 0L then 0.
      else Int64.to_float measured.payload_bytes_published
           /. Int64.to_float measured.source_bytes_submitted
    in
    Printf.printf "%s,%b,%d,%d,%d,%d,%d,%Ld,%Ld,%.6f,%.6f\n%!"
      name compress_frames width height measured.frames_submitted
      measured.frames_published measured.frames_suppressed
      measured.source_bytes_submitted measured.payload_bytes_published
      ratio !encode_seconds)

let () =
  Printf.printf
    "scenario,compression,width,height,submitted,published,suppressed,source_bytes,payload_bytes,payload_ratio,publish_seconds\n";
  List.iter (fun (name, fill) ->
    run name fill false;
    run name fill true)
    ["static_ui", static_ui; "moving_sprite", moving_sprite; "noise", noisy]
