open Prismel_next_api

let fail message = raise (Failure message)
let require condition message = if not condition then fail message
let ok = function Ok value -> value | Error error -> fail (Ogpu.Error.to_string error)
let raster_ok = function Ok value -> value | Error _ -> fail "Raster2 error"
let expect kind = function
  | Error (error : Ogpu.Error.t) when error.kind = kind -> ()
  | Error error -> fail ("unexpected error: " ^ Ogpu.Error.to_string error)
  | Ok _ -> fail "expected rejection"

let ended () =
  let command = Ogpu.Command.begin_encoder () in
  ok (Ogpu.Command.end_encoder command);
  command

let handles_and_passes () =
  let device = Ogpu.Handle.create_device () in
  let resource = Ogpu.Handle.create ~device in
  Ogpu.Handle.destroy resource;
  Ogpu.Handle.destroy resource;
  require (Ogpu.Handle.destroyed resource) "double destroy did not settle";
  expect Ogpu.Error.Stale_handle
    (Ogpu.Handle.validate ~operation:"final-facade" resource);
  let command = Ogpu.Command.begin_encoder () in
  ok (Ogpu.Command.begin_pass command Render);
  expect Ogpu.Error.Invalid_state (Ogpu.Command.begin_pass command Compute);
  expect Ogpu.Error.Invalid_state (Ogpu.Command.end_encoder command);
  ok (Ogpu.Command.end_pass command);
  ok (Ogpu.Command.end_encoder command);
  Ogpu.Handle.destroy_device device;
  Ogpu.Handle.destroy_device device;
  require (Ogpu.Handle.device_destroyed device) "device double destroy"

let synchronization_and_release () =
  let device = Ogpu.Handle.create_device () in
  let fence = ok (Ogpu.Sync.create_fence device ~initial:0L) in
  ignore (ok (Ogpu.Sync.signal_fence device fence 2L));
  ignore (ok (Ogpu.Sync.wait_fence device fence 2L));
  expect Ogpu.Error.Invalid_argument (Ogpu.Sync.signal_fence device fence 1L);
  let queue = ok (Ogpu.Submission.create device) in
  let resource = Ogpu.Handle.create ~device in
  let receipt = ok (Ogpu.Submission.submit queue (ended ()) ~resources:[ resource ]) in
  Ogpu.Handle.destroy resource;
  require (Ogpu.Submission.retained_resource_count queue = 1)
    "deferred resource released before completion";
  ok (Ogpu.Submission.complete_through queue receipt.id);
  require (Ogpu.Submission.retained_resource_count queue = 0)
    "completion retained released resource";
  Ogpu.Submission.drain queue;
  require (Ogpu.Submission.in_flight queue = 0) "submission drain";
  Ogpu.Sync.destroy_fence fence;
  expect Ogpu.Error.Stale_handle (Ogpu.Sync.signal_fence device fence 3L)

let surfaces () =
  let device = Ogpu.Handle.create_device () in
  let config : Ogpu.Surface.configuration = {
    logical_width=16; logical_height=12; physical_width=32; physical_height=24;
    format=Bgra8_unorm; present_mode=Fifo; max_acquired=2 } in
  let surface = ok (Ogpu.Surface.create device config) in
  let frame = match ok (Ogpu.Surface.acquire surface) with
    | Acquired frame -> frame | _ -> fail "surface was not acquired" in
  let generation = Ogpu.Surface.generation surface in
  ok (Ogpu.Surface.resize surface ~logical_width:8 ~logical_height:6
        ~physical_width:16 ~physical_height:12);
  require (Ogpu.Surface.generation surface = Int64.succ generation)
    "surface resize generation";
  expect Ogpu.Error.Stale_handle (Ogpu.Surface.present surface frame);
  Ogpu.Surface.set_availability surface Force_timeout;
  require (ok (Ogpu.Surface.acquire surface) = Timeout) "surface timeout";
  Ogpu.Surface.set_availability surface Force_device_lost;
  require (ok (Ogpu.Surface.acquire surface) = Device_lost) "surface loss";
  Ogpu.Surface.destroy surface;
  Ogpu.Surface.destroy surface;
  expect Ogpu.Error.Invalid_state (Ogpu.Surface.acquire surface)

