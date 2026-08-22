module Mixer3 = Sdl3_mixer

let fail format = Printf.ksprintf failwith format

let sdl = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" Sdl3.pp_error error)

let mixer = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" Mixer3.pp_error error)

type measurement =
  { name : string
  ; iterations : int
  ; ffi_calls : int
  ; wall_seconds : float
  ; allocated_bytes : float
  ; minor_bytes : float
  ; promoted_bytes : float
  ; major_bytes : float
  ; major_collections : int
  ; ending_heap_bytes : int
  ; peak_heap_bytes : int
  }

let gc_bytes words = words *. float_of_int (Sys.word_size / 8)

let measure ~name ~iterations ~calls_per_iteration operation =
  Gc.full_major ();
  let before = Gc.quick_stat () in
  let allocated_before = Gc.allocated_bytes () in
  let started = Unix.gettimeofday () in
  for index = 0 to iterations - 1 do
    operation index
  done;
  let wall_seconds = Unix.gettimeofday () -. started in
  let allocated_bytes = Gc.allocated_bytes () -. allocated_before in
  let after = Gc.quick_stat () in
  { name
  ; iterations
  ; ffi_calls = iterations * calls_per_iteration
  ; wall_seconds
  ; allocated_bytes
  ; minor_bytes = gc_bytes (after.minor_words -. before.minor_words)
  ; promoted_bytes = gc_bytes (after.promoted_words -. before.promoted_words)
  ; major_bytes = gc_bytes (after.major_words -. before.major_words)
  ; major_collections = after.major_collections - before.major_collections
  ; ending_heap_bytes = after.heap_words * (Sys.word_size / 8)
  ; peak_heap_bytes = after.top_heap_words * (Sys.word_size / 8)
  }

let measurement_json value =
  `Assoc
    [ "name", `String value.name
    ; "iterations", `Int value.iterations
    ; "ffi_calls", `Int value.ffi_calls
    ; "wall_seconds", `Float value.wall_seconds
    ; "nanoseconds_per_iteration",
      `Float (value.wall_seconds *. 1e9 /. float_of_int value.iterations)
    ; "allocated_bytes", `Float value.allocated_bytes
    ; "allocated_bytes_per_iteration",
      `Float (value.allocated_bytes /. float_of_int value.iterations)
    ; "minor_bytes", `Float value.minor_bytes
    ; "promoted_bytes", `Float value.promoted_bytes
    ; "major_bytes", `Float value.major_bytes
    ; "major_collections", `Int value.major_collections
    ; "ending_heap_bytes", `Int value.ending_heap_bytes
    ; "peak_heap_bytes", `Int value.peak_heap_bytes
    ]

type arguments =
  { iterations : int
  ; window_iterations : int
  ; audio_iterations : int
  }

let parse_arguments () =
  let iterations = ref 100_000 in
  let window_iterations = ref 100_000 in
  let audio_iterations = ref 100_000 in
  let index = ref 1 in
  let usage () =
    fail
      "usage: %s [--iterations <n>] [--window-iterations <n>] \
       [--audio-iterations <n>]"
      Sys.argv.(0)
  in
  let positive name =
    if !index + 1 >= Array.length Sys.argv then usage ();
    let raw = Sys.argv.(!index + 1) in
    index := !index + 2;
    match int_of_string_opt raw with
    | Some value when value > 0 -> value
    | Some _ | None -> fail "%s must be a positive integer, got %S" name raw
  in
  while !index < Array.length Sys.argv do
    match Sys.argv.(!index) with
    | "--iterations" -> iterations := positive "iterations"
    | "--window-iterations" ->
        window_iterations := positive "window iterations"
    | "--audio-iterations" -> audio_iterations := positive "audio iterations"
    | _ -> usage ()
  done;
  { iterations = !iterations
  ; window_iterations = !window_iterations
  ; audio_iterations = !audio_iterations
  }

let () =
  let arguments = parse_arguments () in
  sdl (Sdl3.Init.init [ Sdl3.Init.Video; Sdl3.Init.Events ]);
  mixer (Mixer3.Init.init ());
  let version =
    measure ~name:"version_and_init_query" ~iterations:arguments.iterations
      ~calls_per_iteration:2 (fun _ ->
        ignore (Sdl3.Version.linked ());
        ignore (Sdl3.Init.initialized [ Sdl3.Init.Events ]))
  in
  let events =
    measure ~name:"event_poll" ~iterations:arguments.iterations
      ~calls_per_iteration:1 (fun _ -> ignore (sdl (Sdl3.Event.poll ())))
  in
  let source = Bytes.of_string "\x01\x02\x03\xff" in
  let surfaces =
    measure ~name:"surface_create_copy_destroy"
      ~iterations:arguments.iterations ~calls_per_iteration:3 (fun _ ->
        let surface =
          sdl (Sdl3.Surface.of_rgba ~width:1 ~height:1 source)
        in
        ignore (sdl (Sdl3.Surface.copy_rgba surface));
        sdl (Sdl3.Surface.destroy surface))
  in
  let windows =
    measure ~name:"hidden_window_create_query_destroy"
      ~iterations:arguments.window_iterations ~calls_per_iteration:3 (fun index ->
        let window =
          sdl
            (Sdl3.Window.create
               ~title:(Printf.sprintf "Prismel SDL3 bench %d" index)
               ~width:16 ~height:16 ~flags:[ Sdl3.Window.Hidden ] ())
        in
        ignore (sdl (Sdl3.Window.size_in_pixels window));
        sdl (Sdl3.Window.destroy window))
  in
  let audio =
    measure ~name:"memory_audio_track_cycle"
      ~iterations:arguments.audio_iterations ~calls_per_iteration:11 (fun _ ->
        let mixer_value =
          mixer (Mixer3.Mixer.create_memory ~sample_rate:8_000 ~channels:1)
        in
        let audio_value =
          mixer
            (Mixer3.Audio.create_sine mixer_value ~frequency:440 ~amplitude:0.1
               ~duration_ms:1)
        in
        let track = mixer (Mixer3.Track.create mixer_value) in
        mixer (Mixer3.Track.set_audio track audio_value);
        mixer (Mixer3.Track.play track ());
        ignore (mixer (Mixer3.Mixer.generate mixer_value ~frames:8));
        ignore (mixer (Mixer3.Track.playing track));
        mixer (Mixer3.Track.stop track ());
        mixer (Mixer3.Track.destroy track);
        mixer (Mixer3.Audio.destroy audio_value);
        mixer (Mixer3.Mixer.destroy mixer_value))
  in
  mixer (Mixer3.Init.quit ());
  sdl (Sdl3.Init.quit ());
  sdl (Sdl3.drain_release_queue ());
  let linked = Sdl3.Version.linked () in
  let mixer_linked = Mixer3.Version.linked () in
  let output =
    `Assoc
      [ "schema", `Int 1
      ; "benchmark", `String "sdl3_ffi"
      ; "ocaml_version", `String Sys.ocaml_version
      ; "word_size", `Int Sys.word_size
      ; ( "sdl3_version"
        , `String
            (Printf.sprintf "%d.%d.%d" linked.major linked.minor linked.patch) )
      ; ( "sdl3_mixer_version"
        , `String
            (Printf.sprintf "%d.%d.%d" mixer_linked.major mixer_linked.minor
               mixer_linked.patch) )
      ; "dropped_release_tokens", `Int (Sdl3.dropped_release_tokens ())
      ; ( "measurements"
        , `List
            (List.map measurement_json
               [ version; events; surfaces; windows; audio ]) )
      ]
  in
  print_endline (Yojson.Safe.to_string output)
