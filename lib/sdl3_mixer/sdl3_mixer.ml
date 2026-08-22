type error_kind =
  | Mixer_error
  | Wrong_domain
  | Destroyed
  | Parent_has_dependents
  | Invalid_argument
  | Incompatible_version
  | Not_initialized
  | Handles_still_open

type error = {
  operation : string;
  kind : error_kind;
  message : string;
}

let pp_error formatter error =
  Format.fprintf formatter "%s: %s" error.operation error.message

let error operation kind message = Error { operation; kind; message }

external raw_version : unit -> int = "caml_sdl3_mixer_version"
external raw_init : unit -> (unit, string) result = "caml_sdl3_mixer_init"
external raw_quit : unit -> unit = "caml_sdl3_mixer_quit"
external raw_create_device : unit -> (nativeint, string) result
  = "caml_sdl3_mixer_create_device"
external raw_create_memory : int -> int -> (nativeint, string) result
  = "caml_sdl3_mixer_create_memory"
external raw_destroy_mixer : nativeint -> unit = "caml_sdl3_mixer_destroy_mixer"
external raw_mixer_format : nativeint -> ((int * int), string) result
  = "caml_sdl3_mixer_format"
external raw_set_mixer_gain : nativeint -> float -> (unit, string) result
  = "caml_sdl3_mixer_set_gain"
external raw_mixer_gain : nativeint -> float = "caml_sdl3_mixer_gain"
external raw_stop_all : nativeint -> int -> (unit, string) result
  = "caml_sdl3_mixer_stop_all"
external raw_generate : nativeint -> bytes -> (int, string) result
  = "caml_sdl3_mixer_generate"

external raw_load_file : nativeint -> string -> bool -> (nativeint, string) result
  = "caml_sdl3_mixer_load_file"
external raw_load_bytes : nativeint -> bytes -> (nativeint, string) result
  = "caml_sdl3_mixer_load_bytes"
external raw_create_sine :
  nativeint -> int -> float -> int -> (nativeint, string) result
  = "caml_sdl3_mixer_create_sine"
external raw_audio_duration : nativeint -> int64
  = "caml_sdl3_mixer_audio_duration"
external raw_destroy_audio : nativeint -> unit = "caml_sdl3_mixer_destroy_audio"

external raw_create_track : nativeint -> (nativeint, string) result
  = "caml_sdl3_mixer_create_track"
external raw_destroy_track : nativeint -> unit = "caml_sdl3_mixer_destroy_track"
external raw_set_track_audio : nativeint -> nativeint -> (unit, string) result
  = "caml_sdl3_mixer_set_track_audio"
external raw_set_track_gain : nativeint -> float -> (unit, string) result
  = "caml_sdl3_mixer_set_track_gain"
external raw_track_gain : nativeint -> float = "caml_sdl3_mixer_track_gain"
external raw_set_track_loops : nativeint -> int -> (unit, string) result
  = "caml_sdl3_mixer_set_track_loops"
external raw_track_loops : nativeint -> int = "caml_sdl3_mixer_track_loops"
external raw_play_track : nativeint -> int -> int -> (unit, string) result
  = "caml_sdl3_mixer_play_track"
external raw_stop_track : nativeint -> int -> (unit, string) result
  = "caml_sdl3_mixer_stop_track"
external raw_pause_track : nativeint -> (unit, string) result
  = "caml_sdl3_mixer_pause_track"
external raw_resume_track : nativeint -> (unit, string) result
  = "caml_sdl3_mixer_resume_track"
external raw_track_playing : nativeint -> bool = "caml_sdl3_mixer_track_playing"
external raw_track_paused : nativeint -> bool = "caml_sdl3_mixer_track_paused"

