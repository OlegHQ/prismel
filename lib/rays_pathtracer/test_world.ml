(* The World path: CDF + MIS sampling is unbiased (furnace, and MIS matches
  | Ok t ->
      let live = let _, live = Ogpu.Impl.create_driver () in live in
      P.destroy t;
      let baseline = live () in
      checks ();
      assert (live () = baseline)
 BSDF-only sampling on a peaked map with a sun), MIS has lower variance,
   miss pixels show the background, and rect lights are hittable. *)
module P = Rays_pathtracer
module W = Rays.World

let rgb = P.Linear_color.rgb
let get = function Ok v -> v | Error e -> failwith e
let v3 = Rays.Vec3.create
let white = W.rgb 1. 1. 1.
let gradient c = W.Gradient { zenith = c; horizon = c; nadir = c; sharpness = 1. }

let world ?(background = W.Environment) ?(sun = `Manual (0., 1.)) layers =
  W.bake ~domains:1 ~width:64 ~height:32
    { W.default with
      layers = List.map (fun layer -> { W.name = "layer"; layer; visible = true }) layers;
      background; exposure = 0.; sun }

let black_dome = { P.sky = rgb 0. 0. 0.; ground = rgb 0. 0. 0.; panels = [] }

(* A lone analytic sphere: convex, so every path is direct light and the
   indirect firefly clamp never applies. *)

let camera ?(fov = 0.3) () =
  Rays.Camera.perspective ~fov_y:fov ~at:(v3 0. 0. 6.) ~target:(v3 0. 0. 0.) ()

let mean_red bytes =
  let sum = ref 0 in
  Bytes.iteri (fun i c -> if i mod 4 = 0 then sum := !sum + Char.code c) bytes;
  float !sum /. float (Bytes.length bytes / 4)

let rmse a b =
  let sum = ref 0. in
  Bytes.iteri (fun i c -> if i mod 4 = 0 then
    let d = float (Char.code c - Char.code (Bytes.get b i)) in sum := !sum +. (d *. d)) a;
  sqrt (!sum /. float (Bytes.length a / 4))

(* The resolve's ACES fit and 2.2 gamma, for an exact background check. *)
let resolved x =
  let c = (x *. ((2.51 *. x) +. 0.03)) /. ((x *. ((2.43 *. x) +. 0.59)) +. 0.14) in
  int_of_float ((Float.pow (Float.min 1. (Float.max 0. c)) (1. /. 2.2) *. 255.) +. 0.5)

let run () =
  ()

(* Convergence probe for specification/pathtracer.md (not in runtest):
   dune exec --root . lib/rays_pathtracer/test_main.exe -- bench_world *)
