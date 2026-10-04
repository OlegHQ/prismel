(* Raster/path tracer parity (plan D15): each built-in World lights a matte
   and a glossy probe; the raster World path must land near the converged
   path tracer in mean probe luminance and in where the brightest highlight
   sits. Qualification only: it converges hundreds of samples per preset. *)
open Rays
module P = Rays_pathtracer

let get = function Ok v -> v | Error e -> failwith e
let width = 128 and height = 64
let camera = Camera.perspective ~fov_y:0.5 ~at:(Vec3.create 0. 0. 7.) ~target:Vec3.zero ()
let probes = [| Vec3.create (-1.3) 0. 0.; Vec3.create 1.3 0. 0. |]

(* Both renderers see the same surfaces: raster's Material mapping gives
   albedo = diffuse (sRGB decoded), roughness = sqrt (2 / (shininess + 2)). *)
let gray = 200
let albedo = Float.pow (float_of_int gray /. 255.) 2.2
let shininess = [| 1.; 2000. |]
let roughness s = Float.min 1. (sqrt (2. /. (s +. 2.)))

let raster baked =
  let canvas = Canvas.create_exn ~width ~height in
  Fun.protect ~finally:(fun () -> Canvas.destroy canvas) (fun () ->
    let sphere index = Scene3.translate probes.(index) [Scene3.sphere ~radius:1.
        ~material:(Material.create ~diffuse:(Color.gray gray) ~ambient:Color.black
          ~specular:Color.white ~shininess:shininess.(index) ()) ()] in
    Canvas.render canvas [Scene.clear Color.black;
      Scene.view3d ~camera (Scene3.with_world baked
        (Scene3.create [sphere 0; sphere 1]))];
    Bytes.init (width * height * 4) (fun index ->
      let pixel = index / 4 in
      let c = Option.get (Canvas.pixel canvas ~x:(pixel mod width) ~y:(pixel / width)) in
      Char.chr (match index mod 4 with 0 -> c.r | 1 -> c.g | 2 -> c.b | _ -> 255)))

let traced baked =
  let spheres = Array.to_list (Array.mapi (fun index center ->
      P.sphere ~radius:1. (P.material ~roughness:(roughness shininess.(index))
        (P.Linear_color.rgb albedo albedo albedo)) center) probes) in
  let t = get (P.create ~spp:8 ~bounces:4 ~width ~height
      { P.objects = []; spheres; strands = [];
        environment = { sky = P.Linear_color.rgb 0. 0. 0.;
          ground = P.Linear_color.rgb 0. 0. 0.; panels = [] }; lights = [] }) in
  Fun.protect ~finally:(fun () -> P.destroy t) (fun () ->
    get (P.set_world t (Some baked));
    for _ = 1 to 64 do get (P.render t camera); get (P.flush t) done;
    Bytes.copy (get (P.pixels t)))

(* Pixels inside each probe's disc on screen. *)
let disc index =
  let center = Option.get (Camera.world_to_screen ~viewport:(0, 0, width, height)
      camera probes.(index)) in
  let edge = Option.get (Camera.world_to_screen ~viewport:(0, 0, width, height)
      camera (Vec3.add probes.(index) (Vec3.create 0.9 0. 0.))) in
  let radius = Float.abs (edge.x -. center.x) in
  List.concat (List.init height (fun y -> List.filter_map (fun x ->
    if Float.hypot (float x +. 0.5 -. center.x) (float y +. 0.5 -. center.y) < radius
    then Some (x, y) else None) (List.init width Fun.id)))

let luminance bytes (x, y) =
  let at channel = float_of_int (Char.code (Bytes.get bytes (4 * (y * width + x) + channel))) in
  0.2126 *. at 0 +. 0.7152 *. at 1 +. 0.0722 *. at 2

let mean bytes pixels =
  List.fold_left (fun sum p -> sum +. luminance bytes p) 0. pixels
  /. float_of_int (List.length pixels)

(* Where the highlight sits: the centroid of the pixels within 10% of the
   probe's brightest, robust to several equally bright reflections. *)
let brightest bytes pixels =
  let peak = List.fold_left (fun peak p -> Float.max peak (luminance bytes p)) 0. pixels in
  let low = mean bytes pixels in
  let bright = List.filter (fun p -> luminance bytes p >= peak -. (0.1 *. (peak -. low)))
      pixels in
  let n = float_of_int (List.length bright) in
  List.fold_left (fun (x, y) (px, py) -> x +. float px /. n, y +. float py /. n) (0., 0.) bright

let run () =
  let failures = ref [] in
  List.iter (fun (name, world) ->
    let baked = World.bake ~width:256 ~height:128 world in
    let raster = raster baked and traced = traced baked in
    Array.iteri (fun index label ->
      let pixels = disc index in
      let r = mean raster pixels and t = mean traced pixels in
      let (rx, ry) = brightest raster pixels and (tx, ty) = brightest traced pixels in
      let offset = Float.hypot (rx -. tx) (ry -. ty) in
      let relative = Float.abs (r -. t) /. Float.max 8. t in
      Printf.printf "parity %-14s %-6s raster %6.1f traced %6.1f (%4.1f%%) highlight %4.1f px\n%!"
        name label r t (100. *. relative) offset;
      (* Measured on the M1: luminance within 2.8%, highlights within 6 px
         except the glossy probe under neon strips (15.7 px). ponytail:
         raster reflections read the environment without occlusion, so the
         glossy probe also mirrors strips the matte probe hides from the
         traced one; screen-space or traced reflections would lift it. *)
      if relative > 0.05 then failures := (name ^ " " ^ label ^ " luminance") :: !failures;
      if index = 1 && offset > 20. then
        failures := (name ^ " " ^ label ^ " highlight") :: !failures)
      [| "matte"; "glossy" |]) World.presets;
  match !failures with
  | [] -> print_endline "raster/path tracer parity: all presets within bounds"
  | failed -> failwith ("parity outside bounds: " ^ String.concat ", " failed)
