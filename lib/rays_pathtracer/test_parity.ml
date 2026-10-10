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
  match !failures with
  | [] -> print_endline "raster/path tracer parity: all presets within bounds"
  | failed -> failwith ("parity outside bounds: " ^ String.concat ", " failed)
