open Binding_presentation_snapshot_model

let () =
  for frame = 1 to 10_000 do
    let layer = { width = frame; height = frame + 1; format = Bgra8 } in
    let drawable = acquire layer in
    resize layer ~width:(frame + 100) ~height:(frame + 200) ~format:Rgba16_float;
    let width, height, format = texture drawable in
    if width <> frame || height <> frame + 1 || format <> Bgra8 then
      failwith "drawable metadata followed mutable layer configuration";
    (match destroy_drawable drawable with
     | Error `Parent_has_dependents -> ()
     | Ok () -> failwith "drawable destroyed before borrowed texture");
    destroy_texture drawable;
    (match destroy_drawable drawable with
     | Ok () -> ()
     | Error _ -> failwith "drawable remained retained after texture release");
    (match present drawable with
     | Ok () -> ()
     | Error _ -> failwith "first presentation rejected");
    (match present drawable with
     | Error `Already_scheduled -> ()
     | Ok () -> failwith "duplicate presentation accepted")
  done;
  print_endline "presentation snapshots: 10k resize/format/ownership/one-shot cases green"
