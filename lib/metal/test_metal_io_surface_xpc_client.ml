open Metal
open Metal_xpc_test_support

let service_name = "org.prismel.metal.io-surface-xpc-conformance"

let same_plane (left : Texture.Io_surface.plane)
    (right : Texture.Io_surface.plane) =
  left.width = right.width
  && left.height = right.height
  && left.bytes_per_element = right.bytes_per_element
  && left.bytes_per_row = right.bytes_per_row
  && left.size = right.size

let () =
  if Sys.backend_type <> Sys.Native then
    fail "Metal IOSurface XPC client must be native";
  let initial = get (Release_queue.stats ()) in
  ignore
    (expect_error Invalid_argument
       (Texture.Io_surface.Xpc.connect ~service_name:"" ()));
  ignore
    (expect_error Invalid_argument
       (Texture.Io_surface.Xpc.connect ~service_name ~max_payload_bytes:0 ()));
  let after_invalid = get (Release_queue.stats ()) in
  if after_invalid.total_created <> initial.total_created then
    fail "invalid IOSurface XPC connection allocated native handles";
  let plane0 =
    Texture.Io_surface.plane_descriptor ~width:2 ~height:2
      ~bytes_per_element:4
  in
  let plane1 =
    Texture.Io_surface.plane_descriptor ~width:4 ~height:2
      ~bytes_per_element:1
  in
  let source =
    get
      (Texture.Io_surface.create_planar ~label:"Metal cross-process IOSurface"
         [ plane0; plane1 ])
  in
  get
    (Texture.Io_surface.write_bytes source ~plane:0 ~dst_offset:0L
       (uint32_bytes 37l));
  let missing =
    get
      (Texture.Io_surface.Xpc.connect
         ~service_name:"org.prismel.metal.io-surface-xpc-conformance.missing"
         ~max_payload_bytes:64 ())
  in
  ignore
    (expect_error Native_error
       (Texture.Io_surface.Xpc.call missing ~timeout_ms:1_000
          ~operation:"exchange" ~surface:source (uint32_bytes 37l)));
  get (Texture.Io_surface.Xpc.destroy_connection missing);
  let timeout_connection =
    get
      (Texture.Io_surface.Xpc.connect ~service_name ~max_payload_bytes:64 ())
  in
  ignore
    (expect_error Native_error
       (Texture.Io_surface.Xpc.call timeout_connection ~timeout_ms:20
          ~operation:"timeout" ~surface:source (uint32_bytes 37l)));
  get (Texture.Io_surface.Xpc.destroy_connection timeout_connection);
  let connection =
    get
      (Texture.Io_surface.Xpc.connect ~service_name ~max_payload_bytes:64 ())
  in
  if Texture.Io_surface.Xpc.service_name connection <> service_name
     || Texture.Io_surface.Xpc.connection_destroyed connection
  then fail "IOSurface XPC connection properties are wrong";
  let service_bound_connection =
    get
      (Texture.Io_surface.Xpc.connect ~service_name ~max_payload_bytes:128 ())
  in
  ignore
    (expect_error Native_error
       (Texture.Io_surface.Xpc.call service_bound_connection
          ~operation:"service-oversized" ~surface:source (Bytes.make 65 '\000')));
  get (Texture.Io_surface.Xpc.destroy_connection service_bound_connection);
  ignore
    (expect_error Invalid_argument
       (Texture.Io_surface.Xpc.call connection ~timeout_ms:0
          ~operation:"exchange" ~surface:source (uint32_bytes 37l)));
  ignore
    (expect_error Invalid_argument
       (Texture.Io_surface.Xpc.call connection ~operation:"bad\000operation"
          ~surface:source (uint32_bytes 37l)));
  ignore
    (expect_error Invalid_argument
       (Texture.Io_surface.Xpc.call connection ~operation:"oversized"
          ~surface:source (Bytes.make 65 '\000')));
  ignore
    (expect_error Native_error
       (Texture.Io_surface.Xpc.call connection ~operation:"reject"
          ~surface:source (uint32_bytes 37l)));
  ignore
    (expect_error Native_error
       (Texture.Io_surface.Xpc.call connection ~operation:"abandon"
          ~surface:source (uint32_bytes 37l)));
  ignore
    (expect_error Native_error
       (Texture.Io_surface.Xpc.call connection ~operation:"raise"
          ~surface:source (uint32_bytes 37l)));
  let response_surface, response =
    get
      (Texture.Io_surface.Xpc.call connection ~operation:"exchange"
         ~surface:source (uint32_bytes 37l))
  in
  if Bytes.length response <> 8 || Bytes.get_int32_le response 0 <> 37l then
    fail "IOSurface XPC response did not preserve the observed value";
  let service_pid = Int32.to_int (Bytes.get_int32_le response 4) in
  if service_pid <= 0 || service_pid = Unix.getpid () then
    fail "IOSurface did not cross a distinct process boundary";
  if Texture.Io_surface.id response_surface <> Texture.Io_surface.id source
     || Texture.Io_surface.allocation_size response_surface
        <> Texture.Io_surface.allocation_size source
     || Texture.Io_surface.planar response_surface
        <> Texture.Io_surface.planar source
     || Texture.Io_surface.plane_count response_surface
        <> Texture.Io_surface.plane_count source
  then fail "IOSurface XPC transport changed its identity or cardinality";
  for plane = 0 to Texture.Io_surface.plane_count source - 1 do
    if
      not
        (same_plane (get (Texture.Io_surface.plane source plane))
           (get (Texture.Io_surface.plane response_surface plane)))
    then fail "IOSurface XPC transport changed plane %d" plane
  done;
  if get (Texture.Io_surface.label response_surface) <> None then
    fail "IOSurface XPC transport synthesized a process-local label";
  let service_bytes =
    get
      (Texture.Io_surface.read_bytes source ~plane:1 ~offset:0L ~length:4)
  in
  if Bytes.get_int32_le service_bytes 0 <> 91l then
    fail "client did not observe the service's IOSurface write";
  let before_reuse = get (Release_queue.stats ()) in
  for _ = 1 to 64 do
    let iteration_surface, iteration_response =
      get
        (Texture.Io_surface.Xpc.call connection ~operation:"exchange"
           ~surface:source (uint32_bytes 37l))
    in
    if Bytes.length iteration_response <> 8
       || Bytes.get_int32_le iteration_response 0 <> 37l
       || Int32.to_int (Bytes.get_int32_le iteration_response 4) <> service_pid
       || Texture.Io_surface.id iteration_surface <> Texture.Io_surface.id source
    then fail "reused IOSurface XPC connection returned inconsistent data";
    get (Texture.Io_surface.destroy iteration_surface)
  done;
  ignore (get (Release_queue.drain ()));
  let after_reuse = get (Release_queue.stats ()) in
  if after_reuse.live_handles <> before_reuse.live_handles
     || Int64.sub after_reuse.total_created before_reuse.total_created <> 64L
     || Int64.sub after_reuse.total_released before_reuse.total_released <> 64L
  then
    fail "reused IOSurface XPC calls did not balance exactly 64 client handles";
  get (Texture.Io_surface.destroy source);
  let retained =
    get
      (Texture.Io_surface.read_bytes response_surface ~plane:1 ~offset:0L
         ~length:4)
  in
  if Bytes.get_int32_le retained 0 <> 91l then
    fail "received IOSurface did not survive source-handle destruction";
  get (Texture.Io_surface.Xpc.destroy_connection connection);
  get (Texture.Io_surface.Xpc.destroy_connection connection);
  if not (Texture.Io_surface.Xpc.connection_destroyed connection) then
    fail "destroyed IOSurface XPC connection remained live";
  ignore
    (expect_error Destroyed
       (Texture.Io_surface.Xpc.call connection ~operation:"exchange"
          ~surface:response_surface (uint32_bytes 37l)));
  get (Texture.Io_surface.destroy response_surface);
  ignore (get (Release_queue.drain ()));
  let finished = get (Release_queue.stats ()) in
  if finished.live_handles <> initial.live_handles then
    fail "IOSurface XPC conformance left native client handles live"