module Version = struct
  type t = { major : int; minor : int; patch : int }

  let compiled =
    let value = Generated_provenance.header_version in
    { major = value.major; minor = value.minor; patch = value.patch }

  let of_number value = {
    major = value / 1_000_000;
    minor = (value / 1_000) mod 1_000;
    patch = value mod 1_000;
  }

  let number value =
    (value.major * 1_000_000) + (value.minor * 1_000) + value.patch

  let stable value = value.minor mod 2 = 0 && value.patch mod 2 = 0
  let linked () = of_number (raw_version ())
  let stable_headers = Generated_provenance.stable_headers
  let generator_version = Generated_provenance.generator_version
  let header_sha256 = Generated_provenance.header_sha256
  let function_count = Generated_provenance.function_count
  let safe_function_count = Generated_provenance.safe_function_count

  let string value =
    Printf.sprintf "%d.%d.%d" value.major value.minor value.patch

  let check ?(release = true) () =
    let linked = linked () in
    if release && not stable_headers then
      error "SDL3_mixer.Version.check" Incompatible_version
        ("compiled against prerelease SDL3_mixer headers " ^ string compiled)
    else if number linked < number compiled then
      error "SDL3_mixer.Version.check" Incompatible_version
        (Printf.sprintf "linked SDL3_mixer %s is older than compiled headers %s"
          (string linked) (string compiled))
    else if release && not (stable linked) then
      error "SDL3_mixer.Version.check" Incompatible_version
        ("linked SDL3_mixer is a development release: " ^ string linked)
    else Ok ()
end

type mixer_mode = Device | Memory

type mixer_handle = {
  raw : nativeint;
  generation : int;
  mode : mixer_mode;
  sample_rate : int;
  channels : int;
  tracks : int Atomic.t;
  audios : int Atomic.t;
  mutable destroyed : bool;
}

type audio_handle = {
  raw : nativeint;
  generation : int;
  mixer : mixer_handle;
  mutable destroyed : bool;
}

type track_handle = {
  raw : nativeint;
  mutable generation : int;
  mixer : mixer_handle;
  mutable destroyed : bool;
}

let next_generation = Atomic.make 1
let fresh_generation () = Atomic.fetch_and_add next_generation 1
let live_mixers = Atomic.make 0
let live_audios = Atomic.make 0
let live_tracks = Atomic.make 0

module Release_queue = struct
  let capacity = 1_024
  let mutex = Mutex.create ()
  let mixers = Queue.create ()
  let audios = Queue.create ()
  let tracks = Queue.create ()
  let dropped = Atomic.make 0

  let enqueue queue raw =
    Mutex.lock mutex;
    if Queue.length mixers + Queue.length audios + Queue.length tracks
        >= capacity then Atomic.incr dropped
    else Queue.add raw queue;
    Mutex.unlock mutex

  let mixer raw = enqueue mixers raw
  let audio raw = enqueue audios raw
  let track raw = enqueue tracks raw

  let drain () =
    Mutex.lock mutex;
    let pending_tracks = Queue.create () in
    let pending_audios = Queue.create () in
    let pending_mixers = Queue.create () in
    Queue.transfer tracks pending_tracks;
    Queue.transfer audios pending_audios;
    Queue.transfer mixers pending_mixers;
    Mutex.unlock mutex;
    Queue.iter raw_destroy_track pending_tracks;
    Queue.iter raw_destroy_audio pending_audios;
    Queue.iter raw_destroy_mixer pending_mixers
end

let dropped_release_tokens () = Atomic.get Release_queue.dropped

let require_main operation =
  if not (Sdl3.Thread.is_initial_domain ())
      || not (Sdl3.Thread.is_sdl_main_thread ()) then
    error operation Wrong_domain
      "SDL3_mixer operation must run on the initial OCaml domain and SDL main thread"
  else Ok ()

let drain_release_queue () =
  match require_main "SDL3_mixer.drain_release_queue" with
  | Error _ as failure -> failure
  | Ok () -> Release_queue.drain (); Ok ()

let on_main operation callback =
  match require_main operation with
  | Error _ as failure -> failure
  | Ok () -> Release_queue.drain (); callback ()

let mixer_result operation = function
  | Ok value -> Ok value
  | Error message -> error operation Mixer_error message

let init_count = ref 0

