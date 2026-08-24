let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected RasterizationRate rejection"
let () =
  let open Binding_rasterization_rate_safe_package in
  validate_handoff ();
  let h = [| 1.0; 0.5 |] and v = [| 1.0 |] in
  let layer = ok (create_layer ~max_samples:4 ~horizontal:h ~vertical:v) in
  h.(0) <- 9.0;
  if layer.horizontal.(0) <> 1.0 then failwith "rate samples were not snapshotted";
  error (create_layer ~max_samples:1 ~horizontal:[|1.0;1.0|] ~vertical:[|1.0|]);
  error (create_layer ~max_samples:4 ~horizontal:[|Float.nan|] ~vertical:[|1.0|]);
  error (create_descriptor ~capability:Unsupported ~screen:{width=4;height=4} ~layers:[|Some layer|] ~label:None);
  let descriptor = ok (create_descriptor ~capability:(Supported {max_layers=2}) ~screen:{width=4;height=4} ~layers:[|Some layer;None|] ~label:(Some "rate")) in
  let next = ok (replace_layer descriptor ~index:1 (Some layer)) in
  if descriptor.layers.(1) <> None || next.layers.(1) = None then failwith "rate layer mutation was not atomic";
  error (replace_layer descriptor ~index:2 None);
  let map = {token=1;device=7;layer_count=2;parameter_size=32;parameter_align=16;destroyed=false}
  and buffer = {token=2;device=7;length=64;destroyed=false} in
  ignore (ok (validate_map map ~layer:1)); error (validate_map map ~layer:2);
  ignore (ok (validate_copy map buffer ~offset:16));
  error (validate_copy map {buffer with device=8} ~offset:16);
  error (validate_copy map buffer ~offset:8);
  error (validate_copy map {buffer with length=40} ~offset:16);
  error (validate_copy {map with destroyed=true} buffer ~offset:16);
  Printf.printf "RasterizationRate safe package: callable50 = constructors5/layer17/descriptor12/map16; capability, snapshot, device, range, alignment, destroyed checks passed\n%!"
