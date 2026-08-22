type error_kind =
  | Ttf_error
  | Wrong_domain
  | Destroyed
  | Invalid_argument
  | Incompatible_version
  | Not_initialized
  | Fonts_still_open
  | Surface_error of Sdl3.error

type error = {
  operation : string;
  kind : error_kind;
  message : string;
}

let pp_error formatter error =
  Format.fprintf formatter "%s: %s" error.operation error.message

let error operation kind message = Error { operation; kind; message }

type decoded = {
  width : int;
  height : int;
  pixels : bytes;
}

external raw_version : unit -> int = "caml_sdl3_ttf_version"
external raw_init : unit -> (unit, string) result = "caml_sdl3_ttf_init"
external raw_quit : unit -> unit = "caml_sdl3_ttf_quit"
external raw_was_init : unit -> int = "caml_sdl3_ttf_was_init"
external raw_open_font : string -> float -> (nativeint, string) result
  = "caml_sdl3_ttf_open_font"
external raw_close_font : nativeint -> unit = "caml_sdl3_ttf_close_font"
external raw_font_metrics : nativeint -> int * int * int * int
  = "caml_sdl3_ttf_font_metrics"
external raw_font_family_name : nativeint -> string option
  = "caml_sdl3_ttf_font_family_name"
external raw_font_style_name : nativeint -> string option
  = "caml_sdl3_ttf_font_style_name"
external raw_set_font_size : nativeint -> float -> (unit, string) result
  = "caml_sdl3_ttf_set_font_size"
external raw_size_text : nativeint -> string -> ((int * int), string) result
  = "caml_sdl3_ttf_size_text"
external raw_render_blended :
  nativeint -> string -> int -> int -> int -> int -> (decoded, string) result
  = "caml_sdl3_ttf_render_blended_bytecode" "caml_sdl3_ttf_render_blended"

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
      error "SDL3_ttf.Version.check" Incompatible_version
        ("compiled against prerelease SDL3_ttf headers " ^ string compiled)
    else if number linked < number compiled then
      error "SDL3_ttf.Version.check" Incompatible_version
        (Printf.sprintf "linked SDL3_ttf %s is older than compiled headers %s"
          (string linked) (string compiled))
    else if release && not (stable linked) then
      error "SDL3_ttf.Version.check" Incompatible_version
        ("linked SDL3_ttf is a development release: " ^ string linked)
    else Ok ()
end

module Release_queue = struct
  let capacity = 1_024
  let mutex = Mutex.create ()
  let fonts = Queue.create ()
  let dropped = Atomic.make 0

  let enqueue raw =
    Mutex.lock mutex;
    if Queue.length fonts >= capacity then Atomic.incr dropped
    else Queue.add raw fonts;
    Mutex.unlock mutex

  let drain () =
    Mutex.lock mutex;
    let pending = Queue.create () in
    Queue.transfer fonts pending;
    Mutex.unlock mutex;
    Queue.iter raw_close_font pending
end

let dropped_release_tokens () = Atomic.get Release_queue.dropped

let require_main operation =
  if not (Sdl3.Thread.is_initial_domain ())
      || not (Sdl3.Thread.is_sdl_main_thread ()) then
    error operation Wrong_domain
      "SDL3_ttf operation must run on the initial OCaml domain and SDL main thread"
  else Ok ()

let drain_release_queue () =
  match require_main "SDL3_ttf.drain_release_queue" with
  | Error _ as failure -> failure
  | Ok () -> Release_queue.drain (); Ok ()

let on_main operation callback =
  match require_main operation with
  | Error _ as failure -> failure
  | Ok () -> Release_queue.drain (); callback ()

let ttf_result operation = function
  | Ok value -> Ok value
  | Error message -> error operation Ttf_error message

let init_count = ref 0
let live_fonts = Atomic.make 0

module Init = struct
  let init () = on_main "SDL3_ttf.Init.init" (fun () ->
    match Version.check () with
    | Error _ as failure -> failure
    | Ok () ->
        (match ttf_result "SDL3_ttf.Init.init" (raw_init ()) with
         | Error _ as failure -> failure
         | Ok () -> incr init_count; Ok ()))

  let initialized () = on_main "SDL3_ttf.Init.initialized" (fun () ->
    Ok (raw_was_init () > 0))

  let quit () = on_main "SDL3_ttf.Init.quit" (fun () ->
    let open_count = Atomic.get live_fonts in
    if open_count <> 0 then
      error "SDL3_ttf.Init.quit" Fonts_still_open
        (Printf.sprintf "%d font handle(s) are still open" open_count)
    else if !init_count = 0 then Ok ()
    else begin
      decr init_count;
      raw_quit ();
      Ok ()
    end)