module Init = struct
  let init () = on_main "SDL3_mixer.Init.init" (fun () ->
    match Version.check () with
    | Error _ as failure -> failure
    | Ok () ->
        (match mixer_result "SDL3_mixer.Init.init" (raw_init ()) with
         | Error _ as failure -> failure
         | Ok () -> incr init_count; Ok ()))

  let initialized () = !init_count > 0

  let quit () = on_main "SDL3_mixer.Init.quit" (fun () ->
    let handles = Atomic.get live_mixers + Atomic.get live_audios
      + Atomic.get live_tracks in
    if handles <> 0 then
      error "SDL3_mixer.Init.quit" Handles_still_open
        (Printf.sprintf "%d mixer/audio/track handle(s) are still open" handles)
    else if !init_count = 0 then Ok ()
    else begin
      decr init_count;
      raw_quit ();
      Ok ()
    end)
end

let require_initialized operation =
  if Init.initialized () then Ok ()
  else error operation Not_initialized "SDL3_mixer is not initialized"

let contains_nul value =
  try ignore (String.index value '\x00'); true with Not_found -> false

module Mixer = struct
  type t = mixer_handle
  type mode = mixer_mode = Device | Memory
  type format = { sample_rate : int; channels : int }
  type generated = { mixed_bytes : int; pcm_f32 : bytes }

  let generation (value : t) = value.generation
  let destroyed (value : t) = value.destroyed
  let mode (value : t) = value.mode

  let owned raw mode sample_rate channels =
    Atomic.incr live_mixers;
    let value : mixer_handle = {
      raw; generation = fresh_generation (); mode; sample_rate; channels;
      tracks = Atomic.make 0; audios = Atomic.make 0; destroyed = false;
    } in
    Gc.finalise (fun (value : mixer_handle) ->
      if not value.destroyed then begin
        value.destroyed <- true;
        Atomic.decr live_mixers;
        Release_queue.mixer value.raw
      end) value;
    value

  let live operation (value : t) callback = on_main operation (fun () ->
    if value.destroyed then error operation Destroyed "mixer is destroyed"
    else
      match require_initialized operation with
      | Error _ as failure -> failure
      | Ok () -> callback value.raw)

  let finish_create operation mode = function
    | Error message -> error operation Mixer_error message
    | Ok raw ->
        (match raw_mixer_format raw with
         | Ok (sample_rate, channels) ->
             Ok (owned raw mode sample_rate channels)
         | Error message ->
             raw_destroy_mixer raw;
             error operation Mixer_error message)

  let create_device () = on_main "SDL3_mixer.Mixer.create_device" (fun () ->
    match require_initialized "SDL3_mixer.Mixer.create_device" with
    | Error _ as failure -> failure
    | Ok () -> finish_create "SDL3_mixer.Mixer.create_device" Device
        (raw_create_device ()))

  let create_memory ~sample_rate ~channels =
    let operation = "SDL3_mixer.Mixer.create_memory" in
    if sample_rate < 8_000 || sample_rate > 384_000 then
      error operation Invalid_argument "sample rate must be in 8000..384000"
    else if channels <= 0 || channels > 8 then
      error operation Invalid_argument "channel count must be in 1..8"
    else on_main operation (fun () ->
      match require_initialized operation with
      | Error _ as failure -> failure
      | Ok () -> finish_create operation Memory
          (raw_create_memory sample_rate channels))

  let format (value : t) = live "SDL3_mixer.Mixer.format" value (fun _ ->
    Ok { sample_rate = value.sample_rate; channels = value.channels })

  let valid_gain gain = Float.is_finite gain && gain >= 0.

  let set_gain (value : t) gain =
    let operation = "SDL3_mixer.Mixer.set_gain" in
    if not (valid_gain gain) then
      error operation Invalid_argument "mixer gain must be finite and non-negative"
    else live operation value (fun raw ->
      mixer_result operation (raw_set_mixer_gain raw gain))

  let gain (value : t) = live "SDL3_mixer.Mixer.gain" value (fun raw ->
    Ok (raw_mixer_gain raw))

  let stop_all (value : t) ?(fade_ms = 0) () =
    let operation = "SDL3_mixer.Mixer.stop_all" in
    if fade_ms < 0 then
      error operation Invalid_argument "fade duration must be non-negative"
    else live operation value (fun raw ->
      mixer_result operation (raw_stop_all raw fade_ms))

  let generate (value : t) ~frames =
    let operation = "SDL3_mixer.Mixer.generate" in
    if value.mode <> Memory then
      error operation Invalid_argument "audio can only be generated by a memory mixer"
    else if frames <= 0 then
      error operation Invalid_argument "frame count must be positive"
    else if value.channels > max_int / 4
        || frames > max_int / (value.channels * 4) then
      error operation Invalid_argument "generated PCM byte count overflows"
    else live operation value (fun raw ->
      let pcm_f32 = Bytes.create (frames * value.channels * 4) in
      match mixer_result operation (raw_generate raw pcm_f32) with
      | Error _ as failure -> failure
      | Ok mixed_bytes -> Ok { mixed_bytes; pcm_f32 })

  let destroy (value : t) = on_main "SDL3_mixer.Mixer.destroy" (fun () ->
    if value.destroyed then Ok ()
    else
      let tracks = Atomic.get value.tracks and audios = Atomic.get value.audios in
      if tracks <> 0 || audios <> 0 then
        error "SDL3_mixer.Mixer.destroy" Parent_has_dependents
          (Printf.sprintf "mixer still owns %d track(s) and %d audio handle(s)"
            tracks audios)
      else begin
        value.destroyed <- true;
        Atomic.decr live_mixers;
        raw_destroy_mixer value.raw;
        Ok ()
      end)
