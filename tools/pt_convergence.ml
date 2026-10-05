(* Convergence dump of the path tracer on a Cornell box: one PNG per rung of a
   doubling sample ladder plus stats.csv (spp,seconds,file). The last rung is
   the reference. ../prismel-support/octane/convergence.py reads this layout
   and the one Octane's convergence.lua writes. *)
open Rays
module P = Rays_pathtracer

let get = function Ok value -> value | Error message -> failwith message
let rdk = function Ok g -> g | Error e -> failwith (Rdk.Error.to_string e)
let v = Vec3.create
let rgb = P.Linear_color.rgb

let dir, width, height = match Sys.argv with
  | [| _; dir |] -> dir, 600, 600
  | [| _; dir; width; height |] -> dir, int_of_string width, int_of_string height
  | _ -> failwith "usage: pt_convergence OUTPUT_DIR [WIDTH HEIGHT]"

let ladder = [2; 4; 8; 16; 32; 64; 128; 256; 1024]

(* A 2-unit room open towards +z, a tall and a short block, one ceiling light. *)
let scene =
  let box ?rotation ~center ~size albedo =
    rdk (Rdk.Box_generator.box ~center ?rotation ~size ()), P.material ~roughness:1. albedo in
  let white = rgb 0.73 0.73 0.73 in
  { P.objects =
      [ box ~center:(v 0. (-0.05) 0.) ~size:(v 2.2 0.1 2.) white
      ; box ~center:(v 0. 2.05 0.) ~size:(v 2.2 0.1 2.) white
      ; box ~center:(v 0. 1. (-1.05)) ~size:(v 2.2 2.2 0.1) white
      ; box ~center:(v (-1.05) 1. 0.) ~size:(v 0.1 2.2 2.) (rgb 0.65 0.05 0.05)
      ; box ~center:(v 1.05 1. 0.) ~size:(v 0.1 2.2 2.) (rgb 0.12 0.45 0.15)
      ; box ~center:(v (-0.35) 0.6 (-0.3)) ~rotation:(v 0. 0.3 0.) ~size:(v 0.6 1.2 0.6) white
      ; box ~center:(v 0.35 0.3 0.3) ~rotation:(v 0. (-0.3) 0.) ~size:(v 0.6 0.6 0.6) white ]
  ; spheres = []; strands = []
  ; environment = { sky = rgb 0. 0. 0.; ground = rgb 0. 0. 0.; panels = [] }
  ; lights = [ P.rect_light ~intensity:16. ~size:(0.5, 0.5) ~target:(v 0. 0. 0.) (v 0. 1.98 0.) ] }

let camera = Camera.perspective ~fov_y:0.69 ~at:(v 0. 1. 3.9) ~target:(v 0. 1. 0.) ()

let () =
  let tracer = P.create ~spp:1 ~bounces:6 ~width ~height scene |> get in
  let canvas = Canvas.create_exn ~width ~height in
  let step () = P.render tracer camera |> get; P.flush tracer |> get in
  Fun.protect ~finally:(fun () -> Canvas.destroy canvas; P.destroy tracer) (fun () ->
    (* Warm-up keeps first-frame setup out of the first rung. *)
    step (); P.reset tracer;
    Out_channel.with_open_text (Filename.concat dir "stats.csv") (fun csv ->
      output_string csv "spp,seconds,file\n";
      let elapsed = ref 0. in
      List.iter (fun samples ->
        let start = Unix.gettimeofday () in
        while P.samples tracer < samples do step () done;
        elapsed := !elapsed +. Unix.gettimeofday () -. start;
        let file = Printf.sprintf "%05d.png" samples in
        Canvas.render canvas [Scene.image (P.image tracer) ~at:(0, 0) ()];
        Canvas.save_png canvas (Filename.concat dir file) |> get;
        Printf.fprintf csv "%d,%.4f,%s\n%!" (P.samples tracer) !elapsed file;
        Printf.printf "%d spp in %.2f s\n%!" (P.samples tracer) !elapsed) ladder))
