(* font.ml — SDL2_ttf backend via tsdl-ttf *)

open Result
open Tsdl
module Ttf = Tsdl_ttf.Ttf

(** In-file re-export of public types so we can pattern-match *)

type render_mode =
  | Solid   of Color.t
  | Shaded  of Color.t * Color.t
  | Blended of Color.t

type style = Normal | Bold | Italic | Underline | Strikethrough

type hinting = Normal_hinting | Light_hinting | Mono_hinting | None_hinting

type alignment = Left | Center | Right

(** Convenient bind alias *)
let ( >>= ) = Result.bind

(* -------------------------------------------------------------------------- *)
(* Helpers                                                                     *)
(* -------------------------------------------------------------------------- *)

let sdl_color (c : Color.t) : Sdl.color =
  Sdl.Color.create ~r:c.r ~g:c.g ~b:c.b ~a:c.a

let map_err (r : ('a, string) result) : ('a, [> `Msg of string ]) result =
  match r with Ok v -> Ok v | Error e -> Error (`Msg e)

(* -------------------------------------------------------------------------- *)
(* One-time TTF init                                                           *)
(* -------------------------------------------------------------------------- *)

let ensure_init () : (unit, [> `Msg of string ]) result =
  if Ttf.was_init () then Ok () else (Ttf.init () :> _)

(* -------------------------------------------------------------------------- *)
(* Font handle                                                                 *)
(* -------------------------------------------------------------------------- *)

type cache_key = string * render_mode * int option * alignment * int

type cached_text = {
  key : cache_key;
  renderer : Sdl.renderer;
  image : Image.t;
}

type handle = {
  raster_size : int;
  value : Ttf.font;
}

type t = {
  font : Ttf.font;
  size : int;
  path : string;
  explicit_density : float option;
  mutable handles : handle list;
  mutable cache : cached_text list;
  mutable draw_cache : cached_text list;
  mutable destroyed : bool;
}

let loaded_fonts : t list ref = ref []
let system_fonts : (int, t) Hashtbl.t = Hashtbl.create 4

(* -------------------------------------------------------------------------- *)
(* Loading                                                                     *)
(* -------------------------------------------------------------------------- *)

let load_with_density ?explicit_density path pt :
    (t, [> `Msg of string ]) result =
  if pt <= 0 then Error (`Msg "font point size must be positive")
  else
  ensure_init () >>= fun () ->
  Ttf.open_font path pt >>= fun font ->
  let loaded = {
    font;
    size = pt;
    path;
    explicit_density;
    handles = [{ raster_size = pt; value = font }];
    cache = [];
    draw_cache = [];
    destroyed = false;
  } in
  loaded_fonts := loaded :: !loaded_fonts;
  Ok loaded

let load path pt = load_with_density path pt

let load_dpi path pt hdpi vdpi =
  if hdpi <= 0 || vdpi <= 0 then
    Error (`Msg "font DPI must be positive")
  else if hdpi <> vdpi then
    Error (`Msg
      "this SDL_ttf binding supports uniform font DPI only (hdpi must equal vdpi)")
  else
    load_with_density
      ~explicit_density:(float_of_int hdpi /. 72.) path pt

let resize f pt =
  load_with_density ?explicit_density:f.explicit_density f.path pt

let system_font_candidates () =
  let fixed = [
    (* macOS: SF is a system resource and is intentionally not bundled. *)
    "/System/Library/Fonts/SFNS.ttf";
    "/System/Library/Fonts/SFCompact.ttf";
    "/System/Library/Fonts/HelveticaNeue.ttc";
    "/System/Library/Fonts/Helvetica.ttc";
    "/System/Library/Fonts/LucidaGrande.ttc";
    (* Common Linux desktop fallbacks. *)
    "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf";
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";
    "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf";
    "/usr/share/fonts/TTF/DejaVuSans.ttf";
  ] in
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
      if Sys.file_exists path then Some path else None
  | _ -> List.find_opt Sys.file_exists (system_font_candidates ())

let system ?(size = 14) () =
  if size <= 0 then Error (`Msg "system font point size must be positive")
  else
    match Hashtbl.find_opt system_fonts size with
    | Some font when not font.destroyed -> Ok font
    | _ ->
        (match system_path () with
         | None ->
             let message =
               match Sys.getenv_opt "PRISMEL_UI_FONT" with
               | Some path when path <> "" ->
                   Printf.sprintf
                     "PRISMEL_UI_FONT does not name a readable font: %s" path
               | _ -> "No supported installed system UI font was found"
             in
             Error (`Msg message)
         | Some path ->
             load path size >>= fun font ->
             Hashtbl.replace system_fonts size font;
             Ok font)

(* -------------------------------------------------------------------------- *)
(* Style / hinting conversion                                                  *)
(* -------------------------------------------------------------------------- *)

let ttf_style_of_list lst =
  List.fold_left
    (fun acc s -> match s with
       | Normal        -> acc
       | Bold          -> Ttf.Style.(acc + bold)
       | Italic        -> Ttf.Style.(acc + italic)
       | Underline     -> Ttf.Style.(acc + underline)
       | Strikethrough -> Ttf.Style.(acc + strikethrough))
    Ttf.Style.normal lst

let list_of_ttf_style v : style list =
  let open Ttf.Style in
  let add flag tag acc = if test v flag then tag :: acc else acc in
  let res = []
    |> add bold Bold |> add italic Italic |> add underline Underline
    |> add strikethrough Strikethrough in
  if eq v normal then Normal :: res else res |> List.rev

let ttf_hint = function
  | Normal_hinting -> Ttf.Hinting.Normal
  | Light_hinting  -> Ttf.Hinting.Light
  | Mono_hinting   -> Ttf.Hinting.Mono
  | None_hinting   -> Ttf.Hinting.None

let hint_of_ttf = function
  | Ttf.Hinting.Normal -> Normal_hinting
  | Ttf.Hinting.Light  -> Light_hinting
  | Ttf.Hinting.Mono   -> Mono_hinting
  | Ttf.Hinting.None   -> None_hinting

let renderer_density renderer =
  let logical_width, logical_height = Sdl.render_get_logical_size renderer in
  if logical_width <= 0 || logical_height <= 0 then 1.
  else
    match Sdl.get_renderer_output_size renderer with
    | Error _ -> 1.
    | Ok (output_width, output_height) ->
        let x =
          float_of_int output_width /. float_of_int logical_width
        in
        let y =
          float_of_int output_height /. float_of_int logical_height
        in
        max 1. (min x y)

let configure_like source destination =
  Ttf.set_font_style destination (Ttf.get_font_style source);
  Ttf.set_font_hinting destination (Ttf.get_font_hinting source);
  Ttf.set_font_kerning destination (Ttf.get_font_kerning source)

let handle_for_renderer f renderer =
  let requested_density =
    Option.value ~default:(renderer_density renderer) f.explicit_density
  in
  let raster_size =
    max 1
      (int_of_float
         ((float_of_int f.size *. requested_density) +. 0.5))
  in
  let density = float_of_int raster_size /. float_of_int f.size in
  match List.find_opt (fun handle -> handle.raster_size = raster_size) f.handles with
  | Some handle -> Ok (handle.value, density, raster_size)
  | None ->
      Ttf.open_font f.path raster_size >>= fun font ->
      configure_like f.font font;
      f.handles <- { raster_size; value = font } :: f.handles;
      Ok (font, density, raster_size)

(* -------------------------------------------------------------------------- *)
(* Surface → Image                                                             *)
(* -------------------------------------------------------------------------- *)

let logical_pixels density pixels =
  max 1 (int_of_float ((float_of_int pixels /. density) +. 0.5))

let image_from_surface ~density (surf : Sdl.surface) :
    (Image.t, [> `Msg of string ]) result =
  map_err (Image.Private.get_renderer ()) >>= fun renderer ->
  Sdl.create_texture_from_surface renderer surf >>= fun tex ->
  match Sdl.query_texture tex with
  | Error _ as error ->
      Sdl.destroy_texture tex;
      error
  | Ok (_, _, (w, h)) ->
      let image = Image.Private.from_texture tex
          (logical_pixels density w) (logical_pixels density h) in
      begin match Image_snapshot.rgba_of_surface surf with
      | Error _ -> Sdl.destroy_texture tex; Error (`Msg "text snapshot failed")
      | Ok (width, height, rgba) ->
          Image_snapshot.register (Obj.repr image) ~width ~height rgba;
          Ok image
      end

(* -------------------------------------------------------------------------- *)
(* Render helpers                                                              *)
(* -------------------------------------------------------------------------- *)

let render_surface font text = function
  | Solid fg          -> Ttf.render_utf8_solid   font text (sdl_color fg)
  | Shaded (fg, bg)   -> Ttf.render_utf8_shaded  font text (sdl_color fg) (sdl_color bg)
  | Blended fg        -> Ttf.render_utf8_blended font text (sdl_color fg)

let transparent_text_surface font =
  let height = max 1 (Ttf.font_height font) in
  Sdl.create_rgb_surface_with_format ~w:1 ~h:height
    ~depth:32 Sdl.Pixel.format_argb8888
  >>= fun surface ->
  match Sdl.fill_rect surface None 0l with
  | Ok () -> Ok surface
  | Error _ as error ->
      Sdl.free_surface surface;
      error

(* -------------------------------------------------------------------------- *)
(* Public API — single-line / wrapped                                          *)
(* -------------------------------------------------------------------------- *)

let render_text_with font density txt mode =
  (if txt = "" then transparent_text_surface font
   else render_surface font txt mode)
  >>= fun surf ->
  Fun.protect
    ~finally:(fun () -> Sdl.free_surface surf)
    (fun () -> image_from_surface ~density surf)

let render_text f txt mode =
  map_err (Image.Private.get_renderer ()) >>= fun renderer ->
  handle_for_renderer f renderer >>= fun (font, density, _) ->
  render_text_with font density txt mode

(* -------------------------------------------------------------------------- *)
(* Multi-line with alignment                                                   *)
(* -------------------------------------------------------------------------- *)

let render_multiline_with font density txt mode align =
  let lines = String.split_on_char '\n' txt in
  (* Measure *)
  let rec measure acc = function
    | [] -> Ok (List.rev acc)
    | "" :: ls ->
        measure (("", 0, max 1 (Ttf.font_height font)) :: acc) ls
    | l :: ls ->
        Ttf.size_utf8 font l >>= fun (w, h) ->
        measure ((l, w, h) :: acc) ls
  in
  measure [] lines >>= fun dims ->
  let max_w = max 1 (List.fold_left (fun m (_,w,_) -> max m w) 0 dims) in
  let total_h = max 1 (List.fold_left (fun s (_,_,h) -> s + h) 0 dims) in
  Sdl.create_rgb_surface_with_format ~w:max_w ~h:total_h
    ~depth:32 Sdl.Pixel.format_argb8888 >>= fun dst ->
  (match Sdl.fill_rect dst None 0l with
   | Error _ as error ->
       Sdl.free_surface dst;
       error
   | Ok () ->
       Fun.protect
         ~finally:(fun () -> Sdl.free_surface dst)
         (fun () ->
           let y = ref 0 in
           let blit (line, w, h) =
             if line = "" then begin
               y := !y + h;
               Ok ()
             end else
             render_surface font line mode >>= fun surf ->
             Fun.protect
               ~finally:(fun () -> Sdl.free_surface surf)
               (fun () ->
                 let x = match align with
                   | Left -> 0
                   | Center -> (max_w - w) / 2
                   | Right -> max_w - w
                 in
                 let rect = Sdl.Rect.create ~x ~y:!y ~w ~h in
                 Sdl.blit_surface ~src:surf None ~dst (Some rect) >>= fun () ->
                 y := !y + h;
                 Ok ())
           in
           List.fold_left
             (fun result dimensions -> result >>= fun () -> blit dimensions)
             (Ok ()) dims
           >>= fun () ->
           image_from_surface ~density dst))

let render_multiline f txt mode align =
  map_err (Image.Private.get_renderer ()) >>= fun renderer ->
  handle_for_renderer f renderer >>= fun (font, density, _) ->
  render_multiline_with font density txt mode align

let wrap_paragraph font width paragraph =
  let words =
    String.split_on_char ' ' paragraph
    |> List.filter (fun word -> word <> "")
  in
  let rec loop lines current = function
    | [] ->
        Ok (List.rev (if current = "" then lines else current :: lines))
    | word :: rest ->
        let candidate = if current = "" then word else current ^ " " ^ word in
        Ttf.size_utf8 font candidate >>= fun (candidate_width, _) ->
        if candidate_width <= width || current = "" then
          loop lines candidate rest
        else
          loop (current :: lines) word rest
  in
  match words with
  | [] -> Ok [""]
  | _ -> loop [] "" words

let wrap_text font width text =
  if width <= 0 then Error (`Msg "text wrap width must be positive")
  else
    let rec paragraphs lines = function
      | [] -> Ok (String.concat "\n" (List.rev lines))
      | paragraph :: rest ->
          wrap_paragraph font width paragraph >>= fun wrapped ->
          paragraphs (List.rev_append wrapped lines) rest
    in
    paragraphs [] (String.split_on_char '\n' text)

let render_wrapped f txt mode width =
  if width <= 0 then Error (`Msg "text wrap width must be positive")
  else
    map_err (Image.Private.get_renderer ()) >>= fun renderer ->
    handle_for_renderer f renderer >>= fun (font, density, _) ->
    let raster_width =
      max 1 (int_of_float ((float_of_int width *. density) +. 0.5))
    in
    wrap_text font raster_width txt >>= fun wrapped ->
    render_multiline_with font density wrapped mode Left >>= fun image ->
    Ok [image]

let render_composed_with ?wrap ~align font density text mode =
  match wrap with
  | Some width ->
      let raster_width =
        max 1 (int_of_float ((float_of_int width *. density) +. 0.5))
      in
      wrap_text font raster_width text >>= fun wrapped ->
      render_multiline_with font density wrapped mode align
  | None when String.contains text '\n' ->
      render_multiline_with font density text mode align
  | None -> render_text_with font density text mode

let cached_text ?wrap ?(align = Left) f text mode =
  map_err (Image.Private.get_renderer ()) >>= fun renderer ->
  handle_for_renderer f renderer >>= fun (font, density, raster_size) ->
  let key = text, mode, wrap, align, raster_size in
  match
    List.find_opt
      (fun cached -> cached.key = key && cached.renderer == renderer)
      f.cache
  with
  | Some cached -> Ok cached.image
  | None ->
      render_composed_with ?wrap ~align font density text mode >>= fun image ->
      f.cache <- { key; renderer; image } :: f.cache;
      Ok image

let cached_text_for_draw ?wrap ?(align = Left) f text mode =
  map_err (Image.Private.get_renderer ()) >>= fun renderer ->
  handle_for_renderer f renderer >>= fun (font, density, raster_size) ->
  let key = text, mode, wrap, align, raster_size in
  let rec extract reversed = function
    | [] -> None, List.rev reversed
    | cached :: rest
      when cached.key = key && cached.renderer == renderer ->
        Some cached, List.rev_append reversed rest
    | cached :: rest -> extract (cached :: reversed) rest
  in
  let cached, remaining = extract [] f.draw_cache in
  match cached with
  | Some cached ->
      f.draw_cache <- cached :: remaining;
      Ok cached.image
  | None ->
      render_composed_with ?wrap ~align font density text mode >>= fun image ->
      let inserted = { key; renderer; image } in
      let maximum_per_renderer = 256 in
      let rec trim count kept evicted = function
        | [] -> List.rev kept, evicted
        | cached :: rest when cached.renderer == renderer ->
            if count < maximum_per_renderer then
              trim (count + 1) (cached :: kept) evicted rest
            else
              trim count kept (cached :: evicted) rest
        | cached :: rest -> trim count (cached :: kept) evicted rest
      in
      let retained, evicted = trim 0 [] [] (inserted :: f.draw_cache) in
      List.iter (fun cached -> Image.destroy cached.image) evicted;
      f.draw_cache <- retained;
      Ok image

let cache_count f = List.length f.cache + List.length f.draw_cache

let clear_cache f =
  List.iter (fun cached -> Image.destroy cached.image) f.cache;
  List.iter (fun cached -> Image.destroy cached.image) f.draw_cache;
  f.cache <- [];
  f.draw_cache <- []

let release_renderer renderer =
  List.iter
    (fun font ->
      let release cache =
        let owned, retained =
          List.partition (fun cached -> cached.renderer == renderer) cache
        in
        List.iter (fun cached -> Image.destroy cached.image) owned;
        retained
      in
      font.cache <- release font.cache;
      font.draw_cache <- release font.draw_cache)
    !loaded_fonts

module Private = struct
  let cached_text = cached_text_for_draw
end

(* -------------------------------------------------------------------------- *)
(* Metrics                                                                     *)
(* -------------------------------------------------------------------------- *)

let text_size  f s = (Ttf.size_utf8 f.font s :> _)
let text_width f s = text_size f s >>= fun (w,_) -> Ok w
let text_height f s = text_size f s >>= fun (_,h) -> Ok h

let get_height    f = Ttf.font_height    f.font
let get_ascent    f = Ttf.font_ascent    f.font
let get_descent   f = Ttf.font_descent   f.font
let get_line_skip f = Ttf.font_line_skip f.font
let get_size      f = f.size

(* -------------------------------------------------------------------------- *)
(* Style / hinting / kerning                                                  *)
(* -------------------------------------------------------------------------- *)

let set_style f lst =
  clear_cache f;
  let style = ttf_style_of_list lst in
  List.iter (fun handle -> Ttf.set_font_style handle.value style) f.handles
let get_style   f     = list_of_ttf_style (Ttf.get_font_style f.font)
let set_hinting f h =
  clear_cache f;
  let hinting = ttf_hint h in
  List.iter
    (fun handle -> Ttf.set_font_hinting handle.value hinting)
    f.handles
let get_hinting f     = hint_of_ttf (Ttf.get_font_hinting f.font)
let set_kerning f b =
  clear_cache f;
  List.iter (fun handle -> Ttf.set_font_kerning handle.value b) f.handles
let get_kerning f     = Ttf.get_font_kerning f.font

(* -------------------------------------------------------------------------- *)
(* Misc info                                                                   *)
(* -------------------------------------------------------------------------- *)

let get_family_name f =
  match Ttf.font_face_family_name f.font with
  | "" -> None | s -> Some s

let get_style_name f =
  match Ttf.font_face_style_name f.font with
  | "" -> None | s -> Some s

let is_fixed_width f = Ttf.font_face_is_fixed_width f.font <> 0

(* -------------------------------------------------------------------------- *)
(* Glyph utilities                                                             *)
(* -------------------------------------------------------------------------- *)

let glyph_provided f cp = Ttf.glyph_is_provided f.font cp

let glyph_metrics f cp =
  Ttf.glyph_metrics f.font cp >>= fun m ->
  Ok (m.min_x, m.max_x, m.min_y, m.max_y, m.advance)

(* -------------------------------------------------------------------------- *)
(* Cleanup                                                                     *)
(* -------------------------------------------------------------------------- *)

let destroy f =
  if not f.destroyed then begin
    clear_cache f;
    List.iter (fun handle -> Ttf.close_font handle.value) f.handles;
    f.handles <- [];
    f.destroyed <- true;
    loaded_fonts := List.filter (fun loaded -> loaded != f) !loaded_fonts;
    Hashtbl.filter_map_inplace
      (fun _ loaded -> if loaded == f then None else Some loaded)
      system_fonts
  end

let shutdown () =
  List.iter destroy (List.rev !loaded_fonts);
  loaded_fonts := [];
  Hashtbl.clear system_fonts
