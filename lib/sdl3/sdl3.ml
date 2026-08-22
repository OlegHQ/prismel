type error_kind =
  | Sdl_error
  | Wrong_domain
  | Destroyed
  | Parent_has_dependents
  | Incompatible_version
  | Invalid_argument

type error = {
  operation : string;
  kind : error_kind;
  message : string;
}

let pp_error formatter error =
  Format.fprintf formatter "%s: %s" error.operation error.message

let error operation kind message = Error { operation; kind; message }

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

type release_token = Metal_view_token of nativeint | Window_token of nativeint

module Release_queue = struct
  let capacity = 1_024
  let mutex = Mutex.create ()
  let metal_views = Queue.create ()
  let windows = Queue.create ()
  let dropped = Atomic.make 0

  let enqueue queue token =
    Mutex.lock mutex;
    if Queue.length metal_views + Queue.length windows >= capacity then
      Atomic.incr dropped
    else Queue.add token queue;
    Mutex.unlock mutex

  let metal_view raw = enqueue metal_views (Metal_view_token raw)
  let window raw = enqueue windows (Window_token raw)

  let drain () =
    Mutex.lock mutex;
    let views = Queue.create () and pending_windows = Queue.create () in
    Queue.transfer metal_views views;
    Queue.transfer windows pending_windows;
    Mutex.unlock mutex;
    Queue.iter (function
      | Metal_view_token raw -> Private_raw.destroy_metal_view raw
      | Window_token _ -> assert false) views;
    Queue.iter (function
      | Window_token raw -> Private_raw.destroy_window raw
      | Metal_view_token _ -> assert false) pending_windows
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
    let requested = mask subsystems in
    Private_raw.was_init requested land requested = requested

  let quit_subsystems subsystems =
    on_main "SDL3.Init.quit_subsystems" (fun () ->
      Private_raw.quit_subsystem (mask subsystems);
      Ok ())

  let quit () =
    on_main "SDL3.Init.quit" (fun () ->
      Private_raw.quit ();
      Ok ())
end

module rec Window : sig
  type flag =
    | Fullscreen | Hidden | Borderless | Resizable | High_pixel_density
    | Always_on_top | Utility | Metal | Transparent
  type t = {
    raw : nativeint;
    generation : int;
    mutable destroyed : bool;
    mutable metal_views : int;
  }
  val create : title:string -> width:int -> height:int -> ?flags:flag list -> unit ->
    (t, error) result
  val generation : t -> int
  val destroyed : t -> bool
  val size : t -> (int * int, error) result
  val size_in_pixels : t -> (int * int, error) result
  val flags : t -> (int64, error) result
  val show : t -> (unit, error) result
  val hide : t -> (unit, error) result
  val set_fullscreen : t -> bool -> (unit, error) result
  val destroy : t -> (unit, error) result
end = struct
  type flag =
    | Fullscreen | Hidden | Borderless | Resizable | High_pixel_density
    | Always_on_top | Utility | Metal | Transparent
  type t = {
    raw : nativeint;
    generation : int;
    mutable destroyed : bool;
    mutable metal_views : int;
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
    if width <= 0 || height <= 0 then
      error "SDL3.Window.create" Invalid_argument "window dimensions must be positive"
    else on_main "SDL3.Window.create" (fun () ->
      Private_raw.clear_error ();
      let raw = Private_raw.create_window title width height (flags_mask flags) in
      if raw = Nativeint.zero then sdl_error "SDL3.Window.create"
      else
        let value = {
          raw; generation = Atomic.fetch_and_add next_generation 1;
          destroyed = false; metal_views = 0;
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

  let flags value = live "SDL3.Window.flags" value (fun raw ->
    Ok (Private_raw.window_flags raw))

  let bool_call operation call value = live operation value (fun raw ->
    Private_raw.clear_error ();
    if call raw then Ok () else sdl_error operation)

  let show = bool_call "SDL3.Window.show" Private_raw.show_window
  let hide = bool_call "SDL3.Window.hide" Private_raw.hide_window
  let set_fullscreen value enabled = live "SDL3.Window.set_fullscreen" value
      (fun raw ->
        Private_raw.clear_error ();
        if Private_raw.set_window_fullscreen raw enabled then Ok ()
        else sdl_error "SDL3.Window.set_fullscreen")

  let destroy value = on_main "SDL3.Window.destroy" (fun () ->
    if value.destroyed then Ok ()
    else if value.metal_views <> 0 then
      error "SDL3.Window.destroy" Parent_has_dependents
        (Printf.sprintf "window still owns %d Metal view(s)" value.metal_views)
    else begin
      value.destroyed <- true;
      Private_raw.destroy_window value.raw;
      Ok ()
    end)
end

and Metal_view : sig
  type layer
  type t
  val create : Window.t -> (t, error) result
  val generation : t -> int
  val destroyed : t -> bool
  val layer : t -> (layer, error) result
  val destroy : t -> (unit, error) result
end = struct
  type layer = Layer of int
  type t = {
    raw : nativeint;
    generation : int;
    window : Window.t;
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
        window.metal_views <- window.metal_views + 1;
        let value = {
          raw; generation = Atomic.fetch_and_add next_generation 1;
          window; destroyed = false;
        } in
        Gc.finalise (fun value ->
          if not value.destroyed then begin
            value.destroyed <- true;
            value.window.metal_views <- max 0 (value.window.metal_views - 1);
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
    else if Private_raw.metal_layer_is_nonnull value.raw then
      Ok (Layer value.generation)
    else sdl_error "SDL3.Metal_view.layer")

  let destroy value = on_main "SDL3.Metal_view.destroy" (fun () ->
    if value.destroyed then Ok ()
    else begin
      value.destroyed <- true;
      value.window.metal_views <- max 0 (value.window.metal_views - 1);
      Private_raw.destroy_metal_view value.raw;
      Ok ()
    end)
end
