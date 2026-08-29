type error_kind =
  | Sdl_error
  | Wrong_domain
  | Destroyed
  | Parent_has_dependents
  | Incompatible_version
  | Invalid_argument
  | Unsupported

type error = {
  operation : string;
  kind : error_kind;
  message : string;
}

type rect = { x : int; y : int; width : int; height : int }

let pp_error formatter error =
  Format.fprintf formatter "%s: %s" error.operation error.message

let error operation kind message = Error { operation; kind; message }

let contains_nul value =
  try ignore (String.index value '\x00'); true with Not_found -> false

let sdl_error operation =
  let message = Private_raw.get_error () in
  let message = if message = "" then "SDL call failed without an error" else message in
  error operation Sdl_error message

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
  let linked () = of_number (Private_raw.linked_version_number ())
  let revision = Private_raw.revision
  let stable_headers = Generated_provenance.stable_headers
  let generator_version = Generated_provenance.generator_version
  let header_sha256 = Generated_provenance.header_aggregate_sha256
  let target_triple = Generated_provenance.target_triple
  let function_count = Generated_provenance.function_count
  let safe_function_count = Generated_provenance.safe_function_count

  let string value =
    Printf.sprintf "%d.%d.%d" value.major value.minor value.patch

  let validate ~release ~linked =
    if release && not stable_headers then
      error "SDL3.Version.validate" Incompatible_version
        ("compiled against prerelease SDL headers " ^ string compiled)
    else if number linked < number compiled then
      error "SDL3.Version.validate" Incompatible_version
        (Printf.sprintf "linked SDL %s is older than compiled headers %s"
          (string linked) (string compiled))
    else if release && not (stable linked) then
      error "SDL3.Version.validate" Incompatible_version
        ("linked SDL is a development release: " ^ string linked)
    else Ok ()

  let check ?(release = true) () = validate ~release ~linked:(linked ())
end

module Time = struct
  let performance_counter = Private_raw.performance_counter
  let performance_frequency = Private_raw.performance_frequency
  let monotonic_seconds () =
    Int64.to_float (performance_counter ())
    /. Int64.to_float (performance_frequency ())

  let max_delay_ms = 0xffff_ffffL

  let delay_ms milliseconds =
    let milliseconds = Int64.of_int milliseconds in
    if milliseconds < 0L || milliseconds > max_delay_ms then
      error "SDL3.Time.delay_ms" Invalid_argument
        "milliseconds must fit in a non-negative unsigned 32-bit integer"
    else (Private_raw.delay_ms milliseconds; Ok ())

  let delay_seconds seconds =
    let operation = "SDL3.Time.delay_seconds" in
    if not (Float.is_finite seconds) then
      error operation Invalid_argument "seconds must be finite"
    else if seconds < 0. then
      error operation Invalid_argument "seconds must be non-negative"
    else
      let milliseconds = Float.ceil (seconds *. 1_000.) in
      if milliseconds > Int64.to_float max_delay_ms then
        error operation Invalid_argument
          "seconds exceed the supported millisecond range"
      else (Private_raw.delay_ms (Int64.of_float milliseconds); Ok ())

  let delay_precise_ns nanoseconds =
    if nanoseconds < 0L then
      error "SDL3.Time.delay_precise_ns" Invalid_argument
        "nanoseconds must be non-negative"
    else (Private_raw.delay_precise_ns nanoseconds; Ok ())

  let delay_precise_seconds seconds =
    let operation = "SDL3.Time.delay_precise_seconds" in
    if not (Float.is_finite seconds) then
      error operation Invalid_argument "seconds must be finite"
    else if seconds < 0. then
      error operation Invalid_argument "seconds must be non-negative"
    else
      let nanoseconds = seconds *. 1_000_000_000. in
      (* [Int64.of_float] is unspecified outside the signed int64 range. *)
      if nanoseconds >= 0x1p63 then
        error operation Invalid_argument
          "seconds exceed the supported nanosecond range"
      else (Private_raw.delay_precise_ns (Int64.of_float nanoseconds); Ok ())
end

module Thread = struct
  let is_initial_domain = Domain.is_main_domain
  let is_sdl_main_thread = Private_raw.is_main_thread

  let require operation =
    if not (is_initial_domain ()) then
      error operation Wrong_domain "SDL operation must run on the initial OCaml domain"
    else if not (is_sdl_main_thread ()) then
      error operation Wrong_domain "SDL operation must run on the platform main thread"
    else Ok ()
end

type release_token =
  | Surface_token of nativeint
  | Metal_view_token of nativeint
  | Window_token of nativeint
  | Cursor_token of nativeint

module Release_queue = struct
  let capacity = 1_024
  let mutex = Mutex.create ()
  let surfaces = Queue.create ()
  let metal_views = Queue.create ()
  let windows = Queue.create ()
  let cursors = Queue.create ()
  let dropped = Atomic.make 0

  let enqueue queue token =
    Mutex.lock mutex;
    if
      Queue.length surfaces + Queue.length metal_views
      + Queue.length windows + Queue.length cursors
        >= capacity then
      Atomic.incr dropped
    else Queue.add token queue;
    Mutex.unlock mutex

  let surface raw = enqueue surfaces (Surface_token raw)
  let metal_view raw = enqueue metal_views (Metal_view_token raw)
  let window raw = enqueue windows (Window_token raw)
  let cursor raw = enqueue cursors (Cursor_token raw)

  let drain () =
    Mutex.lock mutex;
    let pending_surfaces = Queue.create () in
    let views = Queue.create () and pending_windows = Queue.create () in
    let pending_cursors = Queue.create () in
    Queue.transfer surfaces pending_surfaces;
    Queue.transfer metal_views views;
    Queue.transfer windows pending_windows;
    Queue.transfer cursors pending_cursors;
    Mutex.unlock mutex;
    Queue.iter (function
      | Surface_token raw -> Private_raw.destroy_surface raw
      | Metal_view_token _ | Window_token _ | Cursor_token _ ->
          assert false) pending_surfaces;
    Queue.iter (function
      | Metal_view_token raw -> Private_raw.destroy_metal_view raw
      | Surface_token _ | Window_token _ | Cursor_token _ ->
          assert false) views;
    Queue.iter (function
      | Window_token raw -> Private_raw.destroy_window raw
      | Surface_token _ | Metal_view_token _ -> assert false
      | Cursor_token _ -> assert false) pending_windows;
    Queue.iter (function
      | Cursor_token raw -> Private_raw.destroy_cursor raw
      | Surface_token _ | Metal_view_token _ | Window_token _ -> assert false)
      pending_cursors
