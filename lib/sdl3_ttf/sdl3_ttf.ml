type error_kind =
  | Ttf_error
  | Wrong_domain
  | Destroyed
  | Invalid_argument
  | Incompatible_version
  | Not_initialized
  | Font_not_found
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
external raw_set_font_size_dpi :
  nativeint -> float -> int -> int -> (unit, string) result
  = "caml_sdl3_ttf_set_font_size_dpi"
external raw_font_dpi : nativeint -> ((int * int), string) result
  = "caml_sdl3_ttf_font_dpi"
external raw_set_font_style : nativeint -> int -> unit
  = "caml_sdl3_ttf_set_font_style"
external raw_get_font_style : nativeint -> int = "caml_sdl3_ttf_get_font_style"
external raw_set_font_outline : nativeint -> int -> (unit, string) result
  = "caml_sdl3_ttf_set_font_outline"
external raw_get_font_outline : nativeint -> int = "caml_sdl3_ttf_get_font_outline"
external raw_set_font_hinting : nativeint -> int -> unit
  = "caml_sdl3_ttf_set_font_hinting"
external raw_get_font_hinting : nativeint -> int
  = "caml_sdl3_ttf_get_font_hinting"
external raw_set_font_kerning : nativeint -> bool -> unit
  = "caml_sdl3_ttf_set_font_kerning"
external raw_get_font_kerning : nativeint -> bool
  = "caml_sdl3_ttf_get_font_kerning"
external raw_font_has_glyph : nativeint -> int -> bool
  = "caml_sdl3_ttf_font_has_glyph"
external raw_glyph_metrics : nativeint -> int ->
  ((int * int * int * int * int), string) result
  = "caml_sdl3_ttf_glyph_metrics"
external raw_size_text : nativeint -> string -> ((int * int), string) result
  = "caml_sdl3_ttf_size_text"
external raw_size_text_wrapped : nativeint -> string -> int ->
  ((int * int), string) result = "caml_sdl3_ttf_size_text_wrapped"
external raw_render_blended :
  nativeint -> string -> int -> int -> int -> int -> (decoded, string) result
  = "caml_sdl3_ttf_render_blended_bytecode" "caml_sdl3_ttf_render_blended"
