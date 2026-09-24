open Metal
open Metal_xpc_test_support

let () =
  if Sys.backend_type <> Sys.Native then
    fail "Metal IOSurface XPC service must be native";
  let before_invalid = get (Release_queue.stats ()) in
  ignore
    (expect_error Invalid_argument
       (Texture.Io_surface.Xpc.serve ~capacity:0 (fun _ -> ())));
  ignore
    (expect_error Invalid_argument
       (Texture.Io_surface.Xpc.serve ~max_payload_bytes:0 (fun _ -> ())));
  let after_invalid = get (Release_queue.stats ()) in
  if after_invalid.total_created <> before_invalid.total_created then
    fail "invalid IOSurface XPC service configuration allocated native handles";
  let handle_request request =
    match get (Texture.Io_surface.Xpc.request_operation request) with
    | "abandon" -> ()
    | "raise" -> fail "intentional IOSurface XPC handler exception"
    | "timeout" ->
        Unix.sleepf 0.15;
        get
          (Texture.Io_surface.Xpc.reject request
             "intentional delayed IOSurface XPC reply")
    | "reject" ->
        let data = get (Texture.Io_surface.Xpc.request_data request) in
        if Bytes.length data <> 4 || Bytes.get_int32_le data 0 <> 37l then
          fail "IOSurface XPC rejection data did not round-trip";
        get
          (Texture.Io_surface.Xpc.reject request
             "intentional IOSurface XPC rejection");
        if not (Texture.Io_surface.Xpc.request_completed request) then
          fail "rejected IOSurface XPC request remained live";
        ignore
          (expect_error Destroyed
             (Texture.Io_surface.Xpc.request_operation request));
        ignore
          (expect_error Destroyed
             (Texture.Io_surface.Xpc.reject request "again"))
    | "exchange" ->
        let request_data = get (Texture.Io_surface.Xpc.request_data request) in
        if Bytes.length request_data <> 4 then
          fail "IOSurface XPC exchange data did not round-trip";
        let expected = Bytes.get_int32_le request_data 0 in
        let surface = get (Texture.Io_surface.Xpc.request_surface request) in
        if not (Texture.Io_surface.planar surface)
           || Texture.Io_surface.plane_count surface <> 2
        then fail "IOSurface XPC service received the wrong plane shape";
        let incoming =
          get (Texture.Io_surface.read_bytes surface ~plane:0 ~offset:0L ~length:4)
        in
        let observed = Bytes.get_int32_le incoming 0 in
        if observed <> expected then
          fail "IOSurface XPC service observed %ld instead of %ld" observed
            expected;
        get
          (Texture.Io_surface.write_bytes surface ~plane:1 ~dst_offset:0L
             (uint32_bytes 91l));
        let response = Bytes.create 8 in
        Bytes.set_int32_le response 0 observed;
        Bytes.set_int32_le response 4 (Int32.of_int (Unix.getpid ()));
        get (Texture.Io_surface.Xpc.reply request ~surface response);
        if not (Texture.Io_surface.Xpc.request_completed request)
           || not (Texture.Io_surface.destroyed surface)
        then fail "replied IOSurface XPC request did not release its input";
        ignore
          (expect_error Destroyed
             (Texture.Io_surface.Xpc.reply request ~surface response))
    | operation ->
        get
          (Texture.Io_surface.Xpc.reject request
             (Printf.sprintf "unsupported IOSurface XPC operation %S" operation))
  in
  get
    (Texture.Io_surface.Xpc.serve ~capacity:2 ~max_payload_bytes:64
       handle_request)