let mock_faults () =
  let capacities : Ogpu.Mock.capacities = { queues=1; buffers=1; textures=1 } in
  let device = ok (Ogpu.Mock.create_device ~profile:M3_plus ~capacities) in
  let descriptor : Ogpu.Types.buffer_descriptor =
    { label=Some "facade"; size=16L; usage=[ Copy_src; Copy_dst ] } in
  Ogpu.Mock.inject_fault device Create_buffer;
  expect Ogpu.Error.Invalid_state (Ogpu.Mock.create_buffer device descriptor);
  require (Ogpu.Mock.live_counts device = (0, 0, 0))
    "mock fault partially allocated";
  let buffer = ok (Ogpu.Mock.create_buffer device descriptor) in
  Ogpu.Mock.destroy_buffer buffer;
  expect Ogpu.Error.Stale_handle (Ogpu.Mock.buffer_descriptor device buffer);
  Ogpu.Mock.destroy_device device;
  expect Ogpu.Error.Stale_handle (Ogpu.Mock.create_queue device)

let raster_snapshot frame =
  let surface = raster_ok (Raster2.Surface.create ~width:8 ~height:8 ()) in
  Raster2.Surface.clear surface 0x101820ffl;
  Raster2.Primitive.rect surface ~blend:Copy ~x:(frame mod 3) ~y:1
    ~width:4 ~height:5 0xd05020ffl;
  Bytes.copy (Raster2.Surface.bytes surface)

let ordered_description () =
  let command = Ogpu.Command.begin_encoder () in
  ok (Ogpu.Command.push_debug command "frame");
  ok (Ogpu.Command.begin_pass command Transfer);
  ok (Ogpu.Command.declare_resource command ~resource_id:7L ~access:Write
        ~stages:[ Transfer_stage ]);
  ok (Ogpu.Command.end_pass command);
  ok (Ogpu.Command.pop_debug command);
  ok (Ogpu.Command.end_encoder command);
  Array.to_list (Ogpu.Command.descriptions command)

let domain_determinism () =
  let sequence () =
    ordered_description (), List.map raster_snapshot [ 1; 2; 60; 600 ],
    Scene.Private.to_ir
      [ Scene.clear Color.black;
        Scene.rect ~at:(1, 1) ~w:5 ~h:4 ~fill:Color.red () ]
  in
  let expected = sequence () in
  let workers = Array.init 4 (fun _ -> Domain.spawn sequence) in
  Array.iter (fun worker -> require (Domain.join worker = expected)
    "one/four-domain ordering drift") workers

let final_facade target =
  let mesh = Mesh.plane ~width:1. ~height:1. () in
  let camera = Camera.orthographic ~height:2. ~at:(Vec3.create 0. 0. 2.)
      ~target:Vec3.zero () in
  let framebuffer = Framebuffer3.render ~width:8 ~height:8 ~camera
      (Scene3.create ~ambient:Color.white [ Scene3.mesh mesh ]) in
  require (Framebuffer3.size framebuffer = (8, 8)) "final Scene3 bridge";
  Preview.start ~width:8 ~height:8 ~title:("ogpu-" ^ target) ();
  List.iter (fun frame -> Preview.show
    [ Scene.clear Color.black;
      Scene.rect ~at:(frame mod 3, 1) ~w:4 ~h:4 ~fill:Color.red () ])
    [ 1; 2; 60; 600 ];
  Preview.stop ();
  require (not (Preview.is_open ())) "final facade teardown"

let () =
  if Array.length Sys.argv <> 2
     || not (List.mem Sys.argv.(1) [ "headless"; "web" ]) then
    fail "expected headless or web";
  handles_and_passes ();
  synchronization_and_release ();
  surfaces ();
  mock_faults ();
  domain_determinism ();
  final_facade Sys.argv.(1);
  Printf.printf "Phase5 OGPU final-facade %s state/fault/determinism passed\n"
    Sys.argv.(1)
