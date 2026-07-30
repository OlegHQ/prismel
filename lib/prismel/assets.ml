type request =
  | Image_file of string
  | Font_file of string * int
  | Sample_file of string
  | Music_file of string

type t = {
  root : string;
  watch : bool;
  images : (string, Image.t) Hashtbl.t;
  image_stamps : (string, float * int) Hashtbl.t;
  fonts : ((string * int), Font.t) Hashtbl.t;
  samples : (string, Audio.Sample.t) Hashtbl.t;
  music : (string, Audio.Music.t) Hashtbl.t;
  mutable destroyed : bool;
}

let require_main_domain () =
  if not (Domain.is_main_domain ()) then
    invalid_arg "Assets operations must run on the main domain"

let create ?(root = ".") ?(watch = false) () =
  require_main_domain ();
  {
    root;
    watch;
    images = Hashtbl.create 16;
    image_stamps = Hashtbl.create 16;
    fonts = Hashtbl.create 16;
    samples = Hashtbl.create 16;
    music = Hashtbl.create 8;
    destroyed = false;
  }

let ensure assets =
  require_main_domain ();
  if assets.destroyed then invalid_arg "Assets cache has been destroyed"

let root assets = ensure assets; assets.root

let resolve assets path =
  ensure assets;
  if Filename.is_relative path then Filename.concat assets.root path else path

let file_stamp path =
  try
    let stat = Unix.stat path in
    Ok (stat.st_mtime, stat.st_size)
  with Unix.Unix_error (error, operation, _) ->
    Error (Printf.sprintf "%s %S: %s" operation path
      (Unix.error_message error))

let reload_image assets path image =
  match file_stamp path with
  | Error _ as error -> error
  | Ok stamp ->
      (match Hashtbl.find_opt assets.image_stamps path with
       | Some previous when previous = stamp -> Ok false
       | _ ->
           match Image.load path with
           | Error message ->
               Error (Printf.sprintf "image %S: %s" path message)
           | Ok replacement ->
               Image.Private.replace image replacement;
               Hashtbl.replace assets.image_stamps path stamp;
               Ok true)

let image assets path =
  let path = resolve assets path in
  match Hashtbl.find_opt assets.images path with
  | Some image ->
      if assets.watch then
        Result.map (fun _changed -> image) (reload_image assets path image)
      else Ok image
  | None ->
      (match Image.load path with
       | Error message -> Error (Printf.sprintf "image %S: %s" path message)
       | Ok image ->
           Hashtbl.add assets.images path image;
           (match file_stamp path with
            | Ok stamp -> Hashtbl.replace assets.image_stamps path stamp
            | Error _ -> ());
           Ok image)

let image_exn assets path =
  match image assets path with
  | Ok image -> image
  | Error message -> failwith message

let font assets ~size path =
  if size <= 0 then Error "font size must be positive"
  else
    let path = resolve assets path in
    let key = path, size in
    match Hashtbl.find_opt assets.fonts key with
    | Some font -> Ok font
    | None ->
        (match Font.load path size with
         | Error (`Msg message) ->
             Error (Printf.sprintf "font %S at %dpt: %s" path size message)
         | Ok font ->
             Hashtbl.add assets.fonts key font;
             Ok font)

let font_exn assets ~size path =
  match font assets ~size path with
  | Ok font -> font
  | Error message -> failwith message

let cached_file assets table load kind path =
  let path = resolve assets path in
  match Hashtbl.find_opt table path with
  | Some value -> Ok value
  | None ->
      (match load path with
       | Error message -> Error (Printf.sprintf "%s %S: %s" kind path message)
       | Ok value ->
           Hashtbl.add table path value;
           Ok value)

let sample assets path =
  cached_file assets assets.samples Audio.Sample.load "sample" path

let sample_exn assets path =
  match sample assets path with
  | Ok sample -> sample
  | Error message -> failwith message

let music assets path =
  cached_file assets assets.music Audio.Music.load "music" path

let music_exn assets path =
  match music assets path with
  | Ok music -> music
  | Error message -> failwith message

let preload assets requests =
  let load = function
    | Image_file path -> Result.map ignore (image assets path)
    | Font_file (path, size) -> Result.map ignore (font assets ~size path)
    | Sample_file path -> Result.map ignore (sample assets path)
    | Music_file path -> Result.map ignore (music assets path)
  in
  let errors =
    List.filter_map
      (fun request -> match load request with Ok () -> None | Error error -> Some error)
      requests
  in
  match errors with [] -> Ok () | _ -> Error errors

type prepared =
  | Image_bytes of string * (string, string) result
  | Deferred of request

let read_file path =
  try
    let channel = open_in_bin path in
    Ok
      (Fun.protect
         ~finally:(fun () -> close_in channel)
         (fun () -> really_input_string channel (in_channel_length channel)))
  with Sys_error message ->
    Error (Printf.sprintf "image %S: %s" path message)

let preload_parallel assets requests =
  ensure assets;
  let requests =
    List.map
      (function
        | Image_file path -> Image_file (resolve assets path)
        | request -> request)
      requests
  in
  let prepare = function
    | Image_file path ->
        Image_bytes (path, read_file path)
    | request -> Deferred request
  in
  let prepared = Parallel.map ~grain:1 prepare requests in
  let load = function
    | Deferred request ->
        (match preload assets [request] with
         | Ok () -> Ok ()
         | Error [message] -> Error message
         | Error messages -> Error (String.concat "; " messages))
    | Image_bytes (_path, Error message) -> Error message
    | Image_bytes (path, Ok bytes) ->
        if Hashtbl.mem assets.images path then Ok ()
        else
          (match Image.Private.load_memory bytes with
           | Error message ->
               Error (Printf.sprintf "image %S: %s" path message)
           | Ok image ->
               Hashtbl.add assets.images path image;
               (match file_stamp path with
                | Ok stamp -> Hashtbl.replace assets.image_stamps path stamp
                | Error _ -> ());
               Ok ())
  in
  let errors =
    List.filter_map
      (fun prepared -> match load prepared with Ok () -> None | Error e -> Some e)
      prepared
  in
  match errors with [] -> Ok () | _ -> Error errors

let image_count assets = ensure assets; Hashtbl.length assets.images
let font_count assets = ensure assets; Hashtbl.length assets.fonts
let sample_count assets = ensure assets; Hashtbl.length assets.samples
let music_count assets = ensure assets; Hashtbl.length assets.music

let refresh assets =
  ensure assets;
  if not assets.watch then Ok []
  else
    let changed = ref [] and errors = ref [] in
    Hashtbl.iter
      (fun path image ->
        match reload_image assets path image with
        | Ok true -> changed := path :: !changed
        | Ok false -> ()
        | Error message -> errors := message :: !errors)
      assets.images;
    match List.rev !errors with
    | [] -> Ok (List.rev !changed)
    | errors -> Error errors

let clear assets =
  ensure assets;
  Hashtbl.iter (fun _ image -> Image.destroy image) assets.images;
  Hashtbl.iter (fun _ font -> Font.destroy font) assets.fonts;
  Hashtbl.iter (fun _ sample -> Audio.Sample.destroy sample) assets.samples;
  Hashtbl.iter (fun _ music -> Audio.Music.destroy music) assets.music;
  Hashtbl.clear assets.images;
  Hashtbl.clear assets.image_stamps;
  Hashtbl.clear assets.fonts;
  Hashtbl.clear assets.samples;
  Hashtbl.clear assets.music

let destroy assets =
  require_main_domain ();
  if not assets.destroyed then begin
    clear assets;
    assets.destroyed <- true
  end
