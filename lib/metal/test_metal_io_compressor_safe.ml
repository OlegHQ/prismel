open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let reject kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "unexpected error: %a" pp_error error)
  | Ok _ -> failwith "expected IO compressor rejection"

let () =
  let module Compressor = IO.Compressor in
  let chunk_size = get (Compressor.default_chunk_size ()) in
  if chunk_size <= 0L then failwith "IO compressor chunk size is not positive";
  reject Invalid_argument
    (Compressor.create ~path:"" ~method_:Compressor.Zlib ~chunk_size);
  reject Invalid_argument
    (Compressor.create ~path:"bad\000path" ~method_:Compressor.Zlib ~chunk_size);
  reject Invalid_argument
    (Compressor.create ~path:"/tmp/prismel-invalid" ~method_:Compressor.Zlib
       ~chunk_size:0L);
  let path = Filename.temp_file "prismel-metal-io-" ".compressed" in
  Sys.remove path;
  let compressor =
    get (Compressor.create ~path ~method_:Compressor.Zlib ~chunk_size)
  in
  let configured_path, method_, configured_chunk =
    Compressor.configuration compressor
  in
  if configured_path <> path || method_ <> Compressor.Zlib
     || configured_chunk <> chunk_size then
    failwith "IO compressor configuration snapshot drift";
  let payload = Bytes.of_string "prismel-metal-io" in
  reject Invalid_argument
    (Compressor.append compressor payload ~offset:(-1L) ~length:1L);
  reject Invalid_argument
    (Compressor.append compressor payload ~offset:0L ~length:100L);
  get (Compressor.append compressor payload ~offset:0L ~length:0L);
  get
    (Compressor.append compressor payload ~offset:0L
       ~length:(Int64.of_int (Bytes.length payload)));
  if Compressor.appended_bytes compressor <> Int64.of_int (Bytes.length payload)
  then failwith "IO compressor appended-byte count drift";
  get (Compressor.finish compressor);
  if not (Compressor.finalized compressor) then
    failwith "IO compressor did not finalize";
  reject Invalid_state
    (Compressor.append compressor payload ~offset:0L ~length:1L);
  reject Invalid_state (Compressor.finish compressor);
  if not (Sys.file_exists path) then failwith "IO compressor did not create output";
  Sys.remove path;
  Printf.printf "Metal IO compressor safe lifecycle: ok\n%!"
