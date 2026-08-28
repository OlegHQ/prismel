open Tsdl

type t = {
  surface : Sdl.surface;
  renderer : Sdl.renderer;
  width : int;
  height : int;
  mutable destroyed : bool;
  mutable mutation : int64;
  mutable snapshot : (int * int * bytes * int64) option;
}

let require_main_domain () =
  if not (Domain.is_main_domain ()) then
    invalid_arg "Canvas operations must run on the main domain"

let ensure canvas =
  require_main_domain ();
  if canvas.destroyed then invalid_arg "Canvas has been destroyed"

let result_message prefix = function
  | Ok value -> Ok value
  | Error (`Msg message) -> Error (prefix ^ ": " ^ message)

let create ~width ~height =
  require_main_domain ();
  if width <= 0 || height <= 0 then
    Error "Canvas.create: dimensions must be positive"
  else
    match Sdl.create_rgb_surface_with_format ~w:width ~h:height ~depth:32
        Sdl_compat.format_rgba32 with
    | Error (`Msg message) -> Error ("Canvas surface creation failed: " ^ message)
    | Ok surface ->
        (match Sdl.create_software_renderer surface with
         | Error (`Msg message) ->
             Sdl.free_surface surface;
             Error ("Canvas renderer creation failed: " ^ message)
         | Ok renderer ->
             ignore (Sdl.set_render_draw_blend_mode renderer Sdl.Blend.mode_blend);
             ignore (Sdl.set_render_draw_color renderer 0 0 0 0);
             ignore (Sdl.render_clear renderer);
             Ok { surface; renderer; width; height; destroyed = false;
               mutation = 1L; snapshot = None })

let create_exn ~width ~height =
  match create ~width ~height with
  | Ok canvas -> canvas
  | Error message -> failwith message

let width canvas = ensure canvas; canvas.width
let height canvas = ensure canvas; canvas.height
let size canvas = width canvas, height canvas

let restore_sdl_clip renderer clip =
  let rect =
    Option.map
      (fun (x, y, w, h) -> Sdl.Rect.create ~x ~y ~w ~h)
      clip
  in
  ignore (Sdl.render_set_clip_rect renderer rect)

let render canvas scene =
  ensure canvas;
  let previous = !Graphics.graphics_state in
  let previous_image_renderer = !Image.Private.current_renderer in
  Graphics.graphics_state := {
    renderer = Some canvas.renderer;
    current_color = Color.white;
    transform_stack = Stack.create ();
    current_transform = Mat3.identity;
    current_clip = None;
  };
  Image.Private.set_renderer canvas.renderer;
  Fun.protect
    ~finally:(fun () ->
      Graphics.graphics_state := previous;
      Image.Private.current_renderer := previous_image_renderer;
      Option.iter
        (fun renderer -> restore_sdl_clip renderer previous.current_clip)
        previous.renderer)
    (fun () ->
      Scene.render scene;
      Sdl.render_present canvas.renderer;
      canvas.mutation <- Int64.succ canvas.mutation)

let with_pixels canvas operation =
  ensure canvas;
  match Sdl.lock_surface canvas.surface with
  | Error (`Msg message) -> failwith ("Canvas pixel lock failed: " ^ message)
  | Ok () ->
      Fun.protect
        ~finally:(fun () -> Sdl.unlock_surface canvas.surface)
        (fun () ->
          operation
            (Sdl.get_surface_pixels canvas.surface Bigarray.int32)
            (Sdl.get_surface_pitch canvas.surface / 4))

let with_format operation =
  match
    Sdl.alloc_format Sdl_compat.format_rgba32
  with
  | Error (`Msg message) -> failwith ("Canvas pixel format failed: " ^ message)
  | Ok format -> Fun.protect ~finally:(fun () -> Sdl.free_format format)
      (fun () -> operation format)

let color_of_pixel format pixel =
  let r, g, b, a = Sdl.get_rgba format pixel in
  Color.rgba r g b a

let pixel_of_color format color =
  let r, g, b, a = Color.to_tuple color in
  Sdl.map_rgba format r g b a

let pixel canvas ~x ~y =
  ensure canvas;
  if x < 0 || y < 0 || x >= canvas.width || y >= canvas.height then None
  else
    with_format (fun format ->
      with_pixels canvas (fun values stride ->
        Some (color_of_pixel format values.{(y * stride) + x})))

let pixels canvas =
  with_format (fun format ->
    with_pixels canvas (fun values stride ->
      Array.init (canvas.width * canvas.height) (fun index ->
        let x = index mod canvas.width and y = index / canvas.width in
        color_of_pixel format values.{(y * stride) + x})))

let set_pixel canvas ~x ~y color =
  ensure canvas;
  if x < 0 || y < 0 || x >= canvas.width || y >= canvas.height then
    invalid_arg "Canvas.set_pixel: coordinate outside canvas";
  with_format (fun format ->
    with_pixels canvas (fun values stride ->
      values.{(y * stride) + x} <- pixel_of_color format color));
  canvas.mutation <- Int64.succ canvas.mutation

let map_pixels canvas transform =
  with_format (fun format ->
    with_pixels canvas (fun values stride ->
      for y = 0 to canvas.height - 1 do
        for x = 0 to canvas.width - 1 do
          let index = (y * stride) + x in
          values.{index} <-
            pixel_of_color format
              (transform ~x ~y (color_of_pixel format values.{index}))
        done
      done));
  canvas.mutation <- Int64.succ canvas.mutation

let apply_mask ~source ~mask =
  ensure source;
  ensure mask;
  if source.width <> mask.width || source.height <> mask.height then
    invalid_arg "Canvas.apply_mask: canvas dimensions must match";
  with_format (fun format ->
    with_pixels source (fun source_values source_stride ->
      with_pixels mask (fun mask_values mask_stride ->
        for y = 0 to source.height - 1 do
          for x = 0 to source.width - 1 do
            let source_index = (y * source_stride) + x in
            let mask_index = (y * mask_stride) + x in
            let source_color =
              color_of_pixel format source_values.{source_index}
            in
            let mask_alpha =
              (color_of_pixel format mask_values.{mask_index}).a
            in
            source_values.{source_index} <-
              pixel_of_color format
                { source_color with
                  a = (source_color.a * mask_alpha + 127) / 255;
                }
          done
        done)));
  source.mutation <- Int64.succ source.mutation

let synchronize_snapshot canvas =
  match canvas.snapshot with
  | Some (_, _, _, generation) when generation = canvas.mutation ->
      Ok (Option.get canvas.snapshot)
  | _ ->
      match Image_snapshot.rgba_of_surface canvas.surface with
      | Error message ->
          begin match canvas.snapshot with
          | Some snapshot -> Ok snapshot
          | None -> Error ("Canvas snapshot failed: " ^ message)
          end
      | Ok (width, height, rgba) ->
          let snapshot = width, height, rgba, canvas.mutation in
          canvas.snapshot <- Some snapshot;
          Ok snapshot

let to_image canvas =
  ensure canvas;
  match Image.Private.get_renderer () with
  | Error message -> Error message
  | Ok renderer ->
      (match synchronize_snapshot canvas with
       | Error _ as error -> error
       | Ok (width, height, rgba, generation) ->
       match Sdl.create_texture_from_surface renderer canvas.surface with
       | Error (`Msg message) -> Error ("Canvas texture upload failed: " ^ message)
       | Ok texture ->
           let image = Image.Private.from_texture texture canvas.width canvas.height in
           Image_snapshot.register_generation (Obj.repr image) ~generation
             ~width ~height rgba;
           Ok image)

