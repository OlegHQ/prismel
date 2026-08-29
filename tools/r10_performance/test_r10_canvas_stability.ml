let () =
  let candidate =
    Result.get_ok
      (R10_scene2_candidate.create ~target:`Native ~width:640 ~height:480
         R10_scene2_legacy_equivalent.Canvas)
  in
  Fun.protect
    ~finally:(fun () -> R10_scene2_candidate.destroy candidate)
    (fun () ->
      R10_scene2_candidate.render candidate ~width:640 ~height:480;
      R10_scene2_candidate.render candidate ~width:640 ~height:480;
      let before = R10_scene2_candidate.stats candidate in
      Gc.full_major ();
      let allocated_before = Gc.allocated_bytes () in
      for _ = 1 to 120 do
        R10_scene2_candidate.render candidate ~width:640 ~height:480
      done;
      let after = R10_scene2_candidate.stats candidate in
      let allocated = Gc.allocated_bytes () -. allocated_before in
      if Int64.sub after.uploaded_bytes before.uploaded_bytes <> 0L then
        failwith "stable Canvas frames reuploaded pixels";
      if allocated > 5_000_000. then
        failwith (Printf.sprintf "stable Canvas frames allocated %.0f bytes" allocated);
      Printf.printf "R10 stable Canvas: 120 frames, 0 upload bytes, %.0f allocated bytes\n%!" allocated)