end

let dropped_release_tokens () = Atomic.get Release_queue.dropped

let drain_release_queue () =
  match Thread.require "SDL3.drain_release_queue" with
  | Error _ as failure -> failure
  | Ok () -> Release_queue.drain (); Ok ()

let on_main operation callback =
  match Thread.require operation with
  | Error _ as failure -> failure
  | Ok () -> Release_queue.drain (); callback ()

module Init = struct
  type subsystem =
    | Audio
    | Video
    | Joystick
    | Haptic
    | Gamepad
    | Events
    | Sensor
    | Camera

  let bit = function
    | Audio -> 0x00000010
    | Video -> 0x00000020
    | Joystick -> 0x00000200
    | Haptic -> 0x00001000
    | Gamepad -> 0x00002000
    | Events -> 0x00004000
    | Sensor -> 0x00008000
    | Camera -> 0x00010000

  let mask values = List.fold_left (fun mask value -> mask lor bit value) 0 values

  let init ?(release = true) subsystems =
    on_main "SDL3.Init.init" (fun () ->
      match Version.check ~release () with
      | Error _ as failure -> failure
      | Ok () ->
          Private_raw.clear_error ();
          if Private_raw.init_subsystem (mask subsystems) then Ok ()
          else sdl_error "SDL3.Init.init")

  let initialized subsystems =
    on_main "SDL3.Init.initialized" (fun () ->
      let requested = mask subsystems in
      Ok (Private_raw.was_init requested land requested = requested))

  let current_video_driver () =
    on_main "SDL3.Init.current_video_driver" (fun () ->
      Ok (Private_raw.current_video_driver ()))

  let quit_subsystems subsystems =
    on_main "SDL3.Init.quit_subsystems" (fun () ->
      Private_raw.quit_subsystem (mask subsystems);
      Ok ())

  let quit () =
    on_main "SDL3.Init.quit" (fun () ->
      Private_raw.quit ();
      Ok ())
end

module Display = struct
  type t = int64

  let id value = value

  let rect (x, y, width, height) = { x; y; width; height }

  let all () = on_main "SDL3.Display.all" (fun () ->
    Private_raw.clear_error ();
    match Private_raw.displays () with
    | Some displays -> Ok (Array.to_list displays)
    | None -> sdl_error "SDL3.Display.all")

  let primary () = on_main "SDL3.Display.primary" (fun () ->
    Private_raw.clear_error ();
    let display = Private_raw.primary_display () in
    if display = 0L then sdl_error "SDL3.Display.primary" else Ok display)

  let name display = on_main "SDL3.Display.name" (fun () ->
    Private_raw.clear_error ();
    match Private_raw.display_name display with
    | Some name -> Ok name
    | None -> sdl_error "SDL3.Display.name")

  let bounds display = on_main "SDL3.Display.bounds" (fun () ->
    Private_raw.clear_error ();
    match Private_raw.display_bounds display false with
    | Some bounds -> Ok (rect bounds)
    | None -> sdl_error "SDL3.Display.bounds")

  let usable_bounds display = on_main "SDL3.Display.usable_bounds" (fun () ->
    Private_raw.clear_error ();
    match Private_raw.display_bounds display true with
    | Some bounds -> Ok (rect bounds)
    | None -> sdl_error "SDL3.Display.usable_bounds")

  let content_scale display = on_main "SDL3.Display.content_scale" (fun () ->
    Private_raw.clear_error ();
    let scale = Private_raw.display_content_scale display in
    if Float.is_finite scale && scale > 0. then Ok scale
    else sdl_error "SDL3.Display.content_scale")

  let refresh_rate display = on_main "SDL3.Display.refresh_rate" (fun () ->
    Private_raw.clear_error ();
    match Private_raw.display_refresh_rate display with
    | Some rate -> Ok rate
    | None -> error "SDL3.Display.refresh_rate" Unsupported
        "the video driver does not expose a current display refresh rate")
end

module rec Window : sig
  type flag =
    | Fullscreen | Hidden | Borderless | Resizable | High_pixel_density
    | Always_on_top | Utility | Metal | Transparent
  type t = {
    raw : nativeint;
    generation : int;
    mutable destroyed : bool;
    metal_views : int Atomic.t;
  }
  type presentation_facts = {
    logical_width : int; logical_height : int;
    drawable_width : int; drawable_height : int;
    pixel_density : float; display_scale : float;
    refresh_rate : float option; vsync : bool;
  }
  val create : title:string -> width:int -> height:int -> ?flags:flag list -> unit ->
    (t, error) result
  val generation : t -> int
  val destroyed : t -> bool
  val id : t -> (int64, error) result
  val display : t -> (Display.t, error) result
  val size : t -> (int * int, error) result
  val size_in_pixels : t -> (int * int, error) result
  val pixel_density : t -> (float, error) result
  val display_scale : t -> (float, error) result
  val position : t -> (int * int, error) result
  val title : t -> (string, error) result
  val set_title : t -> string -> (unit, error) result
  val set_position : t -> x:int -> y:int -> (unit, error) result
  val center : t -> (unit, error) result
  val set_size : t -> width:int -> height:int -> (unit, error) result
  val set_bordered : t -> bool -> (unit, error) result
  val set_resizable : t -> bool -> (unit, error) result
  val set_always_on_top : t -> bool -> (unit, error) result
  val set_relative_mouse : t -> bool -> (unit, error) result
  val relative_mouse : t -> (bool, error) result
  val presentation_facts : t -> vsync:bool -> (presentation_facts, error) result
  val flags : t -> (int64, error) result
  val show : t -> (unit, error) result
  val raise_window : t -> (unit, error) result
  val hide : t -> (unit, error) result
  val maximize : t -> (unit, error) result
  val minimize : t -> (unit, error) result
  val restore : t -> (unit, error) result
  val set_fullscreen : t -> bool -> (unit, error) result
  val sync : t -> (unit, error) result
  val destroy : t -> (unit, error) result
