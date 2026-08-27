open Tsdl

(* -------------------------------------------------------------------------
   Public type
   ------------------------------------------------------------------------- *)

type t = {
  mutable texture : Sdl.texture;
  mutable width   : int;
  mutable height  : int;
  mutable destroyed : bool;
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

let rgba_of_surface source =
  match Sdl.convert_surface_format source Sdl_compat.format_rgba32 with
  | Error (`Msg message) -> Error ("Failed to convert image: " ^ message)
  | Ok surface ->
      Fun.protect ~finally:(fun () -> Sdl.free_surface surface) (fun () ->
        let width, height = Sdl.get_surface_size surface in
        match Sdl.lock_surface surface with
        | Error (`Msg message) -> Error ("Failed to lock image: " ^ message)
        | Ok () -> Fun.protect ~finally:(fun () -> Sdl.unlock_surface surface)
            (fun () ->
              match Sdl.alloc_format Sdl_compat.format_rgba32 with
              | Error (`Msg message) -> Error message
              | Ok format -> Fun.protect ~finally:(fun () -> Sdl.free_format format)
                  (fun () ->
                    let values = Sdl.get_surface_pixels surface Bigarray.int32
                    and stride = Sdl.get_surface_pitch surface / 4 in
                    let rgba = Bytes.create (width * height * 4) in
                    for y = 0 to height - 1 do
                      for x = 0 to width - 1 do
                        let r, g, b, a = Sdl.get_rgba format values.{y * stride + x} in
                        let offset = (y * width + x) * 4 in
                        Bytes.set rgba offset (Char.chr r);
                        Bytes.set rgba (offset + 1) (Char.chr g);
                        Bytes.set rgba (offset + 2) (Char.chr b);
                        Bytes.set rgba (offset + 3) (Char.chr a)
                      done
                    done;
                    Ok (width, height, rgba))))

let from_surface renderer source =
  match rgba_of_surface source with
  | Error _ as failure -> failure
  | Ok (width, height, rgba) ->
      match Sdl.create_texture_from_surface renderer source with
      | Error (`Msg message) -> Error ("Failed to upload image: " ^ message)
      | Ok texture ->
          let value = { texture; width; height; destroyed = false } in
          Image_snapshot.register (Obj.repr value) ~width ~height rgba;
          Ok value

let load filename =
  match get_renderer () with
  | Error _ as e -> e
  | Ok renderer ->
      begin
        match Tsdl_image.Image.load filename with
        | Error (`Msg e) -> Error ("Failed to load image: " ^ e)
        | Ok surface -> Fun.protect ~finally:(fun () -> Sdl.free_surface surface)
            (fun () -> from_surface renderer surface)
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
           match Tsdl_image.Image.load_rw rw true with
           | Error (`Msg message) ->
               Error ("Failed to decode image memory: " ^ message)
           | Ok surface -> Fun.protect ~finally:(fun () -> Sdl.free_surface surface)
               (fun () -> from_surface renderer surface))

(* -------------------------------------------------------------------------
   In-memory creation
   ------------------------------------------------------------------------- *)

let create ~width ~height ?(color = Color.transparent) () =
  match get_renderer () with
  | Error e -> failwith e
  | Ok renderer ->
      (* create a 32-bit RGBA software surface *)
      begin
        match Sdl.create_rgb_surface_with_format ~w:width ~h:height ~depth:32
            Sdl_compat.format_rgba32 with
        | Error (`Msg e) -> failwith ("Surface create failed: " ^ e)
        | Ok surface ->
            (* optional fill *)
            (if not (Color.equal color Color.transparent) then
               match Sdl.alloc_format Sdl_compat.format_rgba32 with
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
                  let rgba = match rgba_of_surface surface with
                    | Ok (_, _, rgba) -> rgba
                    | Error message ->
                        Sdl.destroy_texture texture;
                        Sdl.free_surface surface;
                        failwith message
                  in
                  Sdl.free_surface surface;
                  let value = { texture; width; height; destroyed = false } in
                  Image_snapshot.register (Obj.repr value) ~width ~height rgba;
                  value
            end
      end

(* -------------------------------------------------------------------------
   Misc helpers
   ------------------------------------------------------------------------- *)

let destroy img =
  if not img.destroyed then begin
    img.destroyed <- true;
    Image_snapshot.remove (Obj.repr img);
    Sdl.destroy_texture img.texture
  end
let get_width img         = img.width
let get_height img        = img.height
let get_size img          = (img.width, img.height)
let get_texture img       = img.texture
let from_texture texture width height =
  { texture; width; height; destroyed = false }

let replace target replacement =
  if target != replacement then begin
    Sdl.destroy_texture target.texture;
    target.texture <- replacement.texture;
    target.width <- replacement.width;
    target.height <- replacement.height;
    target.destroyed <- false;
    Image_snapshot.replace ~target:(Obj.repr target)
      ~replacement:(Obj.repr replacement);
    replacement.destroyed <- true
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
