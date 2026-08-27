let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let require condition message = if not condition then failwith message

let () =
  let width = 64 and height = 64 in
  let canonical = R10_scene3_legacy_equivalent.create ~width ~height in
  ignore
    (Result.get_ok
       (R10_scene3_equivalence_bridge.prove ~width ~height canonical));
  let draws =
    List.map
      (fun draw ->
        (Scene_execution.Scene3, Ogpu.Pipeline.Replace, None, None, 4, draw))
      canonical.software_draws
  in
  let runtime =
    get
      (Runtime_next_headless.create ~logical_width:width ~logical_height:height
         ~drawable_width:width ~drawable_height:height)
  in
  Fun.protect
    ~finally:(fun () -> ignore (Runtime_next_headless.destroy runtime))
    (fun () ->
      require (get (Runtime_next_headless.render_sampled_resources runtime draws))
        "canonical Scene3 presentation";
      let pixels = get (Runtime_next_headless.read_pixels runtime ~bytes_per_row:(width * 4)) in
      let first = Bytes.sub pixels 0 4 in
      let changed = ref 0 and opaque = ref 0 in
      for pixel = 0 to (width * height) - 1 do
        let offset = pixel * 4 in
        if Bytes.sub pixels offset 4 <> first then incr changed;
        if Char.code (Bytes.get pixels (offset + 3)) <> 0 then incr opaque
      done;
      require (!changed > 64) "capture must contain non-background coverage";
      require (!opaque > 64) "capture must contain visible alpha";
      let digest = Digest.to_hex (Digest.bytes pixels) in
      require (digest = "79fd872b9624a3592dd2f3ec302c0079")
        ("frozen canonical candidate capture: " ^ digest);
      Printf.printf
        "R10 canonical Scene3 capture nonblank: changed=%d opaque=%d digest=%s\n"
        !changed !opaque digest)