end = struct
  type flag =
    | Fullscreen | Hidden | Borderless | Resizable | High_pixel_density
    | Always_on_top | Utility | Metal | Transparent
  type t = {
    raw : nativeint;
    generation : int;
    mutable destroyed : bool;
    metal_views : int Atomic.t;
  }
  type presentation_facts = {
    logical_width : int; logical_height : int;
    drawable_width : int; drawable_height : int;
    pixel_density : float; display_scale : float;
    refresh_rate : float option; vsync : bool;
  }

  let next_generation = Atomic.make 1
  let generation value = value.generation
  let destroyed value = value.destroyed

  let flag = function
    | Fullscreen -> 0x0000000000000001L
    | Hidden -> 0x0000000000000008L
    | Borderless -> 0x0000000000000010L
    | Resizable -> 0x0000000000000020L
    | High_pixel_density -> 0x0000000000002000L
    | Always_on_top -> 0x0000000000010000L
    | Utility -> 0x0000000000020000L
    | Metal -> 0x0000000020000000L
    | Transparent -> 0x0000000040000000L

  let flags_mask values =
    List.fold_left (fun bits value -> Int64.logor bits (flag value)) 0L values

  let live operation value callback =
    on_main operation (fun () ->
      if value.destroyed then error operation Destroyed "window is destroyed"
      else callback value.raw)

  let create ~title ~width ~height ?(flags = []) () =
    if contains_nul title then
      error "SDL3.Window.create" Invalid_argument
        "window title contains a NUL byte"
    else if width <= 0 || height <= 0 then
      error "SDL3.Window.create" Invalid_argument "window dimensions must be positive"
    else on_main "SDL3.Window.create" (fun () ->
      Private_raw.clear_error ();
      let raw = Private_raw.create_window title width height (flags_mask flags) in
      if raw = Nativeint.zero then sdl_error "SDL3.Window.create"
      else
        let value = {
          raw; generation = Atomic.fetch_and_add next_generation 1;
          destroyed = false; metal_views = Atomic.make 0;
        } in
        Gc.finalise (fun value ->
          if not value.destroyed then begin
            value.destroyed <- true;
            Release_queue.window value.raw
          end) value;
        Ok value)

  let size value = live "SDL3.Window.size" value (fun raw ->
    match Private_raw.window_size raw with
    | Some size -> Ok size
    | None -> sdl_error "SDL3.Window.size")

  let size_in_pixels value = live "SDL3.Window.size_in_pixels" value (fun raw ->
    match Private_raw.window_size_in_pixels raw with
    | Some size -> Ok size
    | None -> sdl_error "SDL3.Window.size_in_pixels")

  let id value = live "SDL3.Window.id" value (fun raw ->
    Private_raw.clear_error ();
    let id = Private_raw.window_id raw in
    if id = 0L then sdl_error "SDL3.Window.id" else Ok id)

  let display value = live "SDL3.Window.display" value (fun raw ->
    Private_raw.clear_error ();
    let display = Private_raw.window_display raw in
    if display = 0L then sdl_error "SDL3.Window.display" else Ok display)

  let positive_scale operation call value = live operation value (fun raw ->
    Private_raw.clear_error ();
    let scale = call raw in
    if Float.is_finite scale && scale > 0. then Ok scale else sdl_error operation)

  let pixel_density = positive_scale "SDL3.Window.pixel_density"
      Private_raw.window_pixel_density

  let display_scale = positive_scale "SDL3.Window.display_scale"
      Private_raw.window_display_scale

  let position value = live "SDL3.Window.position" value (fun raw ->
    Private_raw.clear_error ();
    match Private_raw.window_position raw with
    | Some position -> Ok position
    | None -> sdl_error "SDL3.Window.position")

  let title value = live "SDL3.Window.title" value (fun raw ->
    Ok (Private_raw.window_title raw))

  let set_title value title =
    let operation = "SDL3.Window.set_title" in
    if contains_nul title then
      error operation Invalid_argument "window title contains a NUL byte"
    else live operation value (fun raw ->
      Private_raw.clear_error ();
      if Private_raw.set_window_title raw title then Ok () else sdl_error operation)

  let set_position value ~x ~y = live "SDL3.Window.set_position" value
      (fun raw ->
        Private_raw.clear_error ();
        if Private_raw.set_window_position raw x y then Ok ()
        else sdl_error "SDL3.Window.set_position")

  let center value = live "SDL3.Window.center" value (fun raw ->
    Private_raw.clear_error ();
    if Private_raw.center_window raw then Ok () else sdl_error "SDL3.Window.center")

  let set_size value ~width ~height =
    let operation = "SDL3.Window.set_size" in
    if width <= 0 || height <= 0 then
      error operation Invalid_argument "window dimensions must be positive"
    else live operation value (fun raw ->
      Private_raw.clear_error ();
      if Private_raw.set_window_size raw width height then Ok ()
      else sdl_error operation)

  let flags value = live "SDL3.Window.flags" value (fun raw ->
    Ok (Private_raw.window_flags raw))

  let bool_call operation call value = live operation value (fun raw ->
    Private_raw.clear_error ();
    if call raw then Ok () else sdl_error operation)

  let set_bordered value enabled = live "SDL3.Window.set_bordered" value
      (fun raw -> Private_raw.clear_error ();
        if Private_raw.set_window_bordered raw enabled then Ok ()
        else sdl_error "SDL3.Window.set_bordered")
  let set_resizable value enabled = live "SDL3.Window.set_resizable" value
      (fun raw -> Private_raw.clear_error ();
        if Private_raw.set_window_resizable raw enabled then Ok ()
        else sdl_error "SDL3.Window.set_resizable")
  let set_always_on_top value enabled = live "SDL3.Window.set_always_on_top" value
      (fun raw -> Private_raw.clear_error ();
        if Private_raw.set_window_always_on_top raw enabled then Ok ()
        else sdl_error "SDL3.Window.set_always_on_top")
  let set_relative_mouse value enabled = live "SDL3.Window.set_relative_mouse" value
      (fun raw -> Private_raw.clear_error ();
        if Private_raw.set_window_relative_mouse raw enabled then Ok ()
        else error "SDL3.Window.set_relative_mouse" Unsupported
          (let message = Private_raw.get_error () in
           if message = "" then "relative mouse mode is unavailable" else message))
  let relative_mouse value = live "SDL3.Window.relative_mouse" value (fun raw ->
    Ok (Private_raw.window_relative_mouse raw))

  let presentation_facts value ~vsync =
    match size value, size_in_pixels value, pixel_density value,
        display_scale value, display value with
    | Ok (logical_width, logical_height), Ok (drawable_width, drawable_height),
      Ok pixel_density, Ok display_scale, Ok display ->
        let refresh_rate = match Display.refresh_rate display with
          | Ok value -> Some value | Error { kind = Unsupported; _ } -> None
          | Error _ -> None
        in
        Ok { logical_width; logical_height; drawable_width; drawable_height;
          pixel_density; display_scale; refresh_rate; vsync }
    | Error error, _, _, _, _ | _, Error error, _, _, _
    | _, _, Error error, _, _ | _, _, _, Error error, _
    | _, _, _, _, Error error -> Error error

  let show = bool_call "SDL3.Window.show" Private_raw.show_window
  let raise_window = bool_call "SDL3.Window.raise_window" Private_raw.raise_window
  let hide = bool_call "SDL3.Window.hide" Private_raw.hide_window
  let maximize = bool_call "SDL3.Window.maximize" Private_raw.maximize_window
  let minimize = bool_call "SDL3.Window.minimize" Private_raw.minimize_window
  let restore = bool_call "SDL3.Window.restore" Private_raw.restore_window
  let set_fullscreen value enabled = live "SDL3.Window.set_fullscreen" value
      (fun raw ->
        Private_raw.clear_error ();
        if Private_raw.set_window_fullscreen raw enabled then Ok ()
        else sdl_error "SDL3.Window.set_fullscreen")
  let sync = bool_call "SDL3.Window.sync" Private_raw.sync_window

  let destroy value = on_main "SDL3.Window.destroy" (fun () ->
    if value.destroyed then Ok ()
    else if Atomic.get value.metal_views <> 0 then
      error "SDL3.Window.destroy" Parent_has_dependents
        (Printf.sprintf "window still owns %d Metal view(s)"
          (Atomic.get value.metal_views))
    else begin
      value.destroyed <- true;
      Private_raw.destroy_window value.raw;
      Ok ()
    end)