external raw_render_blended_wrapped :
  nativeint -> string -> int -> int -> int -> int -> int ->
  (decoded, string) result
  = "caml_sdl3_ttf_render_blended_wrapped_bytecode"
    "caml_sdl3_ttf_render_blended_wrapped"

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

  type style = Normal | Bold | Italic | Underline | Strikethrough
  type hinting = Normal_hinting | Light_hinting | Mono_hinting
    | None_hinting | Light_subpixel_hinting
  type glyph_metrics = {
    min_x : int; max_x : int; min_y : int; max_y : int; advance : int;
  }

  let next_generation = Atomic.make 1
  let generation value = value.generation
  let destroyed value = value.destroyed

  let contains_nul value =
    try ignore (String.index value '\x00'); true with Not_found -> false

  let valid_size value = Float.is_finite value && value > 0.

  let valid_utf8 value =
    let length = String.length value in
    let continuation index =
      index < length && let byte = Char.code value.[index] in
      byte land 0xc0 = 0x80
    in
    let rec loop index =
      if index = length then true
      else
        let byte = Char.code value.[index] in
        if byte < 0x80 then loop (index + 1)
        else if byte >= 0xc2 && byte <= 0xdf && continuation (index + 1) then
          loop (index + 2)
        else if byte >= 0xe0 && byte <= 0xef && continuation (index + 1)
            && continuation (index + 2) then
          let second = Char.code value.[index + 1] in
          if (byte = 0xe0 && second < 0xa0) || (byte = 0xed && second >= 0xa0)
          then false else loop (index + 3)
        else if byte >= 0xf0 && byte <= 0xf4 && continuation (index + 1)
            && continuation (index + 2) && continuation (index + 3) then
          let second = Char.code value.[index + 1] in
          if (byte = 0xf0 && second < 0x90) || (byte = 0xf4 && second >= 0x90)
          then false else loop (index + 4)
        else false
    in
    loop 0

  let validate_text operation text =
    if contains_nul text then
      error operation Invalid_argument "text contains a NUL byte"
    else if not (valid_utf8 text) then
      error operation Invalid_argument "text is not valid UTF-8"
    else Ok ()

  let system_font_candidates () =
    let fixed =
      [ "/System/Library/Fonts/SFNS.ttf"
      ; "/System/Library/Fonts/SFCompact.ttf"
      ; "/System/Library/Fonts/HelveticaNeue.ttc"
      ; "/System/Library/Fonts/Helvetica.ttc"
      ; "/System/Library/Fonts/LucidaGrande.ttc"
      ; "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"
      ; "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
      ; "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"
      ; "/usr/share/fonts/TTF/DejaVuSans.ttf"
      ]
    in
    match Sys.getenv_opt "WINDIR" with
    | None -> fixed
    | Some root ->
        Filename.concat root "Fonts/SegUIVar.ttf"
        :: Filename.concat root "Fonts/segoeui.ttf"
        :: Filename.concat root "Fonts/arial.ttf"
        :: fixed

  let system_path () =
    match Sys.getenv_opt "PRISMEL_UI_FONT" with
    | Some path when path <> "" ->
        if Sys.file_exists path then Ok path
        else error "SDL3_ttf.Font.system_path" Font_not_found
          ("PRISMEL_UI_FONT does not name a readable font: " ^ path)
    | _ ->
        (match List.find_opt Sys.file_exists (system_font_candidates ()) with
         | Some path -> Ok path
         | None -> error "SDL3_ttf.Font.system_path" Font_not_found
             "no supported installed system UI font was found")

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

  let mutate value operation callback = live operation value (fun raw ->
    match callback raw with
    | Error _ as failure -> failure
    | Ok () ->
        value.generation <- Atomic.fetch_and_add next_generation 1;
        Ok ())

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

  let set_size_dpi value ~size ~horizontal ~vertical =
    let operation = "SDL3_ttf.Font.set_size_dpi" in
    if not (valid_size size) then
      error operation Invalid_argument "font size must be finite and positive"
    else if horizontal <= 0 || vertical <= 0 then
      error operation Invalid_argument "font DPI must be positive"
    else live operation value (fun raw ->
      match ttf_result operation
          (raw_set_font_size_dpi raw size horizontal vertical) with
      | Error _ as failure -> failure
      | Ok () ->
          value.generation <- Atomic.fetch_and_add next_generation 1;
          Ok ())

  let dpi value = live "SDL3_ttf.Font.dpi" value (fun raw ->
    ttf_result "SDL3_ttf.Font.dpi" (raw_font_dpi raw))

  let style_bit = function
    | Normal -> 0 | Bold -> 1 | Italic -> 2 | Underline -> 4
    | Strikethrough -> 8

  let set_style value styles =
    let operation = "SDL3_ttf.Font.set_style" in
    let bits = List.fold_left (fun bits style -> bits lor style_bit style) 0 styles in
    mutate value operation (fun raw -> raw_set_font_style raw bits; Ok ())

  let style value = live "SDL3_ttf.Font.style" value (fun raw ->
    let bits = raw_get_font_style raw in
    let styles =
      [ 1, Bold; 2, Italic; 4, Underline; 8, Strikethrough ]
      |> List.filter_map (fun (bit, style) ->
        if bits land bit <> 0 then Some style else None)
    in
    Ok (if styles = [] then [Normal] else styles))

  let set_outline value outline =
    let operation = "SDL3_ttf.Font.set_outline" in
    if outline < 0 then error operation Invalid_argument "outline must be non-negative"
    else mutate value operation (fun raw ->
      ttf_result operation (raw_set_font_outline raw outline))

  let outline value = live "SDL3_ttf.Font.outline" value (fun raw ->
    Ok (raw_get_font_outline raw))

  let hinting_code = function
    | Normal_hinting -> 0 | Light_hinting -> 1 | Mono_hinting -> 2
    | None_hinting -> 3 | Light_subpixel_hinting -> 4

  let hinting_of_code = function
    | 0 -> Ok Normal_hinting | 1 -> Ok Light_hinting | 2 -> Ok Mono_hinting
    | 3 -> Ok None_hinting | 4 -> Ok Light_subpixel_hinting
    | _ -> error "SDL3_ttf.Font.hinting" Ttf_error "SDL3_ttf returned invalid hinting"

  let set_hinting value hinting =
    let operation = "SDL3_ttf.Font.set_hinting" in
    mutate value operation (fun raw ->
      raw_set_font_hinting raw (hinting_code hinting); Ok ())

  let hinting value = live "SDL3_ttf.Font.hinting" value (fun raw ->
    hinting_of_code (raw_get_font_hinting raw))

  let set_kerning value enabled =
    let operation = "SDL3_ttf.Font.set_kerning" in
    mutate value operation (fun raw -> raw_set_font_kerning raw enabled; Ok ())

  let kerning value = live "SDL3_ttf.Font.kerning" value (fun raw ->
    Ok (raw_get_font_kerning raw))

  let valid_codepoint value = value >= 0 && value <= 0x10ffff
    && not (value >= 0xd800 && value <= 0xdfff)

  let has_glyph value codepoint =
    let operation = "SDL3_ttf.Font.has_glyph" in
    if not (valid_codepoint codepoint) then
      error operation Invalid_argument "codepoint is not a Unicode scalar value"
    else live operation value (fun raw -> Ok (raw_font_has_glyph raw codepoint))

  let glyph_metrics value codepoint =
    let operation = "SDL3_ttf.Font.glyph_metrics" in
    if not (valid_codepoint codepoint) then
      error operation Invalid_argument "codepoint is not a Unicode scalar value"
    else live operation value (fun raw ->
      match ttf_result operation (raw_glyph_metrics raw codepoint) with
      | Error _ as failure -> failure
      | Ok (min_x, max_x, min_y, max_y, advance) ->
          Ok { min_x; max_x; min_y; max_y; advance })

  let size_text value text =
    let operation = "SDL3_ttf.Font.size_text" in
    match validate_text operation text with
    | Error _ as failure -> failure
    | Ok () when text = "" -> live operation value (fun _ -> Ok (0, 0))
    | Ok () -> live operation value (fun raw -> ttf_result operation (raw_size_text raw text))

  let size_text_wrapped value ~wrap_width text =
    let operation = "SDL3_ttf.Font.size_text_wrapped" in
    if wrap_width < 0 then error operation Invalid_argument "wrap width must be non-negative"
    else match validate_text operation text with
    | Error _ as failure -> failure
    | Ok () when text = "" -> live operation value (fun _ -> Ok (0, 0))
    | Ok () -> live operation value (fun raw ->
        ttf_result operation (raw_size_text_wrapped raw text wrap_width))

  let valid_channel value = value >= 0 && value <= 255

  let render_blended value ~color:(red, green, blue, alpha) text =
    let operation = "SDL3_ttf.Font.render_blended" in
    if not (valid_channel red && valid_channel green && valid_channel blue
        && valid_channel alpha) then
      error operation Invalid_argument "RGBA channels must be in 0..255"
    else match validate_text operation text with
    | Error _ as failure -> failure
    | Ok () when text = "" -> live operation value (fun _ -> Ok None)
    | Ok () -> live operation value (fun raw ->
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

  let render_blended_wrapped value ~color:(red, green, blue, alpha)
      ~wrap_width text =
    let operation = "SDL3_ttf.Font.render_blended_wrapped" in
    if wrap_width < 0 then error operation Invalid_argument "wrap width must be non-negative"
    else if not (valid_channel red && valid_channel green && valid_channel blue
        && valid_channel alpha) then
      error operation Invalid_argument "RGBA channels must be in 0..255"
    else match validate_text operation text with
    | Error _ as failure -> failure
    | Ok () when text = "" -> live operation value (fun _ -> Ok None)
    | Ok () -> live operation value (fun raw ->
      match ttf_result operation
          (raw_render_blended_wrapped raw text red green blue alpha wrap_width) with
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
