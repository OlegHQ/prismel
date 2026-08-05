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
  let output = Renderer3d.rasterize ~width ~height ~camera scene in
  let colors = output.colors in
  {
    width = output.width;
    height = output.height;
    colors;
    color =
      Texture.Private.create_owned ~width:output.width ~height:output.height
        colors
      |> Result.get_ok;
    depths = output.depths;
    stencils = output.stencils;
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