end

module Mouse = struct
  let capture enabled = on_main "SDL3.Mouse.capture" (fun () ->
    Private_raw.clear_error ();
    if Private_raw.capture_mouse enabled then Ok ()
    else error "SDL3.Mouse.capture" Unsupported
      (let message = Private_raw.get_error () in
       if message = "" then "mouse capture is unavailable" else message))
end

module Cursor = struct
  type shape = Default | Text | Wait | Crosshair | Progress | Nwse_resize
    | Nesw_resize | Ew_resize | Ns_resize | Move | Not_allowed | Pointer
  type t = { raw : nativeint; mutable destroyed : bool }
  let destroyed value = value.destroyed
  let code = function Default -> 0 | Text -> 1 | Wait -> 2 | Crosshair -> 3
    | Progress -> 4 | Nwse_resize -> 5 | Nesw_resize -> 6 | Ew_resize -> 7
    | Ns_resize -> 8 | Move -> 9 | Not_allowed -> 10 | Pointer -> 11
  let create shape = on_main "SDL3.Cursor.create" (fun () ->
    Private_raw.clear_error ();
    let raw = Private_raw.create_system_cursor (code shape) in
    if raw = Nativeint.zero then error "SDL3.Cursor.create" Unsupported
      (let message = Private_raw.get_error () in
       if message = "" then "system cursors are unavailable" else message)
    else let value = { raw; destroyed = false } in
      Gc.finalise (fun value -> if not value.destroyed then begin
        value.destroyed <- true; Release_queue.cursor value.raw end) value;
      Ok value)
  let set value = on_main "SDL3.Cursor.set" (fun () ->
    if value.destroyed then error "SDL3.Cursor.set" Destroyed "cursor is destroyed"
    else (Private_raw.clear_error ();
      if Private_raw.set_cursor value.raw then Ok () else sdl_error "SDL3.Cursor.set"))
  let action operation call = on_main operation (fun () ->
    Private_raw.clear_error (); if call () then Ok () else sdl_error operation)
  let show () = action "SDL3.Cursor.show" Private_raw.show_cursor
  let hide () = action "SDL3.Cursor.hide" Private_raw.hide_cursor
  let visible () = on_main "SDL3.Cursor.visible" (fun () -> Ok (Private_raw.cursor_visible ()))
  let destroy value = on_main "SDL3.Cursor.destroy" (fun () ->
    if value.destroyed then Ok () else begin value.destroyed <- true;
      Private_raw.destroy_cursor value.raw; Ok () end)
end

module Metal_view : sig
  type layer = Native_layer_token.t
  type t
  val create : Window.t -> (t, error) result
  val generation : t -> int
  val destroyed : t -> bool
  val layer : t -> (layer, error) result
  val destroy : t -> (unit, error) result
end = struct
  type layer = Native_layer_token.t
  type t = {
    raw : nativeint;
    generation : int;
    window : Window.t;
    mutable layer_token : layer option;
    mutable destroyed : bool;
  }

  let next_generation = Atomic.make 1
  let generation value = value.generation
  let destroyed value = value.destroyed

  let create window = on_main "SDL3.Metal_view.create" (fun () ->
    if window.Window.destroyed then
      error "SDL3.Metal_view.create" Destroyed "parent window is destroyed"
    else begin
      Private_raw.clear_error ();
      let raw = Private_raw.create_metal_view window.raw in
      if raw = Nativeint.zero then sdl_error "SDL3.Metal_view.create"
      else begin
        Atomic.incr window.metal_views;
        let value = {
          raw; generation = Atomic.fetch_and_add next_generation 1;
          window; layer_token = None; destroyed = false;
        } in
        Gc.finalise (fun value ->
          if not value.destroyed then begin
            value.destroyed <- true;
            Option.iter Private_raw.invalidate_metal_layer_token value.layer_token;
            Atomic.decr value.window.metal_views;
            Release_queue.metal_view value.raw
          end) value;
        Ok value
      end
    end)

  let layer value = on_main "SDL3.Metal_view.layer" (fun () ->
    if value.destroyed then
      error "SDL3.Metal_view.layer" Destroyed "Metal view is destroyed"
    else if value.window.destroyed then
      error "SDL3.Metal_view.layer" Destroyed "parent window is destroyed"
    else match value.layer_token with
    | Some token when Native_layer_token.alive token -> Ok token
    | _ ->
        let token=Private_raw.metal_layer_token value.raw
          (Private_raw.window_id value.window.raw)(Int64.of_int value.generation)in
        if Native_layer_token.alive token then(value.layer_token<-Some token;Ok token)
        else sdl_error "SDL3.Metal_view.layer")

  let destroy value = on_main "SDL3.Metal_view.destroy" (fun () ->
    if value.destroyed then Ok ()
    else begin
      value.destroyed <- true;
      Option.iter Private_raw.invalidate_metal_layer_token value.layer_token;
      Atomic.decr value.window.metal_views;
      Private_raw.destroy_metal_view value.raw;
      Ok ()
    end)
