open Metal
open Metal_xpc_test_support

let () =
  if Sys.backend_type <> Sys.Native then fail "Metal XPC service must be native";
  let device = get (Device.system_default ()) in
  let before_invalid = get (Release_queue.stats ()) in
  ignore
    (expect_error Invalid_argument
       (Texture.Shared_handle.Xpc.serve ~device ~capacity:0 (fun _ -> ())));
  ignore
    (expect_error Invalid_argument
       (Texture.Shared_handle.Xpc.serve ~device ~max_payload_bytes:0
          (fun _ -> ())));
  let after_invalid = get (Release_queue.stats ()) in
  if after_invalid.total_created <> before_invalid.total_created then
    fail "invalid XPC service configuration allocated native handles";
  let kernels = create device in
  let handle_request request =
    match get (Texture.Shared_handle.Xpc.request_operation request) with
    | "abandon" -> ()
    | "raise" -> fail "intentional XPC handler exception"
    | "timeout" ->
        Unix.sleepf 0.15;
        get
          (Texture.Shared_handle.Xpc.reject request
             "intentional delayed XPC reply")
    | "reject" ->
        let data = get (Texture.Shared_handle.Xpc.request_data request) in
        if Bytes.length data <> 4 || Bytes.get_int32_le data 0 <> 37l then
          fail "XPC rejection request data did not round-trip";
        get
          (Texture.Shared_handle.Xpc.reject request
             "intentional shared-texture XPC rejection");
        if not (Texture.Shared_handle.Xpc.request_completed request) then
          fail "rejected XPC request remained live";
        ignore
          (expect_error Destroyed
             (Texture.Shared_handle.Xpc.request_operation request));
        ignore
          (expect_error Destroyed
             (Texture.Shared_handle.Xpc.reject request "again"))
    | "exchange" ->
        let request_data =
          get (Texture.Shared_handle.Xpc.request_data request)
        in
        if Bytes.length request_data <> 4
        then fail "XPC exchange request data did not round-trip";
        let expected = Bytes.get_int32_le request_data 0 in
        let incoming_handle =
          get (Texture.Shared_handle.Xpc.request_handle request)
        in
        let texture = get (Texture.import_shared ~device incoming_handle) in
        let observed = exchange kernels texture 91l in
        if observed <> expected then
          fail "XPC service observed %ld instead of the producer value %ld"
            observed expected;
        let response_handle = get (Texture.shared_handle texture) in
        let response = Bytes.create 8 in
        Bytes.set_int32_le response 0 observed;
        Bytes.set_int32_le response 4 (Int32.of_int (Unix.getpid ()));
        get
          (Texture.Shared_handle.Xpc.reply request ~handle:response_handle
             response);
        if not (Texture.Shared_handle.Xpc.request_completed request)
           || not (Texture.Shared_handle.destroyed incoming_handle)
        then fail "replied XPC request did not release its incoming handle";
        ignore
          (expect_error Destroyed
             (Texture.Shared_handle.Xpc.reply request ~handle:response_handle
                response));
        get (Texture.Shared_handle.destroy response_handle);
        get (Texture.destroy texture)
    | operation ->
        get
          (Texture.Shared_handle.Xpc.reject request
             (Printf.sprintf "unsupported XPC operation %S" operation))
  in
  let result =
    Texture.Shared_handle.Xpc.serve ~device ~capacity:2
      ~max_payload_bytes:64 handle_request
  in
  destroy kernels;
  get (Device.destroy device);
  ignore (get (Release_queue.drain ()));
  get result
