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

type t = { font : Ttf.font; size : int; path : string }

(* -------------------------------------------------------------------------- *)
(* Loading                                                                     *)
(* -------------------------------------------------------------------------- *)

let load path pt : (t, [> `Msg of string ]) result =
  ensure_init () >>= fun () ->
  Ttf.open_font path pt >>= fun font ->
  Ok { font; size = pt; path }

let load_dpi path pt _hdpi _vdpi = load path pt  (* DPI open not yet bound *)

let resize f pt = load f.path pt

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

(* -------------------------------------------------------------------------- *)
(* Surface → Image                                                             *)
(* -------------------------------------------------------------------------- *)

let image_from_surface (surf : Sdl.surface) : (Image.t, [> `Msg of string ]) result =
  map_err (Image.get_renderer ()) >>= fun renderer ->
  Sdl.create_texture_from_surface renderer surf >>= fun tex ->
  Sdl.query_texture tex >>= fun (_, _, (w, h)) ->
  Ok (Image.from_texture tex w h)

(* -------------------------------------------------------------------------- *)
(* Render helpers                                                              *)
(* -------------------------------------------------------------------------- *)

let render_surface font text = function
  | Solid fg          -> Ttf.render_utf8_solid   font text (sdl_color fg)
  | Shaded (fg, bg)   -> Ttf.render_utf8_shaded  font text (sdl_color fg) (sdl_color bg)
  | Blended fg        -> Ttf.render_utf8_blended font text (sdl_color fg)

let render_surface_wrapped font text mode wrap_w =
  let w = Int32.of_int wrap_w in
  match mode with
  | Solid fg        -> Ttf.render_utf8_solid   font text (sdl_color fg)
  | Shaded (fg, bg) -> Ttf.render_utf8_shaded font text (sdl_color fg) (sdl_color bg)
  | Blended fg      -> Ttf.render_utf8_blended_wrapped font text (sdl_color fg) w

(* -------------------------------------------------------------------------- *)
(* Public API — single-line / wrapped                                          *)
(* -------------------------------------------------------------------------- *)

let render_text f txt mode =
  render_surface f.font txt mode >>= fun surf ->
  image_from_surface surf >>= fun img ->
  Sdl.free_surface surf; Ok img

let render_wrapped f txt mode w =
  render_surface_wrapped f.font txt mode w >>= fun surf ->
  image_from_surface surf >>= fun img ->
  Sdl.free_surface surf; Ok [ img ]

(* -------------------------------------------------------------------------- *)
(* Multi-line with alignment                                                   *)
(* -------------------------------------------------------------------------- *)

let render_multiline f txt mode align =
  let lines = String.split_on_char '\n' txt in
  (* Measure *)
  let rec measure acc = function
    | [] -> Ok (List.rev acc)
    | l :: ls ->
        Ttf.size_utf8 f.font l >>= fun (w, h) -> measure ((l, w, h) :: acc) ls
  in
  measure [] lines >>= fun dims ->
  let max_w   = List.fold_left (fun m (_,w,_) -> max m w) 0 dims in
  let total_h = List.fold_left (fun s (_,_,h) -> s + h) 0 dims in
  Sdl.create_rgb_surface_with_format ~w:max_w ~h:total_h
    ~depth:32 Sdl.Pixel.format_argb8888 >>= fun dst ->
  let y = ref 0 in
  let blit (line,w,h) =
    render_surface f.font line mode >>= fun surf ->
    let x = match align with
      | Left -> 0 | Center -> (max_w - w)/2 | Right -> max_w - w in
    let rect = Sdl.Rect.create ~x ~y:!y ~w ~h in
    Sdl.blit_surface ~src:surf None ~dst (Some rect) >>= fun () ->
    y := !y + h;
    Sdl.free_surface surf; Ok ()
  in
  List.fold_left (fun acc d -> acc >>= fun () -> blit d) (Ok ()) dims >>= fun () ->
  image_from_surface dst >>= fun img ->
  Sdl.free_surface dst; Ok img

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

let set_style   f lst = Ttf.set_font_style   f.font (ttf_style_of_list lst)
let get_style   f     = list_of_ttf_style (Ttf.get_font_style f.font)
let set_hinting f h   = Ttf.set_font_hinting f.font (ttf_hint h)
let get_hinting f     = hint_of_ttf (Ttf.get_font_hinting f.font)
let set_kerning f b   = Ttf.set_font_kerning f.font b
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

let destroy f = Ttf.close_font f.font
