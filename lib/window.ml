open Tsdl

(* Window configuration type *)
type config = {
  width : int;
  height : int;
  title : string;
  resizable : bool;
  fullscreen : bool;
  x : int option;
  y : int option;
  vsync : bool;
  highdpi : bool;
}

(* Window state type *)
type t = {
  window : Sdl.window;
  renderer : Sdl.renderer;
  config : config;
  mutable current_width : int;
  mutable current_height : int;
}

(* Default configuration *)
let default_config = {
  width = 800;
  height = 600;
  title = "Creative Coding Framework";
  resizable = false;
  fullscreen = false;
  x = None; (* centered by default *)
  y = None; (* centered by default *)
  vsync = true;
  highdpi = false;
}

(* Current window reference - only one window supported for now *)
let current_window : t option ref = ref None

(* Get window flags based on configuration *)
let get_window_flags config =
  let flags = [] in
  let flags = if config.resizable then Sdl.Window.resizable :: flags else flags in
  let flags = if config.fullscreen then Sdl.Window.fullscreen_desktop :: flags else flags in
  let flags = if config.highdpi then Sdl.Window.allow_highdpi :: flags else flags in
  flags

(* Get renderer flags based on configuration *)
let get_renderer_flags config =
  let flags = [Sdl.Renderer.accelerated] in
  let flags = if config.vsync then Sdl.Renderer.presentvsync :: flags else flags in
  flags

(* Create window with given configuration *)
let create ?(config = default_config) () =
  match !current_window with
  | Some _ -> failwith "Window already created. Only one window is supported."
  | None ->
    (* Determine window position *)
    let x = match config.x with
      | Some x -> x
      | None -> Sdl.Window.pos_centered
    in
    let y = match config.y with
      | Some y -> y  
      | None -> Sdl.Window.pos_centered
    in
    
    (* Create SDL window *)
    let window_flags = get_window_flags config in
    let window_flags= List.fold_left (fun acc flag -> Sdl.Window.(+) acc flag) Sdl.Window.windowed window_flags in
    let window_result = Sdl.create_window config.title
      ~x ~y
      ~w:config.width 
      ~h:config.height 
      window_flags 
    in
    
    match window_result with
    | Error (`Msg e) -> failwith ("Failed to create window: " ^ e)
    | Ok window ->
      (* Create SDL renderer *)
      let renderer_flags = get_renderer_flags config in
      let renderer_flags= List.fold_left (fun acc flag -> Sdl.Renderer.(+) acc flag) Sdl.Renderer.accelerated renderer_flags in
      let renderer_result = Sdl.create_renderer window ~index:(-1) ~flags:renderer_flags in
      
      match renderer_result with
      | Error (`Msg e) ->
        Sdl.destroy_window window;
        failwith ("Failed to create renderer: " ^ e)
      | Ok renderer ->
        let window_state = {
          window;
          renderer;
          config;
          current_width = config.width;
          current_height = config.height;
        } in
        current_window := Some window_state;
        window_state

(* Get current window *)
let get_current () =
  match !current_window with
  | None -> failwith "No window created. Call Window.create first."
  | Some w -> w

(* Window property queries *)
let width () =
  let w = get_current () in
  w.current_width

let height () =
  let w = get_current () in
  w.current_height

let size () =
  let w = get_current () in
  (w.current_width, w.current_height)

let title () =
  let w = get_current () in
  w.config.title

let is_resizable () =
  let w = get_current () in
  w.config.resizable

let is_fullscreen () =
  let w = get_current () in
  w.config.fullscreen

(* Window management functions *)
let set_title new_title =
  let w = get_current () in
  Sdl.set_window_title w.window new_title

let set_size new_width new_height =
  let w = get_current () in
  Sdl.set_window_size w.window ~w:new_width ~h:new_height;
  w.current_width <- new_width;
  w.current_height <- new_height

let set_position x y =
  let w = get_current () in
  Sdl.set_window_position w.window ~x ~y

let center () =
  let w = get_current () in
  Sdl.set_window_position w.window 
    ~x:Sdl.Window.pos_centered 
    ~y:Sdl.Window.pos_centered

let set_fullscreen enable =
  let w = get_current () in
  let flag = if enable then Sdl.Window.fullscreen_desktop else Sdl.Window.windowed in
  match Sdl.set_window_fullscreen w.window flag with
  | Error (`Msg e) -> failwith ("Failed to set fullscreen: " ^ e)
  | Ok () -> ()

let show () =
  let w = get_current () in
  Sdl.show_window w.window

let hide () =
  let w = get_current () in
  Sdl.hide_window w.window

let minimize () =
  let w = get_current () in
  Sdl.minimize_window w.window

let maximize () =
  let w = get_current () in
  Sdl.maximize_window w.window

let restore () =
  let w = get_current () in
  Sdl.restore_window w.window

(* Update window dimensions (called internally when window is resized) *)
let update_dimensions new_width new_height =
  match !current_window with
  | None -> ()
  | Some w ->
    w.current_width <- new_width;
    w.current_height <- new_height

(* Get SDL objects (for internal use by other modules) *)
let get_window () =
  let w = get_current () in
  w.window

let get_renderer () =
  let w = get_current () in
  w.renderer

(* Window cleanup *)
let destroy () =
  match !current_window with
  | None -> ()
  | Some w ->
    Sdl.destroy_renderer w.renderer;
    Sdl.destroy_window w.window;
    current_window := None

(* Check if window exists *)
let exists () =
  match !current_window with
  | None -> false
  | Some _ -> true
