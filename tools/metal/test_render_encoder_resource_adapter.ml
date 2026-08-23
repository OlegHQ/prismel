open Render_encoder_resource_adapter
let get = function Ok value->value | Error message->failwith message
let reject = function Error _->() | Ok _->failwith "expected rejection"
let calls = ref []
let note name = calls := name :: !calls
let backend =
  { update_fence=(fun _ _ _->note "update"); wait_fence=(fun _ _ _->note "wait")
  ; depth_store=(fun _ _->note "depth"); stencil_store=(fun _ _->note "stencil")
  ; use_heaps=(fun _ _ _->note "heaps"); use_resources=(fun _ _ _ _->note "resources")
  ; execute_icb=(fun _ _ _ _->note "icb")
  ; execute_icb_indirect=(fun _ _ _ _->note "icb-indirect") }
let () =
  let e=encoder ~token:1L ~device:7L ~backend ~sample_count:1 ~depth:true
      ~stencil:true ~pipeline_supports_icb:true in
  let fence=owned ~token:2L ~device:7L and heap=owned ~token:3L ~device:7L in
  let resource=owned ~token:4L ~device:7L and range=owned ~token:5L ~device:7L in
  let commands=icb ~token:6L ~device:7L ~max_commands:8 in
  reject (update_fence e (owned ~token:9L ~device:8L) ~after_stages:1);
  reject (use_heaps e [heap;heap] ~stages:1);
  reject (set_depth_store e Resolve);
  get (update_fence e fence ~after_stages:1); get (wait_fence e fence ~before_stages:2);
  get (set_depth_store e Store); get (set_stencil_store e Store);
  get (use_heaps e [heap] ~stages:1); get (use_resources e [resource] ~usage:1 ~stages:2);
  get (execute_icb e commands ~location:0 ~length:8);
  get (execute_icb_indirect e commands range ~offset:0L);
  List.iter (fun value->reject(destroy value)) [fence;heap;resource;range];
  get(end_encoding e); reject(update_fence e fence ~after_stages:1);
  complete e; List.iter (fun value->get(destroy value)) [fence;heap;resource;range];
  if List.length !calls <> 8 then failwith "backend call count drift"
