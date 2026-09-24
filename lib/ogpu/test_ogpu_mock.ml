let fail message = raise (Failure message)
let ok = function Ok value -> value | Error error -> fail (Ogpu.Error.to_string error)
let expect kind = function
  | Error (error : Ogpu.Error.t) when error.kind = kind -> ()
  | Error error -> fail ("unexpected error: " ^ Ogpu.Error.to_string error)
  | Ok _ -> fail "expected rejection"

let capacities : Ogpu.Mock.capacities = { queues = 1; buffers = 2; textures = 1 }
let buffer size : Ogpu.Types.buffer_descriptor =
  { label = None; size; usage = [ Ogpu.Types.Copy_src; Copy_dst ] }
let texture : Ogpu.Types.texture_descriptor =
  { label = Some "mock"; width = 8; height = 8; depth = 1; mip_levels = 1
  ; sample_count = 1; usage = [ Ogpu.Types.Texture_binding ] }

let () =
  let m1 = ok (Ogpu.Mock.create_device ~profile:M1 ~capacities) in
  expect Ogpu.Error.Invalid_state (Ogpu.Mock.require_ray_tracing m1);
  ignore (ok (Ogpu.Mock.require_metal_fx m1));
  let missing_rt = ok (Ogpu.Mock.create_device ~profile:Missing_ray_tracing ~capacities) in
  expect Ogpu.Error.Invalid_state (Ogpu.Mock.require_ray_tracing missing_rt);
  ignore (ok (Ogpu.Mock.require_metal_fx missing_rt));
  let missing_fx = ok (Ogpu.Mock.create_device ~profile:Missing_metal_fx ~capacities) in
  expect Ogpu.Error.Invalid_state (Ogpu.Mock.require_metal_fx missing_fx);
  ignore (ok (Ogpu.Mock.require_ray_tracing missing_fx));
  let future = ok (Ogpu.Mock.create_device ~profile:Future_unknown ~capacities) in
  ignore (ok (Ogpu.Mock.require_ray_tracing future));
  let m3 = ok (Ogpu.Mock.create_device ~profile:M3_plus ~capacities) in
  ignore (ok (Ogpu.Mock.require_ray_tracing m3));
  let queue = ok (Ogpu.Mock.create_queue m1) in
  let first = ok (Ogpu.Mock.create_buffer m1 (buffer 16L)) in
  let second = ok (Ogpu.Mock.create_buffer m1 (buffer 32L)) in
  let image = ok (Ogpu.Mock.create_texture m1 texture) in
  if [ Ogpu.Mock.queue_id queue; Ogpu.Mock.buffer_id first; Ogpu.Mock.buffer_id second
     ; Ogpu.Mock.texture_id image ] <> [ 1L; 2L; 3L; 4L ]
  then fail "mock allocation order is not deterministic";
  expect Ogpu.Error.Invalid_state (Ogpu.Mock.create_buffer m1 (buffer 64L));
  if Ogpu.Mock.live_counts m1 <> (1, 2, 1) then fail "capacity rejection partially allocated";
  Ogpu.Mock.inject_fault m1 Create_buffer;
  Ogpu.Mock.destroy_buffer second;
  expect Ogpu.Error.Invalid_state (Ogpu.Mock.create_buffer m1 (buffer 64L));
  if Ogpu.Mock.live_counts m1 <> (1, 1, 1) then fail "fault injection partially allocated";
  let replacement = ok (Ogpu.Mock.create_buffer m1 (buffer 64L)) in
  if Ogpu.Mock.buffer_id replacement <> 5L then fail "failed allocation consumed an identifier";
  expect Ogpu.Error.Cross_device (Ogpu.Mock.buffer_descriptor missing_fx first);
  Ogpu.Mock.destroy_buffer first;
  expect Ogpu.Error.Stale_handle (Ogpu.Mock.buffer_descriptor m1 first);
  Ogpu.Mock.destroy_device m1;
  expect Ogpu.Error.Stale_handle (Ogpu.Mock.validate_queue m1 queue);
  expect Ogpu.Error.Stale_handle (Ogpu.Mock.texture_descriptor m1 image);
  expect Ogpu.Error.Stale_handle (Ogpu.Mock.create_queue m1);
  expect Ogpu.Error.Invalid_argument
    (Ogpu.Mock.create_device ~profile:M3_plus ~capacities:{ capacities with buffers = -1 });
  Ogpu.Mock.destroy_device future;
  Ogpu.Mock.destroy_device m3;
  Ogpu.Mock.destroy_device missing_rt;
  Ogpu.Mock.destroy_device missing_fx;
  print_endline "OGPU deterministic mock resource backend passed"
