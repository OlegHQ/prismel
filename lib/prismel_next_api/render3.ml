let save_png ~width ~height ?(background = Color.black) ~camera scene filename =
  try
    let target=Framebuffer3.render~width~height~camera scene in
    let colors=Texture.pixels(Framebuffer3.color target)|>Array.of_list in
      (match Canvas.create ~width ~height with
       | Error _ as error -> error
       | Ok canvas ->
           Fun.protect ~finally:(fun () -> Canvas.destroy canvas) (fun () ->
             Canvas.map_pixels canvas (fun ~x ~y _ ->let source=colors.((y*width)+x)in
               Color.blend background source~pct:(float source.a/.255.));
             Canvas.save_png canvas filename))
  with exn->Error("Render3.save_png: "^Printexc.to_string exn)
