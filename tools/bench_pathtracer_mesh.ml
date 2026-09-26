module P = Prismel_pathtracer
let rgb = P.Linear_color.rgb
let get = function Ok value -> value | Error error -> failwith (Pdk.Error.to_string error)
let v = Prismel.Vec3.create
let () =
  let cube = get (Pdk.Box_generator.box_checked ~size:(v 0.86 0.86 1.) ()) in
  let transforms = Array.init (36 * 60) (fun i ->
    Prismel.Mat4.mul
      (Prismel.Mat4.translation (v (float (i mod 36)) (float (i / 36)) 0.))
      (Prismel.Mat4.scaling (v 1. 1. (0.5 +. float (i mod 7))))) in
  let before = Gc.quick_stat () and start = Unix.gettimeofday () in
  let mesh = match P.mesh_instanced ~prototype:(cube, P.material (rgb 0.4 0.4 0.4)) transforms with
    | Ok value -> value | Error error -> failwith error in
  let elapsed = (Unix.gettimeofday () -. start) *. 1000. in
  let after = Gc.quick_stat () in
  Printf.printf "%d instances  %d triangles  %.1f ms  %.0f minor words  %.0f major words\n%!"
    (Array.length transforms) (P.triangle_count mesh) elapsed
    (after.minor_words -. before.minor_words) (after.major_words -. before.major_words);
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--flat" then begin
    let objects = Array.to_list (Array.map (fun matrix ->
      Pdk.Transform_ops.transform matrix cube, P.material (rgb 0.4 0.4 0.4)) transforms) in
    let before = Gc.quick_stat () and start = Unix.gettimeofday () in
    let flat = match P.mesh objects with Ok value -> value | Error error -> failwith error in
    let elapsed = (Unix.gettimeofday () -. start) *. 1000. in
    let after = Gc.quick_stat () in
    Printf.printf "flat: %d triangles  %.1f ms  %.0f minor words  %.0f major words\n%!"
      (P.triangle_count flat) elapsed
      (after.minor_words -. before.minor_words) (after.major_words -. before.major_words)
  end;
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--gpu" then begin
    let scene = { P.objects = [cube, P.material (rgb 0.4 0.4 0.4)]
      ; spheres = []; strands = []; environment = { sky = rgb 0. 0. 0.; ground = rgb 0. 0. 0.; panels = [] }
      ; lights = [] } in
    let tracer = match P.create ~width:32 ~height:32 scene with
      | Ok value -> value | Error error -> failwith error in
    let start = Unix.gettimeofday () in
    (match P.replace_mesh tracer mesh with Ok () -> () | Error error -> failwith error);
    Printf.printf "Metal upload and acceleration build %.1f ms\n%!"
      ((Unix.gettimeofday () -. start) *. 1000.);
    let start = Unix.gettimeofday () in
    (match P.queue_mesh tracer mesh with Ok () -> () | Error error -> failwith error);
    let queued = Unix.gettimeofday () in
    (match P.flush tracer with Ok () -> () | Error error -> failwith error);
    Printf.printf "queued edit: %.1f ms caller, %.1f ms remaining build wait\n%!"
      ((queued -. start) *. 1000.) ((Unix.gettimeofday () -. queued) *. 1000.);
    P.destroy tracer
  end;
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--compare-render" then begin
    let material = P.material ~roughness:0.6 ~round:0.07 (rgb 0.42 0.42 0.44) in
    let scene = { P.objects = [cube, material]
      ; spheres = []; strands = []; environment = { sky = rgb 0.006 0.007 0.009
                      ; ground = rgb 0.002 0.002 0.003; panels = [] }
      ; lights = [P.rect_light ~intensity:9. ~size:(24., 24.)
                    ~target:(v 17. 29. 0.) (v (-17.) 69. 30.)] } in
    let tracer = match P.create ~bounces:4 ~width:560 ~height:800 scene with
      | Ok value -> value | Error error -> failwith error in
    let camera = Prismel.Camera.perspective
      ~at:(v 17. (-50.) 30.) ~target:(v 17. 29. 1.) ~fov_y:0.7 () in
    let run name mesh =
      (match P.replace_mesh tracer mesh with Ok () -> () | Error error -> failwith error);
      let start = Unix.gettimeofday () in
      for _ = 1 to 64 do
        (match P.render tracer camera with Ok () -> () | Error error -> failwith error);
        (match P.flush tracer with Ok () -> () | Error error -> failwith error)
      done;
      Printf.printf "%s  %.1f ms/frame  %d spp\n%!" name
        ((Unix.gettimeofday () -. start) *. 1000. /. 64.) (P.samples tracer);
      Bytes.copy (P.pixels tracer) in
    let instanced = run "instance structure" mesh in
    let flat_objects = Array.to_list (Array.map (fun matrix ->
      Pdk.Transform_ops.transform matrix cube, material) transforms) in
    let flat = match P.mesh flat_objects with Ok value -> value | Error error -> failwith error in
    let flattened = run "flat triangles" flat in
    let max_delta = ref 0 in
    let changed = ref 0 and total_delta = ref 0 and signed_delta=ref 0 in
    Bytes.iteri (fun i byte ->
      let difference=Char.code byte - Char.code (Bytes.get instanced i)in
      let delta = abs difference in
      max_delta := max !max_delta delta;
      total_delta := !total_delta + delta;
      signed_delta:= !signed_delta+difference;
      if delta > 2 then incr changed) flattened;
    Printf.printf "maximum channel difference %d, >2: %d/%d, mean absolute %.3f, signed %.3f\n%!"
      !max_delta !changed (Bytes.length flattened)
      (float !total_delta /. float (Bytes.length flattened))
      (float !signed_delta /. float (Bytes.length flattened));
    P.destroy tracer
  end