end

module Audio = struct
  type t = audio_handle

  let generation (value : t) = value.generation
  let destroyed (value : t) = value.destroyed

  let owned mixer raw =
    Atomic.incr live_audios;
    Atomic.incr mixer.audios;
    let value : audio_handle = {
      raw; generation = fresh_generation (); mixer; destroyed = false;
    } in
    Gc.finalise (fun (value : audio_handle) ->
      if not value.destroyed then begin
        value.destroyed <- true;
        Atomic.decr live_audios;
        Atomic.decr value.mixer.audios;
        Release_queue.audio value.raw
      end) value;
    value

  let with_mixer operation mixer callback =
    Mixer.live operation mixer (fun raw ->
      match callback raw with
      | Ok audio -> Ok (owned mixer audio)
      | Error message -> error operation Mixer_error message)

  let live operation (value : t) callback = on_main operation (fun () ->
    if value.destroyed then error operation Destroyed "audio handle is destroyed"
    else if value.mixer.destroyed then
      error operation Destroyed "audio handle's source mixer is destroyed"
    else
      match require_initialized operation with
      | Error _ as failure -> failure
      | Ok () -> callback value.raw)

  let load_file mixer ~path ?(predecode = true) () =
    let operation = "SDL3_mixer.Audio.load_file" in
    if path = "" || contains_nul path then
      error operation Invalid_argument "audio path must be non-empty and NUL-free"
    else with_mixer operation mixer (fun raw ->
      raw_load_file raw path predecode)

  let load_bytes mixer bytes =
    let operation = "SDL3_mixer.Audio.load_bytes" in
    if Bytes.length bytes = 0 then
      error operation Invalid_argument "encoded audio buffer must be non-empty"
    else with_mixer operation mixer (fun raw -> raw_load_bytes raw bytes)

  let create_sine mixer ~frequency ~amplitude ~duration_ms =
    let operation = "SDL3_mixer.Audio.create_sine" in
    if frequency <= 0 || frequency > 200_000 then
      error operation Invalid_argument "frequency must be in 1..200000 Hz"
    else if not (Float.is_finite amplitude) || amplitude < 0. || amplitude > 1. then
      error operation Invalid_argument "amplitude must be finite and in 0..1"
    else if duration_ms <= 0 then
      error operation Invalid_argument "duration must be positive"
    else with_mixer operation mixer (fun raw ->
      raw_create_sine raw frequency amplitude duration_ms)

  let duration_frames (value : t) = live "SDL3_mixer.Audio.duration_frames" value
      (fun raw -> Ok (raw_audio_duration raw))

  let destroy (value : t) = on_main "SDL3_mixer.Audio.destroy" (fun () ->
    if value.destroyed then Ok ()
    else begin
      value.destroyed <- true;
      Atomic.decr live_audios;
      Atomic.decr value.mixer.audios;
      raw_destroy_audio value.raw;
      Ok ()
    end)
