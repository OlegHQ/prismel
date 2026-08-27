let save_png ~logical_width ~logical_height ~factor
    ?(background = Color.black) ~camera scene filename =
  if logical_width <= 0 || logical_height <= 0 then
    invalid_arg "Render2.save_png: logical dimensions must be positive";
  if factor <= 0 then invalid_arg "Render2.save_png: factor must be positive";
  let width = logical_width * factor and height = logical_height * factor in
  let viewport = 0, 0, width, height in
  let scene =
    Scene.(clear background
      :: Easy_camera2.scene ~viewport ~pixel_scale:(float_of_int factor)
           camera scene)
  in
  match Scene.Private.to_ir scene with
  | Error _ as error -> error
  | Ok ir ->
      let target = Raster2.Offscreen.create ~width ~height () |> Result.get_ok in
      Fun.protect ~finally:(fun () -> ignore (Raster2.Offscreen.destroy target))
        (fun () ->
          let view = Raster2.Offscreen.view target |> Result.get_ok in
          Fun.protect
            ~finally:(fun () -> ignore (Raster2.Offscreen.release_view view))
            (fun () ->
              let surfaces = Hashtbl.create 16 in
              let lookup id = Hashtbl.find_opt surfaces id in
              List.iter
                (fun (id, resource) ->
                  match resource with
                  | Prismel_next_execution.Image image ->
                      let width, height =
                        Prismel_next_resources.Image.size image |> Result.get_ok
                      in
                      let bytes =
                        Prismel_next_resources.Image.pixels image |> Result.get_ok
                      in
                      let surface =
                        Raster2.Surface.of_bytes ~width ~height
                          ~pitch:(width * 4) bytes
                        |> Result.get_ok
                      in
                      Hashtbl.replace surfaces id (Raster2.Consumer.Image surface)
                  | Text _ | Canvas _ -> ())
                (Scene.Private.resources scene);
              match Raster2.Offscreen.render view ~lookup ir with
              | Error _ -> Error "Render2.save_png: Raster2 render failed"
              | Ok () ->
                  let capture = Raster2.Offscreen.capture view |> Result.get_ok in
                  let canvas = Canvas.create_exn ~width ~height in
                  Fun.protect ~finally:(fun () -> Canvas.destroy canvas) (fun () ->
                    Canvas.map_pixels canvas (fun ~x ~y _ ->
                      let offset = (y * capture.pitch) + (x * 4) in
                      Color.rgba
                        (Char.code (Bytes.get capture.pixels offset))
                        (Char.code (Bytes.get capture.pixels (offset + 1)))
                        (Char.code (Bytes.get capture.pixels (offset + 2)))
                        (Char.code (Bytes.get capture.pixels (offset + 3))));
                    Canvas.save_png canvas filename)))
