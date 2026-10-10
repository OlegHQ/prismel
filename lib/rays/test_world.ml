open Rays

let check name ok = if not ok then failwith ("test_world: " ^ name)

let same_bits a b =
  Float.Array.length a = Float.Array.length b
  && (let ok = ref true in
      Float.Array.iteri (fun i x ->
        if Int64.bits_of_float x <> Int64.bits_of_float (Float.Array.get b i)
        then ok := false) a;
      !ok)

let same_baked (a : World.baked) (b : World.baked) =
  same_bits a.camera.pixels b.camera.pixels
  && same_bits a.lighting.pixels b.lighting.pixels
  && same_bits a.cdf.marginal b.cdf.marginal
  && same_bits a.cdf.conditional b.cdf.conditional
  && Array.for_all2 (fun (x : World.map) (y : World.map) -> same_bits x.pixels y.pixels)
       a.specular b.specular
  && a.sh9 = b.sh9 && a.lights = b.lights && a.sun = b.sun

let entry layer = { World.name = "layer"; layer; visible = true }
let with_layers layers = { World.default with layers = List.map entry layers }
let dark v = World.Gradient { zenith = World.rgb v v v; horizon = World.rgb v v v;
                              nadir = World.rgb v v v; sharpness = 1. }

let scatter ?(mirror = false) ?(emit = World.Dome) seed =
  World.Scatter { seed; count = 12; elevation_min = 0.1; elevation_max = 1.;
                  size_min = 0.1; size_max = 0.3; palette = [ World.rgb 1. 0.5 0.2 ];
                  intensity = 3.; mirror; emit }

let domains () =
  List.iter (fun (name, world) ->
    let bake domains = World.bake ~domains ~width:96 ~height:48 world in
    check ("domains " ^ name) (same_baked (bake 1) (bake 4))) World.presets

let seeds () =
  let bake seed = World.bake ~domains:1 ~width:64 ~height:32
      (with_layers [ dark 0.; scatter seed ]) in
  check "same seed" (same_baked (bake 3) (bake 3));
  check "different seed"
    (not (same_bits (bake 3).camera.pixels (bake 4).camera.pixels))

let promoted () =
  let manual = `Manual (1., 0.5) and sun = World.Sun {
      angular_radius = 0.05; intensity = 50.; tint = World.rgb 1. 1. 0.9 } in
  let rect = World.Shape { shape = Rect; azimuth = -0.8; elevation = 0.2;
                           width = 0.6; height = 0.3; softness = 0.1;
                           color = World.rgb 0.2 1. 0.4; intensity = 5.; emit = Light } in
  let circle = World.Shape { shape = Circle; azimuth = 2.; elevation = 0.; width = 0.5;
                             height = 0.; softness = 0.1; color = World.rgb 1. 1. 1.;
                             intensity = 2.; emit = Dome } in
  let world layers = { (with_layers layers) with sun = manual; rotation = 0.3 } in
  let full = World.bake ~width:128 ~height:64
      (world [ dark 0.2; rect; scatter ~mirror:true ~emit:Light 5; circle; sun ])
  and only = World.bake ~width:128 ~height:64
      (world [ rect; scatter ~emit:Light 5; sun ]) in
  let p = Float.Array.length full.camera.pixels in
  for k = 0 to p - 1 do
    let cam = Float.Array.get full.camera.pixels k in
    let diff = cam -. Float.Array.get full.lighting.pixels k in
    check "lighting of promoted-only is black" (Float.Array.get only.lighting.pixels k = 0.);
    check "camera - lighting = promoted + disc"
      (Float.abs (diff -. Float.Array.get only.camera.pixels k) <= 1e-9 *. (1. +. cam))
  done;
  check "some promoted radiance"
    (Float.Array.fold_left ( +. ) 0. only.camera.pixels > 0.);
  check "light count" (List.length full.lights = 13);
  check "sun extracted" (full.sun <> None);
  let room emit = World.bake ~width:64 ~height:32 (with_layers [
      World.Room { width = 6.; depth = 8.; height = 3.; rows = 2; columns = 3; panel = 0.5;
                   intensity = 4.; wall = World.rgb 0.8 0.8 0.8; cove = 1.; emit } ]) in
  let lit = room Light and dome = room Dome in
  check "room camera independent of emit" (same_bits lit.camera.pixels dome.camera.pixels);
  check "room dome lighting = camera" (same_bits dome.lighting.pixels dome.camera.pixels);
  check "room panels leave lighting"
    (Float.Array.fold_left ( +. ) 0. lit.lighting.pixels
     < Float.Array.fold_left ( +. ) 0. lit.camera.pixels);
  check "room panel lights" (List.length lit.lights = 6 && dome.lights = [])

let cached () =
  let a = World.bake_cached ~width:32 ~height:16 World.default in
  let b = World.bake_cached ~width:32 ~height:16 { World.default with exposure = 2. } in
  check "exposure-only change hits the cache" (a.camera == b.camera && b.exposure = 2.)

let run () =
  domains (); seeds (); promoted (); cached ()