end

module Track = struct
  type t = track_handle

  let generation (value : t) = value.generation
  let destroyed (value : t) = value.destroyed

  let bump (value : t) = value.generation <- fresh_generation ()

  let owned mixer raw =
    Atomic.incr live_tracks;
    Atomic.incr mixer.tracks;
    let value : track_handle = {
      raw; generation = fresh_generation (); mixer; destroyed = false;
    } in
    Gc.finalise (fun (value : track_handle) ->
      if not value.destroyed then begin
        value.destroyed <- true;
        Atomic.decr live_tracks;
        Atomic.decr value.mixer.tracks;
        Release_queue.track value.raw
      end) value;
    value

  let live operation (value : t) callback = on_main operation (fun () ->
    if value.destroyed then error operation Destroyed "track is destroyed"
    else if value.mixer.destroyed then
      error operation Destroyed "track's mixer is destroyed"
    else
      match require_initialized operation with
      | Error _ as failure -> failure
      | Ok () -> callback value.raw)

  let mutate operation value call = live operation value (fun raw ->
    match mixer_result operation (call raw) with
    | Error _ as failure -> failure
    | Ok () -> bump value; Ok ())

  let create mixer = Mixer.live "SDL3_mixer.Track.create" mixer (fun raw ->
    match raw_create_track raw with
    | Ok track -> Ok (owned mixer track)
    | Error message -> error "SDL3_mixer.Track.create" Mixer_error message)

  let set_audio (value : t) (audio : Audio.t) =
    let operation = "SDL3_mixer.Track.set_audio" in
    if audio.destroyed then error operation Destroyed "audio handle is destroyed"
    else mutate operation value (fun raw -> raw_set_track_audio raw audio.raw)

  let set_gain (value : t) gain =
    let operation = "SDL3_mixer.Track.set_gain" in
    if not (Float.is_finite gain) || gain < 0. then
      error operation Invalid_argument "track gain must be finite and non-negative"
    else mutate operation value (fun raw -> raw_set_track_gain raw gain)

  let gain (value : t) = live "SDL3_mixer.Track.gain" value (fun raw ->
    Ok (raw_track_gain raw))

  let valid_loops loops = loops >= -1

  let set_loops (value : t) loops =
    let operation = "SDL3_mixer.Track.set_loops" in
    if not (valid_loops loops) then
      error operation Invalid_argument "loop count must be -1 or non-negative"
    else mutate operation value (fun raw -> raw_set_track_loops raw loops)

  let loops (value : t) = live "SDL3_mixer.Track.loops" value (fun raw ->
    Ok (raw_track_loops raw))

  let play (value : t) ?(loops = 0) ?(fade_in_ms = 0) () =
    let operation = "SDL3_mixer.Track.play" in
    if not (valid_loops loops) then
      error operation Invalid_argument "loop count must be -1 or non-negative"
    else if fade_in_ms < 0 then
      error operation Invalid_argument "fade duration must be non-negative"
    else mutate operation value (fun raw ->
      raw_play_track raw loops fade_in_ms)

  let stop (value : t) ?(fade_out_ms = 0) () =
    let operation = "SDL3_mixer.Track.stop" in
    if fade_out_ms < 0 then
      error operation Invalid_argument "fade duration must be non-negative"
    else mutate operation value (fun raw -> raw_stop_track raw fade_out_ms)

  let pause (value : t) = mutate "SDL3_mixer.Track.pause" value raw_pause_track
  let resume (value : t) = mutate "SDL3_mixer.Track.resume" value raw_resume_track

  let playing (value : t) = live "SDL3_mixer.Track.playing" value (fun raw ->
    Ok (raw_track_playing raw))

  let paused (value : t) = live "SDL3_mixer.Track.paused" value (fun raw ->
    Ok (raw_track_paused raw))

  let destroy (value : t) = on_main "SDL3_mixer.Track.destroy" (fun () ->
    if value.destroyed then Ok ()
    else begin
      value.destroyed <- true;
      Atomic.decr live_tracks;
      Atomic.decr value.mixer.tracks;
      raw_destroy_track value.raw;
      Ok ()
    end)
end
