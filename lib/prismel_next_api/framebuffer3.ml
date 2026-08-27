type t = {
  width : int;
  height : int;
  colors : Color.t array;
  color : Texture.t;
  depths : float array;
  stencils : int array;
}

let require_main_domain () =
  if not (Domain.is_main_domain ()) then
    invalid_arg "Framebuffer3 operations must run on the initial domain"

let render ~width ~height ~camera scene =
  require_main_domain ();
  if width <= 0 || height <= 0 then
    invalid_arg "Framebuffer3.render: dimensions";
  let resources = Scene3_raster2_resources.create () in
  let surface, depth =
    Fun.protect
      ~finally:(fun () -> Scene3_raster2_resources.destroy resources)
      (fun () ->
        let prepared =
          match
            Scene3_raster2_lowering.prepare
              ~resources:(Scene3_raster2_resources.callbacks resources)
              ~camera ~viewport:(0, 0, width, height) scene
          with
          | Ok value -> value
          | Error _ -> failwith "Framebuffer3.render: Scene3 lowering failed"
        in
        let surface =
          Raster2.Surface.create ~width ~height () |> Result.get_ok
        and depth =
          Raster2.Depth_stencil.create ~width ~height () |> Result.get_ok
        in
        let multisample =
          if prepared.samples = 1 then None
          else
            Some
              (Raster2.Multisample.create ~width ~height
                 ~samples:prepared.samples ()
               |> Result.get_ok)
        in
        let target : Raster2.Scene3_consumer.target =
          { color = surface; depth = Some depth; multisample }
        in
        (match
           Raster2.Scene3_consumer.render ~target ~clear:0x00000000l
             ~clear_depth:prepared.clear_depth
             ~clear_stencil:prepared.clear_stencil ~draws:prepared.draws
         with
         | Ok () -> ()
         | Error _ -> failwith "Framebuffer3.render: Raster2 execution failed");
        surface, depth)
  in
  let bytes = Raster2.Surface.bytes surface in
  let colors =
    Array.init (width * height) (fun index ->
      let offset = index * 4 in
      Color.rgba (Char.code (Bytes.get bytes offset))
        (Char.code (Bytes.get bytes (offset + 1)))
        (Char.code (Bytes.get bytes (offset + 2)))
        (Char.code (Bytes.get bytes (offset + 3))))
  in
  let depths = Array.make (width * height) 1.
  and stencils = Array.make (width * height) 0 in
  Array.iteri
    (fun index _ ->
      match
        Raster2.Depth_stencil.get depth ~x:(index mod width) ~y:(index / width)
      with
      | Ok (d, s) ->
          depths.(index) <- d;
          stencils.(index) <- s
      | Error _ -> ())
    depths;
  {
    width;
    height;
    colors;
    color =
      Texture.Private.create_owned ~width ~height
        colors
      |> Result.get_ok;
    depths;
    stencils;
  }

let width target = target.width
let height target = target.height
let size target = target.width, target.height
let color target = target.color

let attachment_pixel target values ~x ~y =
  if x < 0 || y < 0 || x >= target.width || y >= target.height then None
  else Some values.((y * target.width) + x)

let color_pixel target = attachment_pixel target target.colors
let depth target = attachment_pixel target target.depths
let stencil target = attachment_pixel target target.stencils
let depths target = Array.copy target.depths
let stencils target = Array.copy target.stencils

let shadow ?bias ?normal_bias ?filter ?strength ~light ~camera target =
  Shadow3.create ?bias ?normal_bias ?filter ?strength
    ~light ~camera ~width:target.width ~height:target.height
    ~depths:target.depths ()

let to_canvas target =
  require_main_domain ();
  match Canvas.create ~width:target.width ~height:target.height with
  | Error _ as error -> error
  | Ok canvas ->
      (try
         Canvas.map_pixels canvas (fun ~x ~y _ ->
           target.colors.((y * target.width) + x));
         Ok canvas
       with exn ->
         Canvas.destroy canvas;
         Error ("Framebuffer3.to_canvas: " ^ Printexc.to_string exn))

let to_image target =
  match to_canvas target with
  | Error _ as error -> error
  | Ok canvas ->
      Fun.protect
        ~finally:(fun () -> Canvas.destroy canvas)
        (fun () -> Canvas.to_image canvas)