end

module Clipboard = struct
  let set_text text =
    let operation = "SDL3.Clipboard.set_text" in
    if contains_nul text then
      error operation Invalid_argument "clipboard text contains a NUL byte"
    else on_main operation (fun () ->
      Private_raw.clear_error ();
      if Private_raw.clipboard_set_text text then Ok () else sdl_error operation)

  let get_text () = on_main "SDL3.Clipboard.get_text" (fun () ->
    Private_raw.clear_error ();
    match Private_raw.clipboard_get_text () with
    | Some text -> Ok text
    | None -> sdl_error "SDL3.Clipboard.get_text")

  let has_text () = on_main "SDL3.Clipboard.has_text" (fun () ->
    Ok (Private_raw.clipboard_has_text ()))
end

module Text_input = struct
  let live operation window callback = on_main operation (fun () ->
    if window.Window.destroyed then
      error operation Destroyed "text input window is destroyed"
    else callback window.Window.raw)

  let bool_call operation call window = live operation window (fun raw ->
    Private_raw.clear_error ();
    if call raw then Ok () else sdl_error operation)

  let start = bool_call "SDL3.Text_input.start" Private_raw.start_text_input
  let stop = bool_call "SDL3.Text_input.stop" Private_raw.stop_text_input

  let active window = live "SDL3.Text_input.active" window (fun raw ->
    Ok (Private_raw.text_input_active raw))

  let set_area window area ~cursor =
    let operation = "SDL3.Text_input.set_area" in
    if cursor < 0 then
      error operation Invalid_argument "text-input cursor offset must be non-negative"
    else
      match area with
      | Some { width; height; _ } when width <= 0 || height <= 0 ->
          error operation Invalid_argument
            "text-input area dimensions must be positive"
      | None | Some _ -> live operation window (fun raw ->
          let raw_area = Option.map (fun area ->
            area.x, area.y, area.width, area.height) area in
          Private_raw.clear_error ();
          if Private_raw.set_text_input_area raw raw_area cursor then Ok ()
          else sdl_error operation)

  let area window = live "SDL3.Text_input.area" window (fun raw ->
    Private_raw.clear_error ();
    match Private_raw.text_input_area raw with
    | Some ((x, y, width, height), cursor) ->
        Ok ({ x; y; width; height }, cursor)
    | None -> sdl_error "SDL3.Text_input.area")
end

