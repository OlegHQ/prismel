open Tsdl

(* -------------------------------------------------------------------------
   Public type
   ------------------------------------------------------------------------- *)

type t = {
  mutable texture : Sdl.texture;
  mutable width   : int;
  mutable height  : int;
}

(* -------------------------------------------------------------------------
   Global renderer state
   ------------------------------------------------------------------------- *)

let current_renderer : Sdl.renderer option ref = ref None

let set_renderer r = current_renderer := Some r

let get_renderer () =
  match !current_renderer with
  | Some r -> Ok r
  | None   -> Error "No renderer set – call Image.set_renderer first."

(* -------------------------------------------------------------------------
   Loading helpers
   ------------------------------------------------------------------------- *)

let load filename =
  match get_renderer () with
  | Error _ as e -> e
  | Ok renderer ->
      begin
        match Tsdl_image.Image.load_texture renderer filename with
        | Error (`Msg e) -> Error ("Failed to load image: " ^ e)
        | Ok texture ->
            begin
              match Sdl.query_texture texture with
              | Error (`Msg e) ->
                  Sdl.destroy_texture texture;
                  Error ("Failed to query texture: " ^ e)
              | Ok (_, _, (w, h)) ->
                  Ok { texture; width = w; height = h }
            end
      end

let load_exn f = match load f with Ok x -> x | Error e -> failwith e

let load_memory bytes =
  match get_renderer () with
  | Error _ as error -> error
  | Ok renderer ->
      (match Sdl.rw_from_const_mem bytes with
       | Error (`Msg message) ->
           Error ("Failed to open image memory: " ^ message)
       | Ok rw ->
           match Tsdl_image.Image.load_texture_rw renderer rw true with
           | Error (`Msg message) ->
               Error ("Failed to decode image memory: " ^ message)
           | Ok texture ->
               match Sdl.query_texture texture with
               | Error (`Msg message) ->
                   Sdl.destroy_texture texture;
                   Error ("Failed to query image texture: " ^ message)
               | Ok (_, _, (width, height)) ->
                   Ok { texture; width; height })

(* -------------------------------------------------------------------------
   In-memory creation
   ------------------------------------------------------------------------- *)

let create ~width ~height ?(color = Color.transparent) () =
  match get_renderer () with
  | Error e -> failwith e
  | Ok renderer ->
      (* create a 32-bit RGBA software surface *)
      begin
        match Sdl.create_rgb_surface ~w:width ~h:height ~depth:32 0l 0l 0l 0l with
        | Error (`Msg e) -> failwith ("Surface create failed: " ^ e)
        | Ok surface ->
            (* optional fill *)
            (if not (Color.equal color Color.transparent) then
               match Sdl.alloc_format Sdl.Pixel.format_rgba8888 with
               | Error (`Msg e) ->
                   Sdl.free_surface surface;
                   failwith ("alloc_format failed: " ^ e)
               | Ok pf ->
                   let r, g, b, a = Color.to_tuple color in
                   let px = Sdl.map_rgba pf r g b a in
                   Sdl.free_format pf;
                   match Sdl.fill_rect surface None px with
                   | Error (`Msg e) ->
                       Sdl.free_surface surface;
                       failwith ("fill_rect failed: " ^ e)
                   | Ok () -> ());
            (* promote to texture *)
            begin
              match Sdl.create_texture_from_surface renderer surface with
              | Error (`Msg e) ->
                  Sdl.free_surface surface;
                  failwith ("Texture create failed: " ^ e)
              | Ok texture ->
                  Sdl.free_surface surface;
                  { texture; width; height }
            end
      end

(* -------------------------------------------------------------------------
   Misc helpers
   ------------------------------------------------------------------------- *)

let destroy img           = Sdl.destroy_texture img.texture
let get_width img         = img.width
let get_height img        = img.height
let get_size img          = (img.width, img.height)
let get_texture img       = img.texture
let from_texture texture width height = { texture; width; height }

let replace target replacement =
  if target != replacement then begin
    Sdl.destroy_texture target.texture;
    target.texture <- replacement.texture;
    target.width <- replacement.width;
    target.height <- replacement.height
  end

module Private = struct
  let current_renderer = current_renderer
  let set_renderer = set_renderer
  let get_renderer = get_renderer
  let get_texture = get_texture
  let from_texture = from_texture
  let load_memory = load_memory
  let replace = replace
end