end

module Font = struct
  type t = {
    raw : nativeint;
    mutable generation : int;
    mutable destroyed : bool;
  }

  type metrics = {
    height : int;
    ascent : int;
    descent : int;
    line_skip : int;
  }

  let next_generation = Atomic.make 1
  let generation value = value.generation
  let destroyed value = value.destroyed

  let contains_nul value =
    try ignore (String.index value '\x00'); true with Not_found -> false

  let valid_size value = Float.is_finite value && value > 0.

  let owned raw =
    Atomic.incr live_fonts;
    let value = {
      raw;
      generation = Atomic.fetch_and_add next_generation 1;
      destroyed = false;
    } in
    Gc.finalise (fun value ->
      if not value.destroyed then begin
        value.destroyed <- true;
        Atomic.decr live_fonts;
        Release_queue.enqueue value.raw
      end) value;
    value

  let live operation value callback = on_main operation (fun () ->
    if value.destroyed then error operation Destroyed "font is destroyed"
    else
      match Init.initialized () with
      | Error _ as failure -> failure
      | Ok false -> error operation Not_initialized "SDL3_ttf is not initialized"
      | Ok true -> callback value.raw)

  let open_file ~path ~size =
    let operation = "SDL3_ttf.Font.open_file" in
    if path = "" || contains_nul path then
      error operation Invalid_argument "font path must be non-empty and NUL-free"
    else if not (valid_size size) then
      error operation Invalid_argument "font size must be finite and positive"
    else on_main operation (fun () ->
      match Init.initialized () with
      | Error _ as failure -> failure
      | Ok false -> error operation Not_initialized "SDL3_ttf is not initialized"
      | Ok true ->
          (match ttf_result operation (raw_open_font path size) with
           | Error _ as failure -> failure
           | Ok raw -> Ok (owned raw)))

  let metrics value = live "SDL3_ttf.Font.metrics" value (fun raw ->
    let height, ascent, descent, line_skip = raw_font_metrics raw in
    Ok { height; ascent; descent; line_skip })

  let family_name value = live "SDL3_ttf.Font.family_name" value (fun raw ->
    Ok (raw_font_family_name raw))

  let style_name value = live "SDL3_ttf.Font.style_name" value (fun raw ->
    Ok (raw_font_style_name raw))

  let set_size value size =
    let operation = "SDL3_ttf.Font.set_size" in
    if not (valid_size size) then
      error operation Invalid_argument "font size must be finite and positive"
    else live operation value (fun raw ->
      match ttf_result operation (raw_set_font_size raw size) with
      | Error _ as failure -> failure
      | Ok () ->
          value.generation <- Atomic.fetch_and_add next_generation 1;
          Ok ())

  let size_text value text =
    let operation = "SDL3_ttf.Font.size_text" in
    if contains_nul text then
      error operation Invalid_argument "text contains a NUL byte"
    else if text = "" then live operation value (fun _ -> Ok (0, 0))
    else live operation value (fun raw ->
      ttf_result operation (raw_size_text raw text))

  let valid_channel value = value >= 0 && value <= 255

  let render_blended value ~color:(red, green, blue, alpha) text =
    let operation = "SDL3_ttf.Font.render_blended" in
    if not (valid_channel red && valid_channel green && valid_channel blue
        && valid_channel alpha) then
      error operation Invalid_argument "RGBA channels must be in 0..255"
    else if contains_nul text then
      error operation Invalid_argument "text contains a NUL byte"
    else if text = "" then live operation value (fun _ -> Ok None)
    else live operation value (fun raw ->
      match ttf_result operation
          (raw_render_blended raw text red green blue alpha) with
      | Error _ as failure -> failure
      | Ok decoded ->
          (match Sdl3.Surface.of_rgba ~width:decoded.width
              ~height:decoded.height decoded.pixels with
           | Ok surface -> Ok (Some surface)
           | Error surface_error ->
               error operation (Surface_error surface_error)
                 (Format.asprintf "%a" Sdl3.pp_error surface_error)))

  let destroy value = on_main "SDL3_ttf.Font.destroy" (fun () ->
    if value.destroyed then Ok ()
    else begin
      value.destroyed <- true;
      Atomic.decr live_fonts;
      raw_close_font value.raw;
      Ok ()
    end)
end