module Event = struct
  type id = int64

  type application_change =
    | Terminating
    | Low_memory
    | Will_enter_background
    | Did_enter_background
    | Will_enter_foreground
    | Did_enter_foreground
    | Locale_changed
    | System_theme_changed

  type display_change =
    | Orientation of int
    | Added
    | Removed
    | Moved
    | Desktop_mode_changed
    | Current_mode_changed
    | Content_scale_changed
    | Usable_bounds_changed
    | Other_display_change of int * int * int

  type window_change =
    | Shown
    | Hidden
    | Exposed
    | Window_moved of int * int
    | Resized of int * int
    | Pixel_size_changed of int * int
    | Metal_view_resized
    | Minimized
    | Maximized
    | Restored
    | Mouse_entered
    | Mouse_left
    | Focus_gained
    | Focus_lost
    | Close_requested
    | Hit_test
    | Icc_profile_changed
    | Display_changed of id
    | Display_scale_changed
    | Safe_area_changed
    | Occluded
    | Entered_fullscreen
    | Left_fullscreen
    | Destroyed
    | Hdr_state_changed
    | Other_window_change of int * int * int

  type device_change = Added | Removed
  type wheel_direction = Normal | Flipped | Other_wheel_direction of int
  type touch_phase = Down | Up | Motion | Cancelled
  type pinch_phase = Began | Updated | Ended
  type pen_proximity_change = Entered | Left

  type gamepad_change =
    | Gamepad_added
    | Gamepad_removed
    | Remapped
    | Update_complete
    | Steam_handle_updated
    | Other_gamepad_change of int

  type drop_change =
    | File of string
    | Text of string
    | Drop_began
    | Drop_complete
    | Drop_position
    | Other_drop_change of int

  type audio_device_change =
    | Audio_added
    | Audio_removed
    | Format_changed
    | Other_audio_device_change of int

  type t =
    | Quit of { timestamp_ns : int64 }
    | Application of { timestamp_ns : int64; change : application_change }
    | Display of {
        timestamp_ns : int64;
        display_id : id;
        change : display_change;
      }
    | Window of {
        timestamp_ns : int64;
        window_id : id;
        change : window_change;
      }
    | Keyboard_device of {
        timestamp_ns : int64;
        which : id;
        change : device_change;
      }
    | Key of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        scancode : int;
        keycode : int;
        modifiers : int;
        raw_scancode : int;
        down : bool;
        repeat : bool;
      }
    | Keymap_changed of { timestamp_ns : int64 }
    | Text_editing of {
        timestamp_ns : int64;
        window_id : id;
        text : string;
        start : int;
        length : int;
      }
    | Text_editing_candidates of {
        timestamp_ns : int64;
        window_id : id;
        candidates : string list;
        selected : int option;
        horizontal : bool;
      }
    | Text_input of {
        timestamp_ns : int64;
        window_id : id;
        text : string;
      }
    | Screen_keyboard of { timestamp_ns : int64; shown : bool }
    | Mouse_device of {
        timestamp_ns : int64;
        which : id;
        change : device_change;
      }
    | Mouse_motion of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        buttons : int64;
        x : float;
        y : float;
        dx : float;
        dy : float;
      }
    | Mouse_button of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        button : int;
        down : bool;
        clicks : int;
        x : float;
        y : float;
      }
    | Mouse_wheel of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        x : float;
        y : float;
        direction : wheel_direction;
        mouse_x : float;
        mouse_y : float;
        integer_x : int;
        integer_y : int;
      }
    | Touch of {
        timestamp_ns : int64;
        window_id : id;
        touch_id : id;
        finger_id : id;
        phase : touch_phase;
        x : float;
        y : float;
        dx : float;
        dy : float;
        pressure : float;
      }
    | Pinch of {
        timestamp_ns : int64;
        window_id : id;
        phase : pinch_phase;
        scale : float;
      }
    | Pen_proximity of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        change : pen_proximity_change;
      }
    | Pen_motion of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        state : int64;
        x : float;
        y : float;
      }
    | Pen_touch of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        state : int64;
        x : float;
        y : float;
        eraser : bool;
        down : bool;
      }
    | Pen_button of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        state : int64;
        x : float;
        y : float;
        button : int;
        down : bool;
      }
    | Pen_axis of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        state : int64;
        x : float;
        y : float;
        axis : int;
        value : float;
      }
    | Gamepad_axis of {
        timestamp_ns : int64;
        which : id;
        axis : int;
        value : int;
      }
    | Gamepad_button of {
        timestamp_ns : int64;
        which : id;
        button : int;
        down : bool;
      }
    | Gamepad_device of {
        timestamp_ns : int64;
        which : id;
        change : gamepad_change;
      }
    | Gamepad_touchpad of {
        timestamp_ns : int64;
        which : id;
        touchpad : int;
        finger : int;
        phase : touch_phase;
        x : float;
        y : float;
        pressure : float;
      }
    | Gamepad_sensor of {
        timestamp_ns : int64;
        sensor_timestamp_ns : int64;
        which : id;
        sensor : int;
        data : float * float * float;
      }
    | Drop of {
        timestamp_ns : int64;
        window_id : id;
        x : float;
        y : float;
        source : string option;
        change : drop_change;
      }
    | Clipboard of {
        timestamp_ns : int64;
        owner : bool;
        mime_types : string list;
      }
    | Audio_device of {
        timestamp_ns : int64;
        which : id;
        recording : bool;
        change : audio_device_change;
      }
    | Sensor of {
        timestamp_ns : int64;
        sensor_timestamp_ns : int64;
        which : id;
        data : float * float * float * float * float * float;
      }
    | Unknown of { timestamp_ns : int64; event_type : int }

  let application_change = function
    | 0x101 -> Some Terminating
    | 0x102 -> Some Low_memory
    | 0x103 -> Some Will_enter_background
    | 0x104 -> Some Did_enter_background
    | 0x105 -> Some Will_enter_foreground
    | 0x106 -> Some Did_enter_foreground
    | 0x107 -> Some Locale_changed
    | 0x108 -> Some System_theme_changed
    | _ -> None

  let display_change event_type data1 data2 =
    match event_type with
    | 0x151 -> Orientation data1
    | 0x152 -> Added
    | 0x153 -> Removed
    | 0x154 -> Moved
    | 0x155 -> Desktop_mode_changed
    | 0x156 -> Current_mode_changed
    | 0x157 -> Content_scale_changed
    | 0x158 -> Usable_bounds_changed
    | value -> Other_display_change (value, data1, data2)

  let window_change event_type data1 data2 =
    match event_type with
    | 0x202 -> Shown
    | 0x203 -> Hidden
    | 0x204 -> Exposed
    | 0x205 -> Window_moved (data1, data2)
    | 0x206 -> Resized (data1, data2)
    | 0x207 -> Pixel_size_changed (data1, data2)
    | 0x208 -> Metal_view_resized
    | 0x209 -> Minimized
    | 0x20a -> Maximized
    | 0x20b -> Restored
    | 0x20c -> Mouse_entered
    | 0x20d -> Mouse_left
    | 0x20e -> Focus_gained
    | 0x20f -> Focus_lost
    | 0x210 -> Close_requested
    | 0x211 -> Hit_test
    | 0x212 -> Icc_profile_changed
    | 0x213 -> Display_changed (Int64.of_int data1)
    | 0x214 -> Display_scale_changed
    | 0x215 -> Safe_area_changed
    | 0x216 -> Occluded
    | 0x217 -> Entered_fullscreen
    | 0x218 -> Left_fullscreen
    | 0x219 -> Destroyed
    | 0x21a -> Hdr_state_changed
    | value -> Other_window_change (value, data1, data2)

  let device_change ~added event_type =
    if event_type = added then Added else Removed

  let touch_phase event_type =
    match event_type with
    | 0x700 | 0x656 -> Down
    | 0x701 | 0x658 -> Up
    | 0x702 | 0x657 -> Motion
    | 0x703 -> Cancelled
    | _ -> Cancelled

  let gamepad_change = function
    | 0x653 -> Gamepad_added
    | 0x654 -> Gamepad_removed
    | 0x655 -> Remapped
    | 0x65a -> Update_complete
    | 0x65b -> Steam_handle_updated
    | value -> Other_gamepad_change value

  let drop_change event_type data =
    match event_type, data with
    | 0x1000, Some path -> File path
    | 0x1001, Some text -> Text text
    | 0x1002, _ -> Drop_began
    | 0x1003, _ -> Drop_complete
    | 0x1004, _ -> Drop_position
    | value, _ -> Other_drop_change value

  let audio_device_change = function
    | 0x1100 -> Audio_added
    | 0x1101 -> Audio_removed
    | 0x1102 -> Format_changed
    | value -> Other_audio_device_change value

  let triple values = values.(0), values.(1), values.(2)
  let sextuple values =
    values.(0), values.(1), values.(2), values.(3), values.(4), values.(5)

  let of_raw = function
    | Private_raw.Application (0x100, timestamp_ns) -> Quit { timestamp_ns }
    | Private_raw.Application (0x304, timestamp_ns) ->
        Keymap_changed { timestamp_ns }
    | Private_raw.Application (0x308, timestamp_ns) ->
        Screen_keyboard { timestamp_ns; shown = true }
    | Private_raw.Application (0x309, timestamp_ns) ->
        Screen_keyboard { timestamp_ns; shown = false }
    | Private_raw.Application (event_type, timestamp_ns) ->
        (match application_change event_type with
         | Some change -> Application { timestamp_ns; change }
         | None -> Unknown { timestamp_ns; event_type })
    | Private_raw.Display
        (event_type, timestamp_ns, display_id, data1, data2) ->
        Display {
          timestamp_ns; display_id; change = display_change event_type data1 data2;
        }
    | Private_raw.Window (event_type, timestamp_ns, window_id, data1, data2) ->
        Window {
          timestamp_ns; window_id; change = window_change event_type data1 data2;
        }
    | Private_raw.Keyboard_device (event_type, timestamp_ns, which) ->
        Keyboard_device {
          timestamp_ns; which; change = device_change ~added:0x305 event_type;
        }
    | Private_raw.Key
        (timestamp_ns, window_id, which, scancode, keycode, modifiers,
         raw_scancode, down, repeat) ->
        Key {
          timestamp_ns; window_id; which; scancode; keycode; modifiers;
          raw_scancode; down; repeat;
        }
    | Private_raw.Text_editing
        (timestamp_ns, window_id, text, start, length) ->
        Text_editing { timestamp_ns; window_id; text; start; length }
    | Private_raw.Text_editing_candidates
        (timestamp_ns, window_id, candidates, selected, horizontal) ->
        Text_editing_candidates {
          timestamp_ns; window_id; candidates = Array.to_list candidates;
          selected = (if selected < 0 then None else Some selected); horizontal;
        }
    | Private_raw.Text_input (timestamp_ns, window_id, text) ->
        Text_input { timestamp_ns; window_id; text }
    | Private_raw.Mouse_device (event_type, timestamp_ns, which) ->
        Mouse_device {
          timestamp_ns; which; change = device_change ~added:0x404 event_type;
        }
    | Private_raw.Mouse_motion
        (timestamp_ns, window_id, which, buttons, x, y, dx, dy) ->
        Mouse_motion { timestamp_ns; window_id; which; buttons; x; y; dx; dy }
    | Private_raw.Mouse_button
        (timestamp_ns, window_id, which, button, down, clicks, x, y) ->
        Mouse_button {
          timestamp_ns; window_id; which; button; down; clicks; x; y;
        }
    | Private_raw.Mouse_wheel
        (timestamp_ns, window_id, which, x, y, raw_direction, mouse_x,
         mouse_y, integer_x, integer_y) ->
        let direction = match raw_direction with
          | 0 -> Normal
          | 1 -> Flipped
          | value -> Other_wheel_direction value
        in
        Mouse_wheel {
          timestamp_ns; window_id; which; x; y; direction; mouse_x; mouse_y;
          integer_x; integer_y;
        }
    | Private_raw.Gamepad_axis (timestamp_ns, which, axis, value) ->
        Gamepad_axis { timestamp_ns; which; axis; value }
    | Private_raw.Gamepad_button (timestamp_ns, which, button, down) ->
        Gamepad_button { timestamp_ns; which; button; down }
    | Private_raw.Gamepad_device (event_type, timestamp_ns, which) ->
        Gamepad_device {
          timestamp_ns; which; change = gamepad_change event_type;
        }
    | Private_raw.Gamepad_touchpad
        (event_type, timestamp_ns, which, touchpad, finger, x, y, pressure) ->
        Gamepad_touchpad {
          timestamp_ns; which; touchpad; finger; phase = touch_phase event_type;
          x; y; pressure;
        }
    | Private_raw.Gamepad_sensor
        (timestamp_ns, which, sensor, data, sensor_timestamp_ns) ->
        Gamepad_sensor {
          timestamp_ns; sensor_timestamp_ns; which; sensor; data = triple data;
        }
    | Private_raw.Touch
        (event_type, timestamp_ns, touch_id, finger_id, x, y, dx, dy,
         pressure, window_id) ->
        Touch {
          timestamp_ns; window_id; touch_id; finger_id;
          phase = touch_phase event_type; x; y; dx; dy; pressure;
        }
    | Private_raw.Pinch (event_type, timestamp_ns, scale, window_id) ->
        let phase = match event_type with
          | 0x710 -> Began
          | 0x711 -> Updated
          | _ -> Ended
        in
        Pinch { timestamp_ns; window_id; phase; scale }
    | Private_raw.Pen_proximity
        (event_type, timestamp_ns, window_id, which) ->
        Pen_proximity {
          timestamp_ns; window_id; which;
          change = (if event_type = 0x1300 then Entered else Left);
        }
    | Private_raw.Pen_motion (timestamp_ns, window_id, which, state, x, y) ->
        Pen_motion { timestamp_ns; window_id; which; state; x; y }
    | Private_raw.Pen_touch
        (timestamp_ns, window_id, which, state, x, y, eraser, down) ->
        Pen_touch { timestamp_ns; window_id; which; state; x; y; eraser; down }
    | Private_raw.Pen_button
        (timestamp_ns, window_id, which, state, x, y, button, down) ->
        Pen_button {
          timestamp_ns; window_id; which; state; x; y; button; down;
        }
    | Private_raw.Pen_axis
        (timestamp_ns, window_id, which, state, x, y, axis, value) ->
        Pen_axis { timestamp_ns; window_id; which; state; x; y; axis; value }
    | Private_raw.Drop
        (event_type, timestamp_ns, window_id, x, y, source, data) ->
        Drop {
          timestamp_ns; window_id; x; y; source;
          change = drop_change event_type data;
        }
    | Private_raw.Clipboard (timestamp_ns, owner, mime_types) ->
        Clipboard { timestamp_ns; owner; mime_types = Array.to_list mime_types }
    | Private_raw.Audio_device
        (event_type, timestamp_ns, which, recording) ->
        Audio_device {
          timestamp_ns; which; recording;
          change = audio_device_change event_type;
        }
    | Private_raw.Sensor (timestamp_ns, which, data, sensor_timestamp_ns) ->
        Sensor {
          timestamp_ns; sensor_timestamp_ns; which; data = sextuple data;
        }
    | Private_raw.Unknown (event_type, timestamp_ns) ->
        Unknown { timestamp_ns; event_type }

  let poll () = on_main "SDL3.Event.poll" (fun () ->
    Ok (Option.map of_raw (Private_raw.poll_event ())))

  let poll_all () = on_main "SDL3.Event.poll_all" (fun () ->
    let rec loop events =
      match Private_raw.poll_event () with
      | None -> Ok (List.rev events)
      | Some event -> loop (of_raw event :: events)
    in
    loop [])

  let size_event_type = function
    | 0x205 | 0x206 | 0x207 | 0x208 -> true
    | _ -> false

  let poll_coalesced () = on_main "SDL3.Event.poll_coalesced" (fun () ->
    let rec loop last_motion last_size events =
      match Private_raw.poll_event () with
      | None ->
          let events = match last_size with
            | None -> events
            | Some event -> of_raw event :: events
          in
          let events = match last_motion with
            | None -> events
            | Some event -> of_raw event :: events
          in
          Ok (List.rev events)
      | Some (Private_raw.Mouse_motion _ as event) ->
          loop (Some event) last_size events
      | Some (Private_raw.Window (event_type, _, _, _, _) as event)
        when size_event_type event_type ->
          loop last_motion (Some event) events
      | Some event ->
          let events = match last_size with
            | None -> events
            | Some size -> of_raw size :: events
          in
          let events = match last_motion with
            | None -> events
            | Some motion -> of_raw motion :: events
          in
          loop None None (of_raw event :: events)
    in
    loop None None [])

  let wait ~timeout_ms =
    if timeout_ms < -1 || Int64.of_int timeout_ms > Int64.of_int32 Int32.max_int then
      error "SDL3.Event.wait" Invalid_argument
        "timeout must be -1 or fit in a signed 32-bit millisecond count"
    else on_main "SDL3.Event.wait" (fun () ->
      Private_raw.clear_error ();
      match Private_raw.wait_event_timeout timeout_ms with
      | Some event -> Ok (Some (of_raw event))
      | None ->
          let message = Private_raw.get_error () in
          if message = "" then Ok None
          else error "SDL3.Event.wait" Sdl_error message)

  let mouse_delta events =
    List.fold_left (fun (total_x, total_y) -> function
      | Mouse_motion { dx; dy; _ } -> total_x +. dx, total_y +. dy
      | _ -> total_x, total_y) (0., 0.) events
