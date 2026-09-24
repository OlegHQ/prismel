let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected IOCompressor rejection"

let () =
  let open Binding_io_compressor_safe_package in
  validate_handoff ();
  if ok (default_chunk_size ~native_value:65536) <> 65536 then failwith "default chunk size";
  error (default_chunk_size ~native_value:0);
  error (create ~path:"" ~method_:Lz4 ~chunk_size:64 ~native_ok:true);
  error (create ~path:"out.bin" ~method_:Lz4 ~chunk_size:0 ~native_ok:true);
  error (create ~path:"out.bin" ~method_:Lz4 ~chunk_size:64 ~native_ok:false);
  let empty = ok (create ~path:"empty.bin" ~method_:Lzma ~chunk_size:64 ~native_ok:true) in
  ignore (ok (flush_and_destroy empty ~native_status:(Ok ())));
  let compressor = ok (create ~path:"out.bin" ~method_:Lzfse ~chunk_size:64 ~native_ok:true) in
  if configuration compressor <> ("out.bin", Lzfse, 64) then failwith "compression ownership snapshot";
  let bytes = Bytes.of_string "abcdefgh" in
  ignore (ok (append compressor bytes ~offset:2 ~length:4 ~native_ok:true));
  Bytes.fill bytes 0 (Bytes.length bytes) 'x';
  if appended_bytes compressor <> 4 then failwith "append byte accounting";
  error (append compressor bytes ~offset:7 ~length:2 ~native_ok:true);
  if appended_bytes compressor <> 4 then failwith "range failure mutated context";
  ignore (ok (append compressor bytes ~offset:0 ~length:0 ~native_ok:true));
  ignore (ok (flush_and_destroy compressor ~native_status:(Ok ())));
  if not (is_finalized compressor) then failwith "flush finalization";
  error (append compressor bytes ~offset:0 ~length:1 ~native_ok:true);
  error (flush_and_destroy compressor ~native_status:(Ok ()));
  let failed = ok (create ~path:"failed.bin" ~method_:Zlib ~chunk_size:64 ~native_ok:true) in
  error (append failed bytes ~offset:0 ~length:1 ~native_ok:false);
  error (flush_and_destroy failed ~native_status:(Error "native flush failure"));
  if not (is_finalized failed) then failwith "failure cleanup did not finalize";
  Printf.printf
    "IOCompressor5 reconciled: callable lifecycle4, opaque typedef1 excluded; create/append/flush/chunk/state/range/error passed\n%!"
