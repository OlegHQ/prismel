open Prismel

type model = {
  started : float option;
  started_at : float;
  allocated_bytes : float;
  elapsed : float;
}

let profile = ref None
let samples : (string, int) Hashtbl.t = Hashtbl.create 64

let start_profile () =
  if Sys.getenv_opt "PRISMEL_RENDER_MEMPROF" = Some "1" then
    let record (allocation : Gc.Memprof.allocation) =
      let stack = Printexc.raw_backtrace_to_string allocation.callstack in
      Hashtbl.replace samples stack
        (allocation.n_samples + Option.value ~default:0
           (Hashtbl.find_opt samples stack));
      None
    in
    profile := Some (Gc.Memprof.start ~sampling_rate:0.01 ~callstack_size:12
      { Gc.Memprof.null_tracker with alloc_minor = record; alloc_major = record })

let stop_profile () =
  match !profile with
  | None -> ()
  | Some active ->
      Gc.Memprof.stop ();
      Gc.Memprof.discard active;
      Hashtbl.to_seq samples |> List.of_seq
      |> List.sort (fun (_, a) (_, b) -> Int.compare b a)
      |> List.to_seq |> Seq.take 15
      |> Seq.iter (fun (stack, count) ->
        Printf.eprintf "samples=%d\n%s\n%!" count stack)

let measured_frames =
  match Sys.getenv_opt "PRISMEL_RENDER_BENCH_FRAMES" with
  | None -> 30
  | Some value -> max 1 (int_of_string value)

let domains =
  match Sys.getenv_opt "PRISMEL_BENCH_DOMAINS" with
  | None -> Parallel.recommended_domains ()
  | Some value -> max 1 (int_of_string value)

let warmup_frames = 4
let render_size =
  match Sys.getenv_opt "PRISMEL_RENDER_BENCH_SIZE" with
  | None -> 128
  | Some value -> max 16 (int_of_string value)

let integer_env name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let segments = integer_env "PRISMEL_RENDER_BENCH_SEGMENTS" 32
let rings = integer_env "PRISMEL_RENDER_BENCH_RINGS" 16
let samples = integer_env "PRISMEL_RENDER_BENCH_SAMPLES" 1
let clear_only = Sys.getenv_opt "PRISMEL_RENDER_BENCH_CLEAR_ONLY" = Some "1"
let textured = Sys.getenv_opt "PRISMEL_RENDER_BENCH_TEXTURED" = Some "1"
let programmable_floor =
  Sys.getenv_opt "PRISMEL_RENDER_BENCH_PROGRAMMABLE_FLOOR" = Some "1"

let floor_shader =
  let floor = Color.hex_exn "#0f172a"
  and grid = Color.hex_exn "#67e8f9" in
  Shader3.create ~varying_count:2
    ~vertex:(fun (input : Shader3.vertex_input) ->
      let output = Shader3.default_vertex input in
      { output with
        varyings = [output.world_position.x; output.world_position.z];
      })
    ~fragment:(fun (input : Shader3.fragment_input) ->
      match input.varyings with
      | [world_x; world_z] ->
          let near_grid coordinate =
            abs_float (coordinate -. Float.round coordinate) < 0.035
          in
          Shader3.output
            (if near_grid world_x || near_grid world_z then grid else floor)
      | _ -> Shader3.discard)
    ()

let update model (frame : Frame.t) =
  if frame.count = warmup_frames then begin
    Gc.full_major ();
    start_profile ();
    { model with
      started = Some (Gc.allocated_bytes ());
      started_at = Unix.gettimeofday ();
    }
  end else if frame.count = warmup_frames + measured_frames then begin
    let started = Option.get model.started in
    Sketch.quit ();
    stop_profile ();
    { model with
      allocated_bytes = Gc.allocated_bytes () -. started;
      elapsed = Unix.gettimeofday () -. model.started_at;
    }
  end else model

let () =
  if not (Sketch.is_headless ()) then
    failwith "bench_render must run with HEADLESS=1";
  if not (List.mem samples [1; 4; 9; 16]) then
    invalid_arg "PRISMEL_RENDER_BENCH_SAMPLES must be 1, 4, 9, or 16";
  let mesh =
    if programmable_floor then Mesh.plane ~width:12. ~height:10. ()
    else Mesh.sphere ~segments ~rings ~radius:1. () in
  let camera = Camera.perspective
      ~at:(Vec3.create 0. 0. 3.2) ~target:Vec3.zero () in
  let texture =
    if not textured then None
    else
      Some
        (Texture.init ~width:64 ~height:64 (fun ~x ~y ->
           if ((x / 8) + (y / 8)) land 1 = 0 then Color.white
           else Color.rgb 24 48 80)
         |> Texture.generate_mipmaps
         |> Scene3.textured ~filter:Texture.Trilinear)
  in
  let node =
    if programmable_floor then
      Scene3.translate (Vec3.create 0. (-1.5) 0.) [
        Scene3.rotate ~axis:Vec3.unit_x (-.Float.pi /. 2.) [
          Scene3.mesh ~cull:Scene3.Cull_none ~shader:floor_shader
            ~material:(Material.unlit Color.white) mesh;
        ];
      ]
    else
      Scene3.mesh ~cull:Scene3.Cull_none ?texture
        ~material:(Material.create ~diffuse:(Color.rgb 40 170 220) ()) mesh
  in
  let scene = Scene3.create ~samples
      ~ambient:(Color.rgb 24 24 24)
      ~lights:[
        Light.directional ~direction:(Vec3.create (-0.4) (-0.7) (-1.))
          ~diffuse:Color.white ();
      ]
      [node]
  in
  let final = Sketch.run_state
      ~config:{ Sketch.default_config with
        width = render_size;
        height = render_size;
        fps = None;
        domains = Some domains;
        clock = Sketch.Fixed (1. /. 60.);
      }
      ~init:(fun _ -> {
        started = None;
        started_at = 0.;
        allocated_bytes = 0.;
        elapsed = 0.;
      })
      ~update
      ~view:(fun _ _ ->
        if clear_only then Scene.[clear Color.black]
        else Scene.[clear Color.black; view3d ~camera scene])
      () in
  Printf.printf
    "benchmark,width,height,triangles,domains,frames,total_seconds,seconds_per_frame,total_allocated_bytes,allocated_bytes_per_frame\n";
  Printf.printf "%s,%d,%d,%d,%d,%d,%.6f,%.6f,%.0f,%.0f\n%!"
    (if clear_only then "clear"
     else if programmable_floor then "programmable_floor"
     else if textured then "software_phong_textured"
     else "software_phong")
    render_size render_size (Mesh.Private.triangle_count mesh) domains measured_frames
    final.elapsed (final.elapsed /. float_of_int measured_frames) final.allocated_bytes
    (final.allocated_bytes /. float_of_int measured_frames)