end

module Surface = struct
  type t = {
    raw : nativeint;
    generation : int;
    mutable destroyed : bool;
  }

  type rgba = {
    width : int;
    height : int;
    stride : int;
    pixels : bytes;
  }

  let next_generation = Atomic.make 1
  let generation value = value.generation
  let destroyed value = value.destroyed

  let checked_layout operation ~width ~height ~stride ~length =
    if width <= 0 || height <= 0 then
      error operation Invalid_argument "surface dimensions must be positive"
    else if width > max_int / 4 then
      error operation Invalid_argument "surface row byte count overflows"
    else
      let row_bytes = width * 4 in
      if stride < row_bytes then
        error operation Invalid_argument
          "RGBA stride is smaller than the tightly packed row"
      else if height > max_int / stride then
        error operation Invalid_argument "surface byte count overflows"
      else if length < stride * height then
        error operation Invalid_argument
          "RGBA source is shorter than stride multiplied by height"
      else Ok ()

  let checked_dimensions operation ~width ~height =
    if width <= 0 || height <= 0 then
      error operation Invalid_argument "surface dimensions must be positive"
    else if width > max_int / 4 || height > max_int / (width * 4) then
      error operation Invalid_argument "surface byte count overflows"
    else Ok ()

  let owned raw =
    let value = {
      raw;
      generation = Atomic.fetch_and_add next_generation 1;
      destroyed = false;
    } in
    Gc.finalise (fun value ->
      if not value.destroyed then begin
        value.destroyed <- true;
        Release_queue.surface value.raw
      end) value;
    value

  let live operation value callback =
    on_main operation (fun () ->
      if value.destroyed then error operation Destroyed "surface is destroyed"
      else callback value.raw)

  let create_rgba ~width ~height =
    let operation = "SDL3.Surface.create_rgba" in
    match checked_dimensions operation ~width ~height with
    | Error _ as failure -> failure
    | Ok () -> on_main operation (fun () ->
        Private_raw.clear_error ();
        let raw = Private_raw.create_surface_rgba width height in
        if raw = Nativeint.zero then sdl_error operation else Ok (owned raw))

  let of_rgba ~width ~height ?stride pixels =
    let operation = "SDL3.Surface.of_rgba" in
    let stride = Option.value stride ~default:(if width > max_int / 4 then 0
      else width * 4) in
    match checked_layout operation ~width ~height ~stride
        ~length:(Bytes.length pixels) with
    | Error _ as failure -> failure
    | Ok () -> on_main operation (fun () ->
        Private_raw.clear_error ();
        let raw = Private_raw.create_surface_rgba width height in
        if raw = Nativeint.zero then sdl_error operation
        else if Private_raw.surface_write_rgba raw pixels stride then
          Ok (owned raw)
        else
          let message = Private_raw.get_error () in
          Private_raw.destroy_surface raw;
          error operation Sdl_error
            (if message = "" then "SDL surface pixel copy failed" else message))

  let info operation value = live operation value (fun raw ->
    match Private_raw.surface_info raw with
    | Some info -> Ok info
    | None -> sdl_error operation)

  let size value =
    Result.map (fun (width, height, _) -> width, height)
      (info "SDL3.Surface.size" value)

  let pitch value =
    Result.map (fun (_, _, pitch) -> pitch) (info "SDL3.Surface.pitch" value)

  let copy_rgba value = live "SDL3.Surface.copy_rgba" value (fun raw ->
    match Private_raw.surface_info raw with
    | None -> sdl_error "SDL3.Surface.copy_rgba"
    | Some (width, height, _) ->
        Private_raw.clear_error ();
        (match Private_raw.surface_copy_rgba raw with
         | Some pixels -> Ok { width; height; stride = width * 4; pixels }
         | None -> sdl_error "SDL3.Surface.copy_rgba"))

  let destroy value = on_main "SDL3.Surface.destroy" (fun () ->
    if value.destroyed then Ok ()
    else begin
      value.destroyed <- true;
      Private_raw.destroy_surface value.raw;
      Ok ()
    end)
end
