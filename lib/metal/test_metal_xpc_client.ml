open Metal
open Metal_xpc_test_support

let service_name = "org.prismel.metal.xpc-conformance"

let () =
  if Sys.backend_type <> Sys.Native then fail "Metal XPC client must be native";
  let device = get (Device.system_default ()) in
  let before_invalid = get (Release_queue.stats ()) in
  ignore
    (expect_error Invalid_argument
       (Texture.Shared_handle.Xpc.connect ~device ~service_name:"" ()));
  ignore
    (expect_error Invalid_argument
       (Texture.Shared_handle.Xpc.connect ~device ~service_name
          ~max_payload_bytes:0 ()));
  let after_invalid = get (Release_queue.stats ()) in
  if after_invalid.total_created <> before_invalid.total_created then
    fail "invalid XPC connection configuration allocated native handles";
  let descriptor =
    Texture.descriptor_2d ~storage:Buffer.Private
      ~usage:[ Texture.Shader_read; Texture.Shader_write ]
      ~label:"Metal cross-process texture" ~format:Texture.R32_uint ~width:1
      ~height:1 ()
  in
  let source = get (Texture.create_shared ~device descriptor) in
  let expected_descriptor = Texture.descriptor source in
  let kernels = create device in
  write kernels source 37l;
  let source_handle = get (Texture.shared_handle source) in
  get (Texture.destroy source);
  let missing =
    get
      (Texture.Shared_handle.Xpc.connect ~device
         ~service_name:"org.prismel.metal.xpc-conformance.missing"
         ~max_payload_bytes:64 ())
  in
  ignore
    (expect_error Native_error
       (Texture.Shared_handle.Xpc.call missing ~timeout_ms:1_000
          ~operation:"exchange" ~handle:source_handle (uint32_bytes 37l)));
  get (Texture.Shared_handle.Xpc.destroy_connection missing);
  let timeout_connection =
    get
      (Texture.Shared_handle.Xpc.connect ~device ~service_name
         ~max_payload_bytes:64 ())
  in
  ignore
    (expect_error Native_error
       (Texture.Shared_handle.Xpc.call timeout_connection ~timeout_ms:20
          ~operation:"timeout" ~handle:source_handle (uint32_bytes 37l)));
  get (Texture.Shared_handle.Xpc.destroy_connection timeout_connection);
  let connection =
    get
      (Texture.Shared_handle.Xpc.connect ~device ~service_name
         ~max_payload_bytes:64 ())
  in
  if Texture.Shared_handle.Xpc.service_name connection <> service_name
     || Texture.Shared_handle.Xpc.connection_destroyed connection
  then fail "XPC connection properties are wrong";
  let service_bound_connection =
    get
      (Texture.Shared_handle.Xpc.connect ~device ~service_name
         ~max_payload_bytes:128 ())
  in
  ignore
    (expect_error Native_error
       (Texture.Shared_handle.Xpc.call service_bound_connection
          ~operation:"service-oversized" ~handle:source_handle
          (Bytes.make 65 '\000')));
  get
    (Texture.Shared_handle.Xpc.destroy_connection service_bound_connection);
  ignore
    (expect_error Invalid_argument
       (Texture.Shared_handle.Xpc.call connection ~timeout_ms:0
          ~operation:"exchange" ~handle:source_handle (uint32_bytes 37l)));
  ignore
    (expect_error Invalid_argument
       (Texture.Shared_handle.Xpc.call connection ~operation:"bad\000operation"
          ~handle:source_handle (uint32_bytes 37l)));
  ignore
    (expect_error Invalid_argument
       (Texture.Shared_handle.Xpc.call connection ~operation:"oversized"
          ~handle:source_handle (Bytes.make 65 '\000')));
  ignore
    (expect_error Native_error
       (Texture.Shared_handle.Xpc.call connection ~operation:"reject"
          ~handle:source_handle (uint32_bytes 37l)));
  ignore
    (expect_error Native_error
       (Texture.Shared_handle.Xpc.call connection ~operation:"abandon"
          ~handle:source_handle (uint32_bytes 37l)));
  ignore
    (expect_error Native_error
       (Texture.Shared_handle.Xpc.call connection ~operation:"raise"
          ~handle:source_handle (uint32_bytes 37l)));
  let response_handle, response =
    get
      (Texture.Shared_handle.Xpc.call connection ~operation:"exchange"
         ~handle:source_handle (uint32_bytes 37l))
  in
  if Bytes.length response <> 8 || Bytes.get_int32_le response 0 <> 37l then
    fail "XPC service response did not preserve the observed value";
  let service_pid = Int32.to_int (Bytes.get_int32_le response 4) in
  if service_pid <= 0 || service_pid = Unix.getpid () then
    fail "shared texture did not cross a distinct process boundary";
  if get (Texture.Shared_handle.label response_handle)
     <> Some "Metal cross-process texture"
  then fail "XPC response handle lost its source label";
  let before_reuse = get (Release_queue.stats ()) in
  for _ = 1 to 64 do
    let iteration_handle, iteration_response =
      get
        (Texture.Shared_handle.Xpc.call connection ~operation:"exchange"
           ~handle:source_handle (uint32_bytes 91l))
    in
    if Bytes.length iteration_response <> 8
       || Bytes.get_int32_le iteration_response 0 <> 91l
       || Int32.to_int (Bytes.get_int32_le iteration_response 4) <> service_pid
    then fail "reused XPC connection returned an inconsistent reply";
    get (Texture.Shared_handle.destroy iteration_handle)
  done;
  ignore (get (Release_queue.drain ()));
  let after_reuse = get (Release_queue.stats ()) in
  if after_reuse.live_handles <> before_reuse.live_handles
     || Int64.sub after_reuse.total_created before_reuse.total_created <> 64L
     || Int64.sub after_reuse.total_released before_reuse.total_released <> 64L
  then fail "reused XPC calls did not balance exactly 64 client handles";
  get (Texture.Shared_handle.destroy source_handle);
  get (Texture.Shared_handle.Xpc.destroy_connection connection);
  get (Texture.Shared_handle.Xpc.destroy_connection connection);
  if not (Texture.Shared_handle.Xpc.connection_destroyed connection) then
    fail "destroyed XPC connection remained live";
  ignore
    (expect_error Destroyed
       (Texture.Shared_handle.Xpc.call connection ~operation:"exchange"
          ~handle:response_handle (uint32_bytes 37l)));
  let imported = get (Texture.import_shared ~device response_handle) in
  get (Texture.Shared_handle.destroy response_handle);
  if Texture.descriptor imported <> expected_descriptor then
    fail "XPC transport changed typed texture descriptor metadata";
  if read kernels imported <> 91l then
    fail "consumer did not observe the service's cross-process texture write";
  get (Texture.destroy imported);
  destroy kernels;
  get (Device.destroy device);
  ignore (get (Release_queue.drain ()))