let save_png canvas filename =
  ensure canvas;
  if Tsdl_image.Image.save_png canvas.surface filename = 0 then Ok ()
  else Error ("PNG save failed: " ^ Sdl.get_error ())

let capture () =
  require_main_domain ();
  (* SDL reads the complete native render target here, which is larger than
     the logical window on high-DPI displays. *)
  let width, height = Window.drawable_size () in
  match create ~width ~height with
  | Error _ as error -> error
  | Ok canvas ->
      (match Image.Private.get_renderer () with
       | Error message ->
           Renderer3d.release_renderer canvas.renderer;
           Sdl.destroy_renderer canvas.renderer;
           Sdl.free_surface canvas.surface;
           Error message
       | Ok renderer ->
           let read_result =
             with_pixels canvas (fun values _stride ->
               result_message "Screen capture failed"
                 (Sdl.render_read_pixels renderer None
                    (Some Sdl_compat.format_rgba32) values
                    (Sdl.get_surface_pitch canvas.surface)))
           in
           match read_result with
           | Ok () -> Ok canvas
           | Error message ->
               Renderer3d.release_renderer canvas.renderer;
               Sdl.destroy_renderer canvas.renderer;
               Sdl.free_surface canvas.surface;
               Error message)

let save_screen_png filename =
  match capture () with
    | Error _ as error -> error
    | Ok canvas ->
        Fun.protect ~finally:(fun () ->
          Renderer3d.release_renderer canvas.renderer;
          Font.release_renderer canvas.renderer;
          Sdl.destroy_renderer canvas.renderer;
          Sdl.free_surface canvas.surface;
          canvas.destroyed <- true)
          (fun () -> save_png canvas filename)

let destroy canvas =
  require_main_domain ();
  if not canvas.destroyed then begin
    Renderer3d.release_renderer canvas.renderer;
    Font.release_renderer canvas.renderer;
    Sdl.destroy_renderer canvas.renderer;
    Sdl.free_surface canvas.surface;
    canvas.snapshot <- None;
    canvas.destroyed <- true
  end
