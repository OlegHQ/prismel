open Ogpu.Binding

let fail message = raise (Failure message)
let ok = function Ok value -> value | Error error -> fail (Ogpu.Error.to_string error)
let expect kind = function
  | Error (error : Ogpu.Error.t) when error.kind = kind -> ()
  | Error error -> fail ("unexpected error: " ^ Ogpu.Error.to_string error)
  | Ok _ -> fail "expected rejection"

let layout () =
  ok (Ogpu.Binding.create_layout
    [ { binding = 2; kind = Sampler; visibility = [ Fragment ] }
    ; { binding = 0; kind = Buffer; visibility = [ Vertex; Fragment ] }
    ; { binding = 1; kind = Texture; visibility = [ Fragment ] } ])

let () =
  let caps = Ogpu.Capabilities.minimum_m1 in
  let device = Ogpu.Handle.create_device () in
  let foreign = Ogpu.Handle.create_device () in
  let pipeline = ok (Ogpu.Binding.create_pipeline_layout ~device ~capabilities:caps [ 0, layout () ]) in
  let buffer = Ogpu.Handle.create ~device and texture = Ogpu.Handle.create ~device
  and sampler = Ogpu.Handle.create ~device and foreign_buffer = Ogpu.Handle.create ~device:foreign in
  let group = ok (Ogpu.Binding.create_group pipeline ~group:0
    [ { binding = 2; resource = Ogpu.Binding.sampler sampler }
    ; { binding = 0; resource = Ogpu.Binding.buffer buffer }
    ; { binding = 1; resource = Ogpu.Binding.texture texture } ]) in
  let snapshot = Ogpu.Binding.group_entries group in
  if List.map (fun (value : Ogpu.Binding.resource_snapshot) -> value.binding) snapshot <> [ 0; 1; 2 ]
  then fail "bind-group snapshot is not sorted";
  expect Ogpu.Error.Invalid_argument (Ogpu.Binding.create_layout
    [ { binding = 0; kind = Buffer; visibility = [ Vertex ] }
    ; { binding = 0; kind = Texture; visibility = [ Fragment ] } ]);
  expect Ogpu.Error.Invalid_argument (Ogpu.Binding.create_layout
    [ { binding = 0; kind = Buffer; visibility = [] } ]);
  expect Ogpu.Error.Invalid_argument (Ogpu.Binding.create_layout
    [ { binding = 0; kind = Buffer; visibility = [ Vertex; Vertex ] } ]);
  expect Ogpu.Error.Invalid_argument (Ogpu.Binding.create_group pipeline ~group:0
    [ { binding = 0; resource = Ogpu.Binding.buffer buffer } ]);
  expect Ogpu.Error.Invalid_argument (Ogpu.Binding.create_group pipeline ~group:0
    [ { binding = 0; resource = Ogpu.Binding.texture texture }
    ; { binding = 1; resource = Ogpu.Binding.texture texture }
    ; { binding = 2; resource = Ogpu.Binding.sampler sampler } ]);
  expect Ogpu.Error.Invalid_argument (Ogpu.Binding.create_group pipeline ~group:0
    [ { binding = 0; resource = Ogpu.Binding.buffer buffer }
    ; { binding = 0; resource = Ogpu.Binding.buffer buffer }
    ; { binding = 1; resource = Ogpu.Binding.texture texture }
    ; { binding = 2; resource = Ogpu.Binding.sampler sampler } ]);
  expect Ogpu.Error.Cross_device (Ogpu.Binding.create_group pipeline ~group:0
    [ { binding = 0; resource = Ogpu.Binding.buffer foreign_buffer }
    ; { binding = 1; resource = Ogpu.Binding.texture texture }
    ; { binding = 2; resource = Ogpu.Binding.sampler sampler } ]);
  Ogpu.Handle.destroy texture;
  expect Ogpu.Error.Stale_handle (Ogpu.Binding.validate_group pipeline group);
  let too_many = List.init (caps.limits.max_bind_groups + 1) (fun group -> group, ok (Ogpu.Binding.create_layout [])) in
  expect Ogpu.Error.Capacity (Ogpu.Binding.create_pipeline_layout ~device ~capabilities:caps too_many);
  expect Ogpu.Error.Invalid_argument
    (Ogpu.Binding.create_pipeline_layout ~device ~capabilities:caps [ 1, ok (Ogpu.Binding.create_layout []) ]);
  expect Ogpu.Error.Invalid_argument
    (Ogpu.Binding.create_pipeline_layout ~device ~capabilities:caps
      [ 0, ok (Ogpu.Binding.create_layout []); 0, ok (Ogpu.Binding.create_layout []) ]);
  let no_rt = ok (Ogpu.Binding.create_layout
    [ { binding = 0; kind = Acceleration_structure; visibility = [ Compute ] } ]) in
  let no_rt_pipeline = ok (Ogpu.Binding.create_pipeline_layout ~device ~capabilities:caps [ 0, no_rt ]) in
  let acceleration = Ogpu.Handle.create ~device in
  expect Ogpu.Error.Invalid_argument (Ogpu.Binding.create_group no_rt_pipeline ~group:0
    [ { binding = 0; resource = Ogpu.Binding.acceleration_structure acceleration } ]);
  let rt_caps = { caps with ray_tracing = true } in
  let rt_pipeline = ok (Ogpu.Binding.create_pipeline_layout ~device ~capabilities:rt_caps [ 0, no_rt ]) in
  ignore (ok (Ogpu.Binding.create_group rt_pipeline ~group:0
    [ { binding = 0; resource = Ogpu.Binding.acceleration_structure acceleration } ]));
  let description () =
    let local = ok (Ogpu.Binding.create_layout
      [ { binding = 3; kind = Buffer; visibility = [ Compute ] }
      ; { binding = 0; kind = Buffer; visibility = [ Vertex; Fragment ] } ]) in
    Ogpu.Binding.layout_entries local
  in
  let expected = description () in
  let workers = Array.init 4 (fun _ -> Domain.spawn description) in
  Array.iter (fun worker -> if Domain.join worker <> expected then fail "domain-dependent binding description") workers;
  Ogpu.Handle.destroy_device device;
  expect Ogpu.Error.Stale_handle (Ogpu.Binding.validate_group pipeline group);
  Ogpu.Handle.destroy_device foreign;
  print_endline "OGPU immutable binding tables passed"
