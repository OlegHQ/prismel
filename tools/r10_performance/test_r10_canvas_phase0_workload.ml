let () =
  let candidate =
    Result.get_ok
      (R10_scene2_candidate.create ~width:640 ~height:480
         R10_scene2_legacy_equivalent.Canvas)
  in
  Fun.protect
    ~finally:(fun () -> R10_scene2_candidate.destroy candidate)
    (fun () ->
      let identity () =
        Prismel_next_api.Image.Private.identity (Option.get candidate.image)
      in
      let first_identity = identity () in
      R10_scene2_candidate.render candidate ~width:640 ~height:480;
      let first = R10_scene2_candidate.capture candidate
      and second_identity = identity () in
      R10_scene2_candidate.render candidate ~width:640 ~height:480;
      let second = R10_scene2_candidate.capture candidate
      and third_identity = identity () in
      if first = second then failwith "Phase0 Canvas animation did not advance";
      if first_identity = second_identity || second_identity = third_identity then
        failwith "Phase0 Canvas did not replace its per-frame snapshot";
      let before = R10_scene2_candidate.stats candidate in
      for _ = 1 to 5 do
        R10_scene2_candidate.render candidate ~width:640 ~height:480
      done;
      let after = R10_scene2_candidate.stats candidate in
      if Int64.sub after.uploaded_bytes before.uploaded_bytes <= 0L then
        failwith "Phase0 Canvas performed no per-frame snapshot upload";
      if after.cache_entries > 256 then
        failwith "Phase0 Canvas exceeded its bounded snapshot cache";
      Printf.printf
        "R10 Phase0 Canvas: phase animation, snapshot replacement, upload, bounded cache passed\n%!" )
