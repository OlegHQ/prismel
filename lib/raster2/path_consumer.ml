type transform = { xx : float; xy : float; yx : float; yy : float; tx : float; ty : float }
type clip = { x : int; y : int; width : int; height : int }
type antialias = Disabled | Supersample4
type style =
  | Fill of Path.fill_rule
  | Stroke of { width : float; cap : Path.cap; join : Path.join; miter_limit : float }
type error = Path_error of Path.error | Surface_error | Invalid_clip

let identity = { xx = 1.; xy = 0.; yx = 0.; yy = 1.; tx = 0.; ty = 0. }

let mesh ~path ~style ~tolerance =
  match style with
  | Fill fill_rule -> Path.tessellate ~tolerance ~fill_rule path
  | Stroke { width; cap; join; miter_limit } ->
      Path.stroke ~tolerance ~width ~cap ~join ~miter_limit path

let vertex scale transform color (point : Path.point) =
  let x = ((transform.xx *. point.x) +. (transform.xy *. point.y) +. transform.tx) *. scale
  and y = ((transform.yx *. point.x) +. (transform.yy *. point.y) +. transform.ty) *. scale in
  { Triangle.x; y; depth = 0.; color; u = 0.; v = 0. }

let render_mesh surface ~scale ~transform ~clip ~color ~blend (mesh : Path.mesh) =
  let vertices = Array.map (vertex scale transform color) mesh.vertices in
  let triangle_clip =
    { Triangle.x = int_of_float (float clip.x *. scale);
      y = int_of_float (float clip.y *. scale);
      width = int_of_float (float clip.width *. scale);
      height = int_of_float (float clip.height *. scale) }
  in
  let depth_state = Depth_stencil.{ depth_compare = Always; depth_write = false; stencil = None } in
  for i = 0 to (Array.length mesh.indices / 3) - 1 do
    Triangle.draw ~color:surface ~depth:None ~depth_state ~blend ~cull:Triangle.Cull_none
      ~clip:triangle_clip ~texture:None vertices.(mesh.indices.(3 * i))
      vertices.(mesh.indices.((3 * i) + 1)) vertices.(mesh.indices.((3 * i) + 2))
  done

let channel color shift = Int32.(to_int (logand (shift_right_logical color shift) 0xffl))
let rgba r g b a =
  Int32.(logor (shift_left (of_int r) 24)
    (logor (shift_left (of_int g) 16) (logor (shift_left (of_int b) 8) (of_int a))))

let resolve4 source target clip blend =
  let x0 = max 0 clip.x and y0 = max 0 clip.y in
  let x1 = min (Surface.width target) (clip.x + clip.width)
  and y1 = min (Surface.height target) (clip.y + clip.height) in
  for y = y0 to y1 - 1 do
    for x = x0 to x1 - 1 do
      let sum shift =
        let total = ref 0 in
        for sy = 0 to 1 do for sx = 0 to 1 do
          match Surface.get_rgba source ~x:((2 * x) + sx) ~y:((2 * y) + sy) with
          | Ok value -> total := !total + channel value shift
          | Error _ -> ()
        done done;
        (!total + 2) / 4
      in
      Composite.pixel target ~blend ~x ~y (rgba (sum 24) (sum 16) (sum 8) (sum 0))
    done
  done

let draw ~target ~path ~style ~tolerance ~transform ~clip ~color ~blend ~antialias =
  if clip.width < 0 || clip.height < 0 then Error Invalid_clip else
  match mesh ~path ~style ~tolerance with
  | Error error -> Error (Path_error error)
  | Ok mesh ->
      begin match antialias with
      | Disabled -> render_mesh target ~scale:1. ~transform ~clip ~color ~blend mesh; Ok ()
      | Supersample4 ->
          begin match Surface.create ~width:(2 * Surface.width target) ~height:(2 * Surface.height target) () with
          | Error _ -> Error Surface_error
          | Ok supersurface ->
              Surface.clear supersurface 0l;
              render_mesh supersurface ~scale:2. ~transform ~clip ~color ~blend:Composite.Copy mesh;
              resolve4 supersurface target clip blend;
              Ok ()
          end
      end
